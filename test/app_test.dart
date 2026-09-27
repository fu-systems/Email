import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/app.dart';
import 'package:look_in/models/email_account.dart';
import 'package:look_in/models/email_message.dart';
import 'package:look_in/models/folder.dart';
import 'package:look_in/services/data_store.dart';

/// Whole-app smoke tests with an offline account and cached mail.
void main() {
  late DataStore store;

  setUp(() {
    store = DataStore.inMemory();
    DataStore.instance = store;
    store.setBool('workOffline', true);
    store.setBool('notifications', false);
    store.saveAccount(const EmailAccount(
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
    ));
    const inbox = MailFolder(
      id: 'acc|INBOX',
      accountId: 'acc',
      name: 'INBOX',
      path: 'INBOX',
      type: FolderType.inbox,
      unreadCount: 1,
      totalCount: 2,
    );
    store.saveFolders('acc', const [
      inbox,
      MailFolder(id: 'acc|Archive', accountId: 'acc', name: 'Archive', path: 'Archive'),
    ]);
    store.saveFullMessage(EmailMessage(
      id: 'acc|INBOX|1',
      accountId: 'acc',
      folderId: inbox.id,
      subject: 'Budget spreadsheet',
      from: const EmailAddress(address: 'bob@example.com', displayName: 'Bob Brown'),
      to: const [EmailAddress(address: 'ann@example.com')],
      date: DateTime.now().subtract(const Duration(hours: 1)),
      uid: 1,
      textBody: 'Attached is the budget for next year.',
      preview: 'Attached is the budget for next year.',
    ));
    store.saveFullMessage(EmailMessage(
      id: 'acc|INBOX|2',
      accountId: 'acc',
      folderId: inbox.id,
      subject: 'Q3 roadmap draft',
      from: const EmailAddress(address: 'carol@example.com', displayName: 'Carol Chen'),
      date: DateTime.now().subtract(const Duration(hours: 2)),
      uid: 2,
      isRead: true,
      textBody: 'Here is the roadmap.',
      preview: 'Here is the roadmap.',
    ));
  });

  tearDown(() => store.close());

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const LookInApp());
    await tester.pumpAndSettle();
  }

  testWidgets('shows cached mail offline and opens a message', (tester) async {
    await pumpApp(tester);
    expect(find.text('Budget spreadsheet'), findsWidgets);
    expect(find.textContaining('WORKING OFFLINE'), findsOneWidget);
    await tester.tap(find.text('Budget spreadsheet').first,
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.textContaining('Attached is the budget'), findsWidgets);
    expect(store.getMessage('acc|INBOX|1')!.isRead, isTrue,
        reason: 'selecting marks the message read');
  });

  testWidgets('Ctrl+E focuses search after clicking a message', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Budget spreadsheet').first,
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus;
    expect(
        focused?.context?.findAncestorStateOfType<EditableTextState>(),
        isNotNull,
        reason: 'primary focus: $focused');
    await tester.enterText(find.byType(TextField).first, 'roadmap');
    await tester.pumpAndSettle();
    expect(find.text('1 results'), findsOneWidget);
  });

  testWidgets('keyboard: arrows move the selection, Delete moves to trash',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Budget spreadsheet').first,
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.textContaining('Here is the roadmap.'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(store.getMessages('acc|INBOX').map((m) => m.subject),
        ['Budget spreadsheet']);
  });

  testWidgets('messages with the same date list newest UID first',
      (tester) async {
    final first = store.getMessage('acc|INBOX|1')!;
    store.saveFullMessage(EmailMessage(
      id: 'acc|INBOX|3',
      accountId: 'acc',
      folderId: first.folderId,
      subject: 'Arrived later',
      from: const EmailAddress(address: 'dan@example.com'),
      date: first.date,
      uid: 3,
      isRead: true,
      textBody: 'Same second.',
      preview: 'Same second.',
    ));
    await pumpApp(tester);
    expect(tester.getTopLeft(find.text('Arrived later').first).dy,
        lessThan(tester.getTopLeft(find.text('Budget spreadsheet').first).dy));
  });

  testWidgets('Ctrl+2 and Ctrl+3 switch modules', (tester) async {
    await pumpApp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Calendar - Look In'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('People - Look In'), findsOneWidget);
  });
}
