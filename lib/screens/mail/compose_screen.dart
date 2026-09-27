import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/email_account.dart';
import '../../models/email_message.dart';
import '../../models/outgoing_message.dart';
import '../../providers/contacts_provider.dart';
import '../../providers/mail_provider.dart';
import '../../services/file_dialogs.dart';
import '../../services/html_sanitizer.dart';
import '../../services/mime_converter.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';
import 'address_book_dialog.dart';

enum ComposeMode { newMessage, reply, replyAll, forward, editDraft }

/// Outlook 2013-style message window (new, reply, reply all, forward,
/// editing a draft or an Outbox item).
class ComposeScreen extends StatefulWidget {
  final ComposeMode mode;
  final EmailMessage? original;
  final List<EmailAddress> initialTo;
  final List<EmailAddress> initialCc;
  final String initialSubject;
  final String initialBody;
  final List<Attachment> initialAttachments;

  const ComposeScreen({
    super.key,
    this.mode = ComposeMode.newMessage,
    this.original,
    this.initialTo = const [],
    this.initialCc = const [],
    this.initialSubject = '',
    this.initialBody = '',
    this.initialAttachments = const [],
  });

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _toController = TextEditingController();
  final _ccController = TextEditingController();
  final _bccController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final _bodyFocus = FocusNode();
  final _toFocus = FocusNode();

  final List<Attachment> _attachments = [];
  EmailAccount? _account;
  MessageImportance _importance = MessageImportance.normal;
  bool _showBcc = false;
  bool _isSending = false;
  bool _isLoadingOriginal = false;
  String? _error;
  String? _draftMessageId;
  String? _outboxId;
  String _initialSnapshot = '';

  @override
  void initState() {
    super.initState();
    final mail = context.read<MailProvider>();
    _account = (widget.original != null
            ? mail.accountById(widget.original!.accountId)
            : null) ??
        mail.currentAccount;
    _showBcc = false;
    _prefill();
  }

  /// Whether the user changed anything since the message was opened or
  /// last saved (programmatic fills such as quoting reset the baseline).
  bool get _dirty => _snapshot() != _initialSnapshot;

  String _snapshot() => [
        _toController.text,
        _ccController.text,
        _bccController.text,
        _subjectController.text,
        _bodyController.text,
        _attachments.map((a) => a.localPath ?? a.id).join(','),
        _importance.name,
        _account?.id,
      ].join('\u0000');

  // ─── Prefill ───────────────────────────────────────────────────────

  void _prefill() {
    final original = widget.original;
    switch (widget.mode) {
      case ComposeMode.newMessage:
        _toController.text = _joinAddresses(widget.initialTo);
        _ccController.text = _joinAddresses(widget.initialCc);
        _subjectController.text = widget.initialSubject;
        _attachments.addAll(widget.initialAttachments);
        _bodyController.text = widget.initialBody.isNotEmpty
            ? widget.initialBody
            : _signatureBlock();
        break;
      case ComposeMode.reply:
      case ComposeMode.replyAll:
        _prefillReply(original!, all: widget.mode == ComposeMode.replyAll);
        break;
      case ComposeMode.forward:
        _subjectController.text = _prefixed(original!.subject, 'FW:');
        _bodyController.text = _signatureBlock();
        _loadOriginal(original, includeAttachments: true);
        break;
      case ComposeMode.editDraft:
        _prefillDraft(original!);
        break;
    }
    // Like Outlook, typing starts above the signature and quoted text.
    _bodyController.selection = const TextSelection.collapsed(offset: 0);
    _initialSnapshot = _snapshot();
  }

