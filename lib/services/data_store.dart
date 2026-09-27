import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_event.dart';
import '../models/contact.dart';
import '../models/email_account.dart';
import '../models/email_message.dart';
import '../models/folder.dart';
import '../models/mail_rule.dart';
import '../models/outgoing_message.dart';
import 'app_log.dart';
import 'credential_store.dart';
import 'database_service.dart';

/// The app's local data layer: synchronous in-memory caches for the UI,
/// written through to SQLite so everything survives restarts and is
/// available offline.
class DataStore {
  final AppDatabase db;
  final CredentialCipher cipher;

  static DataStore? _instance;

  /// The shared store. [initialize] (or tests) must set it up first.
  static DataStore get instance {
    final store = _instance;
    if (store == null) {
      throw StateError('DataStore.initialize() has not been called');
    }
    return store;
  }

  static set instance(DataStore store) => _instance = store;

  static bool get isInitialized => _instance != null;

  final Map<String, EmailAccount> _accounts = {};
  final Map<String, List<MailFolder>> _folders = {};
  final Map<String, List<EmailMessage>> _messages = {};
  final Map<String, Contact> _contacts = {};
  final Map<String, ContactGroup> _groups = {};
  final Map<String, CalendarEvent> _events = {};
  final List<MailRule> _rules = [];
  final List<OutgoingMessage> _outbox = [];
  final Map<String, String> _settings = {};

  DataStore(this.db, this.cipher) {
    _load();
  }

  /// In-memory store for tests.
  factory DataStore.inMemory() =>
      DataStore(AppDatabase.inMemory(), CredentialCipher.random());

  /// Opens the database in the user's data directory
  /// (`~/.local/share/<app id>`), migrates legacy data and sets [instance].
  static Future<DataStore> initialize({String? directory}) async {
    final dir = directory ?? (await getApplicationSupportDirectory()).path;
    await Directory(dir).create(recursive: true);
    AppLog.install(dir);
    final cipher = await CredentialCipher.load(File(p.join(dir, 'master.key')));
    final store = DataStore(AppDatabase.open(p.join(dir, 'look_in.db')), cipher);
    await store._migrateSharedPreferences();
    _instance = store;
    return store;
  }

  void _load() {
    for (final row in db.loadAccounts()) {
      try {
        final password = cipher.decrypt(row.secret) ?? '';
        final account =
            EmailAccount.fromMap({...row.data, 'password': password});
        _accounts[account.id] = account;
      } catch (_) {
        // Skip unreadable rows rather than failing startup.
      }
    }
    for (final id in _accounts.keys) {
      _folders[id] = db
          .loadFolders(id)
          .map(MailFolder.fromMap)
          .toList();
    }
    for (final map in db.loadDocuments('contacts')) {
      final c = Contact.fromMap(map);
      _contacts[c.id] = c;
    }
    for (final map in db.loadDocuments('contact_groups')) {
      final g = ContactGroup.fromMap(map);
      _groups[g.id] = g;
    }
    for (final map in db.loadDocuments('events')) {
      final e = CalendarEvent.fromMap(map);
      _events[e.id] = e;
    }
    _rules.addAll(db.loadRules().map(MailRule.fromMap));
    _outbox.addAll(db.loadOutbox().map(OutgoingMessage.fromMap));
    _settings.addAll(db.loadSettings());
  }

