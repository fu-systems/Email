import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme/outlook_theme.dart';
import 'providers/mail_provider.dart';
import 'providers/calendar_provider.dart';
import 'providers/contacts_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/account_provider.dart';
import 'screens/home_screen.dart';
import 'screens/settings/account_setup_screen.dart';

class LookInApp extends StatelessWidget {
  const LookInApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider(create: (_) => AccountProvider()),
        ChangeNotifierProvider(create: (_) => MailProvider()),
        ChangeNotifierProvider(create: (_) => CalendarProvider()),
        ChangeNotifierProvider(create: (_) => ContactsProvider()),
      ],
      child: MaterialApp(
        title: 'Look In',
        debugShowCheckedModeBanner: false,
        theme: OutlookTheme.themeData,
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

    if (!accountProvider.isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (accountProvider.accounts.isEmpty) {
      return const AccountSetupScreen(isFirstRun: true);
    }

    return const HomeScreen();
  }
}
