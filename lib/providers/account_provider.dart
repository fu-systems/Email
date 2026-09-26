import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/email_account.dart';
import '../services/data_store.dart';

/// Manages the configured email accounts (persisted in the local database
/// with encrypted passwords).
class AccountProvider extends ChangeNotifier {
  final DataStore _store;

  AccountProvider({DataStore? store}) : _store = store ?? DataStore.instance;

  /// Accounts are loaded synchronously from the database at startup.
  bool get isInitialized => true;

  List<EmailAccount> get accounts => _store.accounts;

  EmailAccount? get defaultAccount =>
      accounts.where((a) => a.isDefault).firstOrNull ?? accounts.firstOrNull;

  /// Kept for compatibility with earlier code: the default account.
  EmailAccount? get activeAccount => defaultAccount;

  EmailAccount? byId(String id) => _store.getAccount(id);

  Future<void> addAccount(EmailAccount account) async {
    final isFirst = accounts.isEmpty;
    _store.saveAccount(account.copyWith(isDefault: isFirst || account.isDefault));
    if (account.isDefault && !isFirst) _makeOnlyDefault(account.id);
    notifyListeners();
  }

  Future<void> updateAccount(EmailAccount account) async {
    _store.saveAccount(account);
    if (account.isDefault) _makeOnlyDefault(account.id);
    notifyListeners();
  }

  Future<void> removeAccount(String id) async {
    final wasDefault = byId(id)?.isDefault ?? false;
    _store.removeAccount(id);
    if (wasDefault && accounts.isNotEmpty) {
      _store.saveAccount(accounts.first.copyWith(isDefault: true));
    }
    notifyListeners();
  }

  void setDefaultAccount(String id) {
    final account = byId(id);
    if (account == null) return;
    _store.saveAccount(account.copyWith(isDefault: true));
    _makeOnlyDefault(id);
    notifyListeners();
  }

  void _makeOnlyDefault(String id) {
    for (final a in accounts) {
      if (a.id != id && a.isDefault) {
        _store.saveAccount(a.copyWith(isDefault: false));
      }
    }
  }

  String generateAccountId() => const Uuid().v4();
}
