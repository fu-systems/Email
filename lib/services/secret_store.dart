import 'dart:async';
import 'dart:convert';

import 'package:dbus/dbus.dart';

import 'credential_store.dart';
import 'database_service.dart';

/// Where account passwords and sign-in tokens are kept.
///
/// Secrets are addressed by keys such as `password:<accountId>` or
/// `oauth:<accountId>`. [DataStore] keeps a synchronous in-memory copy and
/// writes through to the store.
abstract class SecretStore {
  /// Stable identifier saved in the settings (`file` or `keyring`).
  String get id;

  /// Human-readable name for the Options page.
  String get label;

  /// All of Look In's secrets.
  Future<Map<String, String>> readAll();

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  Future<void> close();
}

/// Secrets encrypted with AES-256-GCM (see [CredentialCipher]) in the
/// database's `secrets` table. Always available.
class FileSecretStore implements SecretStore {
  final AppDatabase db;
  final CredentialCipher cipher;

  FileSecretStore(this.db, this.cipher);

  @override
  String get id => 'file';

  @override
  String get label => 'Look In (encrypted file)';

  @override
  Future<Map<String, String>> readAll() async => readAllSync();

  Map<String, String> readAllSync() {
    final result = <String, String>{};
    db.loadSecrets().forEach((key, encrypted) {
      final value = cipher.decrypt(encrypted);
      if (value != null) result[key] = value;
    });
    return result;
  }

  @override
  Future<void> write(String key, String value) async => writeSync(key, value);

  void writeSync(String key, String value) =>
      db.upsertSecret(key, cipher.encrypt(value));

  @override
  Future<void> delete(String key) async => db.deleteSecret(key);

  @override
  Future<void> close() async {}
}

/// Thrown when the Secret Service refuses or fails a request.
class SecretStoreException implements Exception {
  final String message;
  const SecretStoreException(this.message);

  @override
  String toString() => message;
}

/// The desktop keyring (GNOME Keyring, KWallet, KeePassXC …) through the
/// freedesktop Secret Service API on the session bus.
///
/// Uses the `plain` session algorithm: secrets cross the user's private
/// session bus unencrypted, as with libsecret's default. Each secret is an
/// item in the default collection with the attributes
/// `{application: systems.fu.look_in, key: <key>}`.
class SecretServiceStore implements SecretStore {
  static const _bus = 'org.freedesktop.secrets';
  static const _service = 'org.freedesktop.Secret.Service';
  static const _collectionIface = 'org.freedesktop.Secret.Collection';
  static const _itemIface = 'org.freedesktop.Secret.Item';
  static const _promptIface = 'org.freedesktop.Secret.Prompt';
  static const defaultApplication = 'systems.fu.look_in';

  final DBusClient _client;
  final bool _ownsClient;
  final DBusObjectPath _session;
  final Duration timeout;

  /// The `application` attribute of this store's items. Tests use their
  /// own value so they never touch a real user's secrets.
  final String application;

  SecretServiceStore._(this._client, this._session, this._ownsClient,
      this.timeout, this.application);

  @override
  String get id => 'keyring';

  @override
  String get label => 'System keyring';

  /// Connects to the Secret Service, or returns null when none is running.
  static Future<SecretServiceStore?> connect({
    DBusClient? client,
    Duration timeout = const Duration(seconds: 5),
    String application = defaultApplication,
  }) async {
    DBusClient? bus;
    try {
      bus = client ?? DBusClient.session();
      final service = DBusRemoteObject(bus,
          name: _bus, path: DBusObjectPath('/org/freedesktop/secrets'));
      final result = await service.callMethod(
        _service,
        'OpenSession',
        [const DBusString('plain'), const DBusVariant(DBusString(''))],
        replySignature: DBusSignature('vo'),
      ).timeout(timeout);
      final session = result.returnValues[1].asObjectPath();
      return SecretServiceStore._(
          bus, session, client == null, timeout, application);
    } catch (_) {
      if (client == null) {
        try {
          await bus?.close();
        } catch (_) {}
      }
      return null;
    }
  }

  DBusRemoteObject get _serviceObject => DBusRemoteObject(_client,
      name: _bus, path: DBusObjectPath('/org/freedesktop/secrets'));

  DBusRemoteObject _object(DBusObjectPath path) =>
      DBusRemoteObject(_client, name: _bus, path: path);

  Future<DBusMethodSuccessResponse> _call(DBusRemoteObject object,
          String iface, String method, List<DBusValue> args,
          {String? reply}) =>
      object
          .callMethod(iface, method, args,
              replySignature: reply == null ? null : DBusSignature(reply))
          .timeout(timeout);

  static DBusDict _attributes(Map<String, String> attributes) => DBusDict(
        DBusSignature('s'),
        DBusSignature('s'),
        {
          for (final e in attributes.entries)
            DBusString(e.key): DBusString(e.value),
        },
      );

  /// Items holding [key] (all of Look In's items when null), unlocking them
  /// first when the keyring is locked.
  Future<List<DBusObjectPath>> _search(String? key) async {
    final result = await _call(
      _serviceObject,
      _service,
      'SearchItems',
      [
        _attributes({'application': application, 'key': ?key}),
      ],
      reply: 'aoao',
    );
    final unlocked = result.returnValues[0].asObjectPathArray().toList();
    final locked = result.returnValues[1].asObjectPathArray().toList();
    if (locked.isNotEmpty) unlocked.addAll(await _unlock(locked));
    return unlocked;
  }

