import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/app.dart' show appLocalizationsDelegates;
import 'package:look_in/models/contact.dart';
import 'package:look_in/models/email_account.dart';
import 'package:look_in/models/email_message.dart';
import 'package:look_in/models/folder.dart';
import 'package:look_in/models/outgoing_message.dart';
import 'package:look_in/providers/contacts_provider.dart';
import 'package:look_in/providers/mail_provider.dart';
import 'package:look_in/screens/mail/compose_screen.dart';
import 'package:look_in/services/data_store.dart';
import 'package:look_in/services/notification_service.dart';
import 'package:look_in/services/rich_text_codec.dart';
import 'package:look_in/services/spell_checker.dart';
import 'package:look_in/services/system_clipboard.dart';
import 'package:look_in/theme/outlook_theme.dart';
import 'package:look_in/widgets/compose/format_controls.dart';
import 'package:provider/provider.dart';

import 'flutter_test_config.dart' show EmptyClipboard;
import 'spell_checker_test.dart' show FakeSpellingBackend;

/// A clipboard holding [formats] (MIME type to content).
class FakeClipboard implements SystemClipboard {
  final Map<String, List<int>> formats;
  FakeClipboard(this.formats);

  @override
  Future<List<String>> types() async => formats.keys.toList();

  @override
  Future<Uint8List?> read(String type) async {
    final data = formats[type];
    return data == null ? null : Uint8List.fromList(data);
  }

  @override
  Future<String?> readText(String type) async {
    final data = formats[type];
    return data == null ? null : utf8.decode(data);
  }
}

