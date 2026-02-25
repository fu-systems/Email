import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// AES-256 credential encryption for storing passwords at rest.
///
/// Generates a random key on first run and persists it in the app's
/// support directory. Uses AES-CBC with PKCS7 padding.
class CryptoService {
  static CryptoService? _instance;
  late final enc.Key _key;
  static const int _keyLength = 32; // AES-256

  CryptoService._();

  static Future<CryptoService> getInstance() async {
    if (_instance != null) return _instance!;
    _instance = CryptoService._();
    await _instance!._loadOrCreateKey();
    return _instance!;
  }

  Future<void> _loadOrCreateKey() async {
    final dir = await getApplicationSupportDirectory();
    final keyFile = File(p.join(dir.path, '.look_in_key'));

    if (await keyFile.exists()) {
      final bytes = await keyFile.readAsBytes();
      if (bytes.length == _keyLength) {
        _key = enc.Key(Uint8List.fromList(bytes));
      } else {
        // Key file is corrupt or wrong length — regenerate
        final newKey = _generateKey();
        _key = enc.Key(newKey);
        await keyFile.writeAsBytes(newKey);
      }
    } else {
      // Generate a random 256-bit key
      final newKey = _generateKey();
      _key = enc.Key(newKey);
      await keyFile.writeAsBytes(newKey);
    }
  }

  static Uint8List _generateKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_keyLength, (_) => random.nextInt(256)),
    );
  }

  /// Encrypt a plaintext string. Returns base64-encoded "iv:ciphertext".
  String encrypt(String plaintext) {
    if (plaintext.isEmpty) return '';
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  /// Decrypt a string produced by [encrypt]. Returns the original plaintext.
  String decrypt(String encoded) {
    if (encoded.isEmpty) return '';
    final parts = encoded.split(':');
    if (parts.length != 2) return encoded; // Not encrypted, return as-is
    final iv = enc.IV.fromBase64(parts[0]);
    final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));
    return encrypter.decrypt64(parts[1], iv: iv);
  }
}
