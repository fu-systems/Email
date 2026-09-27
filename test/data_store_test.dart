import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/calendar_event.dart';
import 'package:look_in/models/contact.dart';
import 'package:look_in/models/email_account.dart';
import 'package:look_in/models/email_message.dart';
import 'package:look_in/models/folder.dart';
import 'package:look_in/models/mail_rule.dart';
import 'package:look_in/models/outgoing_message.dart';
import 'package:look_in/services/credential_store.dart';
import 'package:look_in/services/data_store.dart';
import 'package:look_in/services/database_service.dart';

EmailAccount _account({String id = 'a1', String password = 'hunter2'}) =>
    EmailAccount(
      id: id,
      displayName: 'Ann',
      emailAddress: 'ann@example.com',
      incomingHost: 'imap.example.com',
      incomingPort: 993,
      smtpHost: 'smtp.example.com',
      smtpPort: 587,
      username: 'ann@example.com',
      password: password,
      signature: 'Ann\nExample Corp',
    );

MailFolder _folder(String accountId, String path,
        {FolderType type = FolderType.other}) =>
    MailFolder(
      id: MailFolder.makeId(accountId, path),
      accountId: accountId,
      name: path,
      path: path,
      type: type,
    );

EmailMessage _message(String folderId, int uid,
        {String subject = 'Hello', String? body, DateTime? date}) =>
    EmailMessage(
      id: '$folderId|$uid',
      accountId: 'a1',
      folderId: folderId,
      subject: subject,
      from: const EmailAddress(address: 'bob@example.com', displayName: 'Bob'),
      to: const [EmailAddress(address: 'ann@example.com')],
      date: date ?? DateTime(2026, 1, uid),
      uid: uid,
      textBody: body,
      preview: body ?? '',
    );

