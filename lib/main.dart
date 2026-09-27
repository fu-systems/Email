import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'services/backends/graph_client.dart';
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
  // And a local Microsoft Graph (test/support/fake_graph_server_main.dart).
  final graphBase = Platform.environment['LOOKIN_GRAPH_BASE'];
  if (graphBase != null && graphBase.isNotEmpty) {
    GraphClient.baseUrl = graphBase;
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
