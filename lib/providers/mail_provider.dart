import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/email_account.dart';
import '../models/email_message.dart';
import '../models/folder.dart';
import '../models/mail_rule.dart';
import '../models/outgoing_message.dart';
import '../services/data_store.dart';
import '../services/mail_backend.dart';
import '../services/mime_converter.dart';
import '../services/notification_service.dart';
import 'account_provider.dart';

/// Connection state of one account.
enum AccountConnection { idle, connecting, online, offline, authFailed, error }

/// Where the message list search looks.
enum SearchScope {
  currentFolder('Current Folder'),
  allFolders('All Mailboxes');

  final String label;
  const SearchScope(this.label);
}

enum MessageSort {
  date('Date'),
  from('From'),
  subject('Subject'),
  size('Size'),
  importance('Importance');

  final String label;
  const MessageSort(this.label);
}

enum ReadingPanePosition { right, bottom, off }

/// Outcome of a send attempt.
enum SendResult { sent, queued, failed }

/// State management for the Mail module: accounts, folders, messages,
/// synchronization, sending and search. Works offline from the local cache;
/// changes made while offline are queued and replayed on reconnect.
class MailProvider extends ChangeNotifier {
  final DataStore _store;
  final NotificationService notifications;
  final Map<String, ImapBackend> _imap = {};
  final Map<String, Pop3Backend> _pop = {};
  final Map<String, AccountConnection> _connection = {};
  final Map<String, String> _accountErrors = {};
  final Set<String> _syncingAccounts = {};
  final Set<String> _loadingBodies = {};
  final Set<String> _initialSyncDone = {};
  static const _uuid = Uuid();

  List<EmailAccount> _accounts = [];
  String? _defaultAccountId;

  // Selection
  MailFolder? _selectedFolder;
  EmailMessage? _selectedMessage;
  final Set<String> _selectedIds = <String>{};
  String? _anchorId;

  // Search / sort / filter
  String _searchQuery = '';
  SearchScope _searchScope = SearchScope.currentFolder;
  List<EmailMessage>? _serverResults;
  bool _isSearchingServer = false;
  MessageSort _sort = MessageSort.date;
  bool _sortAscending = false;
  bool _unreadOnly = false;

  // Status
  bool _isLoading = false;
  String? _error;
  String? _statusText;
  DateTime? _lastSync;
  bool _workOffline = false;
  bool _isLoadingOlder = false;
  final Set<String> _noOlderMessages = {};

  // Layout
  ReadingPanePosition _readingPane = ReadingPanePosition.right;
  bool _showFolderPane = true;

  Timer? _syncTimer;
  bool _disposed = false;
  AccountProvider? _accountSource;

  MailProvider({DataStore? store, NotificationService? notifications})
      : _store = store ?? DataStore.instance,
        notifications = notifications ?? NotificationService() {
    _readingPane = ReadingPanePosition.values
            .asNameMap()[_store.getString('readingPane') ?? 'right'] ??
        ReadingPanePosition.right;
    _showFolderPane = _store.getBool('showFolderPane', defaultValue: true);
    _workOffline = _store.getBool('workOffline');
    this.notifications.enabled =
        _store.getBool('notifications', defaultValue: true);
  }

  // ─── Getters ───────────────────────────────────────────────────────

  List<EmailAccount> get accounts => _accounts;
  MailFolder? get selectedFolder => _selectedFolder;
  EmailMessage? get selectedMessage => _selectedMessage;
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  bool get isLoading => _isLoading;
  bool get isSyncing => _syncingAccounts.isNotEmpty;
  bool get isLoadingBody =>
      _selectedMessage != null && _loadingBodies.contains(_selectedMessage!.id);
  bool get isLoadingOlder => _isLoadingOlder;
  String? get error => _error;
  String? get statusText => _statusText;
  DateTime? get lastSync => _lastSync;
  String get searchQuery => _searchQuery;
  SearchScope get searchScope => _searchScope;
  bool get isSearching => _searchQuery.trim().isNotEmpty;
  bool get isSearchingServer => _isSearchingServer;
  MessageSort get sort => _sort;
  bool get sortAscending => _sortAscending;
  bool get unreadOnly => _unreadOnly;
  bool get workOffline => _workOffline;
  ReadingPanePosition get readingPanePosition => _readingPane;
  bool get showReadingPane => _readingPane != ReadingPanePosition.off;
  bool get showFolderPane => _showFolderPane;
  DataStore get store => _store;

  AccountConnection connectionOf(String accountId) =>
      _connection[accountId] ?? AccountConnection.idle;

  String? accountError(String accountId) => _accountErrors[accountId];

  EmailAccount? accountById(String id) =>
      _accounts.where((a) => a.id == id).firstOrNull;

  /// The account new messages are sent from by default.
  EmailAccount? get defaultAccount =>
      accountById(_defaultAccountId ?? '') ??
      _accounts.where((a) => a.isDefault).firstOrNull ??
      _accounts.firstOrNull;

  /// Account of the selected folder, falling back to the default account.
  EmailAccount? get currentAccount =>
      accountById(_selectedFolder?.accountId ?? '') ?? defaultAccount;

  /// True when no enabled account can currently reach its server.
  bool get isOffline {
    if (_workOffline) return true;
    final enabled = _accounts.where((a) => a.isEnabled).toList();
    if (enabled.isEmpty) return false;
    return enabled.every((a) {
      final c = connectionOf(a.id);
      return c == AccountConnection.offline;
    });
  }

  /// Folders of an account, including the virtual Outbox when it has items.
  List<MailFolder> foldersOf(String accountId) {
    final folders = List<MailFolder>.of(_store.getFolders(accountId));
    final pending = _store.outbox.where((m) => m.accountId == accountId).length;
    if (pending > 0) {
      folders.add(MailFolder(
        id: outboxFolderId(accountId),
        accountId: accountId,
        name: 'Outbox',
        path: '__outbox__',
        type: FolderType.outbox,
        totalCount: pending,
        unreadCount: pending,
      ));
    }
    return folders;
  }

  /// All folders of the current account (used by move dialogs and rules).
  List<MailFolder> get folders =>
      currentAccount == null ? [] : foldersOf(currentAccount!.id);

  static String outboxFolderId(String accountId) => '$accountId|__outbox__';

  bool _isOutbox(MailFolder? f) => f?.type == FolderType.outbox;

  MailFolder? folderByType(String accountId, FolderType type) =>
      _store.getFolders(accountId).where((f) => f.type == type).firstOrNull;

  MailFolder? folderByPath(String accountId, String path) =>
      _store.getFolders(accountId).where((f) => f.path == path).firstOrNull;

  /// Messages shown in the message list: search results, or the selected
  /// folder filtered and sorted.
  List<EmailMessage> get messages {
    List<EmailMessage> list;
    if (isSearching) {
      list = _searchResults();
    } else if (_selectedFolder == null) {
      return const [];
    } else if (_isOutbox(_selectedFolder)) {
      list = _outboxMessages(_selectedFolder!.accountId);
    } else {
      list = List.of(_store.getMessages(_selectedFolder!.id));
    }
    if (_unreadOnly) list = list.where((m) => !m.isRead).toList();
    _applySort(list);
    return list;
  }

  List<EmailMessage> _searchResults() {
    final query = _searchQuery.trim();
    final local = _searchScope == SearchScope.currentFolder &&
            _selectedFolder != null
        ? _store.searchMessages(query, folderId: _selectedFolder!.id)
        : _store.searchMessages(query,
            accountIds: _accounts.map((a) => a.id).toList());
    if (_serverResults == null) return local;
    final ids = local.map((m) => m.id).toSet();
    return [...local, ..._serverResults!.where((m) => !ids.contains(m.id))];
  }

