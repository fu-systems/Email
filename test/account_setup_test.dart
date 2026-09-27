import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/email_account.dart';
import 'package:look_in/providers/account_provider.dart';
import 'package:look_in/providers/mail_provider.dart';
import 'package:look_in/screens/settings/account_setup_screen.dart';
import 'package:look_in/services/data_store.dart';
import 'package:look_in/services/notification_service.dart';
import 'package:look_in/services/oauth/token_manager.dart';
import 'package:look_in/theme/outlook_theme.dart';
import 'package:provider/provider.dart';

void main() {
  late DataStore store;

  setUp(() {
    store = DataStore.inMemory();
    DataStore.instance = store;
    store.setBool('workOffline', true);
  });

  tearDown(() {
    TokenManager.instance = null;
    store.close();
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mail = MailProvider(
        store: store, notifications: NotificationService(enabled: false));
    addTearDown(mail.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AccountProvider(store: store)),
        ChangeNotifierProvider.value(value: mail),
      ],
      child: MaterialApp(theme: OutlookTheme.themeData, home: screen),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Outlook.com addresses sign in with Microsoft',
      (tester) async {
    await pump(tester, const AccountSetupScreen(isFirstRun: true));
    await tester.enterText(find.byType(TextField).at(1), 'ann@outlook.com');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Detected: Outlook.com'), findsOneWidget);
    // Microsoft Graph by default: no server settings to fill in.
    expect(find.text('Connect with:'), findsOneWidget);
    expect(find.byType(SegmentedButton<IncomingProtocol>), findsNothing);
    await tester.tap(find.text('IMAP and SMTP'));
    await tester.pumpAndSettle();
    final pop = tester.widget<SegmentedButton<IncomingProtocol>>(
        find.byType(SegmentedButton<IncomingProtocol>));
    expect(pop.segments.last.enabled, isFalse,
        reason: 'POP3 has no Microsoft sign-in');
    await tester.tap(find.text('Microsoft Graph'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Microsoft'), findsOneWidget);
    expect(find.text('Password'), findsNothing);

    // Next without signing in explains what's missing.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Microsoft to continue.'), findsOneWidget);

    // A password is still possible (e.g. on-premises Exchange).
    await tester.tap(find.text('Use a password instead'));
    await tester.pumpAndSettle();
    expect(find.text('Password'), findsOneWidget);
    await tester.tap(find.text('Sign in with Microsoft instead'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Microsoft'), findsOneWidget);
  });

  testWidgets('Account Settings of a Microsoft account show the sign-in',
      (tester) async {
    const account = EmailAccount(
      id: 'ms1',
      displayName: 'Ann',
      emailAddress: 'ann@contoso.com',
      incomingHost: 'outlook.office365.com',
      incomingPort: 993,
      smtpHost: 'smtp.office365.com',
      smtpPort: 587,
      username: 'ann@contoso.com',
      password: '',
      authMethod: AuthMethod.oauth2,
      oauthProvider: 'microsoft',
      oauthClientId: '11111111-2222-3333-4444-555555555555',
      oauthTenant: 'organizations',
    );
    store.saveAccount(account);
    store.setSecret(TokenManager.secretKey('ms1'),
        '{"provider":"microsoft","refreshToken":"r","username":"ann@contoso.com"}');
    await pump(tester, const AccountSetupScreen(accountId: 'ms1'));
    expect(
        find.text('Signed in with Microsoft as ann@contoso.com '
            '(IMAP and SMTP).'),
        findsOneWidget);
    expect(find.text('Sign in again or with another account'), findsOneWidget);
    expect(find.textContaining('organizations'), findsOneWidget);
    expect(find.text('Password'), findsNothing);

    // Switching to Microsoft Graph needs its permission: sign in again.
    await tester.tap(find.text('Microsoft Graph'));
    await tester.pumpAndSettle();
    expect(
        find.text('Signed in as ann@contoso.com. Sign in with Microsoft '
            'again so Look In may use Microsoft Graph.'),
        findsOneWidget);
    expect(find.text('Incoming mail server (IMAP)'), findsNothing);
  });

  testWidgets('A Graph account opens with Microsoft Graph chosen',
      (tester) async {
    const account = EmailAccount(
      id: 'ms2',
      displayName: 'Ann',
      emailAddress: 'ann@outlook.com',
      protocol: IncomingProtocol.graph,
      incomingHost: 'outlook.office365.com',
      incomingPort: 993,
      smtpHost: 'smtp.office365.com',
      smtpPort: 587,
      username: 'ann@outlook.com',
      password: '',
      authMethod: AuthMethod.oauth2,
      oauthProvider: 'microsoft',
      oauthClientId: '11111111-2222-3333-4444-555555555555',
    );
    store.saveAccount(account);
    store.setSecret(TokenManager.secretKey('ms2'),
        '{"provider":"microsoft","refreshToken":"r","resources":["graph"]}');
    await pump(tester, const AccountSetupScreen(accountId: 'ms2'));
    expect(
        find.text('Signed in with Microsoft as ann@outlook.com '
            '(Microsoft Graph).'),
        findsOneWidget);
    final choice = tester.widget<SegmentedButton<bool>>(
        find.byType(SegmentedButton<bool>));
    expect(choice.selected, {true});
  });
}
