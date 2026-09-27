import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/calendar_event.dart';
import '../../models/contact.dart';
import '../../models/email_account.dart';
import '../app_log.dart';
import '../backends/graph_client.dart';
import '../data_store.dart';
import '../ical_service.dart';
import '../mail_backend.dart';
import '../oauth/oauth_config.dart';
import '../oauth/token_manager.dart';
import 'graph_pim_mappers.dart';

/// Keeps the calendar and contacts of Microsoft accounts (through Microsoft
/// Graph) in sync with Look In's Calendar and People.
///
/// Each account's default calendar and default contacts folder become a
/// calendar and an address book next to the local ones. Local changes are
/// marked pending and sent first; then changes from the server arrive by
/// delta. When both sides changed an item, the newer change wins.
///
/// The calendar is read as occurrences (`calendarView`), so recurring
/// series from Outlook show exactly as Outlook shows them; an occurrence
/// edited here changes only that occurrence.
class GraphPimSync extends ChangeNotifier {
  GraphPimSync({
    DataStore? store,
    GraphClient Function(EmailAccount)? clientFor,
  }) : _storeOverride = store,
       _clientFor = clientFor ?? _defaultClient;

  final DataStore? _storeOverride;
  final GraphClient Function(EmailAccount) _clientFor;

  DataStore get _store => _storeOverride ?? DataStore.instance;

  final Map<String, EmailAccount> _accounts = {};
  final Map<String, GraphClient> _clients = {};
  final Map<String, AsyncLock> _locks = {};
  final Map<String, String> _errors = {};
  bool _disposed = false;

  /// Called after a local change to an account's items, to send it soon.
  void Function(String accountId)? onLocalChange;

  /// How far back and ahead the calendar is kept.
  static const windowPast = Duration(days: 183);
  static const windowFuture = Duration(days: 548);

  static const _utc = ['outlook.timezone="UTC"'];

  static const contactFields =
      'givenName,surname,displayName,companyName,jobTitle,emailAddresses,'
      'mobilePhone,businessPhones,homePhones,businessAddress,homeAddress,'
      'otherAddress,personalNotes,createdDateTime,lastModifiedDateTime,'
      'parentFolderId';

  static GraphClient _defaultClient(EmailAccount account) => GraphClient(
    ({bool forceRefresh = false}) => TokenManager.instance.accessToken(
      account,
      resource: OAuthResource.graph,
      forceRefresh: forceRefresh,
    ),
  );

  static String sourceIdFor(String accountId) => 'graph:$accountId';

  static String? accountIdOf(String? sourceId) =>
      sourceId != null && sourceId.startsWith('graph:')
      ? sourceId.substring('graph:'.length)
      : null;

  static String _q(String id) => Uri.encodeComponent(id);

  /// Synced calendars and address books, one per Microsoft account.
  List<({String id, String label})> get sources => [
    for (final a in _accounts.values)
      (id: sourceIdFor(a.id), label: a.emailAddress),
  ];

  /// The account's address for [sourceId], or null.
  String? labelFor(String? sourceId) =>
      _accounts[accountIdOf(sourceId) ?? '']?.emailAddress;

  /// The last problem syncing the calendar or contacts of [sourceId].
  String? errorFor(String sourceId, {required bool calendar}) =>
      _errors['$sourceId|${calendar ? 'calendar' : 'contacts'}'];

  /// Called with all accounts whenever they change. Items of Microsoft
  /// accounts that are gone (or no longer use Graph) are removed.
  void setAccounts(List<EmailAccount> accounts) {
    final graph = {
      for (final a in accounts)
        if (a.isGraph) a.id: a,
    };
    final removed = _accounts.keys.where((id) => !graph.containsKey(id));
    for (final id in removed.toList()) {
      _purge(id);
      _clients.remove(id)?.close();
    }
    final changed =
        removed.isNotEmpty ||
        graph.length != _accounts.length ||
        graph.keys.any((id) => !_accounts.containsKey(id));
    _accounts
      ..clear()
      ..addAll(graph);
    if (changed) _notify();
  }

