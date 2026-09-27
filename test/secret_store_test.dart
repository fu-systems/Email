import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/email_account.dart';
import 'package:look_in/services/credential_store.dart';
import 'package:look_in/services/data_store.dart';
import 'package:look_in/services/database_service.dart';
import 'package:look_in/services/secret_store.dart';
import 'package:sqlite3/sqlite3.dart';

EmailAccount _account(String id, String password) => EmailAccount(
      id: id,
      displayName: 'Ann',
      emailAddress: '$id@example.com',
      incomingHost: 'imap.example.com',
      incomingPort: 993,
      smtpHost: 'smtp.example.com',
      smtpPort: 587,
      username: id,
      password: password,
    );

/// Keyring tests write to the running Secret Service, so they only run when
/// asked to (see tool/test_with_keyring.sh, which starts a throwaway
/// gnome-keyring on a private session bus).
final _keyringTests = Platform.environment['LOOKIN_KEYRING_TESTS'] == '1';
const _testApplication = 'systems.fu.look_in.test';

void main() {
  late Directory dir;
  late CredentialCipher cipher;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lookin_secrets_');
    cipher = CredentialCipher.random();
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  DataStore open() =>
      DataStore(AppDatabase.open('${dir.path}/look_in.db'), cipher);

  group('file secret store', () {
    test('passwords and tokens survive a restart, encrypted', () async {
      var store = open();
      store.saveAccount(_account('a1', 'hunter2'));
      store.setSecret('oauth:a1', '{"refresh_token":"rt-123"}');
      store.close();

      final raw = await File('${dir.path}/look_in.db').readAsBytes();
      final text = String.fromCharCodes(raw);
      expect(text.contains('hunter2'), isFalse);
      expect(text.contains('rt-123'), isFalse);

      store = open();
      expect(store.accounts.single.password, 'hunter2');
      expect(store.secret('oauth:a1'), '{"refresh_token":"rt-123"}');
      expect(store.secretStoreId, 'file');
      store.close();
    });

    test('removing an account deletes its secrets', () {
      var store = open();
      store.saveAccount(_account('a1', 'one'));
      store.saveAccount(_account('a2', 'two'));
      store.setSecret('oauth:a1', 'token');
      store.removeAccount('a1');
      store.close();
      store = open();
      expect(store.secret('password:a1'), isNull);
      expect(store.secret('oauth:a1'), isNull);
      expect(store.accounts.single.password, 'two');
      store.close();
    });

    test('clearing a password removes the secret', () {
      var store = open();
      store.saveAccount(_account('a1', 'one'));
      store.saveAccount(_account('a1', ''));
      store.close();
      store = open();
      expect(store.secret('password:a1'), isNull);
      store.close();
    });

    test('schema 1 databases move account passwords to the secrets table',
        () {
      // Turn a fresh database into the version-1 layout: no secrets table,
      // the encrypted password in accounts.secret.
      final path = '${dir.path}/look_in.db';
      AppDatabase.open(path).close();
      final legacy = sqlite3.open(path);
      legacy.execute('DROP TABLE secrets');
      legacy.execute(
          'INSERT INTO accounts (id, sort_order, data, secret) '
          'VALUES (?, 0, ?, ?)',
          [
            'a1',
            jsonEncode(_account('a1', '').toMap(includePassword: false)),
            cipher.encrypt('legacy-pass'),
          ]);
      legacy.userVersion = 1;
      legacy.close();

      final store = open();
      expect(store.accounts.single.password, 'legacy-pass');
      expect(store.secret('password:a1'), 'legacy-pass');
      store.close();

      final check = sqlite3.open(path);
      expect(check.userVersion, AppDatabase.schemaVersion);
      expect(check.select('SELECT secret FROM accounts').single['secret'],
          isNull);
      check.close();
    });
  });

  group('system keyring', () {
    Future<SecretServiceStore> connect() async {
      final store = await SecretServiceStore.connect(
          application: _testApplication);
      expect(store, isNotNull, reason: 'no Secret Service on the session bus');
      return store!;
    }

    test('write, read and delete', () async {
      final keyring = await connect();
      addTearDown(keyring.close);
      await keyring.write('password:t1', 'pässwörd');
      await keyring.write('password:t1', 'changed');
      await keyring.write('oauth:t1', '{"a":1}');
      final all = await keyring.readAll();
      expect(all['password:t1'], 'changed');
      expect(all['oauth:t1'], '{"a":1}');
      await keyring.delete('password:t1');
      await keyring.delete('oauth:t1');
      expect(await keyring.readAll(), isEmpty);
    });

    test('DataStore moves secrets to the keyring and back', () async {
      final store = open();
      addTearDown(store.close);
      store.saveAccount(_account('a1', 'hunter2'));
      store.setSecret('oauth:a1', 'token');

      await store.useSecretStore('keyring', connect: connect);
      expect(store.secretStoreId, 'keyring');
      expect(store.db.loadSecrets(), isEmpty,
          reason: 'file copies are removed');
      final keyring = await connect();
      addTearDown(keyring.close);
      expect(await keyring.readAll(),
          {'password:a1': 'hunter2', 'oauth:a1': 'token'});

      // Changes made while on the keyring are written there.
      store.saveAccount(_account('a1', 'new-pass'));
      await store.flushSecrets();
      expect((await keyring.readAll())['password:a1'], 'new-pass');

      await store.useSecretStore('file');
      expect(store.secretStoreId, 'file');
      expect(await keyring.readAll(), isEmpty);
      expect(FileSecretStore(store.db, cipher).readAllSync(),
          {'password:a1': 'new-pass', 'oauth:a1': 'token'});
    });
  }, skip: _keyringTests ? false : 'set LOOKIN_KEYRING_TESTS=1');
}