/// A 1x1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

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

  tearDown(() async {
    mail.dispose();
    store.close();
    SystemClipboard.instance = const EmptyClipboard();
    Spelling.detect = () async => null;
    await Spelling.reset(redetect: true);
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
    final file = File('${Directory.systemTemp.createTempSync('pic').path}/dot.png')
      ..writeAsBytesSync(_png);
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

  testWidgets('Esc closes the address suggestions before the window',
      (tester) async {
    store.saveContact(Contact(
      id: 'c1',
      firstName: 'Bob',
      lastName: 'Brown',
      emails: const [ContactEmail(label: 'Work', address: 'bob@example.com')],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ));
    await open(tester, const ComposeScreen());
    await tester.enterText(find.byType(TextField).first, 'bo');
    await tester.pumpAndSettle();
    expect(find.text('Bob Brown <bob@example.com>'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Bob Brown <bob@example.com>'), findsNothing);
    expect(find.text('Want to save your changes to this message?'),
        findsNothing);
    expect(find.byType(ComposeScreen), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Want to save your changes to this message?'),
        findsOneWidget);
  });

  group('sending later', () {
    Future<void> writeMessage(WidgetTester tester, String subject) async {
      await tester.enterText(find.byType(TextField).first, 'bob@example.com');
      await tester.enterText(find.byType(TextField).at(2), subject);
      quill(tester).replaceText(0, 0, 'Hello Bob', null);
      await tester.pump();
    }

    testWidgets('Undo brings a sent message back', (tester) async {
      mail.sendDelaySeconds = 10;
      await open(tester, const ComposeScreen());
      await writeMessage(tester, 'Undo me');
      await ctrl(tester, LogicalKeyboardKey.enter);

      final held = store.outbox.single;
      expect(held.sendAfter, isNotNull);
      expect(find.byType(ComposeScreen), findsNothing);
      expect(find.text('Sending...'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.outbox, isEmpty);
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(find.text('Undo me'), findsWidgets);
      expect(quill(tester).document.toPlainText(), startsWith('Hello Bob'));

      // It is a message being edited again: closing asks to save it.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.text('Want to save your changes to this message?'),
        findsOneWidget,
      );
    });

    testWidgets('a held message goes out when its time comes', (tester) async {
      mail.sendDelaySeconds = 5;
      await open(tester, const ComposeScreen());
      await writeMessage(tester, 'Soon');
      await ctrl(tester, LogicalKeyboardKey.enter);
      expect(store.outbox.single.lastError, isNull);
      expect(mail.messages, isEmpty);

      // Offline (see setUp): at its time it stays in the Outbox for the
      // next Send/Receive.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Sending...'), findsNothing);
      expect(store.outbox.single.lastError, 'Working offline');
      expect(
        mail.foldersOf('acc').where((f) => f.name == 'Outbox'),
        hasLength(1),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('an Outbox item is not sent while it is open',
        (tester) async {
      expect(
        await mail.send(OutgoingMessage(
          id: 'o2',
          accountId: 'acc',
          to: const [EmailAddress(address: 'bob@example.com')],
          subject: 'Held',
          textBody: 'Hello',
          createdAt: clock.now(),
          sendAfter: clock.now().add(const Duration(seconds: 5)),
        )),
        SendResult.scheduled,
      );
      final item = EmailMessage(
        id: 'outbox|o2',
        accountId: 'acc',
        folderId: 'acc|Outbox',
        subject: 'Held',
        from: const EmailAddress(address: 'ann@example.com'),
        date: DateTime(2026),
      );
      await open(tester,
          ComposeScreen(mode: ComposeMode.editDraft, original: item));

      await tester.pump(const Duration(seconds: 6));
      expect(store.outbox.single.lastError, isNull, reason: 'still open');

      // Closed unchanged: its time has come, so it goes out (here: offline).
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ComposeScreen), findsNothing);
      expect(store.outbox.single.lastError, 'Working offline');
    });

    testWidgets('Delay Delivery keeps the message until the chosen time', (
      tester,
    ) async {
      await open(tester, const ComposeScreen());
      await writeMessage(tester, 'Tomorrow');
      await tester.tap(find.text('OPTIONS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delay\nDelivery'));
      await tester.pumpAndSettle();
      expect(find.text('Do not deliver before'), findsOneWidget);
      expect(find.text('5:00 PM'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This message will be sent tomorrow at 5:00 PM. It waits in the '
          'Outbox until then.',
        ),
        findsOneWidget,
      );

      await ctrl(tester, LogicalKeyboardKey.enter);
      final held = store.outbox.single;
      expect(held.sendAfter!.hour, 17);
      expect(
        find.textContaining('will be sent tomorrow at 5:00 PM'),
        findsOneWidget,
      );
      final listed = mail.outboxItem(
        EmailMessage(
          id: 'outbox|${held.id}',
          accountId: 'acc',
          folderId: 'x',
          subject: '',
          from: const EmailAddress(address: 'ann@example.com'),
          date: DateTime(2026),
        ),
      );
      expect(listed, isNotNull);
      mail.removeFromOutbox(held.id);
      await tester.pumpAndSettle();
    });
  });

  group('drag and drop', () {
    Future<void> drop(
      WidgetTester tester,
      List<String> paths,
      Offset at,
    ) async {
      const codec = StandardMethodCodec();
      Future<void> send(String method, Object? args) =>
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'desktop_drop',
            codec.encodeMethodCall(MethodCall(method, args)),
            (_) {},
          );
      await send('entered', [at.dx, at.dy]);
      await tester.pump();
      expect(find.text('Drop files here to attach them'), findsOneWidget);
      await send('performOperation', paths);
      await tester.pumpAndSettle();
    }

    testWidgets('pictures on the message go in it; other files are attached', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('drop');
      final picture = File('${dir.path}/chart.png')..writeAsBytesSync(_png);
      final report = File('${dir.path}/report.txt')
        ..writeAsStringSync('numbers');
      await open(tester, const ComposeScreen());

      final body = tester.getCenter(find.byType(QuillEditor));
      await drop(tester, [picture.path, report.path], body);
      expect(find.text('Drop files here to attach them'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      expect(find.textContaining('report.txt'), findsOneWidget);

      // On the header fields, a picture is attached too.
      final to = tester.getCenter(find.byType(TextField).first);
      await drop(tester, [picture.path], to);
      expect(find.textContaining('chart.png'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('paste', () {
    testWidgets('formatted text keeps its paragraphs and bold', (tester) async {
      SystemClipboard.instance = FakeClipboard({
        'text/html': utf8.encode(
          '<meta charset="utf-8"><p>First line</p><p>Second '
          '<b>bold</b></p><script>x()</script>',
        ),
        'text/plain': utf8.encode('First line\nSecond bold'),
      });
      await open(tester, const ComposeScreen());
      await focusEditor(tester);
      quill(tester).updateSelection(
        const TextSelection.collapsed(offset: 0),
        ChangeSource.local,
      );
      await ctrl(tester, LogicalKeyboardKey.keyV);

      final doc = quill(tester).document;
      expect(doc.toPlainText(), startsWith('First line\nSecond bold\n'));
      final ops = doc.toDelta().toJson();
      expect(
        ops.any(
          (op) =>
              op['insert'] == 'bold' &&
              (op['attributes'] as Map?)?['bold'] == true,
        ),
        isTrue,
      );
      expect(doc.toPlainText(), isNot(contains('x()')));
    });

    testWidgets('a copied picture goes in the message', (tester) async {
      SystemClipboard.instance = FakeClipboard({'image/png': _png});
      await open(tester, const ComposeScreen());
      await focusEditor(tester);
      await ctrl(tester, LogicalKeyboardKey.keyV);
      final images = RichTextCodec.imageSources(
        quill(tester).document.toDelta().toJson().cast(),
      );
      expect(images, hasLength(1));
      expect(images.single, endsWith('.png'));
      expect(File(images.single).readAsBytesSync(), _png);
    });
  });

  group('spelling', () {
    late FakeSpellingBackend backend;

    setUp(() async {
      backend = FakeSpellingBackend({
        'Helo': ['Hello', 'Help'],
        'wrld': ['world'],
      });
      Spelling.detect = () async =>
          const SpellingSetup('/usr/bin/hunspell', ['en_US']);
      Spelling.startBackend = (_, _) async => backend;
      await Spelling.reset(redetect: true);
    });

    bool underlined(WidgetTester tester, String word) {
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        var found = false;
        rich.text.visitChildren((span) {
          if (span is TextSpan &&
              span.text == word &&
              span.style?.decorationStyle == TextDecorationStyle.wavy) {
            found = true;
          }
          return !found;
        });
        if (found) return true;
      }
      return false;
    }

    testWidgets('misspelled words are underlined and F7 corrects them', (
      tester,
    ) async {
      await open(tester, const ComposeScreen());
      quill(tester).replaceText(0, 0, 'Helo wrld', null);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(underlined(tester, 'Helo'), isTrue);
      expect(underlined(tester, 'wrld'), isTrue);

      await focusEditor(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pumpAndSettle();
      expect(find.text('Spelling: English (United States)'), findsOneWidget);
      expect(find.text('Help'), findsOneWidget);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      // Next: "wrld", with "world" suggested.
      await tester.tap(find.text('Ignore All'));
      await tester.pumpAndSettle();
      expect(find.text('The spelling check is complete.'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(quill(tester).document.toPlainText(), startsWith('Hello wrld'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(underlined(tester, 'wrld'), isFalse);
    });

    testWidgets('spelling is checked before sending when asked', (
      tester,
    ) async {
      store.setBool(Spelling.beforeSendKey, true);
      await open(tester, const ComposeScreen());
      await tester.enterText(find.byType(TextField).first, 'bob@example.com');
      await tester.enterText(find.byType(TextField).at(2), 'Check');
      quill(tester).replaceText(0, 0, 'Helo', null);
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.enter);
      expect(find.text('Not in Dictionary:'), findsOneWidget);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(find.text('The spelling check is complete.'), findsNothing);
      expect(store.outbox.single.textBody, startsWith('Hello'));
    });
  });
}