  void _applySort(List<EmailMessage> list) {
    int compare(EmailMessage a, EmailMessage b) {
      switch (_sort) {
        case MessageSort.date:
          return a.date.compareTo(b.date);
        case MessageSort.from:
          return a.from.display.toLowerCase().compareTo(b.from.display.toLowerCase());
        case MessageSort.subject:
          return _normalizeSubject(a.subject)
              .compareTo(_normalizeSubject(b.subject));
        case MessageSort.size:
          return (a.size ?? 0).compareTo(b.size ?? 0);
        case MessageSort.importance:
          return a.importance.index.compareTo(b.importance.index);
      }
    }

    list.sort((a, b) {
      var result = compare(a, b);
      if (result == 0) result = a.date.compareTo(b.date);
      // Messages sent within the same second: the server's UID order is
      // the arrival order.
      if (result == 0) result = (a.uid ?? 0).compareTo(b.uid ?? 0);
      return _sortAscending ? result : -result;
    });
  }

  static String _normalizeSubject(String s) => s
      .replaceFirst(RegExp(r'^((re|fw|fwd|aw|wg)\s*:\s*)+', caseSensitive: false), '')
      .toLowerCase();

  List<EmailMessage> _outboxMessages(String accountId) {
    final account = accountById(accountId);
    return _store.outbox
        .where((m) => m.accountId == accountId)
        .map((m) => EmailMessage(
              id: 'outbox|${m.id}',
              accountId: m.accountId,
              folderId: outboxFolderId(m.accountId),
              subject: m.subject.isEmpty ? '(No Subject)' : m.subject,
              from: EmailAddress(
                address: account?.emailAddress ?? '',
                displayName: account?.displayName,
              ),
              to: m.to,
              cc: m.cc,
              bcc: m.bcc,
              date: m.createdAt,
              textBody: m.textBody,
              htmlBody: m.htmlBody,
              preview: m.lastError != null
                  ? 'Not sent: ${m.lastError}'
                  : MimeConverter.makePreview(m.textBody, null),
              attachments: m.attachments,
              hasAttachments: m.attachments.isNotEmpty,
              isRead: true,
              importance: m.importance,
            ))
        .toList();
  }

  /// Selected messages in list order.
  List<EmailMessage> get selectedMessages {
    if (_selectedIds.isEmpty) return const [];
    return messages.where((m) => _selectedIds.contains(m.id)).toList();
  }

  int get unreadCount {
    if (_selectedFolder == null) return 0;
    if (_isOutbox(_selectedFolder)) return 0;
    return _store.getMessages(_selectedFolder!.id).where((m) => !m.isRead).length;
  }

  /// Unread messages in the inbox of every account.
  int get totalInboxUnread {
    var total = 0;
    for (final a in _accounts) {
      final inbox = folderByType(a.id, FolderType.inbox);
      if (inbox != null) total += inbox.unreadCount;
    }
    return total;
  }

  bool canLoadOlder(MailFolder? folder) =>
      folder != null &&
      !_isOutbox(folder) &&
      !isSearching &&
      !(accountById(folder.accountId)?.isPop3 ?? true) &&
      !_noOlderMessages.contains(folder.id) &&
      _store.getMessages(folder.id).length < folder.totalCount;

  // ─── Account lifecycle ─────────────────────────────────────────────

  /// Follows [source]: accounts added, edited or removed there are
  /// connected, reconnected or dropped here.
  void attachAccounts(AccountProvider source) {
    _accountSource?.removeListener(_onAccountsChanged);
    _accountSource = source;
    source.addListener(_onAccountsChanged);
    // Defer so no listener is notified while the widget tree is building.
    scheduleMicrotask(_onAccountsChanged);
  }

  void _onAccountsChanged() {
    final source = _accountSource;
    if (source == null || _disposed) return;
    updateAccounts(source.accounts,
        defaultAccountId: source.defaultAccount?.id);
  }

  /// Called whenever the configured accounts change.
  void updateAccounts(List<EmailAccount> accounts, {String? defaultAccountId}) {
    final oldIds = _accounts.map((a) => a.id).toSet();
    final previous = {for (final a in _accounts) a.id: a};
    _accounts = List.of(accounts);
    _defaultAccountId = defaultAccountId;
    final newIds = accounts.map((a) => a.id).toSet();

    for (final removed in oldIds.difference(newIds)) {
      _dropBackend(removed);
      if (_selectedFolder?.accountId == removed) {
        _selectedFolder = null;
        _selectedMessage = null;
        _selectedIds.clear();
      }
    }
    for (final account in accounts) {
      final before = previous[account.id];
      final changed = before == null ||
          jsonEncode(before.toMap()) != jsonEncode(account.toMap());
      if (changed) {
        _dropBackend(account.id);
        if (account.isPop3) _ensureLocalFolders(account);
        if (account.isEnabled && !_workOffline) {
          unawaited(_connectAndSync(account));
        }
      }
    }
    if (_selectedFolder == null) _selectDefaultFolder();
    _restartTimer();
    _notify();
  }

  void _dropBackend(String accountId) {
    final imap = _imap.remove(accountId);
    if (imap != null) unawaited(imap.disconnect());
    _pop.remove(accountId);
    _connection.remove(accountId);
    _accountErrors.remove(accountId);
    _initialSyncDone.remove(accountId);
  }

  void _selectDefaultFolder() {
    final account = defaultAccount;
    if (account == null) return;
    final inbox = folderByType(account.id, FolderType.inbox) ??
        _store.getFolders(account.id).where((f) => f.isSelectable).firstOrNull;
    if (inbox != null) {
      _selectedFolder = inbox;
      _selectedIds.clear();
      _selectedMessage = null;
    }
  }

  /// POP3 accounts keep their folders locally (like an Outlook PST).
  void _ensureLocalFolders(EmailAccount account) {
    final existing = _store.getFolders(account.id);
    const defaults = [
      ('INBOX', 'Inbox', FolderType.inbox),
      ('Drafts', 'Drafts', FolderType.drafts),
      ('Sent Items', 'Sent Items', FolderType.sent),
      ('Deleted Items', 'Deleted Items', FolderType.trash),
      ('Junk E-mail', 'Junk E-mail', FolderType.spam),
    ];
    var changed = false;
    final folders = List.of(existing);
    for (final (path, name, type) in defaults) {
      if (!folders.any((f) => f.path == path)) {
        folders.add(MailFolder(
          id: MailFolder.makeId(account.id, path),
          accountId: account.id,
          name: name,
          path: path,
          type: type,
        ));
        changed = true;
      }
    }
    if (changed) _store.saveFolders(account.id, folders);
    _recountLocal(account.id);
  }

  /// Recomputes unread/total counts of local (POP3) folders from the cache.
  void _recountLocal(String accountId) {
    for (final f in _store.getFolders(accountId)) {
      final msgs = _store.getMessages(f.id);
      final unread = msgs.where((m) => !m.isRead).length;
      if (unread != f.unreadCount || msgs.length != f.totalCount) {
        _store.updateFolder(
            f.copyWith(unreadCount: unread, totalCount: msgs.length));
      }
    }
  }

  ImapBackend _imapFor(EmailAccount account) =>
      _imap.putIfAbsent(account.id, () => ImapBackend(account));

  Pop3Backend _popFor(EmailAccount account) =>
      _pop.putIfAbsent(account.id, () => Pop3Backend(account));

  Future<void> _connectAndSync(EmailAccount account) async {
    _connection[account.id] = AccountConnection.connecting;
    _notify();
    try {
      if (account.isPop3) {
        await _popFor(account).checkConnection();
      } else {
        await _imapFor(account).connect();
      }
      _setOnline(account.id);
      await syncAccount(account.id);
    } catch (e) {
      _handleAccountError(account.id, e);
    }
  }

  void _setOnline(String accountId) {
    _connection[accountId] = AccountConnection.online;
    _accountErrors.remove(accountId);
  }

  void _handleAccountError(String accountId, Object e) {
    if (e is MailConnectionException) {
      _connection[accountId] = AccountConnection.offline;
    } else if (e is MailAuthenticationException) {
      _connection[accountId] = AccountConnection.authFailed;
    } else {
      _connection[accountId] = AccountConnection.error;
    }
    _accountErrors[accountId] = e.toString();
    _notify();
  }

  bool _canUseNetwork(String accountId) {
    if (_workOffline) return false;
    final account = accountById(accountId);
    return account != null && account.isEnabled;
  }