  void _purge(String accountId) {
    final source = sourceIdFor(accountId);
    for (final e in _store.events.where((e) => e.sourceId == source).toList()) {
      _store.removeEvent(e.id);
    }
    for (final c
        in _store.contacts.where((c) => c.sourceId == source).toList()) {
      _store.removeContact(c.id);
    }
    for (final key in ['events', 'contacts', 'contactFolder']) {
      _store.setString('pimDelta:$accountId:$key', null);
    }
    final deleted = _tombstones()..remove(accountId);
    _saveTombstones(deleted);
    _errors.removeWhere((key, _) => key.startsWith('$source|'));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final c in _clients.values) {
      c.close();
    }
    super.dispose();
  }

  // ─── Local changes ─────────────────────────────────────────────────

  /// [event] marked as a change to send, when it belongs to a Microsoft
  /// calendar.
  CalendarEvent prepareEvent(CalendarEvent event) {
    if (accountIdOf(event.sourceId) == null) return event;
    return event.copyWith(
      pendingSync: event.remoteId == null ? 'create' : 'update',
    );
  }

  Contact prepareContact(Contact contact) {
    if (accountIdOf(contact.sourceId) == null) return contact;
    return contact.copyWith(
      pendingSync: contact.remoteId == null ? 'create' : 'update',
    );
  }

  /// Remembers to delete [event] on the server.
  void eventDeleted(CalendarEvent event) =>
      _tombstone(event.sourceId, 'events', event.remoteId);

  /// Remembers to delete the whole series [seriesMasterId] on the server.
  void seriesDeleted(String? sourceId, String seriesMasterId) =>
      _tombstone(sourceId, 'events', seriesMasterId);

  void contactDeleted(Contact contact) =>
      _tombstone(contact.sourceId, 'contacts', contact.remoteId);

  void _tombstone(String? sourceId, String kind, String? remoteId) {
    final accountId = accountIdOf(sourceId);
    if (accountId == null || remoteId == null) return;
    final all = _tombstones();
    final lists = all.putIfAbsent(accountId, () => {});
    final list = lists.putIfAbsent(kind, () => []);
    if (!list.contains(remoteId)) list.add(remoteId);
    _saveTombstones(all);
  }

  /// Asks for the change to [sourceId] to be sent.
  void changed(String? sourceId) {
    final accountId = accountIdOf(sourceId);
    if (accountId != null) onLocalChange?.call(accountId);
  }

  Map<String, Map<String, List<String>>> _tombstones() {
    final raw = _store.getString('pimDeleted');
    if (raw == null) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map).entries)
          e.key as String: {
            for (final k in (e.value as Map).entries)
              k.key as String: (k.value as List).cast<String>().toList(),
          },
      };
    } catch (_) {
      return {};
    }
  }

  void _saveTombstones(Map<String, Map<String, List<String>>> all) {
    all.removeWhere((_, kinds) => kinds.values.every((list) => list.isEmpty));
    _store.setString('pimDeleted', all.isEmpty ? null : jsonEncode(all));
  }

  void _untombstone(String accountId, String kind, String remoteId) {
    final all = _tombstones();
    all[accountId]?[kind]?.remove(remoteId);
    _saveTombstones(all);
  }

  // ─── Sync ──────────────────────────────────────────────────────────

  GraphClient _client(EmailAccount account) =>
      _clients.putIfAbsent(account.id, () => _clientFor(account));

  /// Sends local changes of [account] and fetches the server's. Connection
  /// and sign-in problems are thrown; other problems are kept per part
  /// (see [errorFor]) so one failing part doesn't stop the other.
  Future<void> sync(EmailAccount account) {
    final lock = _locks.putIfAbsent(account.id, AsyncLock.new);
    return lock.run(() async {
      final client = _client(account);
      final source = sourceIdFor(account.id);
      await _part('$source|calendar', 'Calendars.ReadWrite', () async {
        await _pushEvents(account, client);
        await _pullEvents(account, client);
      });
      await _part('$source|contacts', 'Contacts.ReadWrite', () async {
        await _pushContacts(account, client);
        await _pullContacts(account, client);
      });
      _notify();
    });
  }

  Future<void> _part(
    String key,
    String permission,
    Future<void> Function() run,
  ) async {
    try {
      await run();
      _errors.remove(key);
    } on MailConnectionException {
      rethrow;
    } on MailAuthenticationException {
      rethrow;
    } catch (e) {
      _errors[key] = e is GraphException && e.isAccessDenied
          ? 'Microsoft denied access. The app registration needs the '
                '$permission permission, and your organization may need to '
                'grant admin consent. (${e.message})'
          : e.toString();
      AppLog.write('Microsoft sync ($key): $e');
    }
  }

  Map<String, String>? _state(String key) {
    final raw = _store.getString(key);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {
      return null;
    }
  }

  /// Follows a delta link to the end; returns the items and the next
  /// delta link. [restart] gives the first link again when the old one
  /// expired.
  Future<({List<Map<String, dynamic>> items, String link, bool full})> _delta(
    GraphClient client, {
    required String? link,
    required Future<String> Function() restart,
    List<String> prefer = const [],
  }) async {
    var full = link == null;
    var url = link ?? await restart();
    final items = <Map<String, dynamic>>[];
    while (true) {
      final Map<String, dynamic> page;
      try {
        page = await client.getJson(url, pageSize: 100, prefer: prefer);
      } on GraphException catch (e) {
        if (!e.isSyncStateGone || full) rethrow;
        full = true;
        items.clear();
        url = await restart();
        continue;
      }
      items.addAll((page['value'] as List? ?? const []).cast());
      final next = page['@odata.nextLink'] as String?;
      final delta = page['@odata.deltaLink'] as String?;
      if (next != null) {
        url = next;
      } else if (delta != null) {
        return (items: items, link: delta, full: full);
      } else {
        throw const GraphException(
          500,
          'InvalidDelta',
          'Microsoft Graph ended a sync without a delta link',
        );
      }
    }
  }

  // ─── Calendar ──────────────────────────────────────────────────────

  Future<void> _pushEvents(EmailAccount account, GraphClient client) async {
    final source = sourceIdFor(account.id);
    for (final id in [...?_tombstones()[account.id]?['events']]) {
      try {
        await client.request('DELETE', '/me/events/${_q(id)}');
      } on GraphException catch (e) {
        if (!e.isNotFound) rethrow;
      }
      _untombstone(account.id, 'events', id);
    }
    final pending = _store.events
        .where((e) => e.sourceId == source && e.pendingSync != null)
        .toList();
    if (pending.isEmpty) return;
    final zone = GraphPimMappers.localTimeZoneName();
    for (final e in pending) {
      if (e.remoteId == null) {
        await _createEvent(client, e, source, zone);
      } else {
        await _updateEvent(client, e, source, zone);
      }
    }
  }

  Future<void> _createEvent(
    GraphClient client,
    CalendarEvent e,
    String source,
    String? zone,
  ) async {
    final created = (await client.request(
      'POST',
      '/me/events',
      json: GraphPimMappers.eventToGraph(e, timeZone: zone),
      prefer: _utc,
    )).json;
    _store.removeEvent(e.id);
    if (!e.isRecurring) {
      _store.saveEvent(GraphPimMappers.eventFromGraph(created, source));
      return;
    }
    // A series arrives as its occurrences with the next pull; occurrences
    // deleted here before it was sent are deleted there now.
    final id = created['id'] as String;
    if (e.excludedDates.isEmpty) return;
    final days = e.excludedDates
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();
    final first = days.reduce((a, b) => a.isBefore(b) ? a : b);
    final last = days.reduce((a, b) => a.isAfter(b) ? a : b);
    final instances = await client.getAll(
      '/me/events/${_q(id)}/instances',
      query: {
        'startDateTime': first.toUtc().toIso8601String(),
        'endDateTime': last
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      },
      prefer: _utc,
    );
    for (final instance in instances) {
      final start = GraphPimMappers.eventFromGraph(instance, source).startTime;
      if (days.contains(DateTime(start.year, start.month, start.day))) {
        await client.request(
          'DELETE',
          '/me/events/${_q(instance['id'] as String)}',
        );
      }
    }
  }

  Future<void> _updateEvent(
    GraphClient client,
    CalendarEvent e,
    String source,
    String? zone,
  ) async {
    // An occurrence can't become a series; a single event can.
    final withRecurrence = e.seriesMasterId == null;
    Map<String, dynamic> graph(CalendarEvent event) =>
        GraphPimMappers.eventToGraph(
          event,
          timeZone: zone,
          withRecurrence: withRecurrence,
        );
    final saved = await _update(
      client,
      '/me/events/${_q(e.remoteId!)}',
      etag: e.etag,
      updatedAt: e.updatedAt,
      prefer: _utc,
      dropped:
          'Calendar: "${e.title}" changed elsewhere later; the change made '
          'here was dropped.',
      changes: (server) {
        final changes = _changedFields(
          graph(e),
          graph(GraphPimMappers.eventFromGraph(server, source)),
        );
        // Graph checks the times together.
        if (const ['start', 'end', 'isAllDay'].any(changes.containsKey)) {
          final all = graph(e);
          for (final key in const ['start', 'end', 'isAllDay']) {
            changes[key] = all[key];
          }
        }
        // Attendees who stay keep their names, types and answers.
        if (changes.containsKey('attendees')) {
          final known = {
            for (final a in server['attendees'] as List? ?? const [])
              if (((a as Map)['emailAddress'] as Map?)?['address']
                  case final String address)
                address.toLowerCase(): {
                  'emailAddress': a['emailAddress'],
                  'type': a['type'] ?? 'required',
                },
          };
          changes['attendees'] = [
            for (final address in e.attendees)
              known[address.toLowerCase()] ??
                  {
                    'emailAddress': {'address': address},
                    'type': 'required',
                  },
          ];
        }
        return changes;
      },
    );
    if (saved == null) {
      // Deleted elsewhere: that wins.
      _store.removeEvent(e.id);
      return;
    }
    final fresh = GraphPimMappers.eventFromGraph(saved, source);
    if (fresh.id != e.id) _store.removeEvent(e.id);
    _store.saveEvent(fresh);
  }

  /// Sends a local change to the item at [path]. Only the fields that
  /// differ from the server's copy go back ([changes]), so what Look In
  /// doesn't show (formatted notes, attendee details) stays as it is, and
  /// attendees hear only about real changes. When the item also changed
  /// elsewhere since the last sync, the newer change wins. Returns the item
  /// as saved, or null when it was deleted elsewhere.
  Future<Map<String, dynamic>?> _update(
    GraphClient client,
    String path, {
    required String? etag,
    required DateTime updatedAt,
    required String dropped,
    required Map<String, dynamic> Function(Map<String, dynamic> server) changes,
    List<String> prefer = const [],
  }) async {
    final Map<String, dynamic> server;
    try {
      server = await client.getJson(path, prefer: prefer);
    } on GraphException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
    final serverEtag = server['@odata.etag'] as String?;
    if (serverEtag != etag && _serverIsNewer(server, updatedAt)) {
      AppLog.write(dropped);
      return server;
    }
    final json = changes(server);
    if (json.isEmpty) return server;
    return (await client.request(
      'PATCH',
      path,
      json: json,
      headers: {'If-Match': ?serverEtag},
      prefer: prefer,
    )).json;
  }

  /// The entries of [local] whose values differ from [server]'s.
  static Map<String, dynamic> _changedFields(
    Map<String, dynamic> local,
    Map<String, dynamic> server,
  ) => {
    for (final MapEntry(:key, :value) in local.entries)
      if (jsonEncode(value) != jsonEncode(server[key])) key: value,
  };

  static bool _serverIsNewer(Map<String, dynamic> server, DateTime local) {
    final modified = DateTime.tryParse(
      server['lastModifiedDateTime'] as String? ?? '',
    );
    return modified != null && modified.isAfter(local.toUtc());
  }

  Future<void> _pullEvents(EmailAccount account, GraphClient client) async {
    final source = sourceIdFor(account.id);
    final key = 'pimDelta:${account.id}:events';
    final today = DateTime.now();
    final from = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(windowPast);
    final to = from.add(windowPast + windowFuture);
    final state = _state(key);
    final storedFrom = DateTime.tryParse(state?['from'] ?? '');
    // The window moves along every month.
    final link = storedFrom != null && from.difference(storedFrom).inDays <= 31
        ? state!['link']
        : null;
    final result = await _delta(
      client,
      link: link,
      prefer: _utc,
      restart: () async => client.buildUri('/me/calendarView/delta', {
        'startDateTime': from.toUtc().toIso8601String(),
        'endDateTime': to.toUtc().toIso8601String(),
      }).toString(),
    );

    final local = {
      for (final e in _store.events)
        if (e.sourceId == source && e.remoteId != null) e.remoteId!: e,
    };
    final seen = <String>{};
    final save = <CalendarEvent>[];
    for (final item in result.items) {
      final remoteId = item['id'] as String;
      seen.add(remoteId);
      final existing = local[remoteId];
      if (item['@removed'] != null) {
        if (existing != null) _store.removeEvent(existing.id);
        continue;
      }
      // A change made here and not sent yet stays until it is sent.
      if (existing?.pendingSync != null) continue;
      save.add(GraphPimMappers.eventFromGraph(item, source));
    }
    if (result.full) {
      for (final e in local.values) {
        if (!seen.contains(e.remoteId) && e.pendingSync == null) {
          _store.removeEvent(e.id);
        }
      }
    }
    _store.saveEvents(save);
    _store.setString(
      key,
      jsonEncode({'link': result.link, 'from': from.toIso8601String()}),
    );
  }

  /// Answers a meeting invitation with Graph, which also tells the
  /// organizer. Returns false when the meeting isn't in the account's
  /// calendar (the caller then replies by email).
  Future<bool> respondToInvitation(
    EmailAccount account,
    String icalUid,
    InviteResponse response,
  ) async {
    final client = _client(account);
    final found = await client.getJson(
      '/me/events',
      query: {
        r'$filter': "iCalUId eq '${icalUid.replaceAll("'", "''")}'",
        r'$select': 'id',
      },
    );
    final id =
        ((found['value'] as List? ?? const []).firstOrNull as Map?)?['id']
            as String?;
    if (id == null) return false;
    final action = switch (response) {
      InviteResponse.accepted => 'accept',
      InviteResponse.tentative => 'tentativelyAccept',
      InviteResponse.declined => 'decline',
    };
    await client.request(
      'POST',
      '/me/events/${_q(id)}/$action',
      json: {'sendResponse': true},
    );
    await sync(account);
    return true;
  }

  // ─── Contacts ──────────────────────────────────────────────────────

  Future<void> _pushContacts(EmailAccount account, GraphClient client) async {
    final source = sourceIdFor(account.id);
    for (final id in [...?_tombstones()[account.id]?['contacts']]) {
      try {
        await client.request('DELETE', '/me/contacts/${_q(id)}');
      } on GraphException catch (e) {
        if (!e.isNotFound) rethrow;
      }
      _untombstone(account.id, 'contacts', id);
    }
    final pending = _store.contacts
        .where((c) => c.sourceId == source && c.pendingSync != null)
        .toList();
    for (final c in pending) {
      final Map<String, dynamic> saved;
      if (c.remoteId == null) {
        saved = (await client.request(
          'POST',
          '/me/contacts',
          json: GraphPimMappers.contactToGraph(c),
        )).json;
        _rememberContactFolder(account, saved);
      } else {
        final updated = await _update(
          client,
          '/me/contacts/${_q(c.remoteId!)}',
          etag: c.etag,
          updatedAt: c.updatedAt,
          dropped:
              'People: ${c.displayName} changed elsewhere later; the change '
              'made here was dropped.',
          changes: (server) => _changedFields(
            GraphPimMappers.contactToGraph(c),
            GraphPimMappers.contactToGraph(
              GraphPimMappers.contactFromGraph(server, source),
            ),
          ),
        );
        if (updated == null) {
          // Deleted elsewhere: that wins.
          _store.removeContact(c.id);
          continue;
        }
        saved = updated;
      }
      final fresh = GraphPimMappers.contactFromGraph(saved, source);
      if (fresh.id != c.id) _store.removeContact(c.id);
      _store.saveContact(fresh.copyWith(photoPath: c.photoPath));
    }
  }

  void _rememberContactFolder(EmailAccount account, Map<String, dynamic> json) {
    final folder = json['parentFolderId'] as String?;
    final key = 'pimDelta:${account.id}:contactFolder';
    if (folder != null && _store.getString(key) == null) {
      _store.setString(key, folder);
    }
  }

  /// The default contacts folder; Graph names it only through its
  /// contacts (and its subfolders).
  Future<String?> _contactFolder(
    EmailAccount account,
    GraphClient client,
  ) async {
    final key = 'pimDelta:${account.id}:contactFolder';
    final known = _store.getString(key);
    if (known != null) return known;
    final one = await client.getJson(
      '/me/contacts',
      query: {r'$top': '1', r'$select': 'parentFolderId'},
    );
    var folder =
        ((one['value'] as List? ?? const []).firstOrNull
                as Map?)?['parentFolderId']
            as String?;
    if (folder == null) {
      final folders = await client.getJson(
        '/me/contactFolders',
        query: {r'$top': '1', r'$select': 'parentFolderId'},
      );
      folder =
          ((folders['value'] as List? ?? const []).firstOrNull
                  as Map?)?['parentFolderId']
              as String?;
    }
    if (folder != null) _store.setString(key, folder);
    return folder;
  }

  Future<void> _pullContacts(EmailAccount account, GraphClient client) async {
    final folder = await _contactFolder(account, client);
    // No contacts on the server yet (and none to find the folder by).
    if (folder == null) return;
    final source = sourceIdFor(account.id);
    final key = 'pimDelta:${account.id}:contacts';
    final result = await _delta(
      client,
      link: _state(key)?['link'],
      restart: () async => client.buildUri(
        '/me/contactFolders/${_q(folder)}/contacts/delta',
        {r'$select': contactFields},
      ).toString(),
    );
    final local = {
      for (final c in _store.contacts)
        if (c.sourceId == source && c.remoteId != null) c.remoteId!: c,
    };
    final seen = <String>{};
    final save = <Contact>[];
    for (final item in result.items) {
      final remoteId = item['id'] as String;
      seen.add(remoteId);
      final existing = local[remoteId];
      if (item['@removed'] != null) {
        if (existing != null) _store.removeContact(existing.id);
        continue;
      }
      if (existing?.pendingSync != null) continue;
      save.add(
        GraphPimMappers.contactFromGraph(
          item,
          source,
        ).copyWith(photoPath: existing?.photoPath),
      );
    }
    if (result.full) {
      for (final c in local.values) {
        if (!seen.contains(c.remoteId) && c.pendingSync == null) {
          _store.removeContact(c.id);
        }
      }
    }
    _store.saveContacts(save);
    _store.setString(key, jsonEncode({'link': result.link}));
  }
}
