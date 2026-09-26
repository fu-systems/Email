import 'package:flutter/material.dart';

import 'app.dart';
import 'services/data_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