  void _restartTimer() {
    _syncTimer?.cancel();
    if (_accounts.isEmpty) return;
    final minutes = _accounts
        .where((a) => a.isEnabled)
        .map((a) => a.syncIntervalMinutes)
        .fold<int>(60, (a, b) => b > 0 && b < a ? b : a);
    _syncTimer = Timer.periodic(Duration(minutes: minutes.clamp(1, 60)), (_) {
      unawaited(syncAll(full: false));
    });
  }

  // ─── Synchronization ───────────────────────────────────────────────

  /// Send/Receive: flushes the Outbox and syncs every enabled account.
  /// With [full] every folder is refreshed, otherwise the inbox and the
  /// selected folder.
  Future<void> syncAll({bool full = true}) async {
    if (_workOffline) {
      _statusText = 'Working offline';
      _notify();
      return;
    }
    await Future.wait(_accounts
        .where((a) => a.isEnabled)
        .map((a) => syncAccount(a.id, full: full)));
  }

  /// Synchronizes one account. Errors mark the account offline/failed.
  Future<void> syncAccount(String accountId, {bool full = false}) async {
    final account = accountById(accountId);
    if (account == null || !_canUseNetwork(accountId)) return;
    if (!_syncingAccounts.add(accountId)) return;
    _statusText = 'Updating ${account.emailAddress}...';
    _notify();
    try {
      await _replayPendingOperations(account);
      await _flushOutbox(accountId);
      if (account.isPop3) {
        await _syncPop(account);
      } else {
        await _syncImap(account, full: full);
      }
      _setOnline(accountId);
      _lastSync = DateTime.now();
      _initialSyncDone.add(accountId);
      _error = null;
    } catch (e) {
      _handleAccountError(accountId, e);
    } finally {
      _syncingAccounts.remove(accountId);
      _statusText = null;
      _notify();
    }
  }

  Future<void> _syncImap(EmailAccount account, {required bool full}) async {
    final backend = _imapFor(account);
    final previous = {for (final f in _store.getFolders(account.id)) f.path: f};
    final remote = await backend.fetchFolders();
    // Keep UIDVALIDITY from the previous sync; it is refreshed per folder.
    final merged = remote
        .map((f) => f.copyWith(uidValidity: previous[f.path]?.uidValidity))
        .toList();
    _store.saveFolders(account.id, merged);
    if (_selectedFolder?.accountId == account.id) {
      _selectedFolder =
          _store.getFolder(_selectedFolder!.id) ?? _selectedFolder;
    }
    if (_selectedFolder == null) _selectDefaultFolder();
    _notify();

    final toSync = <MailFolder>[];
    final inbox = folderByType(account.id, FolderType.inbox);
    if (inbox != null) toSync.add(inbox);
    final selected = _selectedFolder;
    if (selected != null &&
        selected.accountId == account.id &&
        selected.isSelectable &&
        !_isOutbox(selected) &&
        !toSync.any((f) => f.id == selected.id)) {
      toSync.add(selected);
    }
    if (full) {
      for (final f in _store.getFolders(account.id)) {
        if (f.isSelectable && !toSync.any((t) => t.id == f.id)) toSync.add(f);
      }
    }
    for (final folder in toSync) {
      await _syncImapFolder(account, folder);
    }
  }

  Future<void> _syncImapFolder(EmailAccount account, MailFolder folder) async {
    final backend = _imapFor(account);
    final cached = _store.getMessages(folder.id);
    final firstSync = cached.isEmpty && folder.uidValidity == null;
    final cachedUids = cached.map((m) => m.uid).whereType<int>().toSet();
    final snapshot =
        await backend.syncFolder(folder, cachedUids: cachedUids);

    if (snapshot.uidValidityChanged) {
      _store.removeMessages(folder.id, cached.map((m) => m.id));
    } else if (snapshot.messages.isNotEmpty) {
      final minUid = snapshot.messages
          .map((m) => m.uid!)
          .reduce((a, b) => a < b ? a : b);
      // Drop cached messages deleted on the server, and local placeholders
      // (moved while offline) that the server listing now replaces.
      final removed = cached
          .where((m) =>
              m.uid == null ||
              (m.uid! >= minUid && !snapshot.existingUids.contains(m.uid)))
          .map((m) => m.id)
          .toList();
      _store.removeMessages(folder.id, removed);
    } else if (snapshot.folder.totalCount == 0) {
      _store.removeMessages(folder.id, cached.map((m) => m.id));
    }

    final downloaded = {for (final d in snapshot.downloads) d.message.id: d};
    final newMessages = <EmailMessage>[];
    final headerOnly = <EmailMessage>[];
    for (final m in snapshot.messages) {
      final isNew = !cachedUids.contains(m.uid) || snapshot.uidValidityChanged;
      final download = downloaded[m.id];
      if (download != null) {
        // Keep the header fetch's flags (the body fetch may predate them).
        final full = download.message.copyWith(
          isRead: m.isRead,
          isFlagged: m.isFlagged,
          isAnswered: m.isAnswered,
          references: m.references,
          importance: m.importance,
        );
        _store.saveFullMessage(full, source: download.source);
        if (isNew) newMessages.add(full);
      } else {
        headerOnly.add(_mergeCachedPreview(m));
        if (isNew) newMessages.add(m);
      }
    }
    _store.putMessages(folder.id, headerOnly);
    _store.updateFolder(snapshot.folder);
    if (_selectedFolder?.id == folder.id) _selectedFolder = snapshot.folder;
    _refreshSelection();

    if (folder.type == FolderType.inbox && !firstSync) {
      final remaining = await _applyRules(account, folder, newMessages);
      _notifyNewMail(account, remaining.where((m) => !m.isRead).toList());
    }
    _notify();
  }

  /// Keeps the preview computed from a previously downloaded body.
  EmailMessage _mergeCachedPreview(EmailMessage fresh) {
    final old = _store.getMessage(fresh.id);
    if (old == null) return fresh;
    return fresh.copyWith(
      preview: fresh.preview.isEmpty ? old.preview : fresh.preview,
      attachments: fresh.attachments.isEmpty ? old.attachments : null,
    );
  }

  Future<void> _syncPop(EmailAccount account) async {
    _ensureLocalFolders(account);
    final inbox = folderByType(account.id, FolderType.inbox)!;
    final known = <String>{
      for (final f in _store.getFolders(account.id))
        for (final m in _store.getMessages(f.id))
          if (m.popUid != null) m.popUid!,
    };
    final knownSet = _store.getString('popKnown:${account.id}');
    if (knownSet != null) {
      known.addAll((jsonDecode(knownSet) as List).cast<String>());
    }
    final firstSync = !_store.getBool('popSynced:${account.id}');
    final downloads = await _popFor(account)
        .fetchNewMessages(inbox, knownUids: known);
    for (final d in downloads) {
      _store.saveFullMessage(d.message, source: d.source);
      known.add(d.message.popUid!);
    }
    // Remember every UIDL ever downloaded so deleted messages don't return.
    _store.setString('popKnown:${account.id}', jsonEncode(known.toList()));
    _store.setBool('popSynced:${account.id}', true);
    _recountLocal(account.id);
    _refreshSelection();
    if (!firstSync) {
      final remaining =
          await _applyRules(account, inbox, downloads.map((d) => d.message).toList());
      _notifyNewMail(account, remaining);
    }
  }

  /// Applies mail rules to new inbox messages; returns those still in the
  /// inbox afterwards.
  Future<List<EmailMessage>> _applyRules(
    EmailAccount account,
    MailFolder inbox,
    List<EmailMessage> newMessages,
  ) async {
    final rules = _store.rules;
    if (rules.isEmpty || newMessages.isEmpty) return newMessages;
    final remaining = <EmailMessage>[];
    for (final message in newMessages) {
      final outcome = RuleOutcome.evaluate(rules, message);
      if (outcome.isEmpty) {
        remaining.add(message);
        continue;
      }
      var current = message;
      try {
        if (outcome.markAsRead || outcome.flag) {
          await _setFlags([current],
              read: outcome.markAsRead ? true : null,
              flagged: outcome.flag ? true : null);
          current = current.copyWith(
            isRead: outcome.markAsRead ? true : null,
            isFlagged: outcome.flag ? true : null,
          );
        }
        if (outcome.delete) {
          await _deleteMessages([current]);
          continue;
        }
        final target = outcome.moveToFolderPath == null
            ? null
            : folderByPath(account.id, outcome.moveToFolderPath!);
        if (target != null && target.id != inbox.id) {
          await _moveMessages([current], target);
          continue;
        }
      } catch (e) {
        debugPrint('Rule action failed: $e');
      }
      remaining.add(current);
    }
    return remaining;
  }

