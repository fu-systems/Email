import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/email_account.dart';
import 'package:look_in/models/email_message.dart';
import 'package:look_in/models/folder.dart';
import 'package:look_in/models/outgoing_message.dart';
import 'package:look_in/providers/mail_provider.dart';
import 'package:look_in/services/backends/graph_client.dart';
import 'package:look_in/services/backends/graph_mail_backend.dart';
import 'package:look_in/services/data_store.dart';
import 'package:look_in/services/mail_backend.dart';
import 'package:look_in/services/notification_service.dart';
import 'package:look_in/services/oauth/oauth_config.dart';
import 'package:look_in/services/oauth/token_manager.dart';

import 'support/fake_graph_server.dart';

/// Hands out "graph-token-N"; a forced refresh moves to the next one.
class FakeTokens extends TokenManager {
  FakeTokens(super.store);

  var _n = 1;
  var refreshes = 0;
  final resources = <OAuthResource>[];

  @override
  Future<String> accessToken(
    EmailAccount account, {
    OAuthResource resource = OAuthResource.outlookMail,
    bool forceRefresh = false,
  }) async {
    resources.add(resource);
    if (forceRefresh) {
      refreshes++;
      _n++;
    }
    return 'graph-token-$_n';
  }
}

const _account = EmailAccount(
  id: 'ms',
  displayName: 'Ann Example',
  emailAddress: 'ann@outlook.com',
  protocol: IncomingProtocol.graph,
  incomingHost: 'graph.microsoft.com',
  incomingPort: 443,
  smtpHost: 'graph.microsoft.com',
  smtpPort: 443,
  username: 'ann@outlook.com',
  password: '',
  authMethod: AuthMethod.oauth2,
  oauthProvider: 'microsoft',
  oauthClientId: '11111111-2222-3333-4444-555555555555',
  oauthTenant: 'common',
  syncIntervalMinutes: 60,
);

