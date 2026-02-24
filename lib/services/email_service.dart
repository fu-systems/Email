import 'dart:async';
import 'package:enough_mail/enough_mail.dart' as enough;
import '../models/email_account.dart';
import '../models/email_message.dart';
import '../models/folder.dart';

/// Service for IMAP/SMTP email operations.
class EmailService {
  enough.ImapClient? _imapClient;
  enough.SmtpClient? _smtpClient;
  EmailAccount? _account;
  bool _isConnected = false;
  Timer? _idleTimer;

  bool get isConnected => _isConnected;
  EmailAccount? get account => _account;

  // ─── Connection Management ─────────────────────────────────────────

  Future<void> connect(EmailAccount account) async {
    _account = account;
    await _connectImap(account);
  }

  Future<void> _connectImap(EmailAccount account) async {
    try {
      _imapClient = enough.ImapClient(isLogEnabled: false);

      final isSecure = account.imapSecurity == ImapSecurity.ssl;
      await _imapClient!.connectToServer(
        account.imapHost,
        account.imapPort,
        isSecure: isSecure,
      );

      if (account.imapSecurity == ImapSecurity.starttls) {
        await _imapClient!.startTls();
      }

      await _imapClient!.login(account.username, account.password);
      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      rethrow;
    }
  }

  Future<enough.SmtpClient> _getSmtpClient() async {
    final account = _account;
    if (account == null) throw StateError('No account configured');

    _smtpClient = enough.SmtpClient(
      'look-in',
      isLogEnabled: false,
    );

    final isSecure = account.smtpSecurity == SmtpSecurity.ssl;
    await _smtpClient!.connectToServer(
      account.smtpHost,
      account.smtpPort,
      isSecure: isSecure,
    );

    if (account.smtpSecurity == SmtpSecurity.starttls) {
      await _smtpClient!.ehlo();
      await _smtpClient!.startTls();
    }

    await _smtpClient!.authenticate(
      account.username,
      account.password,
      enough.AuthMechanism.plain,
    );

    return _smtpClient!;
  }

  Future<void> disconnect() async {
    _idleTimer?.cancel();
    try {
      await _imapClient?.logout();
    } catch (_) {}
    try {
      await _smtpClient?.quit();
    } catch (_) {}
    _imapClient = null;
    _smtpClient = null;
    _isConnected = false;
  }

  // ─── Folder Operations ─────────────────────────────────────────────

  Future<List<MailFolder>> fetchFolders() async {
    _ensureConnected();
    final mailboxes = await _imapClient!.listMailboxes();
    return mailboxes.map((mb) => _mailboxToFolder(mb)).toList();
  }

  MailFolder _mailboxToFolder(enough.Mailbox mailbox) {
    final name = mailbox.name;
    final path = mailbox.path;
    return MailFolder(
      id: '${_account!.id}_$path',
      accountId: _account!.id,
      name: name,
      path: path,
      type: MailFolder.detectType(name),
      unreadCount: mailbox.messagesUnseen ?? 0,
      totalCount: mailbox.messagesExists ?? 0,
    );
  }

  // ─── Message Operations ────────────────────────────────────────────

  Future<List<EmailMessage>> fetchMessages(
    MailFolder folder, {
    int limit = 50,
    int offset = 0,
  }) async {
    _ensureConnected();
    final mailbox = await _imapClient!.selectMailbox(
      enough.Mailbox.setup(folder.path, folder.path, []),
    );

    final total = mailbox.messagesExists ?? 0;
    if (total == 0) return [];

    final end = total - offset;
    final start = (end - limit + 1).clamp(1, end);
    if (start > end) return [];

    final sequence = enough.MessageSequence.fromRange(start, end);
    final fetchResult = await _imapClient!.fetchMessages(
      sequence,
      '(FLAGS ENVELOPE BODY.PEEK[TEXT]<0.200>)',
    );

    return fetchResult.messages.reversed.map((msg) {
      return _mimeMessageToEmail(msg, folder);
    }).toList();
  }

  Future<EmailMessage> fetchFullMessage(
    MailFolder folder,
    EmailMessage message,
  ) async {
    _ensureConnected();
    await _imapClient!.selectMailbox(
      enough.Mailbox.setup(folder.path, folder.path, []),
    );

    final uid = message.uid;
    if (uid == null) return message;

    final sequence = enough.MessageSequence.fromId(uid, isUid: true);
    final fetchResult = await _imapClient!.uidFetchMessages(
      sequence,
      '(FLAGS ENVELOPE BODY[])',
    );

    if (fetchResult.messages.isEmpty) return message;
    return _mimeMessageToEmail(fetchResult.messages.first, folder);
  }

  EmailMessage _mimeMessageToEmail(
    enough.MimeMessage msg,
    MailFolder folder,
  ) {
    final envelope = msg.envelope;
    final from = envelope?.from?.firstOrNull;
    final uid = msg.uid;

    String? textBody;
    String? htmlBody;
    try {
      textBody = msg.decodeTextPlainPart();
      htmlBody = msg.decodeTextHtmlPart();
    } catch (_) {}

    final preview = textBody?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

    return EmailMessage(
      id: '${_account!.id}_${folder.path}_${uid ?? msg.sequenceId}',
      accountId: _account!.id,
      folderId: folder.id,
      subject: envelope?.subject ?? '(No Subject)',
      from: EmailAddress(
        address: from?.email ?? '',
        displayName: from?.personalName,
      ),
      to: (envelope?.to ?? [])
          .map((a) => EmailAddress(
                address: a.email,
                displayName: a.personalName,
              ))
          .toList(),
      cc: (envelope?.cc ?? [])
          .map((a) => EmailAddress(
                address: a.email,
                displayName: a.personalName,
              ))
          .toList(),
      date: envelope?.date ?? DateTime.now(),
      messageId: envelope?.messageId,
      inReplyTo: envelope?.inReplyTo,
      textBody: textBody,
      htmlBody: htmlBody,
      preview: preview.length > 200 ? preview.substring(0, 200) : preview,
      isRead: msg.flags?.contains(enough.MessageFlags.seen) ?? false,
      isFlagged: msg.flags?.contains(enough.MessageFlags.flagged) ?? false,
      isDraft: msg.flags?.contains(enough.MessageFlags.draft) ?? false,
      isDeleted: msg.flags?.contains(enough.MessageFlags.deleted) ?? false,
      hasAttachments: _hasAttachments(msg),
      uid: uid,
      sequenceNumber: msg.sequenceId,
    );
  }