  void _notifyNewMail(EmailAccount account, List<EmailMessage> fresh) {
    if (fresh.isEmpty) return;
    final latest = fresh.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
    final title = fresh.length == 1
        ? latest.from.display
        : '${fresh.length} new messages (${account.emailAddress})';
    final body = fresh.length == 1
        ? latest.subject
        : '${latest.from.display}: ${latest.subject}';
    unawaited(notifications.show(
        title: title, body: body, tag: 'mail-${account.id}'));
  }

  /// Loads the next batch of older messages of the selected IMAP folder.
  Future<void> loadOlderMessages() async {
    final folder = _selectedFolder;
    if (folder == null || _isLoadingOlder || !canLoadOlder(folder)) return;
    final account = accountById(folder.accountId);
    if (account == null || !_canUseNetwork(account.id)) return;
    final cached = _store.getMessages(folder.id);
    final oldest = cached
        .map((m) => m.uid)
        .whereType<int>()
        .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    if (oldest == null) return;
    _isLoadingOlder = true;
    _notify();
    try {
      final snapshot =
          await _imapFor(account).fetchOlder(folder, oldestUid: oldest);
      if (snapshot.messages.isEmpty) _noOlderMessages.add(folder.id);
      final downloaded = {for (final d in snapshot.downloads) d.message.id: d};
      final headerOnly = <EmailMessage>[];
      for (final m in snapshot.messages) {
        final d = downloaded[m.id];
        if (d != null) {
          _store.saveFullMessage(
              d.message.copyWith(isRead: m.isRead, isFlagged: m.isFlagged),
              source: d.source);
        } else {
          headerOnly.add(m);
        }
      }
      _store.putMessages(folder.id, headerOnly);
    } catch (e) {
      _error = 'Could not load older messages: $e';
    } finally {
      _isLoadingOlder = false;
      _notify();
    }
  }

  // ─── Folder selection & operations ─────────────────────────────────

  Future<void> selectFolder(MailFolder folder) async {
    if (!folder.isSelectable) return;
    _selectedFolder = folder;
    _selectedMessage = null;
    _selectedIds.clear();
    _anchorId = null;
    if (isSearching && _searchScope == SearchScope.currentFolder) {
      _searchQuery = '';
      _serverResults = null;
    }
    _notify();
    if (_isOutbox(folder)) return;
    final account = accountById(folder.accountId);
    if (account == null || account.isPop3 || !_canUseNetwork(account.id)) {
      return;
    }
    if (connectionOf(account.id) == AccountConnection.online ||
        connectionOf(account.id) == AccountConnection.idle) {
      _isLoading = _store.getMessages(folder.id).isEmpty;
      _notify();
      try {
        await _syncImapFolder(account, folder);
        _setOnline(account.id);
      } catch (e) {
        _handleAccountError(account.id, e);
      } finally {
        _isLoading = false;
        _notify();
      }
    }
  }

  /// Refreshes the selected folder (or everything when nothing selected).
  Future<void> refreshMessages() async {
    final folder = _selectedFolder;
    if (folder == null || _isOutbox(folder)) return syncAll();
    final account = accountById(folder.accountId);
    if (account == null) return;
    if (account.isPop3) return syncAccount(account.id);
    if (!_canUseNetwork(account.id)) return;
    _syncingAccounts.add(account.id);
    _notify();
    try {
      await _flushOutbox(account.id);
      await _syncImapFolder(account, folder);
      _setOnline(account.id);
    } catch (e) {
      _handleAccountError(account.id, e);
    } finally {
      _syncingAccounts.remove(account.id);
      _notify();
    }
  }

  /// Creates a folder under [parent] (or at the top level of [accountId]).
  Future<void> createFolder(String accountId, String name,
      {MailFolder? parent}) async {
    final account = accountById(accountId);
    if (account == null || name.trim().isEmpty) return;
    final clean = name.trim();
    if (account.isPop3) {
      final path = parent == null ? clean : '${parent.path}/$clean';
      _store.updateFolder(MailFolder(
        id: MailFolder.makeId(accountId, path),
        accountId: accountId,
        name: clean,
        path: path,
      ));
    } else {
      _requireOnline(accountId);
      final folder = await _imapFor(account).createFolder(clean, parent: parent);
      _store.updateFolder(folder);
    }
    _notify();
  }

  Future<void> renameFolder(MailFolder folder, String newName) async {
    final account = accountById(folder.accountId);
    if (account == null || newName.trim().isEmpty) return;
    if (folder.type != FolderType.other) {
      throw StateError('Special folders cannot be renamed');
    }
    MailFolder renamed;
    if (account.isPop3) {
      final parent = folder.parentPath;
      final path = parent == null ? newName.trim() : '$parent/${newName.trim()}';
      renamed = folder.copyWith(
        id: MailFolder.makeId(account.id, path),
        name: newName.trim(),
        path: path,
      );
      // Move cached messages to the renamed folder.
      final msgs = _store.getMessages(folder.id);
      _store.updateFolder(renamed);
      _store.putMessages(renamed.id, [
        for (final m in msgs)
          m.copyWith(
            id: '${renamed.id}|${m.id.split('|').last}',
            folderId: renamed.id,
          ),
      ]);
      _store.removeFolder(folder);
    } else {
      _requireOnline(account.id);
      renamed = await _imapFor(account).renameFolder(folder, newName.trim());
      await syncAccount(account.id);
    }
    if (_selectedFolder?.id == folder.id) _selectedFolder = renamed;
    _notify();
  }

  Future<void> deleteFolder(MailFolder folder) async {
    final account = accountById(folder.accountId);
    if (account == null) return;
    if (folder.type != FolderType.other) {
      throw StateError('Special folders cannot be deleted');
    }
    if (!account.isPop3) {
      _requireOnline(account.id);
      await _imapFor(account).deleteFolder(folder);
    }
    _store.removeFolder(folder);
    if (_selectedFolder?.id == folder.id) _selectDefaultFolder();
    _notify();
  }

  /// Marks every message in [folder] as read.
  Future<void> markFolderRead(MailFolder folder) async {
    final unread =
        _store.getMessages(folder.id).where((m) => !m.isRead).toList();
    await _setFlags(unread, read: true);
    _notify();
  }

  /// Permanently deletes every message in [folder] (Empty Folder / Empty
  /// Deleted Items).
  Future<void> emptyFolder(MailFolder folder) async {
    final all = _store.getMessages(folder.id).toList();
    if (all.isEmpty) return;
    final account = accountById(folder.accountId);
    if (account == null) return;
    await _expunge(account, folder, all);
    _notify();
  }

  /// Returns the account's folder of [type], creating it on the server
  /// when missing (many IMAP servers start with only an Inbox). Returns
  /// null when it cannot be created (offline).
  Future<MailFolder?> ensureSpecialFolder(
      String accountId, FolderType type) async {
    final existing = folderByType(accountId, type);
    if (existing != null) return existing;
    final account = accountById(accountId);
    if (account == null || account.isPop3) return null;
    if (!_canUseNetwork(accountId) ||
        connectionOf(accountId) == AccountConnection.offline) {
      return null;
    }
    const names = {
      FolderType.sent: 'Sent',
      FolderType.drafts: 'Drafts',
      FolderType.trash: 'Trash',
      FolderType.spam: 'Junk',
      FolderType.archive: 'Archive',
    };
    final name = names[type];
    if (name == null) return null;
    try {
      final created = await _imapFor(account).createFolder(name);
      final folder = created.copyWith(type: type);
      _store.updateFolder(folder);
      _notify();
      return folder;
    } catch (e) {
      // It may exist under this name without being recognized; reuse it.
      final byName = folderByPath(accountId, name);
      if (byName != null) {
        final typed = byName.copyWith(type: type);
        _store.updateFolder(typed);
        return typed;
      }
      debugPrint('Could not create $name: $e');
      return null;
    }
  }

