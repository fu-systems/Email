import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/email_account.dart';
import '../services/database_service.dart';

/// Manages email accounts -- loading, saving, adding, removing.
class AccountProvider extends ChangeNotifier {
  final DataCache _cache = DataCache.instance;
  bool _isInitialized = false;
  String? _activeAccountId;

  bool get isInitialized => _isInitialized;
  List<EmailAccount> get accounts => _cache.accounts;

  EmailAccount? get activeAccount {
    if (_activeAccountId != null) return _cache.getAccount(_activeAccountId!);
    return accounts.isNotEmpty ? accounts.first : null;
  }

  AccountProvider() {
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('accounts') ?? [];
      for (final json in raw) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        final account = EmailAccount.fromMap(map);
        _cache.saveAccount(account);
      }
      _activeAccountId = prefs.getString('activeAccountId');
    } catch (e) {
      print('Error loading accounts: $e');
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> addAccount(EmailAccount account) async {
    _cache.saveAccount(account);
    if (accounts.length == 1) {
      _activeAccountId = account.id;
    }
    await _persistAccounts();
    notifyListeners();
  }

  Future<void> updateAccount(EmailAccount account) async {
    _cache.saveAccount(account);
    await _persistAccounts();
    notifyListeners();
  }

  Future<void> removeAccount(String id) async {
    _cache.removeAccount(id);
    if (_activeAccountId == id) {
      _activeAccountId = accounts.isNotEmpty ? accounts.first.id : null;
    }
    await _persistAccounts();
    notifyListeners();
  }

  void setActiveAccount(String id) {
    _activeAccountId = id;
    notifyListeners();
  }

  String generateAccountId() => const Uuid().v4();

  Future<void> _persistAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = accounts.map((a) => jsonEncode(a.toMap())).toList();
    await prefs.setStringList('accounts', raw);
    if (_activeAccountId != null) {
      await prefs.setString('activeAccountId', _activeAccountId!);
    }
  }
}
