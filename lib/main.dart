import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'services/data_store.dart';
import 'services/oauth/oauth_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // For testing against a local identity server (see
  // test/support/fake_identity_server_main.dart).
  final loginBase = Platform.environment['LOOKIN_MS_LOGIN_BASE'];
  if (loginBase != null && loginBase.isNotEmpty) {
    OAuthProviderConfig.microsoftLoginBase = loginBase;
  }
  Object? startupError;
  try {
    await DataStore.initialize();
  } catch (e) {
    startupError = e;
  }
  runApp(startupError == null
      ? const LookInApp()
      : StartupErrorApp(error: startupError));
}
