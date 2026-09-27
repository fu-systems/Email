import 'dart:async';
import 'dart:typed_data';

import 'package:look_in/services/spell_checker.dart';
import 'package:look_in/services/system_clipboard.dart';

/// Tests don't use this computer's spelling program or clipboard; tests
/// that need them install fakes.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Spelling.detect = () async => null;
  SystemClipboard.instance = const EmptyClipboard();
  await testMain();
}

class EmptyClipboard implements SystemClipboard {
  const EmptyClipboard();

  @override
  Future<List<String>> types() async => const [];

  @override
  Future<Uint8List?> read(String type) async => null;

  @override
  Future<String?> readText(String type) async => null;
}