void main() {
  late FakeGraphServer graph;
  late DataStore store;
  late FakeTokens tokens;
  final originalBase = GraphClient.baseUrl;

  setUp(() async {
    graph = await FakeGraphServer.start();
    GraphClient.baseUrl = graph.baseUrl;
    store = DataStore.inMemory();
    DataStore.instance = store;
    tokens = FakeTokens(store);
    TokenManager.instance = tokens;
  });

  tearDown(() async {
    GraphClient.baseUrl = originalBase;
    TokenManager.instance = null;
    store.close();
    await graph.close();
  });

  group('GraphClient', () {
    GraphClient client() => GraphClient(
      ({bool forceRefresh = false}) =>
          tokens.accessToken(_account, forceRefresh: forceRefresh),
    );

    test('waits out throttling and retries', () async {
      graph.throttle = 2;
      final me = await client().getJson('/me');
      expect(me['mail'], 'ann@outlook.com');
      expect(
        graph.requests.where((r) => r.endsWith('(throttled)')),
        hasLength(2),
      );
    });

    test('gives up when Graph stays busy', () async {
      graph.throttle = 100;
      final busy = GraphClient(
        ({bool forceRefresh = false}) async => 't',
        maxRetries: 2,
      );
      await expectLater(
        busy.getJson('/me'),
        throwsA(isA<MailConnectionException>()),
      );
    });

    test('gets a new token once when one is refused', () async {
      graph.rejectedTokens.add('graph-token-1');
      await client().getJson('/me');
      expect(tokens.refreshes, 1);
      expect(graph.seenTokens, ['graph-token-1', 'graph-token-2']);

      graph.rejectedTokens.add('graph-token-2');
      graph.rejectedTokens.add('graph-token-3');
      await expectLater(
        client().getJson('/me'),
        throwsA(isA<MailAuthenticationException>()),
      );
    });

    test('explains errors and batches in groups of 20', () async {
      await expectLater(
        client().getJson('/me/mailFolders/nope'),
        throwsA(
          isA<GraphException>()
              .having((e) => e.status, 'status', 404)
              .having((e) => e.isNotFound, 'isNotFound', true),
        ),
      );
      expect(
        const GraphException(
          403,
          'ErrorAccessDenied',
          'Access is denied',
        ).toString(),
        contains('Mail.ReadWrite'),
      );

      final answers = await client().batch([
        for (var i = 0; i < 25; i++)
          const GraphBatchRequest('GET', '/me/mailFolders/inbox'),
      ]);
      expect(answers, hasLength(25));
      expect(answers.every((a) => a.ok), isTrue);
      expect(graph.requests.where((r) => r == r'POST /$batch'), hasLength(2));
    });
  });

  group('Graph mailbox through MailProvider', () {
    late MailProvider mail;

    Future<void> settle() async {
      for (var i = 0; i < 400; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final state = mail.connectionOf(_account.id);
        if (!mail.isSyncing &&
            state != AccountConnection.connecting &&
            state != AccountConnection.idle) {
          return;
        }
      }
    }

    MailFolder folder(FolderType type) => mail.folderByType(_account.id, type)!;

    List<EmailMessage> cached(FolderType type) =>
        store.getMessages(folder(type).id);

    EmailMessage bySubject(FolderType type, String subject) =>
        cached(type).firstWhere((m) => m.subject == subject);

    setUp(() async {
      final now = DateTime.now().toUtc();
      graph.addMessage(
        'inbox',
        fakeMime(subject: 'Welcome', body: 'First message'),
        received: now.subtract(const Duration(hours: 3)),
        isRead: true,
      );
      graph.addMessage(
        'inbox',
        fakeMime(subject: 'Budget', body: 'Numbers attached'),
        received: now.subtract(const Duration(hours: 2)),
        flagged: true,
      );
      graph.addMessage(
        'f-projects',
        fakeMime(subject: 'Roadmap'),
        received: now.subtract(const Duration(hours: 1)),
      );
      store.saveAccount(_account);
      mail = MailProvider(
        store: store,
        notifications: NotificationService(enabled: false),
      );
      mail.updateAccounts([_account], defaultAccountId: _account.id);
      await settle();
      expect(
        mail.connectionOf(_account.id),
        AccountConnection.online,
        reason: mail.accountError(_account.id),
      );
    });

    tearDown(() => mail.dispose());

    test('first sync: folders by type and the newest messages', () async {
      final folders = store.getFolders(_account.id);
      expect(
        {for (final f in folders) f.path: f.type},
        {
          'Inbox': FolderType.inbox,
          'Inbox/Projects': FolderType.other,
          'Drafts': FolderType.drafts,
          'Sent Items': FolderType.sent,
          'Deleted Items': FolderType.trash,
          'Junk Email': FolderType.spam,
          'Archive': FolderType.archive,
        },
        reason: "Graph's Outbox is replaced by Look In's",
      );
      expect(folder(FolderType.inbox).remoteId, 'f-inbox');
      expect(folder(FolderType.inbox).syncState, contains(r'$deltatoken='));
      expect(folder(FolderType.inbox).unreadCount, 1);

      final budget = bySubject(FolderType.inbox, 'Budget');
      expect(budget.isFlagged, isTrue);
      expect(budget.isRead, isFalse);
      expect(budget.remoteId, startsWith('msg-'));
      expect(budget.id, 'ms|Inbox|${budget.remoteId}');
      expect(budget.from.address, 'bob@example.com');
      // New messages are downloaded for reading offline.
      expect(store.withCachedBody(budget)?.textBody, contains('Numbers'));
      expect(tokens.resources.toSet(), {OAuthResource.graph});
    });

    test('changes on the server arrive with the delta link', () async {
      final welcome = graph
          .messagesIn('inbox')
          .firstWhere((m) => m.mime.contains('Welcome'));
      graph.remove(welcome.id);
      final budget = graph.messagesIn('inbox').single;
      graph.setRead(budget.id, true);
      graph.addMessage('inbox', fakeMime(subject: 'Lunch?'));

      await mail.syncAccount(_account.id);
      final subjects = cached(FolderType.inbox).map((m) => m.subject).toSet();
      expect(subjects, {'Budget', 'Lunch?'});
      expect(bySubject(FolderType.inbox, 'Budget').isRead, isTrue);
      expect(
        graph.requests.where((r) => r.contains('/messages/delta')),
        isNotEmpty,
      );
    });

    test('an expired delta link starts the folder over', () async {
      graph.expireDeltaLinks = true;
      graph.addMessage('inbox', fakeMime(subject: 'After expiry'));
      await mail.syncAccount(_account.id);
      final subjects = cached(FolderType.inbox).map((m) => m.subject).toList();
      expect(subjects..sort(), ['After expiry', 'Budget', 'Welcome']);
    });

    test('read, flag, move and delete reach the server', () async {
      final budget = bySubject(FolderType.inbox, 'Budget');
      await mail.selectMessage(budget);
      await mail.toggleFlag(bySubject(FolderType.inbox, 'Budget'));
      expect(mail.error, isNull);
      final server = graph.messages[budget.remoteId]!;
      expect(server.isRead, isTrue, reason: 'read when opened');
      expect(server.flagged, isFalse);

      final projects = store
          .getFolders(_account.id)
          .firstWhere((f) => f.path == 'Inbox/Projects');
      await mail.moveMessagesTo([
        bySubject(FolderType.inbox, 'Budget'),
      ], projects);
      expect(mail.error, isNull);
      expect(server.folderId, 'f-projects');
      final moved = store
          .getMessages(projects.id)
          .firstWhere((m) => m.subject == 'Budget');
      expect(moved.remoteId, budget.remoteId, reason: 'immutable ids');
      expect(moved.id, 'ms|Inbox/Projects|${budget.remoteId}');

      // Delete: to Deleted Items, then for good.
      await mail.deleteMessage(moved);
      expect(mail.error, isNull);
      expect(server.folderId, 'f-deleted');
      final trashed = bySubject(FolderType.trash, 'Budget');
      await mail.deleteMessage(trashed);
      expect(mail.error, isNull);
      expect(graph.messages.containsKey(budget.remoteId), isFalse);
      expect(graph.requests, contains(r'POST /$batch'));
    });

    test('sending uses sendMail, with Bcc, and files no copy itself', () async {
      final result = await mail.send(
        OutgoingMessage(
          id: 'out1',
          accountId: _account.id,
          to: const [EmailAddress(address: 'bob@example.com')],
          bcc: const [EmailAddress(address: 'carol@example.com')],
          subject: 'Hello from Graph',
          textBody: 'Sent without SMTP',
          createdAt: DateTime.now(),
        ),
      );
      expect(result, SendResult.sent, reason: mail.error);
      expect(graph.sent.single, contains('Subject: Hello from Graph'));
      expect(graph.sent.single, contains('carol@example.com'));
      // The only Sent Items copy is the one Exchange made.
      expect(graph.messagesIn('sentitems'), hasLength(1));
      expect(
        graph.requests.where(
          (r) => r.contains('f-sent/messages') && r.startsWith('POST'),
        ),
        isEmpty,
      );
    });

    test('large attachments go up in an upload session', () async {
      final dir = Directory.systemTemp.createTempSync('graph_send');
      final big = File('${dir.path}/video.mp4')
        ..writeAsBytesSync(List.filled(5 * 1024 * 1024 + 7, 42));
      final small = File('${dir.path}/notes.txt')..writeAsStringSync('notes');
      Attachment file(File f, String type) => Attachment(
        id: f.path,
        fileName: f.uri.pathSegments.last,
        mimeType: type,
        size: f.lengthSync(),
        localPath: f.path,
      );
      final result = await mail.send(
        OutgoingMessage(
          id: 'big',
          accountId: _account.id,
          to: const [EmailAddress(address: 'bob@example.com')],
          subject: 'The recording',
          textBody: 'Too big for one request',
          attachments: [file(big, 'video/mp4'), file(small, 'text/plain')],
          inReplyTo: '<thread@example.com>',
          createdAt: DateTime.now(),
        ),
      );
      expect(result, SendResult.sent, reason: mail.error);
      expect(graph.sent.single, contains('Subject: The recording'));
      expect(graph.sent.single, contains('In-Reply-To: <thread@example.com>'));
      expect(graph.sentAttachments.single, {
        'video.mp4': 5 * 1024 * 1024 + 7,
        'notes.txt': 5,
      });
      // Two chunks, and the token never went to the upload address.
      expect(graph.uploadAuthorization, [null, null]);
      expect(graph.messagesIn('drafts'), isEmpty);
      expect(graph.messagesIn('sentitems'), hasLength(1));
    });

    test('drafts are saved on the server and not duplicated', () async {
      final saved = await mail.saveDraft(
        OutgoingMessage(
          id: 'd1',
          accountId: _account.id,
          to: const [EmailAddress(address: 'bob@example.com')],
          subject: 'Unfinished',
          textBody: 'To be continued',
          createdAt: DateTime.now(),
        ),
      );
      final serverDraft = graph.messagesIn('drafts').single;
      expect(serverDraft.isDraft, isTrue);
      expect(saved.draftMessageId, 'ms|Drafts|${serverDraft.id}');

      await mail.syncAccount(_account.id, full: true);
      expect(
        cached(FolderType.drafts).where((m) => m.subject == 'Unfinished'),
        hasLength(1),
      );
    });

    test('server search and older messages', () async {
      await mail.selectFolder(folder(FolderType.inbox));
      mail.setSearchScope(SearchScope.currentFolder);
      mail.setSearchQuery('numbers');
      await mail.searchOnServer();
      expect(mail.error, isNull);
      expect(mail.messages.map((m) => m.subject), contains('Budget'));
      mail.setSearchQuery('');

      // More than the first sync's window: older ones come on request.
      final base = DateTime.now().toUtc().subtract(const Duration(days: 30));
      for (var i = 0; i < GraphMailBackend.initialWindow + 3; i++) {
        graph.addMessage(
          'archive',
          fakeMime(subject: 'Old $i'),
          received: base.add(Duration(minutes: i)),
          isRead: true,
        );
      }
      await mail.syncAccount(_account.id, full: true);
      final archive = folder(FolderType.archive);
      expect(
        store.getMessages(archive.id),
        hasLength(GraphMailBackend.initialWindow),
      );
      await mail.selectFolder(archive);
      expect(mail.canLoadOlder(archive), isTrue);
      await mail.loadOlderMessages();
      expect(
        store.getMessages(archive.id),
        hasLength(GraphMailBackend.initialWindow + 3),
      );
      expect(
        store.getMessages(archive.id).map((m) => m.subject),
        containsAll(['Old 0', 'Old 1', 'Old 2']),
      );
    });

    test('the connection test signs in to Graph', () async {
      expect(await testAccountConnection(_account), isNull);
      graph.rejectedTokens.addAll(['graph-token-1', 'graph-token-2']);
      tokens.refreshes = 0;
      final error = await testAccountConnection(_account);
      expect(error, startsWith('Microsoft Graph:'));
    });
  });
}
