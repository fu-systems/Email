import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Encrypts account passwords before they are written to the database.
///
/// Passwords are encrypted with AES-256-GCM using a random 256-bit master
/// key stored in a separate key file that only the current user can read
/// (mode 0600). Keeping the key out of the database protects stored
/// passwords when the database is copied or backed up on its own; it cannot
/// protect against malware running as the same user.
class CredentialCipher {
  final Uint8List _key;

  CredentialCipher(Uint8List keyBytes) : _key = Uint8List.fromList(keyBytes) {
    if (keyBytes.length != 32) {
      throw ArgumentError('Master key must be 32 bytes');
    }
  }

  /// Creates a cipher with a fresh random key (used by tests).
  factory CredentialCipher.random() => CredentialCipher(randomBytes(32));

  static const _prefix = 'v1:';

  /// Cryptographically secure random bytes.
  static Uint8List randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(length, (_) => random.nextInt(256)));
  }

  GCMBlockCipher _gcm(bool forEncryption, Uint8List iv) =>
      GCMBlockCipher(AESEngine())
        ..init(forEncryption,
            AEADParameters(KeyParameter(_key), 128, iv, Uint8List(0)));

  /// Encrypts [plainText] with AES-256-GCM: `v1:<iv>:<ciphertext+tag>`,
  /// both base64, with a random 96-bit IV.
  String encrypt(String plainText) {
    final iv = randomBytes(12);
    final sealed =
        _gcm(true, iv).process(Uint8List.fromList(utf8.encode(plainText)));
    return '$_prefix${base64.encode(iv)}:${base64.encode(sealed)}';
  }

  /// Decrypts a value produced by [encrypt]. Returns null when the value is
  /// malformed, was tampered with, or was encrypted with another key.
  String? decrypt(String? value) {
    if (value == null || !value.startsWith(_prefix)) return null;
    final parts = value.substring(_prefix.length).split(':');
    if (parts.length != 2) return null;
    try {
      final iv = base64.decode(parts[0]);
      final sealed = base64.decode(parts[1]);
      return utf8.decode(_gcm(false, iv).process(sealed));
    } catch (_) {
      return null;
    }
  }

  /// Loads the master key from [keyFile], creating it on first use.
  static Future<CredentialCipher> load(File keyFile) async {
    if (await keyFile.exists()) {
      try {
        final bytes = base64Decode((await keyFile.readAsString()).trim());
        if (bytes.length == 32) return CredentialCipher(bytes);
      } catch (_) {
        // Corrupt key file: fall through and create a new key. Stored
        // passwords then fail to decrypt and must be re-entered.
      }
    }
    final key = randomBytes(32);
    await keyFile.parent.create(recursive: true);
    // Create the file empty and restrict it before the key is written.
    await keyFile.writeAsString('', flush: true);
    await _restrictPermissions(keyFile);
    await keyFile.writeAsString(base64Encode(key), flush: true);
    return CredentialCipher(key);
  }

  static Future<void> _restrictPermissions(File file) async {
    try {
      await Process.run('chmod', ['600', file.path]);
    } catch (_) {
      // Not fatal: the file still lives in the user's private data dir.
    }
  }
}