  void _prefillReply(EmailMessage original, {required bool all}) {
    final own = context
        .read<MailProvider>()
        .accounts
        .map((a) => a.emailAddress.toLowerCase())
        .toSet();
    bool notOwn(EmailAddress a) => !own.contains(a.address.toLowerCase());

    final to = <EmailAddress>[...original.replyAddresses];
    final cc = <EmailAddress>[];
    if (all) {
      to.addAll(original.to.where(notOwn));
      cc.addAll(original.cc.where(notOwn));
    }
    // When replying to our own sent message, reply to its recipients.
    final filteredTo = to.where(notOwn).toSet().toList();
    _toController.text = _joinAddresses(
        filteredTo.isEmpty ? original.to : filteredTo);
    _ccController.text =
        _joinAddresses(cc.where((a) => !filteredTo.contains(a)).toSet().toList());
    _subjectController.text = _prefixed(original.subject, 'RE:');
    _bodyController.text = _signatureBlock();
    _loadOriginal(original, includeAttachments: false);
  }

  void _prefillDraft(EmailMessage original) {
    final mail = context.read<MailProvider>();
    final outboxItem = mail.outboxItem(original);
    if (outboxItem != null) {
      _outboxId = outboxItem.id;
      _toController.text = _joinAddresses(outboxItem.to);
      _ccController.text = _joinAddresses(outboxItem.cc);
      _bccController.text = _joinAddresses(outboxItem.bcc);
      _showBcc = outboxItem.bcc.isNotEmpty;
      _subjectController.text = outboxItem.subject;
      _bodyController.text = outboxItem.textBody;
      _attachments.addAll(outboxItem.attachments);
      _importance = outboxItem.importance;
      _draftMessageId = outboxItem.draftMessageId;
      return;
    }
    _draftMessageId = original.id;
    _toController.text = _joinAddresses(original.to);
    _ccController.text = _joinAddresses(original.cc);
    _bccController.text = _joinAddresses(original.bcc);
    _showBcc = original.bcc.isNotEmpty;
    _subjectController.text =
        original.subject == '(No Subject)' ? '' : original.subject;
    _importance = original.importance;
    _isLoadingOriginal = true;
    mail.loadFullMessage(original).then((full) async {
      final attachments = await mail.materializeAttachments(full);
      if (!mounted) return;
      setState(() {
        _bodyController.text =
            full.textBody ?? htmlToPlainText(full.htmlBody ?? '');
        _attachments
          ..clear()
          ..addAll(attachments);
        _isLoadingOriginal = false;
        _initialSnapshot = _snapshot();
      });
    });
  }

  /// Downloads the original's body (and attachments for forwards) and
  /// appends the Outlook-style quoted original below the cursor area.
  void _loadOriginal(EmailMessage original, {required bool includeAttachments}) {
    final mail = context.read<MailProvider>();
    setState(() => _isLoadingOriginal = true);
    mail.loadFullMessage(original).then((full) async {
      final attachments = includeAttachments
          ? await mail.materializeAttachments(full)
          : const <Attachment>[];
      if (!mounted) return;
      final quote = _quotedOriginal(full);
      final wasDirty = _dirty;
      setState(() {
        _bodyController.text = '${_bodyController.text}$quote';
        _attachments.addAll(attachments);
        _isLoadingOriginal = false;
        if (!wasDirty) _initialSnapshot = _snapshot();
      });
      _bodyController.selection = const TextSelection.collapsed(offset: 0);
    });
  }

  String _signatureBlock() {
    final signature = _account?.signature?.trim();
    if (signature == null || signature.isEmpty) return '';
    return '\n\n$signature';
  }

  static String _prefixed(String subject, String prefix) {
    final clean = subject == '(No Subject)' ? '' : subject.trim();
    final pattern = RegExp('^${RegExp.escape(prefix)}\\s*', caseSensitive: false);
    final alt = prefix == 'FW:'
        ? RegExp(r'^fwd?:\s*', caseSensitive: false)
        : RegExp(r'^re:\s*', caseSensitive: false);
    if (pattern.hasMatch(clean) || alt.hasMatch(clean)) return clean;
    return '$prefix $clean';
  }

  static String _joinAddresses(List<EmailAddress> list) =>
      list.map((a) => a.toString()).join('; ');