  /// Imports accounts saved by version 0.1 (SharedPreferences, plain-text
  /// passwords) and removes them from SharedPreferences.
  Future<void> _migrateSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('accounts');
      if (raw == null) return;
      for (final json in raw) {
        final account = EmailAccount.fromMap(
            (jsonDecode(json) as Map).cast<String, dynamic>());
        if (!_accounts.containsKey(account.id)) saveAccount(account);
      }
      final active = prefs.getString('activeAccountId');
      if (active != null) setString('activeAccountId', active);
      await prefs.remove('accounts');
      await prefs.remove('activeAccountId');
    } catch (_) {
      // Missing plugin (tests) or corrupt legacy data: nothing to migrate.
    }
  }

  void close() => db.close();

  // ─── Accounts ──────────────────────────────────────────────────────

  List<EmailAccount> get accounts => _accounts.values.toList();

  EmailAccount? getAccount(String id) => _accounts[id];

  void saveAccount(EmailAccount account) {
    _accounts[account.id] = account;
    _persistAccountOrder();
  }

  void _persistAccountOrder() {
    var order = 0;
    db.transaction(() {
      for (final a in _accounts.values) {
        db.upsertAccount(
          a.id,
          a.toMap(includePassword: false),
          a.password.isEmpty ? null : cipher.encrypt(a.password),
          sortOrder: order++,
        );
      }
    });
  }

  void removeAccount(String id) {
    _accounts.remove(id);
    final folders = _folders.remove(id) ?? const [];
    for (final f in folders) {
      _messages.remove(f.id);
    }
    _outbox.removeWhere((m) => m.accountId == id);
    db.deleteAccount(id);
  }

  // ─── Folders ───────────────────────────────────────────────────────

  List<MailFolder> getFolders(String accountId) =>
      List.unmodifiable(_folders[accountId] ?? const <MailFolder>[]);

  MailFolder? getFolder(String folderId) {
    for (final list in _folders.values) {
      for (final f in list) {
        if (f.id == folderId) return f;
      }
    }
    return null;
  }

  /// Replaces an account's folder list (after a server refresh).
  void saveFolders(String accountId, List<MailFolder> folders) {
    final sorted = MailFolder.sortHierarchically(folders);
    final newIds = sorted.map((f) => f.id).toSet();
    for (final old in _folders[accountId] ?? const <MailFolder>[]) {
      if (!newIds.contains(old.id)) _messages.remove(old.id);
    }
    _folders[accountId] = sorted;
    db.replaceFolders(accountId, sorted.map((f) => f.toMap()).toList());
  }

  void updateFolder(MailFolder folder) {
    final list = _folders[folder.accountId];
    if (list == null) return;
    final idx = list.indexWhere((f) => f.id == folder.id);
    if (idx >= 0) {
      list[idx] = folder;
    } else {
      list.add(folder);
      _folders[folder.accountId] = MailFolder.sortHierarchically(list);
    }
    db.upsertFolder(folder.toMap());
  }

  void removeFolder(MailFolder folder) {
    _folders[folder.accountId]?.removeWhere((f) => f.id == folder.id);
    _messages.remove(folder.id);
    db.deleteFolder(folder.id);
  }

  // ─── Messages ──────────────────────────────────────────────────────

  /// Cached messages of a folder, newest first (bodies not included).
  List<EmailMessage> getMessages(String folderId) {
    return _messages.putIfAbsent(
      folderId,
      () => db.loadMessages(folderId).map(EmailMessage.fromMap).toList(),
    );
  }

  EmailMessage? getMessage(String id) {
    for (final list in _messages.values) {
      for (final m in list) {
        if (m.id == id) return m;
      }
    }
    final map = db.loadMessage(id);
    return map == null ? null : EmailMessage.fromMap(map);
  }

  /// Inserts or updates messages of one folder.
  void putMessages(String folderId, List<EmailMessage> messages) {
    if (messages.isEmpty) return;
    final list = getMessages(folderId);
    final index = {for (var i = 0; i < list.length; i++) list[i].id: i};
    for (final m in messages) {
      final lean = _withoutBody(m);
      final i = index[m.id];
      if (i != null) {
        list[i] = lean;
      } else {
        index[m.id] = list.length;
        list.add(lean);
      }
    }
    list.sort((a, b) => b.date.compareTo(a.date));
    db.upsertMessages(messages.map((m) => m.toMap()).toList());
  }

  /// Updates a single cached message (flags, folder-local changes...).
  void updateMessage(EmailMessage message) =>
      putMessages(message.folderId, [message]);

  void removeMessages(String folderId, Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _messages[folderId]?.removeWhere((m) => idSet.contains(m.id));
    db.deleteMessages(idSet);
  }

  static EmailMessage _withoutBody(EmailMessage m) {
    if (!m.hasBody) return m;
    return EmailMessage.fromMap(m.toMap()
      ..remove('textBody')
      ..remove('htmlBody'));
  }

  /// Returns [message] with its cached body, or null if not downloaded yet.
  EmailMessage? withCachedBody(EmailMessage message) {
    if (message.hasBody) return message;
    final body = db.loadBody(message.id);
    if (body == null) return null;
    return message.copyWith(textBody: body.text, htmlBody: body.html);
  }

  /// Stores a downloaded message including its body and raw MIME source.
  void saveFullMessage(EmailMessage message, {Uint8List? source}) {
    putMessages(message.folderId, [message]);
    db.saveBody(
      message.id,
      text: message.textBody,
      html: message.htmlBody,
      source: source,
    );
  }

  Uint8List? getMessageSource(String id) => db.loadSource(id);

  /// Searches cached messages (see [AppDatabase.searchMessages]).
  List<EmailMessage> searchMessages(
    String query, {
    List<String>? accountIds,
    String? folderId,
    int limit = 500,
  }) {
    return db
        .searchMessages(query,
            accountIds: accountIds, folderId: folderId, limit: limit)
        .map(EmailMessage.fromMap)
        .toList();
  }

  // ─── Contacts ──────────────────────────────────────────────────────

  List<Contact>? _sortedContacts;

  /// All contacts sorted by "File As" (cached until contacts change).
  List<Contact> get contacts {
    return _sortedContacts ??= List.unmodifiable(_contacts.values.toList()
      ..sort((a, b) =>
          a.fileAs.toLowerCase().compareTo(b.fileAs.toLowerCase())));
  }

  Map<String, Contact> get contactsById => Map.unmodifiable(_contacts);

  Contact? getContact(String id) => _contacts[id];

  void saveContact(Contact contact) {
    _contacts[contact.id] = contact;
    _sortedContacts = null;
    db.upsertDocument('contacts', contact.id, contact.toMap());
  }

  void saveContacts(List<Contact> contacts) {
    db.transaction(() => contacts.forEach(saveContact));
  }

  void removeContact(String id) {
    _contacts.remove(id);
    _sortedContacts = null;
    db.deleteDocument('contacts', id);
    // Drop the contact from any group it belonged to.
    for (final g in _groups.values.toList()) {
      if (g.memberIds.contains(id)) {
        saveGroup(g.copyWith(
          memberIds: g.memberIds.where((m) => m != id).toList(),
          updatedAt: DateTime.now(),
        ));
      }
    }
  }

  List<Contact> searchContacts(String query) {
    final lower = query.toLowerCase();
    return contacts.where((c) {
      return c.displayName.toLowerCase().contains(lower) ||
          c.emails.any((e) => e.address.toLowerCase().contains(lower)) ||
          (c.company?.toLowerCase().contains(lower) ?? false) ||
          c.phones.any((ph) => ph.number.contains(query));
    }).toList();
  }

  // ─── Contact groups ────────────────────────────────────────────────

  List<ContactGroup> get groups {
    final list = _groups.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  ContactGroup? getGroup(String id) => _groups[id];

  void saveGroup(ContactGroup group) {
    _groups[group.id] = group;
    db.upsertDocument('contact_groups', group.id, group.toMap());
  }

  void removeGroup(String id) {
    _groups.remove(id);
    db.deleteDocument('contact_groups', id);
  }

  // ─── Calendar events ───────────────────────────────────────────────

  List<CalendarEvent> get events => _events.values.toList();

  CalendarEvent? getEvent(String id) => _events[id];

  CalendarEvent? getEventByUid(String uid) {
    for (final e in _events.values) {
      if (e.uid == uid) return e;
    }
    return null;
  }

  /// Occurrences overlapping [start, end), sorted by start time.
  List<EventOccurrence> getOccurrencesInRange(DateTime start, DateTime end) {
    final result = <EventOccurrence>[];
    for (final e in _events.values) {
      result.addAll(e.occurrencesBetween(start, end));
    }
    result.sort((a, b) {
      if (a.event.isAllDay != b.event.isAllDay) {
        return a.event.isAllDay ? -1 : 1;
      }
      return a.start.compareTo(b.start);
    });
    return result;
  }

  List<EventOccurrence> getOccurrencesForDate(DateTime date) =>
      getOccurrencesInRange(
        DateTime(date.year, date.month, date.day),
        DateTime(date.year, date.month, date.day + 1),
      );

  void saveEvent(CalendarEvent event) {
    _events[event.id] = event;
    db.upsertDocument('events', event.id, event.toMap());
  }

  void saveEvents(List<CalendarEvent> events) {
    db.transaction(() => events.forEach(saveEvent));
  }

  void removeEvent(String id) {
    _events.remove(id);
    db.deleteDocument('events', id);
  }

  // ─── Rules ─────────────────────────────────────────────────────────

  List<MailRule> get rules => List.unmodifiable(_rules);

  void saveRules(List<MailRule> rules) {
    _rules
      ..clear()
      ..addAll(rules);
    db.saveRules(rules.map((r) => r.toMap()).toList());
  }

  // ─── Outbox ────────────────────────────────────────────────────────

  List<OutgoingMessage> get outbox => List.unmodifiable(_outbox);

  void addToOutbox(OutgoingMessage message) {
    _outbox.removeWhere((m) => m.id == message.id);
    _outbox.add(message);
    db.addToOutbox(message.id, message.accountId, message.toMap());
  }

  void removeFromOutbox(String id) {
    _outbox.removeWhere((m) => m.id == id);
    db.removeFromOutbox(id);
  }

  // ─── Settings ──────────────────────────────────────────────────────

  String? getString(String key) => _settings[key];

  void setString(String key, String? value) {
    if (value == null) {
      _settings.remove(key);
    } else {
      _settings[key] = value;
    }
    db.setSetting(key, value);
  }

  bool getBool(String key, {bool defaultValue = false}) {
    final v = _settings[key];
    return v == null ? defaultValue : v == 'true';
  }

  void setBool(String key, bool value) => setString(key, value.toString());

  int getInt(String key, {int defaultValue = 0}) =>
      int.tryParse(_settings[key] ?? '') ?? defaultValue;

  void setInt(String key, int value) => setString(key, value.toString());
}