  void _requireOnline(String accountId) {
    if (!_canUseNetwork(accountId) ||
        connectionOf(accountId) == AccountConnection.offline) {
      throw const MailConnectionException(
          'This action needs a connection to the mail server');
    }
  }

  // ─── Message selection ─────────────────────────────────────────────

  /// Selects [message]. With [toggle] (Ctrl+click) it is added to/removed
  /// from the selection; with [range] (Shift+click) the range from the last
  /// clicked message is selected.
  Future<void> selectMessage(
    EmailMessage message, {
    bool toggle = false,
    bool range = false,
  }) async {
    if (range && _anchorId != null) {
      final list = messages;
      final a = list.indexWhere((m) => m.id == _anchorId);
      final b = list.indexWhere((m) => m.id == message.id);
      if (a >= 0 && b >= 0) {
        _selectedIds.clear();
        for (var i = a < b ? a : b; i <= (a < b ? b : a); i++) {
          _selectedIds.add(list[i].id);
        }
      }
    } else if (toggle) {
      if (_selectedIds.contains(message.id)) {
        _selectedIds.remove(message.id);
        if (_selectedMessage?.id == message.id) {
          _selectedMessage = null;
          _notify();
          return;
        }
      } else {
        _selectedIds.add(message.id);
      }
      _anchorId = message.id;
    } else {
      _selectedIds
        ..clear()
        ..add(message.id);
      _anchorId = message.id;
    }
    await _focusMessage(message);
  }

  /// Selects all messages in the list.
  void selectAll() {
    _selectedIds.clear();
    for (final m in messages) {
      _selectedIds.add(m.id);
    }
    _notify();
  }

  /// Moves the selection up or down (keyboard navigation).
  Future<void> selectAdjacent(int delta) async {
    final list = messages;
    if (list.isEmpty) return;
    final current = list.indexWhere((m) => m.id == _selectedMessage?.id);
    final next = current < 0 ? 0 : (current + delta).clamp(0, list.length - 1);
    await selectMessage(list[next]);
  }

  Future<void> _focusMessage(EmailMessage message) async {
    _selectedMessage = _store.withCachedBody(message) ?? message;
    _notify();

    if (message.id.startsWith('outbox|')) return;
    if (!message.isRead && _store.getBool('markReadOnSelect', defaultValue: true)) {
      await _setFlags([message], read: true);
    }
    if (!_selectedMessage!.hasBody) await _downloadBody(message);
  }

  Future<void> _downloadBody(EmailMessage message) async {
    final account = accountById(message.accountId);
    final folder = _store.getFolder(message.folderId);
    if (account == null || folder == null || account.isPop3) return;
    if (!_canUseNetwork(account.id) || !_loadingBodies.add(message.id)) return;
    _notify();
    try {
      final download = await _imapFor(account).fetchFullMessage(folder, message);
      if (download != null) {
        final current = _store.getMessage(message.id) ?? message;
        final full = download.message.copyWith(
          isRead: current.isRead,
          isFlagged: current.isFlagged,
        );
        _store.saveFullMessage(full, source: download.source);
        if (_selectedMessage?.id == message.id) _selectedMessage = full;
      }
      _setOnline(account.id);
    } catch (e) {
      _handleAccountError(account.id, e);
    } finally {
      _loadingBodies.remove(message.id);
      _notify();
    }
  }

  /// Keeps the selected message in sync with the cache after changes.
  void _refreshSelection() {
    final selected = _selectedMessage;
    if (selected == null) return;
    final cached = _store.getMessage(selected.id);
    if (cached == null) {
      if (!selected.id.startsWith('outbox|')) {
        _selectedMessage = null;
        _selectedIds.remove(selected.id);
      }
      return;
    }
    _selectedMessage = cached.hasBody
        ? cached
        : cached.copyWith(
            textBody: selected.textBody,
            htmlBody: selected.htmlBody,
            attachments:
                selected.attachments.isNotEmpty ? selected.attachments : null,
          );
  }

  /// Returns the full message (with body), downloading it if necessary.
  Future<EmailMessage> loadFullMessage(EmailMessage message) async {
    final cached = _store.withCachedBody(message);
    if (cached != null) return cached;
    await _downloadBody(message);
    return _store.withCachedBody(message) ?? message;
  }

  // ─── Message actions ───────────────────────────────────────────────

  /// Targets of an action: the selection, or [message] when given.
  List<EmailMessage> _targets(EmailMessage? message) {
    if (message != null && !_selectedIds.contains(message.id)) {
      return [message];
    }
    final selected = selectedMessages;
    if (selected.isNotEmpty) return selected;
    return _selectedMessage == null ? const [] : [_selectedMessage!];
  }

  Future<void> markAsRead([EmailMessage? message]) =>
      _action(() => _setFlags(_targets(message), read: true));

  Future<void> markAsUnread([EmailMessage? message]) =>
      _action(() => _setFlags(_targets(message), read: false));

  Future<void> toggleFlag([EmailMessage? message]) {
    final targets = _targets(message);
    if (targets.isEmpty) return Future.value();
    final flag = !targets.first.isFlagged;
    return _action(() => _setFlags(targets, flagged: flag));
  }

  Future<void> setFlagged(bool flagged, [EmailMessage? message]) =>
      _action(() => _setFlags(_targets(message), flagged: flagged));

  /// Deletes messages: moves them to Deleted Items, or removes them
  /// permanently when they already are in Deleted Items.
  Future<void> deleteMessage([EmailMessage? message]) async {
    final targets = _targets(message);
    if (targets.isEmpty) return;
    final successor = _successorOf(targets);
    final outbox = targets.where((m) => m.id.startsWith('outbox|')).toList();
    for (final m in outbox) {
      _store.removeFromOutbox(m.id.substring('outbox|'.length));
    }
    final rest = targets.where((m) => !m.id.startsWith('outbox|')).toList();
    await _action(() => _deleteMessages(rest));
    _clearSelectionOf(targets, successor);
  }

  Future<void> moveMessage(MailFolder target, [EmailMessage? message]) async {
    final targets = _targets(message)
        .where((m) => !m.id.startsWith('outbox|') && m.folderId != target.id)
        .toList();
    if (targets.isEmpty) return;
    final successor = _successorOf(targets);
    await _action(() => _moveMessages(targets, target));
    _clearSelectionOf(targets, successor);
  }

  /// Moves specific messages (drag and drop) regardless of the selection.
  Future<void> moveMessagesTo(List<EmailMessage> msgs, MailFolder target) async {
    final list = msgs
        .where((m) => !m.id.startsWith('outbox|') && m.folderId != target.id)
        .toList();
    if (list.isEmpty) return;
    final successor = _successorOf(list);
    await _action(() => _moveMessages(list, target));
    _clearSelectionOf(list, successor);
  }

  /// The message Outlook would open after [removed] disappear from the
  /// list: the next one below the focused message, else the one above.
  EmailMessage? _successorOf(List<EmailMessage> removed) {
    final list = messages;
    final ids = removed.map((m) => m.id).toSet();
    final focus = list.indexWhere((m) => m.id == _selectedMessage?.id);
    if (focus < 0 || !ids.contains(list[focus].id)) return null;
    for (var i = focus + 1; i < list.length; i++) {
      if (!ids.contains(list[i].id)) return list[i];
    }
    for (var i = focus - 1; i >= 0; i--) {
      if (!ids.contains(list[i].id)) return list[i];
    }
    return null;
  }

  void _clearSelectionOf(List<EmailMessage> removed, EmailMessage? successor) {
    final ids = removed.map((m) => m.id).toSet();
    _selectedIds.removeAll(ids);
    if (_selectedMessage != null && ids.contains(_selectedMessage!.id)) {
      _selectedMessage = null;
      if (successor != null) {
        final current = messages.where((m) => m.id == successor.id).firstOrNull;
        if (current != null) {
          unawaited(selectMessage(current));
          return;
        }
      }
    }
    _notify();
  }

