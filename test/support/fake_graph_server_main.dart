// Runs a fake Microsoft Graph mailbox for manual testing:
//
//   dart run test/support/fake_graph_server_main.dart [port]
//
// then start Look In with LOOKIN_GRAPH_BASE set to the printed address (and
// LOOKIN_MS_LOGIN_BASE pointing at fake_identity_server_main.dart), and add
// an Outlook.com account with "Connect with: Microsoft Graph".
import 'dart:io';

import 'fake_graph_server.dart';

Future<void> main(List<String> args) async {
  final graph = await FakeGraphServer.start(
    port: args.isEmpty ? 0 : int.parse(args.first),
  );
  final now = DateTime.now().toUtc();
  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
  graph.addMessage(
    'inbox',
    fakeMime(
      subject: 'Welcome to your Microsoft mailbox',
      from: 'Microsoft Outlook <no-reply@microsoft.com>',
      body: 'Your mailbox is synced with Microsoft Graph.',
    ),
    received: ago(300),
    isRead: true,
  );
  graph.addMessage(
    'inbox',
    fakeMime(
      subject: 'Quarterly numbers',
      from: 'Bob Example <bob@example.com>',
      body: 'The Q3 figures are in. Can you review them before Friday?',
    ),
    received: ago(90),
    flagged: true,
  );
  graph.addMessage(
    'inbox',
    fakeMime(
      subject: 'Lunch on Thursday?',
      from: 'Carol Example <carol@example.com>',
      body: 'The new place on Main Street opens this week.',
    ),
    received: ago(20),
  );
  graph.addMessage(
    'f-projects',
    fakeMime(
      subject: 'Roadmap draft',
      from: 'Dave Example <dave@example.com>',
      body: 'First pass at next year\'s roadmap attached.',
    ),
    received: ago(600),
  );
  graph.addMessage(
    'sentitems',
    fakeMime(
      subject: 'RE: Budget',
      from: 'Ann Example <ann@outlook.com>',
      to: 'Bob Example <bob@example.com>',
      body: 'Looks good to me.',
    ),
    received: ago(1440),
    isRead: true,
  );
  stdout.writeln(graph.baseUrl);

  // Type a subject to deliver a new message to the inbox.
  stdin.listen((line) {
    final subject = String.fromCharCodes(line).trim();
    if (subject.isEmpty) return;
    graph.addMessage('inbox', fakeMime(subject: subject));
    stdout.writeln('delivered: $subject');
  });
  await ProcessSignal.sigterm.watch().first;
  await graph.close();
}
