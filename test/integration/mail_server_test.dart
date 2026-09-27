// Integration tests against a real IMAP/POP3/SMTP server.
//
// They expect GreenMail (https://greenmail-mail-test.github.io/) listening on
// 127.0.0.1 with its test ports (SMTP 3025, POP3 3110, IMAP 3143) and users
// alice/bob/carol@example.com with password "secret", logging in with the
// full address:
//
//   java -Dgreenmail.setup.test.all -Dgreenmail.hostname=127.0.0.1 \
//     -Dgreenmail.users=alice:secret@example.com,bob:secret@example.com,carol:secret@example.com \
//     -Dgreenmail.users.login=email -jar greenmail-standalone.jar
//
// When no server is reachable the tests are skipped.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/email_account.dart';
import 'package:look_in/models/email_message.dart';
import 'package:look_in/models/folder.dart';
import 'package:look_in/models/mail_rule.dart';
import 'package:look_in/models/outgoing_message.dart';
import 'package:look_in/providers/account_provider.dart';
import 'package:look_in/providers/mail_provider.dart';
import 'package:look_in/services/data_store.dart';
import 'package:look_in/services/mail_backend.dart';
import 'package:look_in/services/mime_converter.dart';
import 'package:look_in/services/notification_service.dart';
import 'package:look_in/services/oauth/oauth_config.dart';
import 'package:look_in/services/oauth/oauth_flow.dart';
import 'package:look_in/services/oauth/token_manager.dart';

import '../support/fake_identity_server.dart';

const _host = '127.0.0.1';

EmailAccount _account(String user,
        {IncomingProtocol protocol = IncomingProtocol.imap}) =>
    EmailAccount(
      id: '$user-${protocol.name}',
      displayName: '${user[0].toUpperCase()}${user.substring(1)} Example',
      emailAddress: '$user@example.com',
      protocol: protocol,
      incomingHost: _host,
      incomingPort: protocol == IncomingProtocol.imap ? 3143 : 3110,
      incomingSecurity: ConnectionSecurity.none,
      smtpHost: _host,
      smtpPort: 3025,
      smtpSecurity: ConnectionSecurity.none,
      username: '$user@example.com',
      password: 'secret',
    );