  String _quotedOriginal(EmailMessage msg) {
    final body = msg.textBody?.trim().isNotEmpty == true
        ? msg.textBody!
        : htmlToPlainText(msg.htmlBody ?? '');
    final sent = DateFormat('EEEE, MMMM d, yyyy h:mm a').format(msg.date);
    final buffer = StringBuffer('\n\n')
      ..writeln('-----Original Message-----')
      ..writeln('From: ${msg.from}')
      ..writeln('Sent: $sent');
    if (msg.to.isNotEmpty) buffer.writeln('To: ${_joinAddresses(msg.to)}');
    if (msg.cc.isNotEmpty) buffer.writeln('Cc: ${_joinAddresses(msg.cc)}');
    buffer
      ..writeln('Subject: ${msg.subject}')
      ..writeln()
      ..write(body.trimRight());
    return buffer.toString();
  }

  @override
  void dispose() {
    for (final c in [
      _toController,
      _ccController,
      _bccController,
      _subjectController,
      _bodyController,
    ]) {
      c.dispose();
    }
    _bodyFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  // ─── Recipients ────────────────────────────────────────────────────

  /// Parses a recipient field, expanding contact group names.
  ({List<EmailAddress> valid, List<String> invalid}) _resolve(String text) {
    final contacts = context.read<ContactsProvider>();
    final valid = <EmailAddress>[];
    final invalid = <String>[];
    for (final token in EmailAddress.parseList(text)) {
      if (token.isValid) {
        valid.add(token);
        continue;
      }
      final group = contacts.groupByName(token.display);
      if (group != null) {
        valid.addAll(
            contacts.groupAddresses(group).map((a) => EmailAddress(address: a)));
        continue;
      }
      // A bare name matching exactly one contact resolves to that contact.
      final matches = contacts.allContacts
          .where((c) =>
              c.primaryEmail != null &&
              c.displayName.toLowerCase() == token.display.toLowerCase())
          .toList();
      if (matches.length == 1) {
        valid.add(EmailAddress(
            address: matches.first.primaryEmail!,
            displayName: matches.first.displayName));
      } else {
        invalid.add(token.toString());
      }
    }
    return (valid: valid.toSet().toList(), invalid: invalid);
  }

  /// "Check Names": resolves names and groups in all recipient fields.
  bool _checkNames({bool quiet = false}) {
    final problems = <String>[];
    for (final c in [_toController, _ccController, _bccController]) {
      final result = _resolve(c.text);
      problems.addAll(result.invalid);
      if (result.invalid.isEmpty) {
        c.text = _joinAddresses(result.valid);
      }
    }
    if (problems.isNotEmpty) {
      setState(() => _error =
          'Outlook does not recognize: ${problems.join(', ')}. '
          'Enter full email addresses.');
      return false;
    }
    if (!quiet) setState(() => _error = null);
    return true;
  }

  Future<void> _openAddressBook() async {
    final result = await showDialog<AddressBookSelection>(
      context: context,
      builder: (_) => const AddressBookDialog(),
    );
    if (result == null) return;
    void append(TextEditingController c, List<String> entries) {
      if (entries.isEmpty) return;
      final existing = c.text.trim();
      final joined = entries.join('; ');
      c.text = existing.isEmpty
          ? joined
          : '${existing.replaceFirst(RegExp(r'[;,]\s*$'), '')}; $joined';
    }

    append(_toController, result.to);
    append(_ccController, result.cc);
    if (result.bcc.isNotEmpty) setState(() => _showBcc = true);
    append(_bccController, result.bcc);
  }

  // ─── Attachments ───────────────────────────────────────────────────

  Future<void> _attachFiles() async {
    final paths = await FileDialogs.pickFiles(context, title: 'Insert File');
    if (paths.isEmpty || !mounted) return;
    setState(() {
      for (final path in paths) {
        final file = File(path);
        if (!file.existsSync()) continue;
        _attachments.add(Attachment(
          id: const Uuid().v4(),
          fileName: p.basename(path),
          mimeType: MimeConverter.guessMimeType(path),
          size: file.lengthSync(),
          localPath: path,
        ));
      }
    });
    final total = _attachments.fold<int>(0, (s, a) => s + a.size);
    if (total > 20 * 1024 * 1024 && mounted) {
      showStatusMessage(
        context,
        'Attachments total ${Attachment.formatBytes(total)}; many servers '
        'reject messages larger than 20 MB.',
      );
    }
  }

  void _insertSignature() {
    final signature = _account?.signature?.trim();
    if (signature == null || signature.isEmpty) {
      showStatusMessage(context,
          'No signature set. Add one in File > Account Settings.');
      return;
    }
    final sel = _bodyController.selection;
    final text = _bodyController.text;
    final offset = sel.isValid ? sel.start : text.length;
    final insert = '\n$signature\n';
    _bodyController.value = TextEditingValue(
      text: text.replaceRange(offset, sel.isValid ? sel.end : offset, insert),
      selection: TextSelection.collapsed(offset: offset + insert.length),
    );
  }

  // ─── Send / save ───────────────────────────────────────────────────

  OutgoingMessage? _buildMessage({bool requireRecipients = true}) {
    final account = _account;
    if (account == null) {
      setState(() => _error = 'Add an email account before sending.');
      return null;
    }
    final to = _resolve(_toController.text);
    final cc = _resolve(_ccController.text);
    final bcc = _resolve(_bccController.text);
    final invalid = [...to.invalid, ...cc.invalid, ...bcc.invalid];
    if (requireRecipients) {
      if (invalid.isNotEmpty) {
        setState(() => _error =
            'Outlook does not recognize: ${invalid.join(', ')}. '
            'Enter full email addresses.');
        return null;
      }
      if (to.valid.isEmpty && cc.valid.isEmpty && bcc.valid.isEmpty) {
        setState(() => _error = 'There must be at least one name or '
            'contact group in the To, Cc, or Bcc box.');
        return null;
      }
    }
    final original = widget.original;
    final isReply = widget.mode == ComposeMode.reply ||
        widget.mode == ComposeMode.replyAll;
    final refs = [
      if (isReply && original?.references != null) original!.references!,
    ].join(' ');
    return OutgoingMessage(
      id: _outboxId ?? const Uuid().v4(),
      accountId: account.id,
      to: to.valid,
      cc: cc.valid,
      bcc: bcc.valid,
      subject: _subjectController.text.trim(),
      textBody: _bodyController.text,
      attachments: List.of(_attachments),
      inReplyTo: isReply ? original?.messageId : null,
      references: refs.isEmpty ? null : refs,
      importance: _importance,
      createdAt: DateTime.now(),
      draftMessageId: _draftMessageId,
    );
  }

  Future<void> _send() async {
    if (_isSending || _isLoadingOriginal) return;
    final message = _buildMessage();
    if (message == null) return;

    if (message.subject.isEmpty) {
      final ok = await showConfirmDialog(
        context,
        title: 'No Subject',
        message: 'Do you want to send this message without a subject?',
        confirmLabel: 'Send Anyway',
      );
      if (!ok || !mounted) return;
    }
    final mentionsAttachment = RegExp(r'\battach(ed|ment|ments)?\b', caseSensitive: false)
        .hasMatch(_bodyController.text.split('-----Original Message-----').first);
    if (mentionsAttachment && _attachments.isEmpty) {
      final ok = await showConfirmDialog(
        context,
        title: 'Attachment Reminder',
        message: 'You may have forgotten to attach a file. Send anyway?',
        confirmLabel: 'Send Anyway',
      );
      if (!ok || !mounted) return;
    }

    setState(() {
      _isSending = true;
      _error = null;
    });
    final mail = context.read<MailProvider>();
    if (_outboxId != null) mail.removeFromOutbox(_outboxId!);
    final result = await mail.send(message);
    if (!mounted) return;
    setState(() => _isSending = false);
    switch (result) {
      case SendResult.sent:
        _close(message: 'Message sent');
        break;
      case SendResult.queued:
        _close(message: 'You are offline. The message is in your Outbox and '
            'will be sent when you are back online.');
        break;
      case SendResult.failed:
        setState(() => _error = mail.error ?? 'The message could not be sent.');
        break;
    }
  }

  Future<bool> _saveDraft({bool closeAfter = false}) async {
    final message = _buildMessage(requireRecipients: false);
    if (message == null) return false;
    try {
      final saved = await context.read<MailProvider>().saveDraft(message);
      if (!mounted) return true;
      setState(() {
        _draftMessageId = saved.draftMessageId;
        _initialSnapshot = _snapshot();
      });
      if (closeAfter) {
        _close(message: 'Draft saved');
      } else {
        showStatusMessage(context, 'Saved to Drafts');
      }
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save the draft: $e');
      return false;
    }
  }

  void _close({String? message}) {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    navigator.pop();
    if (message != null) {
      messenger?.showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        width: 520,
      ));
    }
  }

  /// Outlook asks whether to save changes when closing an edited message.
  Future<void> _requestClose() async {
    if (!_dirty) {
      _close();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => OutlookDialog(
        title: 'Look In',
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: const Text("Don't Save"),
          ),
          ElevatedButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: const Text('Save'),
          ),
        ],
        child: const Text('Want to save your changes to this message?'),
      ),
    );
    if (!mounted) return;
    if (choice == 'save') {
      await _saveDraft(closeAfter: true);
    } else if (choice == 'discard') {
      _close();
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────

  String get _windowTitle {
    final subject = _subjectController.text.trim();
    return '${subject.isEmpty ? 'Untitled' : subject} - Message';
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<MailProvider>().accounts;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // Runs while the Navigator is busy; close afterwards.
        if (!didPop) Future.microtask(_requestClose);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              _saveDraft(),
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              _checkNames(),
          const SingleActivator(LogicalKeyboardKey.escape): _requestClose,
        },
        // No autofocus here: the To field (new message) or the body
        // (reply/forward) takes focus; shortcuts bubble up from there.
        child: Focus(
          child: Scaffold(
            body: Column(
              children: [
                _TitleStrip(
                  title: _windowTitle,
                  onClose: _requestClose,
                ),
                _ComposeRibbon(
                  isSending: _isSending,
                  importance: _importance,
                  onSend: _send,
                  onAttach: _attachFiles,
                  onSignature: _insertSignature,
                  onAddressBook: _openAddressBook,
                  onCheckNames: () {
                    if (_checkNames()) {
                      showStatusMessage(context, 'All names resolved');
                    }
                  },
                  onImportance: (value) => setState(() {
                    _importance =
                        _importance == value ? MessageImportance.normal : value;
                  }),
                  onSave: () => _saveDraft(),
                  onDiscard: () async {
                    if (!_dirty ||
                        await showConfirmDialog(context,
                            title: 'Discard Message',
                            message: 'Discard this message?',
                            confirmLabel: 'Discard',
                            destructive: true)) {
                      if (mounted) _close();
                    }
                  },
                ),
                if (_error != null)
                  _InfoBar(
                    text: _error!,
                    isError: true,
                    onDismiss: () => setState(() => _error = null),
                  ),
                if (_isLoadingOriginal)
                  const _InfoBar(text: 'Downloading the original message...'),
                if (_importance != MessageImportance.normal)
                  _InfoBar(
                    text: _importance == MessageImportance.high
                        ? 'This message will be sent with High importance.'
                        : 'This message will be sent with Low importance.',
                  ),
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: Column(
                      children: [
                        _HeaderFields(
                          accounts: accounts,
                          account: _account,
                          onAccountChanged: (a) =>
                              setState(() => _account = a),
                          onSend: _send,
                          isSending: _isSending,
                          toController: _toController,
                          ccController: _ccController,
                          bccController: _bccController,
                          subjectController: _subjectController,
                          toFocus: _toFocus,
                          showBcc: _showBcc,
                          onShowBcc: () => setState(() => _showBcc = true),
                          onAddressBook: _openAddressBook,
                          onSubjectChanged: () => setState(() {}),
                        ),
                        if (_attachments.isNotEmpty)
                          _AttachmentStrip(
                            attachments: _attachments,
                            onRemove: (a) =>
                                setState(() => _attachments.remove(a)),
                          ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            child: TextField(
                              controller: _bodyController,
                              focusNode: _bodyFocus,
                              autofocus: widget.mode != ComposeMode.newMessage,
                              maxLines: null,
                              expands: true,
                              keyboardType: TextInputType.multiline,
                              textAlignVertical: TextAlignVertical.top,
                              style: const TextStyle(
                                fontFamily: OutlookTheme.fontFamily,
                                fontFamilyFallback:
                                    OutlookTheme.fontFamilyFallback,
                                fontSize: 14,
                                height: 1.45,
                                color: OutlookTheme.textPrimary,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleStrip extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const _TitleStrip({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      color: OutlookTheme.primaryBlue,
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        children: [
          const Icon(Icons.mail_outline, size: 14, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: OutlookTheme.titleBarStyle,
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: 'Close (Esc)',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 14, color: Colors.white),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
          ),
        ],
      ),
    );
  }
}

class _InfoBar extends StatelessWidget {
  final String text;
  final bool isError;
  final VoidCallback? onDismiss;

  const _InfoBar({required this.text, this.isError = false, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFDE7E9) : const Color(0xFFFFF4CE),
        border: const Border(
            bottom: BorderSide(color: OutlookTheme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.info_outline,
              size: 14,
              color: isError
                  ? OutlookTheme.flaggedColor
                  : OutlookTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
          if (onDismiss != null)
            InkWell(
              onTap: onDismiss,
              child: const Icon(Icons.close,
                  size: 14, color: OutlookTheme.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _ComposeRibbon extends StatelessWidget {
  final bool isSending;
  final MessageImportance importance;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onSignature;
  final VoidCallback onAddressBook;
  final VoidCallback onCheckNames;
  final ValueChanged<MessageImportance> onImportance;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  const _ComposeRibbon({
    required this.isSending,
    required this.importance,
    required this.onSend,
    required this.onAttach,
    required this.onSignature,
    required this.onAddressBook,
    required this.onCheckNames,
    required this.onImportance,
    required this.onSave,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    Widget group(String label, List<Widget> children) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: children,
                ),
              ),
              Text(label, style: OutlookTheme.ribbonGroupLabel),
            ],
          ),
        );
    const separator = VerticalDivider(width: 9, indent: 6, endIndent: 6);

    return Container(
      height: 88,
      decoration: OutlookTheme.ribbonDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          group('Send', [
            _BigButton(
              icon: Icons.send,
              label: isSending ? 'Sending…' : 'Send',
              tooltip: 'Send (Ctrl+Enter)',
              onTap: isSending ? null : onSend,
            ),
          ]),
          separator,
          group('Names', [
            _BigButton(
              icon: Icons.contacts_outlined,
              label: 'Address\nBook',
              onTap: onAddressBook,
            ),
            _BigButton(
              icon: Icons.how_to_reg_outlined,
              label: 'Check\nNames',
              tooltip: 'Check Names (Ctrl+K)',
              onTap: onCheckNames,
            ),
          ]),
          separator,
          group('Include', [
            _BigButton(
              icon: Icons.attach_file,
              label: 'Attach\nFile',
              onTap: onAttach,
            ),
            _BigButton(
              icon: Icons.draw_outlined,
              label: 'Signature',
              onTap: onSignature,
            ),
          ]),
          separator,
          group('Tags', [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HoverButton(
                  icon: Icons.priority_high,
                  label: 'High Importance',
                  color: OutlookTheme.flaggedColor,
                  selected: importance == MessageImportance.high,
                  onTap: () => onImportance(MessageImportance.high),
                ),
                HoverButton(
                  icon: Icons.arrow_downward,
                  label: 'Low Importance',
                  selected: importance == MessageImportance.low,
                  onTap: () => onImportance(MessageImportance.low),
                ),
              ],
            ),
          ]),
          separator,
          group('Draft', [
            _BigButton(
              icon: Icons.save_outlined,
              label: 'Save',
              tooltip: 'Save to Drafts (Ctrl+S)',
              onTap: onSave,
            ),
            _BigButton(
              icon: Icons.delete_outline,
              label: 'Discard',
              onTap: onDiscard,
            ),
          ]),
        ],
      ),
    );
  }
}

class _BigButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onTap;

  const _BigButton({
    required this.icon,
    required this.label,
    this.tooltip,
    this.onTap,
  });

  @override
  State<_BigButton> createState() => _BigButtonState();
}

class _BigButtonState extends State<_BigButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Tooltip(
      message: widget.tooltip ?? widget.label.replaceAll('\n', ' '),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: _hovered && enabled ? OutlookTheme.hoverColor : null,
              border: Border.all(
                color: _hovered && enabled
                    ? OutlookTheme.selectedItemBorder
                    : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon,
                    size: 24,
                    color: enabled
                        ? OutlookTheme.primaryBlue
                        : OutlookTheme.textMuted),
                const SizedBox(height: 2),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: OutlookTheme.ribbonButtonLabel.copyWith(
                    color: enabled ? null : OutlookTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderFields extends StatelessWidget {
  final List<EmailAccount> accounts;
  final EmailAccount? account;
  final ValueChanged<EmailAccount> onAccountChanged;
  final VoidCallback onSend;
  final bool isSending;
  final TextEditingController toController;
  final TextEditingController ccController;
  final TextEditingController bccController;
  final TextEditingController subjectController;
  final FocusNode toFocus;
  final bool showBcc;
  final VoidCallback onShowBcc;
  final VoidCallback onAddressBook;
  final VoidCallback onSubjectChanged;

  const _HeaderFields({
    required this.accounts,
    required this.account,
    required this.onAccountChanged,
    required this.onSend,
    required this.isSending,
    required this.toController,
    required this.ccController,
    required this.bccController,
    required this.subjectController,
    required this.toFocus,
    required this.showBcc,
    required this.onShowBcc,
    required this.onAddressBook,
    required this.onSubjectChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Outlook's tall Send button next to the address fields.
          SizedBox(
            width: 64,
            height: showBcc ? 136 : 102,
            child: OutlinedButton(
              onPressed: isSending ? null : onSend,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: const BorderSide(color: OutlookTheme.dividerColor),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send, color: OutlookTheme.primaryBlue),
                  SizedBox(height: 4),
                  Text('Send', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                _FieldRow(
                  label: 'From',
                  child: accounts.length > 1
                      ? DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: account?.id,
                            isDense: true,
                            isExpanded: true,
                            style: const TextStyle(
                                fontSize: 13, color: OutlookTheme.textPrimary),
                            items: [
                              for (final a in accounts)
                                DropdownMenuItem(
                                  value: a.id,
                                  child: Text(a.fromDisplay,
                                      overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (id) {
                              final a = accounts.where((x) => x.id == id).firstOrNull;
                              if (a != null) onAccountChanged(a);
                            },
                          ),
                        )
                      : Text(account?.fromDisplay ?? '(no account)',
                          style: const TextStyle(fontSize: 13)),
                ),
                _FieldRow(
                  label: 'To...',
                  onLabelTap: onAddressBook,
                  trailing: showBcc
                      ? null
                      : ExcludeFocus(
                          child: TextButton(
                            onPressed: onShowBcc,
                            child: const Text('Bcc',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ),
                  child: RecipientField(
                    controller: toController,
                    focusNode: toFocus,
                    autofocus: true,
                  ),
                ),
                _FieldRow(
                  label: 'Cc...',
                  onLabelTap: onAddressBook,
                  child: RecipientField(controller: ccController),
                ),
                if (showBcc)
                  _FieldRow(
                    label: 'Bcc...',
                    onLabelTap: onAddressBook,
                    child: RecipientField(controller: bccController),
                  ),
                _FieldRow(
                  label: 'Subject',
                  child: TextField(
                    controller: subjectController,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => onSubjectChanged(),
                    style: const TextStyle(fontSize: 13),
                    decoration: _fieldDecoration,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _fieldDecoration = InputDecoration(
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  isDense: true,
  contentPadding: EdgeInsets.symmetric(vertical: 8),
);

class _FieldRow extends StatelessWidget {
  final String label;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onLabelTap;

  const _FieldRow({
    required this.label,
    required this.child,
    this.trailing,
    this.onLabelTap,
  });

  @override
  Widget build(BuildContext context) {
    final labelWidget = SizedBox(
      width: 64,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: onLabelTap != null
              ? OutlookTheme.textPrimary
              : OutlookTheme.textSecondary,
        ),
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OutlookTheme.dividerColor)),
      ),
      child: Row(
        children: [
          if (onLabelTap != null)
            Tooltip(
              message: 'Select names from the Address Book',
              child: InkWell(
                onTap: onLabelTap,
                canRequestFocus: false,
                child: labelWidget,
              ),
            )
          else
            labelWidget,
          Expanded(child: child),
          ?trailing,
        ],
      ),
    );
  }
}

/// A recipient text field with auto-complete from contacts and groups.
class RecipientField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;

  const RecipientField({
    super.key,
    required this.controller,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<RecipientField> createState() => _RecipientFieldState();
}

class _RecipientFieldState extends State<RecipientField> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void dispose() {
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  static String _lastToken(String text) {
    final idx = text.lastIndexOf(RegExp(r'[;,]'));
    return text.substring(idx + 1).trim();
  }

  static String _replaceLastToken(String text, String replacement) {
    final idx = text.lastIndexOf(RegExp(r'[;,]'));
    final prefix = idx < 0 ? '' : '${text.substring(0, idx + 1)} ';
    return '${prefix.replaceAll(RegExp(r'\s+$'), ' ').trimLeft()}$replacement; ';
  }

  @override
  Widget build(BuildContext context) {
    final contacts = context.read<ContactsProvider>();
    return RawAutocomplete<RecipientSuggestion>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        final token = _lastToken(value.text);
        if (token.length < 2) return const Iterable.empty();
        return contacts.suggestions(token);
      },
      displayStringForOption: (option) => _replaceLastToken(
        widget.controller.text,
        option.isGroup ? option.label : option.insertText,
      ),
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: widget.autofocus,
          style: const TextStyle(fontSize: 13),
          decoration: _fieldDecoration,
          // Enter picks the highlighted suggestion and keeps the focus
          // here (a single-line field would otherwise unfocus on submit).
          onSubmitted: (_) => onFieldSubmitted(),
          onEditingComplete: () {},
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            shape: const RoundedRectangleBorder(
              side: BorderSide(color: OutlookTheme.dividerColor),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 260),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    InkWell(
                      onTap: () => onSelected(option),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              option.isGroup ? Icons.groups : Icons.person,
                              size: 16,
                              color: OutlookTheme.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                option.isGroup
                                    ? '${option.label} (group, '
                                        '${option.group!.memberCount} members)'
                                    : option.insertText,
                                style: const TextStyle(fontSize: 12.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AttachmentStrip extends StatelessWidget {
  final List<Attachment> attachments;
  final ValueChanged<Attachment> onRemove;

  const _AttachmentStrip({required this.attachments, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(84, 6, 12, 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OutlookTheme.dividerColor)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Attached',
              style: TextStyle(fontSize: 12, color: OutlookTheme.textSecondary)),
          for (final a in attachments)
            Container(
              padding: const EdgeInsets.only(left: 8, right: 2),
              decoration: BoxDecoration(
                border: Border.all(color: OutlookTheme.dividerColor),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insert_drive_file_outlined,
                      size: 14, color: OutlookTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text('${a.fileName} (${a.sizeFormatted})',
                      style: const TextStyle(fontSize: 12)),
                  IconButton(
                    tooltip: 'Remove attachment',
                    onPressed: () => onRemove(a),
                    icon: const Icon(Icons.close, size: 12),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 22, minHeight: 22),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
