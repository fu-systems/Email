import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/email_account.dart';
import '../services/database_service.dart';
import '../services/crypto_service.dart';
import '../services/oauth_service.dart';

/// Manages email accounts -- loading, saving, adding, removing.
/// Persists to SQLite via DataCache with encrypted credentials.
/// Handles OAuth token refresh for OAuth-authenticated accounts.
class AccountProvider extends ChangeNotifier {
  final DataCache _cache = DataCache.instance;
  CryptoService? _crypto;
  bool _isInitialized = false;
  String? _activeAccountId;

  bool get isInitialized => _isInitialized;
  List<EmailAccount> get accounts => _cache.accounts;

  EmailAccount? get activeAccount {
    if (_activeAccountId != null) return _cache.getAccount(_activeAccountId!);
    return accounts.isNotEmpty ? accounts.first : null;
  }

  AccountProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _cache.initialize();
      _crypto = await CryptoService.getInstance();

      // Decrypt secrets for in-memory accounts
      for (final account in _cache.accounts) {
        final decrypted = account.copyWith(
          password: account.password.isNotEmpty
              ? _crypto!.decrypt(account.password)
              : '',
          accessToken: account.accessToken != null
              ? _crypto!.decrypt(account.accessToken!)
              : null,
          refreshToken: account.refreshToken != null
              ? _crypto!.decrypt(account.refreshToken!)
              : null,
        );
        _cache.accountsMap[account.id] = decrypted;
      }

      if (accounts.isNotEmpty) {
        _activeAccountId = accounts.first.id;
      }
    } catch (e) {
      debugPrint('Error initializing accounts: $e');
    }
    _isInitialized = true;
    notifyListeners();
  }

  /// Encrypt sensitive fields before persisting to DB.
  Map<String, dynamic> _encryptedMap(EmailAccount account) {
    final encrypted = account.copyWith(
      password: account.password.isNotEmpty
          ? (_crypto?.encrypt(account.password) ?? account.password)
          : '',
      accessToken: account.accessToken != null
          ? (_crypto?.encrypt(account.accessToken!) ?? account.accessToken)
          : null,
      refreshToken: account.refreshToken != null
          ? (_crypto?.encrypt(account.refreshToken!) ?? account.refreshToken)
          : null,
    );
    return encrypted.toMap();
  }

  Future<void> addAccount(EmailAccount account) async {
    _cache.accountsMap[account.id] = account; // plaintext in memory
    _cache.db?.upsertAccount(_encryptedMap(account)); // encrypted in DB

    if (accounts.length == 1) {
      _activeAccountId = account.id;
    }
    notifyListeners();
  }

  Future<void> updateAccount(EmailAccount account) async {
    _cache.accountsMap[account.id] = account;
    _cache.db?.upsertAccount(_encryptedMap(account));
    notifyListeners();
  }

  Future<void> removeAccount(String id) async {
    _cache.removeAccount(id);
    if (_activeAccountId == id) {
      _activeAccountId = accounts.isNotEmpty ? accounts.first.id : null;
    }
    notifyListeners();
  }

  void setActiveAccount(String id) {
    _activeAccountId = id;
    notifyListeners();
  }

  String generateAccountId() => const Uuid().v4();

  // ─── OAuth Token Management ───────────────────────────────────────────

  /// Ensure the account has a valid access token.
  /// Refreshes the token if expired. Returns the updated account,
  /// or null if refresh fails.
  Future<EmailAccount?> ensureValidToken(EmailAccount account) async {
    if (!account.isOAuth) return account;
    if (!account.isTokenExpired) return account;
    if (account.refreshToken == null || account.oauthProvider == null) {
      return null;
    }

    try {
      final result = await OAuthService.refreshAccessToken(
        account.oauthProvider!,
        account.refreshToken!,
        account.emailAddress,
      );

      final updated = account.copyWith(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        tokenExpiry: result.expiry,
      );

      await updateAccount(updated);
      return updated;
    } catch (e) {
      debugPrint('Token refresh failed: $e');
      return null;
    }
  }
}