  Future<void> _action(Future<void> Function() run) async {
    try {
      await run();
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _notify();
  }

  Future<void> _setFlags(
    List<EmailMessage> targets, {
    bool? read,
    bool? flagged,
    bool? answered,
  }) async {
    if (targets.isEmpty) return;
    final byFolder = <String, List<EmailMessage>>{};
    for (final m in targets) {
      final changes = (read != null && m.isRead != read) ||
          (flagged != null && m.isFlagged != flagged) ||
          (answered != null && m.isAnswered != answered);
      if (changes) byFolder.putIfAbsent(m.folderId, () => []).add(m);
    }
    for (final entry in byFolder.entries) {
      final folder = _store.getFolder(entry.key);
      if (folder == null) continue;
      var unreadDelta = 0;
      final updated = entry.value.map((m) {
        if (read != null && m.isRead != read) unreadDelta += read ? -1 : 1;
        return m.copyWith(isRead: read, isFlagged: flagged, isAnswered: answered);
      }).toList();
      _store.putMessages(folder.id, updated);
      _store.updateFolder(folder.copyWith(
          unreadCount: (folder.unreadCount + unreadDelta).clamp(0, 1 << 30)));
      if (_selectedFolder?.id == folder.id) {
        _selectedFolder = _store.getFolder(folder.id);
      }
      _refreshSelection();

      final account = accountById(folder.accountId);
      if (account == null || account.isPop3) continue;
      final uids = updated.map((m) => m.uid).whereType<int>().toList();
      if (uids.isEmpty) continue;
      final op = _PendingOp(
        type: 'flags',
        accountId: account.id,
        folderPath: folder.path,
        uids: uids,
        args: {'seen': read, 'flagged': flagged, 'answered': answered},
      );
      await _runOrQueue(account, op);
    }
  }

  Future<void> _deleteMessages(List<EmailMessage> targets) async {
    final byFolder = <String, List<EmailMessage>>{};
    for (final m in targets) {
      byFolder.putIfAbsent(m.folderId, () => []).add(m);
    }
    for (final entry in byFolder.entries) {
      final folder = _store.getFolder(entry.key);
      final account = accountById(folder?.accountId ?? '');
      if (folder == null || account == null) continue;
      final trash = folderByType(account.id, FolderType.trash) ??
          await ensureSpecialFolder(account.id, FolderType.trash);
      if (trash == null || folder.id == trash.id) {
        await _expunge(account, folder, entry.value);
      } else {
        await _moveMessages(entry.value, trash);
      }
    }
  }

  Future<void> _expunge(
    EmailAccount account,
    MailFolder folder,
    List<EmailMessage> msgs,
  ) async {
    _store.removeMessages(folder.id, msgs.map((m) => m.id));
    final unreadRemoved = msgs.where((m) => !m.isRead).length;
    _store.updateFolder(folder.copyWith(
      unreadCount: (folder.unreadCount - unreadRemoved).clamp(0, 1 << 30),
      totalCount: (folder.totalCount - msgs.length).clamp(0, 1 << 30),
    ));
    if (account.isPop3) {
      final popUids = msgs.map((m) => m.popUid).whereType<String>().toSet();
      if (popUids.isNotEmpty &&
          account.leaveMessagesOnServer &&
          _canUseNetwork(account.id)) {
        try {
          await _popFor(account).deleteFromServer(popUids);
        } catch (e) {
          debugPrint('POP3 delete failed: $e');
        }
      }
      _recountLocal(account.id);
      return;
    }
    final uids = msgs.map((m) => m.uid).whereType<int>().toList();
    if (uids.isEmpty) return;
    await _runOrQueue(
      account,
      _PendingOp(
          type: 'expunge',
          accountId: account.id,
          folderPath: folder.path,
          uids: uids),
    );
  }

  Future<void> _moveMessages(List<EmailMessage> msgs, MailFolder target) async {
    final byFolder = <String, List<EmailMessage>>{};
    for (final m in msgs) {
      byFolder.putIfAbsent(m.folderId, () => []).add(m);
    }
    for (final entry in byFolder.entries) {
      final source = _store.getFolder(entry.key);
      final account = accountById(source?.accountId ?? '');
      if (source == null || account == null) continue;
      if (target.accountId != account.id) {
        throw StateError('Messages can only be moved within one account');
      }
      final list = entry.value;
      // Keep bodies so the moved copy is readable offline right away.
      final full = list.map((m) => _store.withCachedBody(m) ?? m).toList();
      final sources = {
        for (final m in list) m.id: _store.getMessageSource(m.id),
      };
      _store.removeMessages(source.id, list.map((m) => m.id));
      final unreadMoved = list.where((m) => !m.isRead).length;
      _store.updateFolder(source.copyWith(
        unreadCount: (source.unreadCount - unreadMoved).clamp(0, 1 << 30),
        totalCount: (source.totalCount - list.length).clamp(0, 1 << 30),
      ));

      Map<int, int> uidMap = const {};
      if (!account.isPop3) {
        final uids = list.map((m) => m.uid).whereType<int>().toList();
        if (uids.isNotEmpty) {
          final op = _PendingOp(
          type: 'move',
          accountId: account.id,
          folderPath: source.path,
          uids: uids,
            args: {'target': target.path},
          );
          uidMap = await _runOrQueue(account, op) ?? const {};
        }
      }

      for (final m in full) {
        final newUid = m.uid == null ? null : uidMap[m.uid!];
        final String newId;
        if (account.isPop3) {
          newId = '${target.id}|${m.popUid != null ? 'pop:${m.popUid}' : _uuid.v4()}';
        } else if (newUid != null) {
          newId = '${account.id}|${target.path}|$newUid';
        } else {
          newId = '${target.id}|local-${_uuid.v4()}';
        }
        final moved = EmailMessage.fromMap({
          ...m.toMap(),
          'id': newId,
          'folderId': target.id,
          'uid': account.isPop3 ? null : newUid,
        });
        _store.saveFullMessage(moved, source: sources[m.id]);
      }
      final latestTarget = _store.getFolder(target.id) ?? target;
      _store.updateFolder(latestTarget.copyWith(
        unreadCount: latestTarget.unreadCount + unreadMoved,
        totalCount: latestTarget.totalCount + list.length,
      ));
      if (account.isPop3) _recountLocal(account.id);
    }
  }

  // ─── Pending (offline) operations ──────────────────────────────────

  List<_PendingOp> _loadPending() {
    final raw = _store.getString('pendingOps');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => _PendingOp.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  void _savePending(List<_PendingOp> ops) {
    _store.setString(
        'pendingOps', ops.isEmpty ? null : jsonEncode(ops.map((o) => o.toMap()).toList()));
  }

  int get pendingOperationCount => _loadPending().length;

  /// Runs [op] against the server, or queues it when the account is
  /// offline. Returns the operation's result (UID map for moves).
  Future<Map<int, int>?> _runOrQueue(EmailAccount account, _PendingOp op) async {
    final offline = !_canUseNetwork(account.id) ||
        connectionOf(account.id) == AccountConnection.offline;
    if (offline) {
      _savePending([..._loadPending(), op]);
      return null;
    }
    try {
      final result = await _execute(account, op);
      _setOnline(account.id);
      return result;
    } on MailConnectionException catch (e) {
      _handleAccountError(account.id, e);
      _savePending([..._loadPending(), op]);
      return null;
    }
  }

  Future<Map<int, int>?> _execute(EmailAccount account, _PendingOp op) async {
    final folder = folderByPath(account.id, op.folderPath) ??
        MailFolder(
          id: MailFolder.makeId(account.id, op.folderPath),
          accountId: account.id,
          name: op.folderPath,
          path: op.folderPath,
        );
    final backend = _imapFor(account);
    switch (op.type) {
      case 'flags':
        await backend.setFlags(
          folder,
          op.uids,
          seen: op.args['seen'] as bool?,
          flagged: op.args['flagged'] as bool?,
          answered: op.args['answered'] as bool?,
        );
        return null;
      case 'expunge':
        await backend.expungeMessages(folder, op.uids);
        return null;
      case 'move':
        final targetPath = op.args['target'] as String;
        final target = folderByPath(account.id, targetPath) ??
            MailFolder(
              id: MailFolder.makeId(account.id, targetPath),
              accountId: account.id,
              name: targetPath,
              path: targetPath,
            );
        return backend.moveMessages(folder, target, op.uids);
    }
    return null;
  }

  Future<void> _replayPendingOperations(EmailAccount account) async {
    final all = _loadPending();
    final mine = all.where((o) => o.accountId == account.id).toList();
    if (mine.isEmpty || account.isPop3) return;
    final remaining = all.where((o) => o.accountId != account.id).toList();
    for (var i = 0; i < mine.length; i++) {
      try {
        await _execute(account, mine[i]);
      } on MailConnectionException {
        // Still offline: keep this and the following operations.
        remaining.addAll(mine.sublist(i));
        _savePending(remaining);
        rethrow;
      } catch (e) {
        // The server rejected it (e.g. message already gone): drop it.
        debugPrint('Dropping pending ${mine[i].type}: $e');
      }
    }
    _savePending(remaining);
  }

  // ─── Sending ───────────────────────────────────────────────────────

  /// Sends [message]. When the server can't be reached the message goes to
  /// the Outbox and is sent on the next Send/Receive.
  Future<SendResult> send(OutgoingMessage message) async {
    final account = accountById(message.accountId);
    if (account == null) {
      _error = 'No account to send from';
      _notify();
      return SendResult.failed;
    }
    if (!_canUseNetwork(account.id)) {
      _store.addToOutbox(message.copyWith(lastError: 'Working offline'));
      _notify();
      return SendResult.queued;
    }
    try {
      await _deliver(account, message);
      _error = null;
      _notify();
      return SendResult.sent;
    } on MailConnectionException catch (e) {
      _store.addToOutbox(message.copyWith(lastError: e.message));
      _handleAccountError(account.id, e);
      return SendResult.queued;
    } catch (e) {
      _error = e.toString();
      _notify();
      return SendResult.failed;
    }
  }

  /// Sends a message and files a copy in Sent Items; throws on failure.
  Future<void> _deliver(
    EmailAccount account,
    OutgoingMessage message, {
    ({String ics, String method})? calendarPart,
  }) async {
    final mime = await MimeConverter.buildMimeMessage(message, account,
        calendarPart: calendarPart);
    await SmtpSender.send(account, mime, message.allRecipients);

    // File a copy in Sent Items (with Bcc, which was not transmitted).
    if (message.bcc.isNotEmpty) {
      mime.setHeader('Bcc', message.bcc.map((a) => a.toString()).join(', '));
    }
    final raw = mime.renderMessage();
    await _fileCopy(account, FolderType.sent, raw, message, seen: true);

    // Flag the original as answered and remove the draft it came from.
    if (message.inReplyTo != null) {
      final original = _findByMessageId(account.id, message.inReplyTo!);
      if (original != null) {
        try {
          await _setFlags([original], answered: true);
        } catch (_) {}
      }
    }
    if (message.draftMessageId != null) {
      final draft = _store.getMessage(message.draftMessageId!);
      if (draft != null) {
        final folder = _store.getFolder(draft.folderId);
        if (folder != null) {
          try {
            await _expunge(account, folder, [draft]);
          } catch (_) {}
        }
      }
    }
  }

  /// Providers that store sent mail automatically when sending via SMTP.
  static bool _serverSavesSent(EmailAccount account) {
    final host = account.smtpHost.toLowerCase();
    return host.contains('gmail') ||
        host.contains('googlemail') ||
        host.contains('office365') ||
        host.contains('outlook.com');
  }

  Future<void> _fileCopy(
    EmailAccount account,
    FolderType type,
    String raw,
    OutgoingMessage message, {
    required bool seen,
  }) async {
    if (type == FolderType.sent && !account.isPop3 && _serverSavesSent(account)) {
      return;
    }
    final folder = folderByType(account.id, type) ??
        await ensureSpecialFolder(account.id, type);
    if (folder == null) return;
    final source = Uint8List.fromList(utf8.encode(raw));
    if (account.isPop3) {
      final parsed = MimeConverter.toEmailMessage(
        MimeConverter.parse(raw),
        id: '${folder.id}|local-${_uuid.v4()}',
        accountId: account.id,
        folderId: folder.id,
        isRead: true,
      ).copyWith(isDraft: type == FolderType.drafts);
      _store.saveFullMessage(parsed, source: source);
      _recountLocal(account.id);
      return;
    }
    try {
      await _imapFor(account).appendMessage(folder, raw, flags: [
        if (seen) r'\Seen',
        if (type == FolderType.drafts) r'\Draft',
      ]);
      if (_selectedFolder?.id == folder.id) {
        unawaited(_syncImapFolder(account, folder).catchError((_) {}));
      }
    } catch (e) {
      debugPrint('Could not save copy to ${folder.name}: $e');
    }
  }

  EmailMessage? _findByMessageId(String accountId, String messageId) {
    for (final folder in _store.getFolders(accountId)) {
      for (final m in _store.getMessages(folder.id)) {
        if (m.messageId == messageId) return m;
      }
    }
    return null;
  }

  /// Saves [message] to the Drafts folder, replacing its previous version.
  /// Returns the updated message (with the new draft id when known).
  Future<OutgoingMessage> saveDraft(OutgoingMessage message) async {
    final account = accountById(message.accountId);
    if (account == null) return message;
    final drafts = folderByType(account.id, FolderType.drafts) ??
        await ensureSpecialFolder(account.id, FolderType.drafts);
    if (drafts == null) {
      throw StateError('The Drafts folder could not be created. Connect to '
          'the mail server and try again.');
    }
    final mime = await MimeConverter.buildMimeMessage(message, account);
    if (message.bcc.isNotEmpty) {
      mime.setHeader('Bcc', message.bcc.map((a) => a.toString()).join(', '));
    }
    final raw = mime.renderMessage();
    final source = Uint8List.fromList(utf8.encode(raw));

    // Remove the previous version of this draft.
    if (message.draftMessageId != null) {
      final old = _store.getMessage(message.draftMessageId!);
      if (old != null) {
        final folder = _store.getFolder(old.folderId);
        if (folder != null) {
          try {
            await _expunge(account, folder, [old]);
          } catch (_) {}
        }
      }
    }

    int? uid;
    if (!account.isPop3 && _canUseNetwork(account.id)) {
      try {
        uid = await _imapFor(account)
            .appendMessage(drafts, raw, flags: [r'\Seen', r'\Draft']);
      } catch (e) {
        debugPrint('Saving draft on server failed: $e');
      }
    }
    final id = uid != null
        ? '${account.id}|${drafts.path}|$uid'
        : '${drafts.id}|local-${_uuid.v4()}';
    final parsed = MimeConverter.toEmailMessage(
      MimeConverter.parse(raw),
      id: id,
      accountId: account.id,
      folderId: drafts.id,
      uid: uid,
      isRead: true,
    ).copyWith(isDraft: true);
    _store.saveFullMessage(parsed, source: source);
    if (account.isPop3) _recountLocal(account.id);
    _notify();
    return message.copyWith(draftMessageId: id);
  }

  /// Attempts to send everything in the Outbox of [accountId].
  Future<void> _flushOutbox(String accountId) async {
    final account = accountById(accountId);
    if (account == null) return;
    for (final item in _store.outbox.where((m) => m.accountId == accountId).toList()) {
      try {
        await _deliver(account, item);
        _store.removeFromOutbox(item.id);
      } on MailConnectionException {
        rethrow;
      } catch (e) {
        _store.addToOutbox(item.copyWith(lastError: e.toString()));
      }
      _notify();
    }
  }

  /// Returns the Outbox entry behind an Outbox list item.
  OutgoingMessage? outboxItem(EmailMessage listItem) {
    if (!listItem.id.startsWith('outbox|')) return null;
    final id = listItem.id.substring('outbox|'.length);
    return _store.outbox.where((m) => m.id == id).firstOrNull;
  }

  void removeFromOutbox(String id) {
    _store.removeFromOutbox(id);
    _notify();
  }

  /// Sends an iCalendar reply (e.g. to a meeting invitation).
  Future<SendResult> sendCalendarReply({
    required String accountId,
    required EmailAddress organizer,
    required String subject,
    required String text,
    required String ics,
  }) async {
    final account = accountById(accountId);
    if (account == null) return SendResult.failed;
    final message = OutgoingMessage(
      id: _uuid.v4(),
      accountId: accountId,
      to: [organizer],
      subject: subject,
      textBody: text,
      createdAt: DateTime.now(),
    );
    try {
      await _deliver(account, message, calendarPart: (ics: ics, method: 'REPLY'));
      return SendResult.sent;
    } catch (e) {
      _error = 'Could not send the response: $e';
      _notify();
      return SendResult.failed;
    }
  }

  // ─── Attachments & drafts ──────────────────────────────────────────

  /// Raw MIME source of a message, downloading it if necessary.
  Future<Uint8List?> messageSource(EmailMessage message) async {
    var source = _store.getMessageSource(message.id);
    if (source != null) return source;
    await _downloadBody(message);
    source = _store.getMessageSource(message.id);
    return source;
  }

  /// Decoded content of an attachment.
  Future<Uint8List?> attachmentData(
    EmailMessage message,
    Attachment attachment,
  ) async {
    if (attachment.localPath != null) {
      final file = File(attachment.localPath!);
      return await file.exists() ? file.readAsBytes() : null;
    }
    final source = await messageSource(message);
    if (source == null) return null;
    return MimeConverter.extractPart(source, attachment.id);
  }

  /// Extracts a draft's attachments to a temporary folder so the draft can
  /// be edited and re-sent. Returns attachments with [Attachment.localPath].
  Future<List<Attachment>> materializeAttachments(EmailMessage message) async {
    final visible = message.attachments.where((a) => !a.isInline).toList();
    if (visible.isEmpty) return const [];
    final dir = await Directory.systemTemp.createTemp('look_in_draft_');
    final result = <Attachment>[];
    for (final att in visible) {
      final data = await attachmentData(message, att);
      if (data == null) continue;
      final file = File(p.join(dir.path, p.basename(att.fileName)));
      await file.writeAsBytes(data);
      result.add(Attachment(
        id: att.id,
        fileName: att.fileName,
        mimeType: att.mimeType,
        size: data.length,
        localPath: file.path,
      ));
    }
    return result;
  }

  // ─── Search ────────────────────────────────────────────────────────

  void setSearchQuery(String query) {
    _searchQuery = query;
    _serverResults = null;
    _notify();
  }

  void setSearchScope(SearchScope scope) {
    _searchScope = scope;
    _serverResults = null;
    _notify();
  }

  void clearSearch() => setSearchQuery('');

  /// Searches the selected IMAP folder on the server (finds messages that
  /// are not cached locally).
  Future<void> searchOnServer() async {
    final query = _searchQuery.trim();
    if (query.isEmpty) return;
    final targets = <MailFolder>[];
    if (_searchScope == SearchScope.currentFolder) {
      if (_selectedFolder != null && !_isOutbox(_selectedFolder)) {
        targets.add(_selectedFolder!);
      }
    } else {
      for (final a in _accounts.where((a) => !a.isPop3)) {
        final inbox = folderByType(a.id, FolderType.inbox);
        if (inbox != null) targets.add(inbox);
        final sent = folderByType(a.id, FolderType.sent);
        if (sent != null) targets.add(sent);
      }
    }
    _isSearchingServer = true;
    _notify();
    final results = <EmailMessage>[];
    try {
      for (final folder in targets) {
        final account = accountById(folder.accountId);
        if (account == null || account.isPop3 || !_canUseNetwork(account.id)) {
          continue;
        }
        final backend = _imapFor(account);
        final uids = await backend.search(folder, query);
        final cached = {
          for (final m in _store.getMessages(folder.id))
            if (m.uid != null) m.uid!: m,
        };
        final missing = uids.where((u) => !cached.containsKey(u)).take(100).toList();
        results.addAll(uids.where(cached.containsKey).map((u) => cached[u]!));
        final fetched = await backend.fetchHeaders(folder, missing);
        _store.putMessages(folder.id, fetched);
        results.addAll(fetched);
      }
      if (_searchQuery.trim() == query) _serverResults = results;
    } catch (e) {
      _error = 'Server search failed: $e';
    } finally {
      _isSearchingServer = false;
      _notify();
    }
  }

  // ─── Sort, filter, layout, settings ────────────────────────────────

  void setSort(MessageSort sort) {
    if (_sort == sort) {
      _sortAscending = !_sortAscending;
    } else {
      _sort = sort;
      _sortAscending = sort == MessageSort.from || sort == MessageSort.subject;
    }
    _notify();
  }

  void setUnreadOnly(bool value) {
    _unreadOnly = value;
    _notify();
  }

  void setReadingPanePosition(ReadingPanePosition position) {
    _readingPane = position;
    _store.setString('readingPane', position.name);
    _notify();
  }

  void toggleReadingPane() => setReadingPanePosition(
      showReadingPane ? ReadingPanePosition.off : ReadingPanePosition.right);

  void toggleFolderPane() {
    _showFolderPane = !_showFolderPane;
    _store.setBool('showFolderPane', _showFolderPane);
    _notify();
  }

  void setWorkOffline(bool value) {
    _workOffline = value;
    _store.setBool('workOffline', value);
    if (!value) {
      for (final a in _accounts.where((a) => a.isEnabled)) {
        unawaited(_connectAndSync(a));
      }
    } else {
      for (final backend in _imap.values) {
        unawaited(backend.disconnect());
      }
      _imap.clear();
    }
    _notify();
  }

  bool preference(String key, {bool defaultValue = false}) =>
      _store.getBool(key, defaultValue: defaultValue);

  /// Stores a boolean user preference (Options dialog) and refreshes views.
  void setPreference(String key, bool value) {
    _store.setBool(key, value);
    _notify();
  }

  void setNotificationsEnabled(bool value) {
    notifications.enabled = value;
    _store.setBool('notifications', value);
    _notify();
  }

  void clearError() {
    _error = null;
    _notify();
  }

  // ─── Rules ─────────────────────────────────────────────────────────

  List<MailRule> get rules => _store.rules;

  void saveRules(List<MailRule> rules) {
    _store.saveRules(rules);
    _notify();
  }

  /// Runs the rules over the messages currently in [inbox] ("Run Rules
  /// Now"). Returns the number of messages affected.
  Future<int> runRulesNow(MailFolder inbox) async {
    final account = accountById(inbox.accountId);
    if (account == null) return 0;
    final msgs = List.of(_store.getMessages(inbox.id));
    final affected =
        msgs.where((m) => !RuleOutcome.evaluate(_store.rules, m).isEmpty).length;
    await _applyRules(account, inbox, msgs);
    _notify();
    return affected;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _accountSource?.removeListener(_onAccountsChanged);
    _syncTimer?.cancel();
    for (final backend in _imap.values) {
      unawaited(backend.disconnect());
    }
    unawaited(notifications.close());
    super.dispose();
  }
}

/// A server change recorded while offline, replayed on reconnect.
class _PendingOp {
  final String type;
  final String accountId;
  final String folderPath;
  final List<int> uids;
  final Map<String, dynamic> args;

  const _PendingOp({
    required this.type,
    required this.accountId,
    required this.folderPath,
    required this.uids,
    this.args = const {},
  });

  Map<String, dynamic> toMap() => {
        'type': type,
        'accountId': accountId,
        'folderPath': folderPath,
        'uids': uids,
        'args': args,
      };

  factory _PendingOp.fromMap(Map<String, dynamic> map) => _PendingOp(
        type: map['type'] as String,
        accountId: map['accountId'] as String,
        folderPath: map['folderPath'] as String,
        uids: (map['uids'] as List).cast<int>(),
        args: (map['args'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}
