import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import '../models/email_account.dart';
import '../models/email_message.dart';
import '../models/folder.dart';
import '../models/contact.dart';
import '../models/calendar_event.dart';

/// SQLite database service for local data persistence.
class DatabaseService {
  static DatabaseService? _instance;
  late final NativeDatabase _db;
  bool _isInitialized = false;

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'look_in.db');
    _db = NativeDatabase.createInBackground(
      File(dbPath),
    );

    await _createTables();
    _isInitialized = true;
  }

  Future<void> _createTables() async {
    await _db.ensureOpen(QueryExecutorUser());

    // We'll use raw SQL for simplicity since we're not using drift's
    // code generation for this initial version.
    // In production, you'd use drift's table definitions and code gen.
  }

  // For the initial version, we'll use a simpler approach with
  // shared_preferences for accounts and in-memory caching for messages.
  // Full SQLite persistence will be added in a future version.

  Future<void> close() async {
    await _db.close();
  }
}

/// Simple in-memory cache for email data.
/// This serves as the data layer until full SQLite persistence is implemented.
class DataCache {
  static final DataCache instance = DataCache._();
  DataCache._();

  final Map<String, EmailAccount> _accounts = {};
  final Map<String, List<MailFolder>> _folders = {};
  final Map<String, List<EmailMessage>> _messages = {};
  final Map<String, Contact> _contacts = {};
  final Map<String, CalendarEvent> _events = {};

  // ─── Accounts ──────────────────────────────────────────────────────

  List<EmailAccount> get accounts => _accounts.values.toList();

  void saveAccount(EmailAccount account) {
    _accounts[account.id] = account;
  }

  void removeAccount(String id) {
    _accounts.remove(id);
    _folders.remove(id);
  }

  EmailAccount? getAccount(String id) => _accounts[id];

  // ─── Folders ───────────────────────────────────────────────────────

  List<MailFolder> getFolders(String accountId) =>
      _folders[accountId] ?? [];

  void saveFolders(String accountId, List<MailFolder> folders) {
    _folders[accountId] = folders;
  }

  // ─── Messages ──────────────────────────────────────────────────────

  List<EmailMessage> getMessages(String folderId) =>
      _messages[folderId] ?? [];

  void saveMessages(String folderId, List<EmailMessage> messages) {
    _messages[folderId] = messages;
  }

  void updateMessage(EmailMessage message) {
    final messages = _messages[message.folderId];
    if (messages == null) return;
    final idx = messages.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      messages[idx] = message;
    }
  }

  void removeMessage(String folderId, String messageId) {
    _messages[folderId]?.removeWhere((m) => m.id == messageId);
  }

  // ─── Contacts ──────────────────────────────────────────────────────

  List<Contact> get contacts {
    final list = _contacts.values.toList();
    list.sort((a, b) => a.fileAs.compareTo(b.fileAs));
    return list;
  }

  void saveContact(Contact contact) {
    _contacts[contact.id] = contact;
  }

  void removeContact(String id) {
    _contacts.remove(id);
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
  }

  void removeEvent(String id) {
    _events.remove(id);
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

// Minimal File class for drift's NativeDatabase path (re-exported from dart:io)
export 'dart:io' show File;
