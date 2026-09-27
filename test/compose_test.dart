import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/app.dart' show appLocalizationsDelegates;
import 'package:look_in/models/email_account.dart';
import 'package:look_in/models/email_message.dart';
import 'package:look_in/models/folder.dart';
import 'package:look_in/models/outgoing_message.dart';
import 'package:look_in/providers/contacts_provider.dart';
import 'package:look_in/providers/mail_provider.dart';
import 'package:look_in/screens/mail/compose_screen.dart';
import 'package:look_in/services/data_store.dart';
import 'package:look_in/services/notification_service.dart';
import 'package:look_in/theme/outlook_theme.dart';
import 'package:look_in/widgets/compose/format_controls.dart';
import 'package:provider/provider.dart';

const _account = EmailAccount(
  id: 'acc',
  displayName: 'Ann Example',
  emailAddress: 'ann@example.com',
  incomingHost: 'imap.example.com',
  incomingPort: 993,
  smtpHost: 'smtp.example.com',
  smtpPort: 587,
  username: 'ann',
  password: 'secret',
  isDefault: true,
  signatureHtml: '<div><b>Ann</b> Example</div>',
  signature: 'Ann Example',
);

void main() {
  late DataStore store;
  late MailProvider mail;

  setUp(() {
    store = DataStore.inMemory();
    DataStore.instance = store;
    store.setBool('workOffline', true);
    store.saveAccount(_account);
    store.saveFolders('acc', const [
      MailFolder(
          id: 'acc|INBOX',
          accountId: 'acc',
          name: 'INBOX',
          path: 'INBOX',
          type: FolderType.inbox),
    ]);
    mail = MailProvider(
        store: store, notifications: NotificationService(enabled: false));
    mail.updateAccounts(store.accounts, defaultAccountId: 'acc');
  });

  tearDown(() {
    mail.dispose();
    store.close();
  });

  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: mail),
        ChangeNotifierProvider(create: (_) => ContactsProvider(store: store)),
      ],
      child: MaterialApp(
        theme: OutlookTheme.themeData,
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => screen)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> focusEditor(WidgetTester tester) async {
    await tester.tap(find.byType(QuillEditor), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  QuillController quill(WidgetTester tester) =>
      tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

  testWidgets('formatted messages are sent as HTML with a text part',
      (tester) async {
    await open(tester, const ComposeScreen());
    expect(find.text('MESSAGE'), findsOneWidget);
    expect(find.text('FORMAT TEXT'), findsOneWidget);
    // The HTML signature is in the editor below two empty lines.
    expect(quill(tester).document.toPlainText(), '\n\nAnn Example\n');

    await tester.enterText(find.byType(TextField).first, 'bob@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'Budget');
    final controller = quill(tester);
    controller.updateSelection(
        const TextSelection.collapsed(offset: 0), ChangeSource.local);
    controller.replaceText(0, 0, 'See the numbers', null);
    controller.updateSelection(
        const TextSelection(baseOffset: 8, extentOffset: 15),
        ChangeSource.local);
    await tester.tap(find.byTooltip('Bold (Ctrl+B)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bullets'));
    await tester.pumpAndSettle();

    await ctrl(tester, LogicalKeyboardKey.enter);
    final sent = store.outbox.single;
    expect(sent.htmlBody, contains('<li>See the <strong>numbers</strong></li>'));
    expect(sent.htmlBody, contains('<strong>Ann</strong> Example'));
    expect(sent.htmlBody, contains('font-family: Calibri'));
    expect(sent.textBody, contains('See the numbers'));
    expect(sent.textBody, isNot(contains('<')));
    expect(jsonDecode(sent.editorDelta!), isA<List>());
  });

  testWidgets('replies keep the original HTML, tables included',
      (tester) async {
    final original = EmailMessage(
      id: 'acc|INBOX|7',
      accountId: 'acc',
      folderId: 'acc|INBOX',
      subject: 'Figures',
      from: const EmailAddress(address: 'bob@example.com', displayName: 'Bob'),
      to: const [EmailAddress(address: 'ann@example.com')],
      date: DateTime(2026, 3, 2, 9, 30),
      uid: 7,
      messageId: '<figures@example.com>',
      htmlBody: '<table><tr><td>Q1</td><td>42</td></tr></table>'
          '<script>evil()</script>',
      textBody: 'Q1 42',
    );
    store.saveFullMessage(original);
    await open(tester, ComposeScreen(mode: ComposeMode.reply, original: original));
    expect(find.text('Original message'), findsOneWidget);
    expect(find.text('Q1'), findsOneWidget, reason: 'the table is shown');

    await ctrl(tester, LogicalKeyboardKey.enter);
    final sent = store.outbox.single;
    expect(sent.subject, 'RE: Figures');
    expect(sent.inReplyTo, '<figures@example.com>');
    expect(sent.htmlBody, contains('id="lookin-quoted"'));
    expect(sent.htmlBody, contains('<td>Q1</td>'));
    expect(sent.htmlBody, isNot(contains('evil')));
    expect(sent.htmlBody, contains('<b>From:</b> Bob'));
    expect(sent.textBody, contains('-----Original Message-----'));
    expect(sent.quotedHtml, contains('<table>'));
  });

  testWidgets('plain text mode sends the text as written', (tester) async {
    await open(tester, const ComposeScreen());
    await tester.tap(find.text('FORMAT TEXT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plain\nText').first);
    await tester.pumpAndSettle();
    // The bold signature would lose its formatting: confirm.
    expect(find.textContaining('removes its formatting'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(QuillEditor), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'bob@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'Plain');
    await tester.enterText(find.byType(TextField).last, 'Just *text*');
    await ctrl(tester, LogicalKeyboardKey.enter);
    final sent = store.outbox.single;
    expect(sent.textBody, 'Just *text*');
    expect(sent.htmlBody, isNull, reason: 'generated from the text on sending');
    expect(sent.editorDelta, isNull);
  });

  testWidgets('an Outbox item reopens with its formatting', (tester) async {
    final delta = [
      {'insert': 'Hello '},
      {'insert': 'world', 'attributes': {'italic': true}},
      {'insert': '\n'},
    ];
    store.addToOutbox(OutgoingMessage(
      id: 'o1',
      accountId: 'acc',
      to: const [EmailAddress(address: 'bob@example.com')],
      subject: 'Queued',
      textBody: 'Hello world',
      htmlBody: '<div>Hello <em>world</em></div>',
      editorDelta: jsonEncode(delta),
      createdAt: DateTime(2026),
    ));
    final item = EmailMessage(
      id: 'outbox|o1',
      accountId: 'acc',
      folderId: 'acc|Outbox',
      subject: 'Queued',
      from: const EmailAddress(address: 'ann@example.com'),
      date: DateTime(2026),
    );
    await open(tester, ComposeScreen(mode: ComposeMode.editDraft, original: item));
    final doc = quill(tester).document;
    expect(doc.toPlainText(), 'Hello world\n');
    expect(doc.toDelta().toJson()[1]['attributes'], {'italic': true});
  });

  testWidgets('Ctrl+K in the message opens Insert Hyperlink', (tester) async {
    await open(tester, const ComposeScreen());
    await focusEditor(tester);
    await ctrl(tester, LogicalKeyboardKey.keyK);
    expect(find.text('Insert Hyperlink'), findsOneWidget);
  });

  testWidgets('pictures in the message are sent inline with a Content-ID',
      (tester) async {
    // A 1x1 transparent PNG.
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');
    final file = File('${Directory.systemTemp.createTempSync('pic').path}/dot.png')
      ..writeAsBytesSync(png);
    await open(tester, const ComposeScreen());
    await tester.enterText(find.byType(TextField).first, 'bob@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'Picture');
    TextFormatting.insertImage(quill(tester), file.path);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);

    await ctrl(tester, LogicalKeyboardKey.enter);
    final sent = store.outbox.single;
    final inline = sent.attachments.single;
    expect(inline.isInline, isTrue);
    expect(inline.localPath, file.path);
    expect(sent.htmlBody, contains('src="cid:${inline.contentId}"'));
    expect(sent.htmlBody, isNot(contains(file.path)),
        reason: 'local paths never leave the computer');
  });
}