Future<bool> _serverAvailable() async {
  try {
    final socket = await Socket.connect(_host, 3143,
        timeout: const Duration(seconds: 1));
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// Unique subject so tests don't see each other's messages.
String _subject(String name) =>
    '$name ${DateTime.now().microsecondsSinceEpoch}';

Future<MailFolder> _inbox(ImapBackend backend) async {
  final folders = await backend.fetchFolders();
  return folders.firstWhere((f) => f.type == FolderType.inbox);
}

Future<List<EmailMessage>> _waitForSubject(
  ImapBackend backend,
  MailFolder folder,
  String subject,
) async {
  for (var i = 0; i < 40; i++) {
    final snapshot = await backend.syncFolder(folder, cachedUids: const {});
    final found = snapshot.messages.where((m) => m.subject == subject).toList();
    if (found.isNotEmpty) return found;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return const [];
}

Future<void> _send(
  EmailAccount from, {
  required List<EmailAddress> to,
  List<EmailAddress> cc = const [],
  List<EmailAddress> bcc = const [],
  required String subject,
  String body = 'Hello from Look In',
  List<Attachment> attachments = const [],
}) async {
  final message = OutgoingMessage(
    id: subject,
    accountId: from.id,
    to: to,
    cc: cc,
    bcc: bcc,
    subject: subject,
    textBody: body,
    attachments: attachments,
    createdAt: DateTime.now(),
  );
  final mime = await MimeConverter.buildMimeMessage(message, from);
  await SmtpSender.send(from, mime, message.allRecipients);
}

void main() {
  late bool available;

  setUpAll(() async {
    available = await _serverAvailable();
  });

  final alice = _account('alice');
  final bob = _account('bob');
  final carol = _account('carol');
  const bobAddress =
      EmailAddress(address: 'bob@example.com', displayName: 'Bob Example');
  const carolAddress = EmailAddress(address: 'carol@example.com');

  test('account test succeeds with valid and fails with invalid credentials',
      () async {
    if (!available) return markTestSkipped('no mail server');
    expect(await testAccountConnection(alice), isNull);
    final wrong = alice.copyWith(password: 'nope');
    expect(await testAccountConnection(wrong), contains('Login failed'));
    final unreachable = alice.copyWith(incomingPort: 1);
    expect(await testAccountConnection(unreachable), isNotNull);
  });

  test('send, sync, download body and attachment', () async {
    if (!available) return markTestSkipped('no mail server');
    final dir = await Directory.systemTemp.createTemp('lookin_test_');
    final file = File('${dir.path}/report.txt');
    await file.writeAsString('quarterly numbers ✓');
    final subject = _subject('Report');
    await _send(
      alice,
      to: [bobAddress],
      subject: subject,
      body: 'Please see the attached report.\n\nThanks, Alice',
      attachments: [
        Attachment(
          id: 'a',
          fileName: 'report.txt',
          mimeType: 'text/plain',
          size: await file.length(),
          localPath: file.path,
        ),
      ],
    );

    final backend = ImapBackend(bob);
    final inbox = await _inbox(backend);
    final found = await _waitForSubject(backend, inbox, subject);
    expect(found, hasLength(1));
    final header = found.single;
    expect(header.from.address, 'alice@example.com');
    expect(header.from.displayName, 'Alice Example');
    expect(header.isRead, isFalse);
    expect(header.hasAttachments, isTrue);

    final full = await backend.fetchFullMessage(inbox, header);
    expect(full, isNotNull);
    expect(full!.message.textBody, contains('attached report'));
    expect(full.message.htmlBody, contains('attached report'));
    final att = full.message.visibleAttachments.single;
    expect(att.fileName, 'report.txt');
    final bytes = MimeConverter.extractPart(full.source, att.id);
    expect(utf8.decode(bytes!), 'quarterly numbers ✓');
    await backend.disconnect();
  });

  test('Bcc recipients receive the message but are not disclosed', () async {
    if (!available) return markTestSkipped('no mail server');
    final subject = _subject('Secret');
    await _send(alice,
        to: [bobAddress], bcc: [carolAddress], subject: subject);

    final bobBackend = ImapBackend(bob);
    final bobInbox = await _inbox(bobBackend);
    final bobCopy = (await _waitForSubject(bobBackend, bobInbox, subject)).single;
    final source = (await bobBackend.fetchFullMessage(bobInbox, bobCopy))!.source;
    final raw = utf8.decode(source, allowMalformed: true);
    expect(raw.toLowerCase(), isNot(contains('carol@example.com')));

    final carolBackend = ImapBackend(carol);
    final carolInbox = await _inbox(carolBackend);
    expect(await _waitForSubject(carolBackend, carolInbox, subject), hasLength(1));
    await bobBackend.disconnect();
    await carolBackend.disconnect();
  });

  test('flags, folders, move, append and server search', () async {
    if (!available) return markTestSkipped('no mail server');
    final subject = _subject('Organize');
    await _send(alice, to: [bobAddress], subject: subject, body: 'zebra-token');

    final backend = ImapBackend(bob);
    final inbox = await _inbox(backend);
    final message = (await _waitForSubject(backend, inbox, subject)).single;

    await backend.setFlags(inbox, [message.uid!], seen: true, flagged: true);
    var again = (await _waitForSubject(backend, inbox, subject)).single;
    expect(again.isRead, isTrue);
    expect(again.isFlagged, isTrue);

    final uids = await backend.search(inbox, 'zebra-token');
    expect(uids, contains(message.uid));

    final folderName = 'Projects${DateTime.now().millisecondsSinceEpoch}';
    final folder = await backend.createFolder(folderName);
    expect((await backend.fetchFolders()).map((f) => f.path), contains(folder.path));

    await backend.moveMessages(inbox, folder, [message.uid!]);
    expect(await _waitForSubject(backend, folder, subject), hasLength(1));
    final inboxAfter = await backend.syncFolder(inbox, cachedUids: const {});
    expect(inboxAfter.messages.where((m) => m.subject == subject), isEmpty);

    final renamed = await backend.renameFolder(folder, '${folderName}X');
    expect((await backend.fetchFolders()).map((f) => f.path),
        contains(renamed.path));

    final appendSubject = _subject('Appended');
    final mime = await MimeConverter.buildMimeMessage(
      OutgoingMessage(
        id: 'x',
        accountId: bob.id,
        to: const [EmailAddress(address: 'alice@example.com')],
        subject: appendSubject,
        textBody: 'draft body',
        createdAt: DateTime.now(),
      ),
      bob,
    );
    await backend.appendMessage(renamed, mime.renderMessage(),
        flags: [r'\Seen', r'\Draft']);
    final appended = (await _waitForSubject(backend, renamed, appendSubject)).single;
    expect(appended.isDraft, isTrue);
    expect(appended.isRead, isTrue);

    await backend.deleteFolder(renamed);
    expect((await backend.fetchFolders()).map((f) => f.path),
        isNot(contains(renamed.path)));
    await backend.disconnect();
  });

  test('POP3 downloads new messages once', () async {
    if (!available) return markTestSkipped('no mail server');
    final popCarol = _account('carol', protocol: IncomingProtocol.pop3);
    final subject = _subject('Pop');
    await _send(alice, to: [carolAddress], subject: subject);
    final pop = Pop3Backend(popCarol);
    const inbox = MailFolder(
        id: 'carol|INBOX', accountId: 'carol-pop3', name: 'Inbox', path: 'INBOX');
    List<DownloadedMessage> first = const [];
    for (var i = 0; i < 40 && first.every((d) => d.message.subject != subject); i++) {
      first = await pop.fetchNewMessages(inbox, knownUids: const {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final mine = first.where((d) => d.message.subject == subject).single;
    expect(mine.message.popUid, isNotNull);
    final known = first.map((d) => d.message.popUid!).toSet();
    final second = await pop.fetchNewMessages(inbox, knownUids: known);
    expect(second.where((d) => d.message.subject == subject), isEmpty);
  });

  test('MailProvider: sync, read, flag, move, delete, rules, send', () async {
    if (!available) return markTestSkipped('no mail server');
    final store = DataStore.inMemory();
    final accounts = AccountProvider(store: store);
    final mail = MailProvider(
      store: store,
      notifications: NotificationService(enabled: false),
    );
    final dave = bob.copyWith(id: 'bob-provider');
    await accounts.addAccount(dave);
    mail.attachAccounts(accounts);

    final subject = _subject('Provider');
    await _send(alice, to: [bobAddress], subject: subject, body: 'provider body');

    // Wait for the initial connect + sync, then refresh until it arrives.
    EmailMessage? found;
    for (var i = 0; i < 50 && found == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await mail.syncAccount(dave.id);
      found = store
          .getMessages(MailFolder.makeId(dave.id, 'INBOX'))
          .where((m) => m.subject == subject)
          .firstOrNull;
    }
    expect(found, isNotNull, reason: mail.accountError(dave.id));
    expect(mail.connectionOf(dave.id), AccountConnection.online);

    final inbox = mail.folderByType(dave.id, FolderType.inbox)!;
    await mail.selectFolder(inbox);
    final listed = mail.messages.firstWhere((m) => m.subject == subject);
    await mail.selectMessage(listed);
    expect(mail.selectedMessage!.textBody, contains('provider body'));
    expect(mail.selectedMessage!.isRead, isTrue);

    await mail.toggleFlag();
    expect(mail.messages.firstWhere((m) => m.subject == subject).isFlagged,
        isTrue);

    // A rule that files future messages from Alice into a folder.
    final ruleFolder = 'FromAlice${DateTime.now().millisecondsSinceEpoch}';
    await mail.createFolder(dave.id, ruleFolder);
    final target = mail.folderByPath(dave.id, ruleFolder);
    expect(target, isNotNull);
    mail.saveRules([
      MailRule(
        id: 'r1',
        name: 'Alice',
        accountId: dave.id,
        conditions: const [
          RuleCondition(field: RuleField.from, value: 'alice@example.com'),
        ],
        moveToFolderPath: ruleFolder,
      ),
    ]);
    final ruleSubject = _subject('Ruled');
    await _send(alice, to: [bobAddress], subject: ruleSubject);
    var filed = false;
    for (var i = 0; i < 50 && !filed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await mail.syncAccount(dave.id);
      filed = store
          .getMessages(target!.id)
          .any((m) => m.subject == ruleSubject);
    }
    expect(filed, isTrue, reason: 'rule did not move the new message');
    mail.saveRules(const []);

    // Move the original message and delete it (to Deleted Items or expunge).
    await mail.moveMessage(target!, listed);
    expect(store.getMessages(inbox.id).any((m) => m.subject == subject), isFalse);
    expect(store.getMessages(target.id).any((m) => m.subject == subject), isTrue);

    // Send through the provider; the message arrives at Alice.
    final reply = _subject('Reply');
    final result = await mail.send(OutgoingMessage(
      id: 'out1',
      accountId: dave.id,
      to: const [EmailAddress(address: 'alice@example.com')],
      subject: reply,
      textBody: 'Thanks!',
      createdAt: DateTime.now(),
    ));
    expect(result, SendResult.sent, reason: mail.error);
    final aliceBackend = ImapBackend(alice);
    final aliceInbox = await _inbox(aliceBackend);
    expect(await _waitForSubject(aliceBackend, aliceInbox, reply), hasLength(1));
    await aliceBackend.disconnect();

    mail.dispose();
    store.close();
  });

  test('MailProvider queues mail in the Outbox when the server is down',
      () async {
    if (!available) return markTestSkipped('no mail server');
    final store = DataStore.inMemory();
    final mail = MailProvider(
      store: store,
      notifications: NotificationService(enabled: false),
    );
    final offline = bob.copyWith(
      id: 'offline',
      incomingPort: 1,
      smtpPort: 1,
    );
    store.saveAccount(offline);
    mail.updateAccounts([offline]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final result = await mail.send(OutgoingMessage(
      id: 'queued',
      accountId: offline.id,
      to: const [EmailAddress(address: 'alice@example.com')],
      subject: 'Later',
      textBody: 'queued',
      createdAt: DateTime.now(),
    ));
    expect(result, SendResult.queued);
    expect(store.outbox.single.subject, 'Later');
    expect(mail.foldersOf(offline.id).any((f) => f.type == FolderType.outbox),
        isTrue);
    expect(mail.connectionOf(offline.id), AccountConnection.offline);
    mail.dispose();
    store.close();
  });

  test('MailProvider holds a message in the Outbox until its time', () async {
    if (!available) return markTestSkipped('no mail server');
    final store = DataStore.inMemory();
    final mail = MailProvider(
      store: store,
      notifications: NotificationService(enabled: false),
    );
    store.saveAccount(bob);
    mail.updateAccounts([bob]);
    OutgoingMessage held(String id, String subject) => OutgoingMessage(
      id: id,
      accountId: bob.id,
      to: const [EmailAddress(address: 'alice@example.com')],
      subject: subject,
      textBody: 'Sent after a pause',
      createdAt: DateTime.now(),
      sendAfter: DateTime.now().add(const Duration(seconds: 2)),
    );

    // Undo: taken back before its time, it is never sent.
    final undone = _subject('Undone');
    expect(await mail.send(held('undo', undone)), SendResult.scheduled);
    expect(mail.cancelScheduled('undo')?.subject, undone);
    expect(store.outbox, isEmpty);

    final later = _subject('Held');
    expect(await mail.send(held('held', later)), SendResult.scheduled);
    expect(store.outbox.single.subject, later);
    for (var i = 0; i < 60 && store.outbox.isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(store.outbox, isEmpty, reason: store.outbox.firstOrNull?.lastError);
    expect(mail.cancelScheduled('held'), isNull);

    final aliceBackend = ImapBackend(alice);
    final aliceInbox = await _inbox(aliceBackend);
    expect(
      await _waitForSubject(aliceBackend, aliceInbox, later),
      hasLength(1),
    );
    final all = await aliceBackend.syncFolder(aliceInbox, cachedUids: const {});
    expect(all.messages.where((m) => m.subject == undone), isEmpty);
    await aliceBackend.disconnect();
    mail.dispose();
    store.close();
  });

  test('Microsoft-style sign-in: XOAUTH2 for IMAP and SMTP with refresh',
      () async {
    if (!available) return markTestSkipped('no mail server');
    // GreenMail accepts the user's password as an XOAUTH2 bearer token, so
    // the fake identity platform hands out "secret" as the access token.
    final idp = await FakeIdentityServer.start();
    OAuthProviderConfig.microsoftLoginBase = idp.base;
    final store = DataStore.inMemory();
    DataStore.instance = store;
    addTearDown(() async {
      OAuthProviderConfig.microsoftLoginBase =
          'https://login.microsoftonline.com';
      TokenManager.instance = null;
      store.close();
      await idp.close();
    });
    idp
      ..accessToken = 'secret'
      ..username = 'carol@example.com';

    final account = carol.copyWith(
      id: 'carol-oauth',
      password: '',
      authMethod: AuthMethod.oauth2,
      oauthProvider: 'microsoft',
      oauthClientId: '11111111-2222-3333-4444-555555555555',
      oauthTenant: 'common',
    );
    // Sign in as the app does, through the loopback redirect.
    final signIn = await OAuthFlow.start(
      OAuthProviderConfig.microsoft(const OAuthRegistration(
          clientId: '11111111-2222-3333-4444-555555555555')),
      scopes: OAuthResource.outlookMail.signInScopes,
      launch: idp.browse,
    );
    final tokens = await signIn.result;
    expect(tokens.username, 'carol@example.com');
    // Pretend the token is about to expire so the first use refreshes it.
    TokenManager.instance.saveSignIn(
      account.id,
      OAuthTokens(
        accessToken: 'stale',
        refreshToken: tokens.refreshToken,
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      ),
      resource: OAuthResource.outlookMail,
    );

    expect(await testAccountConnection(account), isNull);
    expect(idp.tokenRequests.last['grant_type'], 'refresh_token');

    final subject = _subject('OAuth');
    final mime = await MimeConverter.buildMimeMessage(
        OutgoingMessage(
          id: subject,
          accountId: account.id,
          to: const [carolAddress],
          subject: subject,
          textBody: 'sent with a token',
          createdAt: DateTime.now(),
        ),
        account);
    await SmtpSender.send(account, mime, const [carolAddress]);
    final backend = ImapBackend(account);
    final found = await _waitForSubject(backend, await _inbox(backend), subject);
    expect(found, hasLength(1));
    await backend.disconnect();

    // A revoked sign-in surfaces as an authentication problem.
    TokenManager.instance.saveSignIn(
      account.id,
      OAuthTokens(
        accessToken: 'stale',
        refreshToken: 'revoked',
        expiresAt: DateTime.now(),
      ),
      resource: OAuthResource.outlookMail,
    );
    idp.failRefreshWith = 'invalid_grant';
    await expectLater(ImapBackend(account).connect(),
        throwsA(isA<MailAuthenticationException>()));
  });
}
