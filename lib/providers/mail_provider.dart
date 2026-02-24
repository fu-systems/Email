import 'package:flutter/material.dart';
import '../models/email_account.dart';
import '../models/email_message.dart';
import '../models/folder.dart';
import '../services/email_service.dart';
import '../services/database_service.dart';

/// State management for the Mail module.
class MailProvider extends ChangeNotifier {
  final DataCache _cache = DataCache.instance;
  final Map<String, EmailService> _services = {};

  // Current state
  MailFolder? _selectedFolder;
  EmailMessage? _selectedMessage;
  String? _activeAccountId;
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _error;
  String _searchQuery = '';

  // Getters
  MailFolder? get selectedFolder => _selectedFolder;
  EmailMessage? get selectedMessage => _selectedMessage;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get error => _error;
  String get searchQuery => _searchQuery;

  List<MailFolder> get folders =>
      _activeAccountId != null ? _cache.getFolders(_activeAccountId!) : [];

  List<EmailMessage> get messages {
    if (_selectedFolder == null) return [];
    var msgs = _cache.getMessages(_selectedFolder!.id);
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      msgs = msgs.where((m) {
        return m.subject.toLowerCase().contains(query) ||
            m.from.display.toLowerCase().contains(query) ||
            m.preview.toLowerCase().contains(query);
      }).toList();
    }
    return msgs;
  }

  int get unreadCount {
    if (_selectedFolder == null) return 0;
    return _cache
        .getMessages(_selectedFolder!.id)
        .where((m) => !m.isRead)
        .length;
  }

  int get totalInboxUnread {
    final inboxFolder = folders
        .where((f) => f.type == FolderType.inbox)
        .firstOrNull;
    if (inboxFolder == null) return 0;
    return _cache
        .getMessages(inboxFolder.id)
        .where((m) => !m.isRead)
        .length;
  }

  // ─── Account Management ────────────────────────────────────────────

  Future<void> connectAccount(EmailAccount account) async {
    _activeAccountId = account.id;
    final service = EmailService();
    _services[account.id] = service;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await service.connect(account);
      await refreshFolders();

      // Auto-select Inbox
      final inbox = folders.firstWhere(
        (f) => f.type == FolderType.inbox,
        orElse: () => folders.first,
      );
      await selectFolder(inbox);
    } catch (e) {
      _error = 'Connection failed: ${e.toString()}';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> disconnectAccount(String accountId) async {
    await _services[accountId]?.disconnect();
    _services.remove(accountId);
    if (_activeAccountId == accountId) {
      _activeAccountId = null;
      _selectedFolder = null;
      _selectedMessage = null;
    }
    notifyListeners();
  }

  EmailService? get _activeService =>
      _activeAccountId != null ? _services[_activeAccountId] : null;

  // ─── Folder Operations ─────────────────────────────────────────────

  Future<void> refreshFolders() async {
    final service = _activeService;
    if (service == null || _activeAccountId == null) return;

    try {
      final remoteFolders = await service.fetchFolders();
      _cache.saveFolders(_activeAccountId!, remoteFolders);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to fetch folders: $e';
      notifyListeners();
    }
  }

  Future<void> selectFolder(MailFolder folder) async {
    _selectedFolder = folder;
    _selectedMessage = null;
    _searchQuery = '';
    notifyListeners();
    await refreshMessages();
  }

  // ─── Message Operations ────────────────────────────────────────────

  Future<void> refreshMessages() async {
    if (_selectedFolder == null) return;
    final service = _activeService;
    if (service == null) return;

    _isSyncing = true;
    notifyListeners();

    try {
      final msgs = await service.fetchMessages(_selectedFolder!);
      _cache.saveMessages(_selectedFolder!.id, msgs);
    } catch (e) {
      _error = 'Failed to fetch messages: $e';
    }

    _isSyncing = false;
    notifyListeners();
  }

  Future<void> selectMessage(EmailMessage message) async {
    _selectedMessage = message;
    notifyListeners();

    // Auto-mark as read
    if (!message.isRead) {
      await markAsRead(message);
    }

    // Fetch full message body if needed
    if (message.textBody == null && message.htmlBody == null) {
      await _fetchFullMessage(message);
    }
  }

  Future<void> _fetchFullMessage(EmailMessage message) async {
    final service = _activeService;
    if (service == null || _selectedFolder == null) return;

    try {
      final full = await service.fetchFullMessage(_selectedFolder!, message);
      _cache.updateMessage(full);
      if (_selectedMessage?.id == message.id) {
        _selectedMessage = full;
        notifyListeners();
      }
    } catch (e) {
      print('Error fetching full message: $e');
    }
  }

  Future<void> markAsRead(EmailMessage message) async {
    final service = _activeService;
    if (service == null || _selectedFolder == null || message.uid == null) {
      return;
    }

    try {
      await service.markAsRead(_selectedFolder!, message.uid!);
      final updated = message.copyWith(isRead: true);
      _cache.updateMessage(updated);
      if (_selectedMessage?.id == message.id) {
        _selectedMessage = updated;
      }
      notifyListeners();
    } catch (e) {
      print('Error marking as read: $e');
    }
  }

  Future<void> markAsUnread(EmailMessage message) async {
    final service = _activeService;
    if (service == null || _selectedFolder == null || message.uid == null) {
      return;
    }

    try {
      await service.markAsUnread(_selectedFolder!, message.uid!);
      final updated = message.copyWith(isRead: false);
      _cache.updateMessage(updated);
      if (_selectedMessage?.id == message.id) {
        _selectedMessage = updated;
      }
      notifyListeners();
    } catch (e) {
      print('Error marking as unread: $e');
    }
  }

  Future<void> toggleFlag(EmailMessage message) async {
    final service = _activeService;
    if (service == null || _selectedFolder == null || message.uid == null) {
      return;
    }

    final newFlagged = !message.isFlagged;
    try {
      await service.toggleFlag(_selectedFolder!, message.uid!, newFlagged);
      final updated = message.copyWith(isFlagged: newFlagged);
      _cache.updateMessage(updated);
      if (_selectedMessage?.id == message.id) {
        _selectedMessage = updated;
      }
      notifyListeners();
    } catch (e) {
      print('Error toggling flag: $e');
    }
  }

  Future<void> deleteMessage(EmailMessage message) async {
    final service = _activeService;
    if (service == null || _selectedFolder == null || message.uid == null) {
      return;
    }

    try {
      await service.deleteMessage(_selectedFolder!, message.uid!);
      _cache.removeMessage(_selectedFolder!.id, message.id);
      if (_selectedMessage?.id == message.id) {
        _selectedMessage = null;
      }
      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete message: $e';
      notifyListeners();
    }
  }

  Future<void> moveMessage(EmailMessage message, MailFolder target) async {
    final service = _activeService;
    if (service == null || _selectedFolder == null || message.uid == null) {
      return;
    }

    try {
      await service.moveMessage(_selectedFolder!, target, message.uid!);
      _cache.removeMessage(_selectedFolder!.id, message.id);
      if (_selectedMessage?.id == message.id) {
        _selectedMessage = null;
      }
      notifyListeners();
    } catch (e) {
      _error = 'Failed to move message: $e';
      notifyListeners();
    }
  }

  // ─── Send ──────────────────────────────────────────────────────────

  Future<bool> sendMessage({
    required String from,
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    String? textBody,
    String? htmlBody,
    String? inReplyTo,
  }) async {
    final service = _activeService;
    if (service == null) return false;

    try {
      await service.sendMessage(
        from: from,
        to: to,
        cc: cc,
        bcc: bcc,
        subject: subject,
        textBody: textBody,
        htmlBody: htmlBody,
        inReplyTo: inReplyTo,
      );
      return true;
    } catch (e) {
      _error = 'Failed to send: $e';
      notifyListeners();
      return false;
    }
  }

  // ─── Search ────────────────────────────────────────────────────────

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
