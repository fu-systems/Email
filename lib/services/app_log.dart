import 'dart:io';

import 'package:flutter/foundation.dart';

/// Appends uncaught errors to `look_in.log` in the app's data folder so
/// problems can be diagnosed when Look In is started from a desktop launcher
/// (where console output is not visible). The file is truncated when it
/// grows beyond 1 MB.
class AppLog {
  AppLog._();

  static File? _file;
  static const _maxBytes = 1024 * 1024;

  /// Starts logging to [directory] and installs global error handlers.
  static void install(String directory) {
    _file = File('$directory/look_in.log');
    try {
      if (_file!.existsSync() && _file!.lengthSync() > _maxBytes) {
        _file!.writeAsStringSync('');
      }
    } catch (_) {}

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      write('Flutter error: ${details.exceptionAsString()}', details.stack);
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      write('Uncaught error: $error', stack);
      return false;
    };
  }

  /// Writes a timestamped entry (and optional stack trace).
  static void write(String message, [StackTrace? stack]) {
    final file = _file;
    if (file == null) return;
    try {
      final buffer = StringBuffer()
        ..writeln('[${DateTime.now().toIso8601String()}] $message');
      if (stack != null) buffer.writeln(stack);
      file.writeAsStringSync(buffer.toString(),
          mode: FileMode.append, flush: true);
    } catch (_) {
      // Logging must never crash the app.
    }
  }
}
