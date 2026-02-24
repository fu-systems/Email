import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import '../models/email_account.dart';
import '../models/email_message.dart';
import '../models/folder.dart';
import '../models/contact.dart';
import '../models/calendar_event.dart';

// ─── Drift Database (no code-gen, raw SQL) ─────────────────────────────────

class AppDatabase extends GeneratedDatabase {
  AppDatabase._(QueryExecutor e) : super(e);

  static AppDatabase? _instance;

  static Future<AppDatabase> getInstance() async {
    if (_instance != null) return _instance!;
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'look_in.db');
    final db = NativeDatabase.createInBackground(File(dbPath));
    _instance = AppDatabase._(db);
    return _instance!;
  }

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, DataClass>> get allTables => [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement('''
            CREATE TABLE IF NOT EXISTS accounts (
              id TEXT PRIMARY KEY,
              displayName TEXT NOT NULL,
              emailAddress TEXT NOT NULL,
              imapHost TEXT NOT NULL,
              imapPort INTEGER NOT NULL,
              imapSecurity TEXT NOT NULL,
              smtpHost TEXT NOT NULL,
              smtpPort INTEGER NOT NULL,
              smtpSecurity TEXT NOT NULL,
              username TEXT NOT NULL,
              password TEXT NOT NULL,
              isDefault INTEGER NOT NULL DEFAULT 0,
              isEnabled INTEGER NOT NULL DEFAULT 1,
              signature TEXT
            )
          ''');
          await customStatement('''
            CREATE TABLE IF NOT EXISTS folders (
              id TEXT PRIMARY KEY,
              accountId TEXT NOT NULL,
              name TEXT NOT NULL,
              path TEXT NOT NULL,
              type TEXT NOT NULL,
              parentId TEXT,
              unreadCount INTEGER NOT NULL DEFAULT 0,
              totalCount INTEGER NOT NULL DEFAULT 0,
              isSubscribed INTEGER NOT NULL DEFAULT 1,
              FOREIGN KEY (accountId) REFERENCES accounts(id) ON DELETE CASCADE
            )
          ''');
          await customStatement('''
            CREATE TABLE IF NOT EXISTS messages (
              id TEXT PRIMARY KEY,
              accountId TEXT NOT NULL,
              folderId TEXT NOT NULL,
              subject TEXT NOT NULL DEFAULT '',
              fromAddress TEXT NOT NULL DEFAULT '',
              fromName TEXT,
              toAddresses TEXT,
              ccAddresses TEXT,
              bccAddresses TEXT,
              date TEXT NOT NULL,
              inReplyTo TEXT,
              messageId TEXT,
              textBody TEXT,
              htmlBody TEXT,
              preview TEXT NOT NULL DEFAULT '',
              isRead INTEGER NOT NULL DEFAULT 0,
              isFlagged INTEGER NOT NULL DEFAULT 0,
              isDraft INTEGER NOT NULL DEFAULT 0,
              isDeleted INTEGER NOT NULL DEFAULT 0,
              hasAttachments INTEGER NOT NULL DEFAULT 0,
              uid INTEGER,
              FOREIGN KEY (folderId) REFERENCES folders(id) ON DELETE CASCADE
            )
          ''');
          await customStatement('''
            CREATE INDEX IF NOT EXISTS idx_messages_folder
              ON messages(folderId)
          ''');
          await customStatement('''
            CREATE TABLE IF NOT EXISTS contacts (
              id TEXT PRIMARY KEY,
              firstName TEXT,
              lastName TEXT,
              company TEXT,
              jobTitle TEXT,
              emails TEXT,
              phones TEXT,
              street TEXT,
              city TEXT,
              state TEXT,
              zipCode TEXT,
              country TEXT,
              notes TEXT,
              photoPath TEXT,
              createdAt TEXT NOT NULL,
              updatedAt TEXT NOT NULL
            )
          ''');
          await customStatement('''
            CREATE TABLE IF NOT EXISTS events (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              description TEXT,
              location TEXT,
              startTime TEXT NOT NULL,
              endTime TEXT NOT NULL,
              isAllDay INTEGER NOT NULL DEFAULT 0,
              category TEXT NOT NULL DEFAULT 'blue',
              reminder TEXT,
              recurrence TEXT,
              attendees TEXT,
              createdAt TEXT NOT NULL,
              updatedAt TEXT NOT NULL
            )
          ''');
        },
      );

  // ─── Account Operations ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAllAccounts() async {
    return await customSelect('SELECT * FROM accounts').get().then(
        (rows) => rows.map((r) => r.data).toList());
  }

  Future<void> upsertAccount(Map<String, dynamic> data) async {
    await customStatement(
      '''INSERT OR REPLACE INTO accounts
         (id, displayName, emailAddress, imapHost, imapPort, imapSecurity,
          smtpHost, smtpPort, smtpSecurity, username, password,
          isDefault, isEnabled, signature)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        data['id'], data['displayName'], data['emailAddress'],
        data['imapHost'], data['imapPort'], data['imapSecurity'],
        data['smtpHost'], data['smtpPort'], data['smtpSecurity'],
        data['username'], data['password'],
        data['isDefault'], data['isEnabled'], data['signature'],
      ],
    );
  }

  Future<void> deleteAccount(String id) async {
    await customStatement('DELETE FROM accounts WHERE id = ?', [id]);
  }

  // ─── Folder Operations ─────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getFolders(String accountId) async {
    return await customSelect(
      'SELECT * FROM folders WHERE accountId = ?',
      variables: [Variable.withString(accountId)],
    ).get().then((rows) => rows.map((r) => r.data).toList());
  }

  Future<void> upsertFolder(Map<String, dynamic> data) async {
    await customStatement(
      '''INSERT OR REPLACE INTO folders
         (id, accountId, name, path, type, parentId,
          unreadCount, totalCount, isSubscribed)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        data['id'], data['accountId'], data['name'], data['path'],
        data['type'], data['parentId'],
        data['unreadCount'], data['totalCount'], data['isSubscribed'],
      ],
    );
  }

  Future<void> deleteFoldersForAccount(String accountId) async {
    await customStatement(
        'DELETE FROM folders WHERE accountId = ?', [accountId]);
  }

  // ─── Message Operations ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMessages(String folderId) async {
    return await customSelect(
      'SELECT * FROM messages WHERE folderId = ? ORDER BY date DESC',
      variables: [Variable.withString(folderId)],
    ).get().then((rows) => rows.map((r) => r.data).toList());
  }

  Future<void> upsertMessage(Map<String, dynamic> data) async {
    await customStatement(
      '''INSERT OR REPLACE INTO messages
         (id, accountId, folderId, subject, fromAddress, fromName,
          toAddresses, ccAddresses, bccAddresses, date, inReplyTo,
          messageId, textBody, htmlBody, preview,
          isRead, isFlagged, isDraft, isDeleted, hasAttachments, uid)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        data['id'], data['accountId'], data['folderId'],
        data['subject'], data['fromAddress'], data['fromName'],
        data['toAddresses'], data['ccAddresses'], data['bccAddresses'],
        data['date'], data['inReplyTo'], data['messageId'],
        data['textBody'], data['htmlBody'], data['preview'],
        data['isRead'], data['isFlagged'], data['isDraft'],
        data['isDeleted'], data['hasAttachments'], data['uid'],
      ],
    );
  }

  Future<void> deleteMessage(String id) async {
    await customStatement('DELETE FROM messages WHERE id = ?', [id]);
  }

  Future<void> deleteMessagesForFolder(String folderId) async {
    await customStatement(
        'DELETE FROM messages WHERE folderId = ?', [folderId]);
  }

  // ─── Contact Operations ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAllContacts() async {
    return await customSelect(
        'SELECT * FROM contacts ORDER BY lastName, firstName')
        .get()
        .then((rows) => rows.map((r) => r.data).toList());
  }

  Future<void> upsertContact(Map<String, dynamic> data) async {
    await customStatement(
      '''INSERT OR REPLACE INTO contacts
         (id, firstName, lastName, company, jobTitle, emails, phones,
          street, city, state, zipCode, country, notes, photoPath,
          createdAt, updatedAt)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        data['id'], data['firstName'], data['lastName'],
        data['company'], data['jobTitle'], data['emails'], data['phones'],
        data['street'], data['city'], data['state'],
        data['zipCode'], data['country'], data['notes'], data['photoPath'],
        data['createdAt'], data['updatedAt'],
      ],
    );
  }

  Future<void> deleteContact(String id) async {
    await customStatement('DELETE FROM contacts WHERE id = ?', [id]);
  }

  // ─── Event Operations ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAllEvents() async {
    return await customSelect('SELECT * FROM events ORDER BY startTime')
        .get()
        .then((rows) => rows.map((r) => r.data).toList());
  }

  Future<void> upsertEvent(Map<String, dynamic> data) async {
    await customStatement(
      '''INSERT OR REPLACE INTO events
         (id, title, description, location, startTime, endTime,
          isAllDay, category, reminder, recurrence, attendees,
          createdAt, updatedAt)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        data['id'], data['title'], data['description'], data['location'],
        data['startTime'], data['endTime'],
        data['isAllDay'], data['category'], data['reminder'],
        data['recurrence'], data['attendees'],
        data['createdAt'], data['updatedAt'],
      ],
    );
  }

  Future<void> deleteEvent(String id) async {
    await customStatement('DELETE FROM events WHERE id = ?', [id]);
  }
}

// ─── DataCache (write-through to SQLite) ────────────────────────────────────

/// In-memory cache backed by SQLite persistence.
/// Call [initialize] once at app startup to load persisted data.
class DataCache {
  static final DataCache instance = DataCache._();
  DataCache._();

  AppDatabase? _db;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Direct access for AccountProvider's encrypt/decrypt workflow.
  AppDatabase? get db => _db;
  Map<String, EmailAccount> get accountsMap => _accounts;

  final Map<String, EmailAccount> _accounts = {};
  final Map<String, List<MailFolder>> _folders = {};
  final Map<String, List<EmailMessage>> _messages = {};
  final Map<String, Contact> _contacts = {};
  final Map<String, CalendarEvent> _events = {};

  /// Initialize cache: open DB and load all persisted data into memory.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _db = await AppDatabase.getInstance();

    // Load accounts
    final accountRows = await _db!.getAllAccounts();
    for (final row in accountRows) {
      final account = EmailAccount.fromMap(row);
      _accounts[account.id] = account;
    }

    // Load folders for each account
    for (final accountId in _accounts.keys) {
      final folderRows = await _db!.getFolders(accountId);
      _folders[accountId] =
          folderRows.map((r) => MailFolder.fromMap(r)).toList();
    }

    // Load messages for each folder
    for (final folderList in _folders.values) {
      for (final folder in folderList) {
        final msgRows = await _db!.getMessages(folder.id);
        if (msgRows.isNotEmpty) {
          _messages[folder.id] =
              msgRows.map((r) => EmailMessage.fromMap(r)).toList();
        }
      }
    }

    // Load contacts
    final contactRows = await _db!.getAllContacts();
    for (final row in contactRows) {
      final contact = Contact.fromMap(row);
      _contacts[contact.id] = contact;
    }

    // Load events
    final eventRows = await _db!.getAllEvents();
    for (final row in eventRows) {
      final event = CalendarEvent.fromMap(row);
      _events[event.id] = event;
    }

    _isInitialized = true;
  }

  // ─── Accounts ──────────────────────────────────────────────────────

  List<EmailAccount> get accounts => _accounts.values.toList();

  void saveAccount(EmailAccount account) {
    _accounts[account.id] = account;
    _db?.upsertAccount(account.toMap());
  }

  void removeAccount(String id) {
    _accounts.remove(id);
    _folders.remove(id);
    _db?.deleteAccount(id);
  }

  EmailAccount? getAccount(String id) => _accounts[id];

  // ─── Folders ───────────────────────────────────────────────────────

  List<MailFolder> getFolders(String accountId) =>
      _folders[accountId] ?? [];

  void saveFolders(String accountId, List<MailFolder> folders) {
    _folders[accountId] = folders;
    _db?.deleteFoldersForAccount(accountId).then((_) {
      for (final folder in folders) {
        _db?.upsertFolder(folder.toMap());
      }
    });
  }

  // ─── Messages ──────────────────────────────────────────────────────

  List<EmailMessage> getMessages(String folderId) =>
      _messages[folderId] ?? [];

  void saveMessages(String folderId, List<EmailMessage> messages) {
    _messages[folderId] = messages;
    _db?.deleteMessagesForFolder(folderId).then((_) {
      for (final msg in messages) {
        _db?.upsertMessage(msg.toMap());
      }
    });
  }

  void updateMessage(EmailMessage message) {
    final messages = _messages[message.folderId];
    if (messages == null) return;
    final idx = messages.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      messages[idx] = message;
      _db?.upsertMessage(message.toMap());
    }
  }

  void removeMessage(String folderId, String messageId) {
    _messages[folderId]?.removeWhere((m) => m.id == messageId);
    _db?.deleteMessage(messageId);
  }

  // ─── Contacts ──────────────────────────────────────────────────────

  List<Contact> get contacts {
    final list = _contacts.values.toList();
    list.sort((a, b) => a.fileAs.compareTo(b.fileAs));
    return list;
  }

  void saveContact(Contact contact) {
    _contacts[contact.id] = contact;
    _db?.upsertContact(contact.toMap());
  }

  void removeContact(String id) {
    _contacts.remove(id);
    _db?.deleteContact(id);
  }

  Contact? getContact(String id) => _contacts[id];

  List<Contact> searchContacts(String query) {
    final lower = query.toLowerCase();
    return contacts.where((c) {
      return c.displayName.toLowerCase().contains(lower) ||
          c.emails.any((e) => e.address.toLowerCase().contains(lower)) ||
          (c.company?.toLowerCase().contains(lower) ?? false);
    }).toList();
  }

  // ─── Calendar Events ──────────────────────────────────────────────

  List<CalendarEvent> get events => _events.values.toList();

  List<CalendarEvent> getEventsForDate(DateTime date) {
    return _events.values.where((e) => e.occursOn(date)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  List<CalendarEvent> getEventsInRange(DateTime start, DateTime end) {
    return _events.values.where((e) {
      return e.startTime.isBefore(end) && e.endTime.isAfter(start);
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  void saveEvent(CalendarEvent event) {
    _events[event.id] = event;
    _db?.upsertEvent(event.toMap());
  }

  void removeEvent(String id) {
    _events.remove(id);
    _db?.deleteEvent(id);
  }

  CalendarEvent? getEvent(String id) => _events[id];

  // ─── Clear ─────────────────────────────────────────────────────────

  void clearAll() {
    _accounts.clear();
    _folders.clear();
    _messages.clear();
    _contacts.clear();
    _events.clear();
  }
}
