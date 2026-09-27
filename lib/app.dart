import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:provider/provider.dart';

import 'theme/outlook_theme.dart';
import 'providers/mail_provider.dart';
import 'providers/calendar_provider.dart';
import 'providers/contacts_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/account_provider.dart';
import 'screens/home_screen.dart';
import 'screens/settings/account_setup_screen.dart';
import 'services/data_store.dart';
import 'services/notification_service.dart';
import 'services/sync/graph_pim_sync.dart';

/// Material, widgets and editor (flutter_quill) localizations.
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  FlutterQuillLocalizations.delegate,
];

class LookInApp extends StatelessWidget {
  const LookInApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<NotificationService>(
          create: (_) => NotificationService(
            enabled: DataStore.instance
                .getBool('notifications', defaultValue: true),
          ),
          dispose: (_, service) => service.close(),
        ),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider(create: (_) => AccountProvider()),
        ChangeNotifierProvider(create: (_) => GraphPimSync()),
        ChangeNotifierProvider(
          create: (context) => MailProvider(
            notifications: context.read<NotificationService>(),
            pim: context.read<GraphPimSync>(),
          )..attachAccounts(context.read<AccountProvider>()),
        ),
        ChangeNotifierProvider(
          create: (context) => CalendarProvider(
            notifications: context.read<NotificationService>(),
            pim: context.read<GraphPimSync>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              ContactsProvider(pim: context.read<GraphPimSync>()),
        ),
      ],
      child: MaterialApp(
        title: 'Look In',
        debugShowCheckedModeBanner: false,
        theme: OutlookTheme.themeData,
        localizationsDelegates: appLocalizationsDelegates,
        home: const _AppRoot(),
        routes: {
          '/account-setup': (context) => const AccountSetupScreen(),
        },
      ),
    );
  }
}

class _AppRoot extends StatelessWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context) {
    final accountProvider = context.watch<AccountProvider>();

    if (accountProvider.accounts.isEmpty) {
      return const AccountSetupScreen(isFirstRun: true);
    }

    return const HomeScreen();
  }
}

/// Shown when the local database cannot be opened.
class StartupErrorApp extends StatelessWidget {
  final Object error;

  const StartupErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Look In',
      debugShowCheckedModeBanner: false,
      theme: OutlookTheme.themeData,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: OutlookTheme.flaggedColor, size: 28),
                    SizedBox(width: 12),
                    Text('Look In could not start',
                        style: OutlookTheme.readingPaneSubject),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'The local mail database could not be opened. Make sure '
                  'your data directory '
                  '(${DataStore.dataDirectory ?? '~/.local/share/systems.fu.look_in'}) '
                  'is writable and not used by another running copy of '
                  'Look In.',
                ),
                const SizedBox(height: 12),
                SelectableText(
                  '$error',
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: OutlookTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
