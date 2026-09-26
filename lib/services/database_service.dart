import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

/// Thin wrapper around a SQLite database holding all of Look In's local data.
///
/// Records are stored as JSON documents (`data` column) produced by the
/// models' `toMap()`, with the fields that are filtered or sorted on
/// duplicated into real columns. Message bodies and raw MIME sources live in
/// separate columns so that folder listings stay cheap.
class AppDatabase {
  final Database _db;

  /// Current schema version, stored in `PRAGMA user_version`.
  static const int schemaVersion = 1;

  AppDatabase._(this._db) {
    _migrate();
  }

  /// Opens (creating if necessary) the database file at [path].
  factory AppDatabase.open(String path) {
    final db = sqlite3.open(path);
    // WAL keeps reads fast while the sync loop writes.
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = NORMAL');
    return AppDatabase._(db);
  }

  /// Opens a private in-memory database (used by tests).
  factory AppDatabase.inMemory() => AppDatabase._(sqlite3.openInMemory());

  void _migrate() {
    final version = _db.userVersion;
    if (version < 1) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS accounts (
          id TEXT PRIMARY KEY,
          sort_order INTEGER NOT NULL DEFAULT 0,
          data TEXT NOT NULL,
          secret TEXT
        );
        CREATE TABLE IF NOT EXISTS folders (
          id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL,
          path TEXT NOT NULL,
          data TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS folders_account ON folders(account_id);
        CREATE TABLE IF NOT EXISTS messages (
          id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL,
          folder_id TEXT NOT NULL,
          uid INTEGER,
          date INTEGER NOT NULL,
          is_read INTEGER NOT NULL DEFAULT 0,
          is_flagged INTEGER NOT NULL DEFAULT 0,
          subject TEXT,
          sender TEXT,
          recipients TEXT,
          preview TEXT,
          data TEXT NOT NULL,
          text_body TEXT,
          html_body TEXT,
          source BLOB
        );
        CREATE INDEX IF NOT EXISTS messages_folder_date
          ON messages(folder_id, date DESC);
        CREATE INDEX IF NOT EXISTS messages_account ON messages(account_id);
        CREATE TABLE IF NOT EXISTS contacts (
          id TEXT PRIMARY KEY,
          data TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS contact_groups (
          id TEXT PRIMARY KEY,
          data TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS events (
          id TEXT PRIMARY KEY,
          data TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS rules (
          id TEXT PRIMARY KEY,
          sort_order INTEGER NOT NULL DEFAULT 0,
          data TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS outbox (
          id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL,
          created INTEGER NOT NULL,
          data TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT
        );
      ''');
    }
    if (version != schemaVersion) _db.userVersion = schemaVersion;
  }

  /// Runs [action] inside a transaction, rolling back on error. Nested calls
  /// join the outer transaction.
  T transaction<T>(T Function() action) {
    if (!_db.autocommit) return action();
    _db.execute('BEGIN');
    try {
      final result = action();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => _db.close();

  static Map<String, dynamic> _decode(Object? json) =>
      (jsonDecode(json as String) as Map).cast<String, dynamic>();

  // ─── Accounts ──────────────────────────────────────────────────────

  /// Returns accounts as (map without password, encrypted secret).
  List<({Map<String, dynamic> data, String? secret})> loadAccounts() {
    return _db
        .select('SELECT data, secret FROM accounts ORDER BY sort_order, rowid')
        .map((r) => (data: _decode(r['data']), secret: r['secret'] as String?))
        .toList();
  }

  void upsertAccount(
    String id,
    Map<String, dynamic> data,
    String? secret, {
    int sortOrder = 0,
  }) {
    _db.execute(
      'INSERT INTO accounts (id, sort_order, data, secret) VALUES (?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET data = excluded.data, '
      'secret = excluded.secret, sort_order = excluded.sort_order',
      [id, sortOrder, jsonEncode(data), secret],
    );
  }

  /// Deletes an account and everything that belongs to it.
  void deleteAccount(String id) {
    transaction(() {
      _db.execute('DELETE FROM messages WHERE account_id = ?', [id]);
      _db.execute('DELETE FROM folders WHERE account_id = ?', [id]);
      _db.execute('DELETE FROM outbox WHERE account_id = ?', [id]);
      _db.execute('DELETE FROM accounts WHERE id = ?', [id]);
    });
  }

  // ─── Folders ───────────────────────────────────────────────────────

  List<Map<String, dynamic>> loadFolders(String accountId) => _db
      .select('SELECT data FROM folders WHERE account_id = ? ORDER BY path',
          [accountId])
      .map((r) => _decode(r['data']))
      .toList();

  /// Replaces the folder list of an account. Messages in folders that no
  /// longer exist are deleted.
  void replaceFolders(String accountId, List<Map<String, dynamic>> folders) {
    transaction(() {
      final ids = folders.map((f) => f['id'] as String).toSet();
      final existing = _db
          .select('SELECT id FROM folders WHERE account_id = ?', [accountId])
          .map((r) => r['id'] as String)
          .toList();
      for (final id in existing) {
        if (!ids.contains(id)) {
          _db.execute('DELETE FROM messages WHERE folder_id = ?', [id]);
          _db.execute('DELETE FROM folders WHERE id = ?', [id]);
        }
      }
      for (final f in folders) {
        upsertFolder(f);
      }
    });
  }

  void upsertFolder(Map<String, dynamic> folder) {
    _db.execute(
      'INSERT INTO folders (id, account_id, path, data) VALUES (?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET path = excluded.path, data = excluded.data',
      [folder['id'], folder['accountId'], folder['path'], jsonEncode(folder)],
    );
  }

  void deleteFolder(String folderId) {
    transaction(() {
      _db.execute('DELETE FROM messages WHERE folder_id = ?', [folderId]);
      _db.execute('DELETE FROM folders WHERE id = ?', [folderId]);
    });
  }

  // ─── Messages ──────────────────────────────────────────────────────

  /// Message metadata (without bodies) of a folder, newest first.
  List<Map<String, dynamic>> loadMessages(String folderId, {int? limit}) {
    return _db
        .select(
          'SELECT data FROM messages WHERE folder_id = ? ORDER BY date DESC'
          '${limit != null ? ' LIMIT ${limit.toInt()}' : ''}',
          [folderId],
        )
        .map((r) => _decode(r['data']))
        .toList();
  }

  Map<String, dynamic>? loadMessage(String id) {
    final rows = _db.select('SELECT data FROM messages WHERE id = ?', [id]);
    return rows.isEmpty ? null : _decode(rows.first['data']);
  }

  /// Inserts or updates message metadata. Bodies present in the maps are
  /// stored; absent bodies keep what was cached before.
  void upsertMessages(List<Map<String, dynamic>> messages) {
    if (messages.isEmpty) return;
    transaction(() {
      final stmt = _db.prepare('''
        INSERT INTO messages (id, account_id, folder_id, uid, date, is_read,
          is_flagged, subject, sender, recipients, preview, data,
          text_body, html_body)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          account_id = excluded.account_id,
          folder_id = excluded.folder_id,
          uid = excluded.uid,
          date = excluded.date,
          is_read = excluded.is_read,
          is_flagged = excluded.is_flagged,
          subject = excluded.subject,
          sender = excluded.sender,
          recipients = excluded.recipients,
          preview = excluded.preview,
          data = excluded.data,
          text_body = COALESCE(excluded.text_body, messages.text_body),
          html_body = COALESCE(excluded.html_body, messages.html_body)
      ''');
      try {
        for (final m in messages) {
          final meta = Map<String, dynamic>.of(m)
            ..remove('textBody')
            ..remove('htmlBody');
          stmt.execute([
            m['id'],
            m['accountId'],
            m['folderId'],
            m['uid'],
            DateTime.parse(m['date'] as String).millisecondsSinceEpoch,
            m['isRead'] == true ? 1 : 0,
            m['isFlagged'] == true ? 1 : 0,
            m['subject'],
            _addressText([m['from']]),
            _addressText([
              ...(m['to'] as List? ?? const []),
              ...(m['cc'] as List? ?? const []),
            ]),
            m['preview'],
            jsonEncode(meta),
            m['textBody'] as String?,
            m['htmlBody'] as String?,
          ]);
        }
      } finally {
        stmt.close();
      }
    });
  }

  static String _addressText(List<Object?> addresses) => addresses
      .whereType<Map>()
      .map((a) => '${a['name'] ?? ''} ${a['address'] ?? ''}'.trim())
      .join('; ');

  ({String? text, String? html})? loadBody(String id) {
    final rows = _db.select(
      'SELECT text_body, html_body FROM messages WHERE id = ? '
      'AND (text_body IS NOT NULL OR html_body IS NOT NULL)',
      [id],
    );
    if (rows.isEmpty) return null;
    return (
      text: rows.first['text_body'] as String?,
      html: rows.first['html_body'] as String?,
    );
  }

  void saveBody(String id, {String? text, String? html, Uint8List? source}) {
    _db.execute(
      'UPDATE messages SET text_body = ?, html_body = ?, '
      'source = COALESCE(?, source) WHERE id = ?',
      [text, html, source, id],
    );
  }

  Uint8List? loadSource(String id) {
    final rows = _db.select('SELECT source FROM messages WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return rows.first['source'] as Uint8List?;
  }

  void deleteMessages(Iterable<String> ids) {
    if (ids.isEmpty) return;
    transaction(() {
      final stmt = _db.prepare('DELETE FROM messages WHERE id = ?');
      try {
        for (final id in ids) {
          stmt.execute([id]);
        }
      } finally {
        stmt.close();
      }
    });
  }

  /// Case-insensitive search over subject, sender, recipients, preview and
  /// plain-text body. Returns metadata maps, newest first.
  List<Map<String, dynamic>> searchMessages(
    String query, {
    List<String>? accountIds,
    String? folderId,
    int limit = 500,
  }) {
    final escaped = query
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final params = <Object?>['%$escaped%'];
    final where = <String>[
      r"(subject LIKE ?1 ESCAPE '\' OR sender LIKE ?1 ESCAPE '\' "
          r"OR recipients LIKE ?1 ESCAPE '\' OR preview LIKE ?1 ESCAPE '\' "
          r"OR text_body LIKE ?1 ESCAPE '\')",
    ];
    if (folderId != null) {
      params.add(folderId);
      where.add('folder_id = ?${params.length}');
    }
    if (accountIds != null) {
      if (accountIds.isEmpty) return [];
      final placeholders = <String>[];
      for (final id in accountIds) {
        params.add(id);
        placeholders.add('?${params.length}');
      }
      where.add('account_id IN (${placeholders.join(', ')})');
    }
    return _db
        .select(
          'SELECT data FROM messages WHERE ${where.join(' AND ')} '
          'ORDER BY date DESC LIMIT ${limit.toInt()}',
          params,
        )
        .map((r) => _decode(r['data']))
        .toList();
  }

  // ─── Simple document tables ────────────────────────────────────────

  static const _documentTables = {'contacts', 'contact_groups', 'events'};

  List<Map<String, dynamic>> loadDocuments(String table) {
    _checkTable(table);
    return _db
        .select('SELECT data FROM $table ORDER BY rowid')
        .map((r) => _decode(r['data']))
        .toList();
  }

  void upsertDocument(String table, String id, Map<String, dynamic> data) {
    _checkTable(table);
    _db.execute(
      'INSERT INTO $table (id, data) VALUES (?, ?) '
      'ON CONFLICT(id) DO UPDATE SET data = excluded.data',
      [id, jsonEncode(data)],
    );
  }

  void deleteDocument(String table, String id) {
    _checkTable(table);
    _db.execute('DELETE FROM $table WHERE id = ?', [id]);
  }

  static void _checkTable(String table) {
    if (!_documentTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'Unknown document table');
    }
  }

  // ─── Rules ─────────────────────────────────────────────────────────

  List<Map<String, dynamic>> loadRules() => _db
      .select('SELECT data FROM rules ORDER BY sort_order, rowid')
      .map((r) => _decode(r['data']))
      .toList();

  /// Replaces all rules, preserving the given order.
  void saveRules(List<Map<String, dynamic>> rules) {
    transaction(() {
      _db.execute('DELETE FROM rules');
      for (var i = 0; i < rules.length; i++) {
        _db.execute(
          'INSERT INTO rules (id, sort_order, data) VALUES (?, ?, ?)',
          [rules[i]['id'], i, jsonEncode(rules[i])],
        );
      }
    });
  }

  // ─── Outbox ────────────────────────────────────────────────────────

  List<Map<String, dynamic>> loadOutbox() => _db
      .select('SELECT data FROM outbox ORDER BY created')
      .map((r) => _decode(r['data']))
      .toList();

  void addToOutbox(String id, String accountId, Map<String, dynamic> data) {
    _db.execute(
      'INSERT OR REPLACE INTO outbox (id, account_id, created, data) '
      'VALUES (?, ?, ?, ?)',
      [id, accountId, DateTime.now().millisecondsSinceEpoch, jsonEncode(data)],
    );
  }

  void removeFromOutbox(String id) {
    _db.execute('DELETE FROM outbox WHERE id = ?', [id]);
  }

  // ─── Settings ──────────────────────────────────────────────────────

  Map<String, String> loadSettings() {
    return {
      for (final r in _db.select('SELECT key, value FROM settings'))
        r['key'] as String: (r['value'] as String?) ?? '',
    };
  }

  void setSetting(String key, String? value) {
    if (value == null) {
      _db.execute('DELETE FROM settings WHERE key = ?', [key]);
    } else {
      _db.execute(
        'INSERT INTO settings (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, value],
      );
    }
  }
}
