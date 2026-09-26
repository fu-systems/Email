import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;

/// Encrypts account passwords before they are written to the database.
///
/// Passwords are encrypted with AES-256-GCM using a random 256-bit master
/// key stored in a separate key file that only the current user can read
/// (mode 0600). Keeping the key out of the database protects stored
/// passwords when the database is copied or backed up on its own; it cannot
/// protect against malware running as the same user.
class CredentialCipher {
  final enc.Key _key;

  CredentialCipher(Uint8List keyBytes) : _key = enc.Key(keyBytes) {
    if (keyBytes.length != 32) {
      throw ArgumentError('Master key must be 32 bytes');
    }
  }

  /// Creates a cipher with a fresh random key (used by tests).
  factory CredentialCipher.random() =>
      CredentialCipher(enc.Key.fromSecureRandom(32).bytes);

  static const _prefix = 'v1:';

  /// Encrypts [plainText]; the result embeds the random IV.
  String encrypt(String plainText) {
    final iv = enc.IV.fromSecureRandom(12);
    final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.gcm));
    final cipherText = encrypter.encrypt(plainText, iv: iv);
    return '$_prefix${iv.base64}:${cipherText.base64}';
  }

  /// Decrypts a value produced by [encrypt]. Returns null when the value is
  /// malformed or was encrypted with another key.
  String? decrypt(String? value) {
    if (value == null || !value.startsWith(_prefix)) return null;
    final parts = value.substring(_prefix.length).split(':');
    if (parts.length != 2) return null;
    try {
      final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.gcm));
      return encrypter.decrypt64(parts[1], iv: enc.IV.fromBase64(parts[0]));
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
    final key = enc.Key.fromSecureRandom(32).bytes;
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