void main() {
  group('CredentialCipher', () {
    test('decrypts values written by Look In 0.2 (encrypt package)', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));
      expect(
          CredentialCipher(key).decrypt(
              'v1:DbdyzVzSrIYHDvwN:mph45qFImuS3A5AjqZvKHJaq7LNqqxRkPXIm2mxlJCs='),
          'päss wörd 🔑');
    });

    test('round-trips and uses a random IV', () {
      final cipher = CredentialCipher.random();
      final a = cipher.encrypt('päss wörd');
      final b = cipher.encrypt('päss wörd');
      expect(a, isNot(b));
      expect(cipher.decrypt(a), 'päss wörd');
    });

    test('a different key or tampered value cannot decrypt', () {
      final value = CredentialCipher.random().encrypt('secret');
      expect(CredentialCipher.random().decrypt(value), isNull);
      final cipher = CredentialCipher.random();
      final good = cipher.encrypt('secret');
      final tampered = '${good.substring(0, good.length - 4)}AAAA';
      expect(cipher.decrypt(tampered), isNull);
      expect(cipher.decrypt('garbage'), isNull);
      expect(cipher.decrypt(null), isNull);
    });

    test('load creates a private key file and reuses it', () async {
      final dir = await Directory.systemTemp.createTemp('lookin_key_');
      final file = File('${dir.path}/sub/master.key');
      final first = await CredentialCipher.load(file);
      expect(await file.exists(), isTrue);
      final mode = (await file.stat()).mode & 0x1ff;
      expect(mode, 0x180, reason: 'key file must be 0600');
      final second = await CredentialCipher.load(file);
      expect(second.decrypt(first.encrypt('x')), 'x');
      await dir.delete(recursive: true);
    });
  });

  group('DataStore persistence', () {
    late Directory dir;
    late CredentialCipher cipher;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('lookin_db_');
      cipher = CredentialCipher.random();
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    DataStore open() =>
        DataStore(AppDatabase.open('${dir.path}/look_in.db'), cipher);

    test('everything survives a restart; passwords are encrypted', () async {
      var store = open();
      store.saveAccount(_account());
      final inbox = _folder('a1', 'INBOX', type: FolderType.inbox);
      store.saveFolders('a1', [inbox, _folder('a1', 'Work')]);
      store.saveFullMessage(
        _message(inbox.id, 1, body: 'body text'),
        source: Uint8List.fromList('raw source'.codeUnits),
      );
      store.putMessages(inbox.id, [_message(inbox.id, 2)]);
      final now = DateTime(2026, 2, 1);
      store.saveContact(Contact(
        id: 'c1',
        firstName: 'Bob',
        lastName: 'Builder',
        emails: const [ContactEmail(label: 'Email', address: 'bob@example.com')],
        createdAt: now,
        updatedAt: now,
      ));
      store.saveGroup(ContactGroup(
        id: 'g1',
        name: 'Team',
        memberIds: const ['c1'],
        createdAt: now,
        updatedAt: now,
      ));
      store.saveEvent(CalendarEvent(
        id: 'e1',
        title: 'Standup',
        startTime: DateTime(2026, 2, 2, 9),
        endTime: DateTime(2026, 2, 2, 9, 15),
        recurrence: RecurrenceRule.weekdays,
        createdAt: now,
        updatedAt: now,
      ));
      store.saveRules(const [
        MailRule(
          id: 'r1',
          name: 'News',
          conditions: [RuleCondition(field: RuleField.subject, value: 'news')],
          markAsRead: true,
        ),
      ]);
      store.addToOutbox(OutgoingMessage(
        id: 'o1',
        accountId: 'a1',
        to: const [EmailAddress(address: 'x@example.com')],
        subject: 'Queued',
        createdAt: now,
      ));
      store.setBool('workOffline', true);
      store.close();

      final raw = await File('${dir.path}/look_in.db').readAsBytes();
      expect(String.fromCharCodes(raw).contains('hunter2'), isFalse,
          reason: 'password stored in plain text');

      store = open();
      final account = store.accounts.single;
      expect(account.password, 'hunter2');
      expect(account.signature, 'Ann\nExample Corp');
      expect(store.getFolders('a1').first.type, FolderType.inbox,
          reason: 'folders sorted with Inbox first');
      final messages = store.getMessages(inbox.id);
      expect(messages.map((m) => m.uid), [2, 1], reason: 'newest first');
      expect(messages.last.hasBody, isFalse, reason: 'list excludes bodies');
      expect(store.withCachedBody(messages.last)!.textBody, 'body text');
      expect(String.fromCharCodes(store.getMessageSource(messages.last.id)!),
          'raw source');
      expect(store.contacts.single.displayName, 'Bob Builder');
      expect(store.groups.single.memberIds, ['c1']);
      expect(store.getOccurrencesForDate(DateTime(2026, 2, 3)), hasLength(1));
      expect(store.getOccurrencesForDate(DateTime(2026, 2, 7)), isEmpty,
          reason: 'Saturday is not a weekday');
      expect(store.rules.single.markAsRead, isTrue);
      expect(store.outbox.single.subject, 'Queued');
      expect(store.getBool('workOffline'), isTrue);
      store.close();
    });

    test('a lost key leaves accounts usable with an empty password', () {
      var store = open();
      store.saveAccount(_account());
      store.close();
      store = DataStore(
          AppDatabase.open('${dir.path}/look_in.db'), CredentialCipher.random());
      expect(store.accounts.single.password, '');
      store.close();
    });
  });

  group('DataStore behaviour', () {
    late DataStore store;
    final inbox = _folder('a1', 'INBOX', type: FolderType.inbox);
    final work = _folder('a1', 'Work');

    setUp(() {
      store = DataStore.inMemory();
      store.saveAccount(_account());
      store.saveFolders('a1', [inbox, work]);
    });

    tearDown(() => store.close());

    test('replacing folders drops messages of removed folders', () {
      store.putMessages(work.id, [_message(work.id, 1)]);
      store.saveFolders('a1', [inbox]);
      expect(store.getFolders('a1').map((f) => f.path), ['INBOX']);
      expect(store.getMessages(work.id), isEmpty);
      expect(store.getMessage('${work.id}|1'), isNull);
    });

    test('updating flags keeps the downloaded body', () {
      store.saveFullMessage(_message(inbox.id, 7, body: 'keep me'));
      final lean = store.getMessages(inbox.id).single;
      store.updateMessage(lean.copyWith(isRead: true));
      final again = store.getMessages(inbox.id).single;
      expect(again.isRead, isTrue);
      expect(store.withCachedBody(again)!.textBody, 'keep me');
    });

    test('search matches subject, sender and body across folders', () {
      store.saveFullMessage(
          _message(inbox.id, 1, subject: 'Invoice 42', body: 'pay soon'));
      store.saveFullMessage(
          _message(work.id, 2, subject: 'Lunch', body: 'the invoice is attached'));
      expect(store.searchMessages('invoice').map((m) => m.uid).toSet(), {1, 2});
      expect(store.searchMessages('invoice', folderId: work.id).single.uid, 2);
      expect(store.searchMessages('bob').length, 2);
      expect(store.searchMessages('100%'), isEmpty,
          reason: 'LIKE wildcards are escaped');
      expect(store.searchMessages('invoice', accountIds: const []), isEmpty);
    });

    test('removing a contact removes it from groups', () {
      final now = DateTime.now();
      store.saveContact(Contact(id: 'c1', firstName: 'A', createdAt: now, updatedAt: now));
      store.saveContact(Contact(id: 'c2', firstName: 'B', createdAt: now, updatedAt: now));
      store.saveGroup(ContactGroup(
          id: 'g', name: 'G', memberIds: const ['c1', 'c2'], createdAt: now, updatedAt: now));
      store.removeContact('c1');
      expect(store.getGroup('g')!.memberIds, ['c2']);
      expect(store.contacts.map((c) => c.id), ['c2']);
    });

    test('removing an account removes its folders, messages and outbox', () {
      store.putMessages(inbox.id, [_message(inbox.id, 1)]);
      store.addToOutbox(OutgoingMessage(
          id: 'o', accountId: 'a1', createdAt: DateTime.now()));
      store.removeAccount('a1');
      expect(store.accounts, isEmpty);
      expect(store.getFolders('a1'), isEmpty);
      expect(store.getMessage('${inbox.id}|1'), isNull);
      expect(store.outbox, isEmpty);
    });
  });
}
