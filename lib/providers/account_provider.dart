import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/email_account.dart';
import '../services/database_service.dart';
import '../services/crypto_service.dart';

/// Manages email accounts -- loading, saving, adding, removing.
/// Persists to SQLite via DataCache with encrypted credentials.
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
      // Initialize the database-backed cache and crypto service
      await _cache.initialize();
      _crypto = await CryptoService.getInstance();

      // Decrypt passwords for in-memory accounts
      for (final account in _cache.accounts) {
        final decrypted = account.copyWith(
          password: _crypto!.decrypt(account.password),
        );
        // Update in-memory only (don't re-write to DB)
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

  Future<void> addAccount(EmailAccount account) async {
    // Store with encrypted password in DB, plaintext in memory
    final encrypted = account.copyWith(
      password: _crypto?.encrypt(account.password) ?? account.password,
    );
    _cache.accountsMap[account.id] = account; // plaintext in memory
    _cache.db?.upsertAccount(encrypted.toMap()); // encrypted in DB

    if (accounts.length == 1) {
      _activeAccountId = account.id;
    }
    notifyListeners();
  }

  Future<void> updateAccount(EmailAccount account) async {
    final encrypted = account.copyWith(
      password: _crypto?.encrypt(account.password) ?? account.password,
    );
    _cache.accountsMap[account.id] = account;
    _cache.db?.upsertAccount(encrypted.toMap());
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
}