  Future<List<DBusObjectPath>> _unlock(List<DBusObjectPath> objects) async {
    final result = await _call(
        _serviceObject, _service, 'Unlock', [DBusArray.objectPath(objects)],
        reply: 'aoo');
    final unlocked = result.returnValues[0].asObjectPathArray().toList();
    final prompt = result.returnValues[1].asObjectPath();
    if (prompt.value == '/') return unlocked;
    final completed = await _prompt(prompt);
    if (completed == null) {
      throw const SecretStoreException('The keyring was not unlocked.');
    }
    return completed.asObjectPathArray().toList();
  }

  /// Runs a Secret Service prompt (for example the keyring's unlock
  /// dialog). Returns its result, or null when the user dismissed it.
  Future<DBusValue?> _prompt(DBusObjectPath path) async {
    final object = _object(path);
    final signals = DBusRemoteObjectSignalStream(
        object: object, interface: _promptIface, name: 'Completed');
    final completer = Completer<DBusValue?>();
    final subscription = signals.listen((signal) {
      if (completer.isCompleted) return;
      final dismissed = signal.values[0].asBoolean();
      completer.complete(dismissed ? null : signal.values[1].asVariant());
    });
    try {
      // Give the match rule time to reach the bus before prompting.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await object
          .callMethod(_promptIface, 'Prompt', [const DBusString('')],
              replySignature: DBusSignature(''))
          .timeout(timeout);
      // The user may take a while to type the keyring password.
      return await completer.future.timeout(const Duration(minutes: 5));
    } finally {
      await subscription.cancel();
    }
  }

  /// The default collection (usually the "login" keyring).
  Future<DBusObjectPath> _collection() async {
    final alias = await _call(_serviceObject, _service, 'ReadAlias',
        [const DBusString('default')],
        reply: 'o');
    var path = alias.returnValues[0].asObjectPath();
    if (path.value == '/') {
      // No default keyring yet: ask the service to create one.
      final created = await _call(
        _serviceObject,
        _service,
        'CreateCollection',
        [
          DBusDict.stringVariant({
            'org.freedesktop.Secret.Collection.Label':
                const DBusString('Default keyring'),
          }),
          const DBusString('default'),
        ],
        reply: 'oo',
      );
      path = created.returnValues[0].asObjectPath();
      final prompt = created.returnValues[1].asObjectPath();
      if (path.value == '/' && prompt.value != '/') {
        final result = await _prompt(prompt);
        if (result == null) {
          throw const SecretStoreException('No keyring was created.');
        }
        path = result.asObjectPath();
      }
    }
    final locked = await _object(path)
        .getProperty(_collectionIface, 'Locked',
            signature: DBusSignature('b'))
        .timeout(timeout);
    if (locked.asBoolean()) await _unlock([path]);
    return path;
  }

  @override
  Future<Map<String, String>> readAll() async {
    final items = await _search(null);
    if (items.isEmpty) return {};
    final result = await _call(_serviceObject, _service, 'GetSecrets',
        [DBusArray.objectPath(items), _session],
        reply: 'a{o(oayays)}');
    final secrets = result.returnValues[0].asDict();
    final values = <String, String>{};
    for (final item in items) {
      final secret = secrets[item];
      if (secret == null) continue;
      final attributes = await _object(item)
          .getProperty(_itemIface, 'Attributes',
              signature: DBusSignature('a{ss}'))
          .timeout(timeout);
      final key = attributes
          .asDict()
          .map((k, v) => MapEntry(k.asString(), v.asString()))['key'];
      if (key == null) continue;
      final bytes = secret.asStruct()[2].asByteArray().toList();
      values[key] = utf8.decode(bytes, allowMalformed: true);
    }
    return values;
  }

  @override
  Future<void> write(String key, String value) async {
    final collection = await _collection();
    final result = await _call(
      _object(collection),
      _collectionIface,
      'CreateItem',
      [
        DBusDict.stringVariant({
          'org.freedesktop.Secret.Item.Label':
              DBusString('Look In: ${_describe(key)}'),
          'org.freedesktop.Secret.Item.Attributes':
              _attributes({'application': application, 'key': key}),
        }),
        DBusStruct([
          _session,
          DBusArray.byte(const []),
          DBusArray.byte(utf8.encode(value)),
          const DBusString('text/plain; charset=utf8'),
        ]),
        const DBusBoolean(true),
      ],
      reply: 'oo',
    );
    final prompt = result.returnValues[1].asObjectPath();
    if (prompt.value != '/' && await _prompt(prompt) == null) {
      throw const SecretStoreException('The keyring refused to save.');
    }
  }

  @override
  Future<void> delete(String key) async {
    for (final item in await _search(key)) {
      final result =
          await _call(_object(item), _itemIface, 'Delete', [], reply: 'o');
      final prompt = result.returnValues[0].asObjectPath();
      if (prompt.value != '/') await _prompt(prompt);
    }
  }

  static String _describe(String key) {
    final colon = key.indexOf(':');
    if (colon < 0) return key;
    final kind = key.substring(0, colon);
    final account = key.substring(colon + 1);
    return switch (kind) {
      'password' => 'password ($account)',
      'oauth' => 'sign-in token ($account)',
      _ => key,
    };
  }

  @override
  Future<void> close() async {
    try {
      await _object(_session)
          .callMethod('org.freedesktop.Secret.Session', 'Close', [],
              replySignature: DBusSignature(''))
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    if (_ownsClient) {
      try {
        await _client.close();
      } catch (_) {}
    }
  }
}