  bool _hasAttachments(enough.MimeMessage msg) {
    try {
      final info = msg.findContentInfo();
      return info.any((ci) =>
          ci.disposition == enough.ContentDisposition.attachment ||
          (ci.disposition == enough.ContentDisposition.inline &&
              ci.mediaType?.top != enough.MediaToptype.text));
    } catch (_) {
      return false;
    }
  }

  // ─── Flag Operations ───────────────────────────────────────────────

  Future<void> markAsRead(MailFolder folder, int uid) async {
    _ensureConnected();
    await _imapClient!.selectMailbox(
      enough.Mailbox.setup(folder.path, folder.path, []),
    );
    await _imapClient!.uidStore(
      enough.MessageSequence.fromId(uid, isUid: true),
      [enough.MessageFlags.seen],
      action: enough.StoreAction.add,
    );
  }

  Future<void> markAsUnread(MailFolder folder, int uid) async {
    _ensureConnected();
    await _imapClient!.selectMailbox(
      enough.Mailbox.setup(folder.path, folder.path, []),
    );
    await _imapClient!.uidStore(
      enough.MessageSequence.fromId(uid, isUid: true),
      [enough.MessageFlags.seen],
      action: enough.StoreAction.remove,
    );
  }

  Future<void> toggleFlag(MailFolder folder, int uid, bool flagged) async {
    _ensureConnected();
    await _imapClient!.selectMailbox(
      enough.Mailbox.setup(folder.path, folder.path, []),
    );
    await _imapClient!.uidStore(
      enough.MessageSequence.fromId(uid, isUid: true),
      [enough.MessageFlags.flagged],
      action: flagged ? enough.StoreAction.add : enough.StoreAction.remove,
    );
  }

  // ─── Delete / Move ─────────────────────────────────────────────────

  Future<void> deleteMessage(MailFolder folder, int uid) async {
    _ensureConnected();
    await _imapClient!.selectMailbox(
      enough.Mailbox.setup(folder.path, folder.path, []),
    );
    await _imapClient!.uidStore(
      enough.MessageSequence.fromId(uid, isUid: true),
      [enough.MessageFlags.deleted],
      action: enough.StoreAction.add,
    );
    await _imapClient!.expunge();
  }

  Future<void> moveMessage(
    MailFolder fromFolder,
    MailFolder toFolder,
    int uid,
  ) async {
    _ensureConnected();
    await _imapClient!.selectMailbox(
      enough.Mailbox.setup(fromFolder.path, fromFolder.path, []),
    );
    await _imapClient!.uidMove(
      enough.MessageSequence.fromId(uid, isUid: true),
      targetMailbox: enough.Mailbox.setup(toFolder.path, toFolder.path, []),
    );
  }

  // ─── Send ──────────────────────────────────────────────────────────

  Future<void> sendMessage({
    required String from,
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    String? textBody,
    String? htmlBody,
    String? inReplyTo,
  }) async {
    final builder = enough.MessageBuilder.prepareMultipartAlternativeMessage()
      ..from = [enough.MailAddress(null, from)]
      ..to = to.map((a) => enough.MailAddress(null, a)).toList()
      ..cc = cc.map((a) => enough.MailAddress(null, a)).toList()
      ..bcc = bcc.map((a) => enough.MailAddress(null, a)).toList()
      ..subject = subject;

    if (inReplyTo != null) {
      builder.setHeader('In-Reply-To', inReplyTo);
    }

    if (textBody != null) {
      builder.addTextPlain(textBody);
    }
    if (htmlBody != null) {
      builder.addTextHtml(htmlBody);
    }

    final message = builder.buildMimeMessage();
    final smtpClient = await _getSmtpClient();
    try {
      await smtpClient.sendMessage(message);
    } finally {
      await smtpClient.quit();
      _smtpClient = null;
    }
  }

  // ─── Search ────────────────────────────────────────────────────────

  Future<List<int>> searchMessages(
    MailFolder folder,
    String query,
  ) async {
    _ensureConnected();
    await _imapClient!.selectMailbox(
      enough.Mailbox.setup(folder.path, folder.path, []),
    );

    final searchResult = await _imapClient!.searchMessages(
      searchCriteria:
          'OR OR SUBJECT "$query" FROM "$query" BODY "$query"',
    );

    return searchResult.matchingSequence?.toList() ?? [];
  }

  // ─── Helpers ───────────────────────────────────────────────────────

  void _ensureConnected() {
    if (!_isConnected || _imapClient == null) {
      throw StateError(
        'Not connected to IMAP server. Call connect() first.',
      );
    }
  }

  /// Test connection with the given account settings.
  static Future<String?> testConnection(EmailAccount account) async {
    final service = EmailService();
    try {
      await service.connect(account);
      await service.fetchFolders();
      await service.disconnect();
      return null; // Success
    } catch (e) {
      await service.disconnect();
      return e.toString();
    }
  }
}
