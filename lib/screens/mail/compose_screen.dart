import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
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
import '../../services/rich_text_codec.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/compose/format_controls.dart';
import '../../widgets/compose/rich_body_editor.dart';
import '../../widgets/email_html_view.dart';
import '../../widgets/ribbon/ribbon_toolbar.dart';
import 'address_book_dialog.dart';

enum ComposeMode { newMessage, reply, replyAll, forward, editDraft }

/// Outlook 2013-style message window (new, reply, reply all, forward,
/// editing a draft or an Outbox item).
///
/// Messages are written in HTML with a rich text editor by default
/// (Options > "Compose messages in"); FORMAT TEXT > Plain Text switches a
/// message to plain text. The original of a reply or forward is kept as
/// sanitized HTML below the editor, so its formatting reaches the
/// recipients unchanged.
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

  /// Preference: compose new messages in HTML (default) or plain text.
  static const htmlPreference = 'composeHtml';

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _toController = TextEditingController();
  final _ccController = TextEditingController();
  final _bccController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final _bodyFocus = FocusNode(debugLabel: 'plain body');
  final _editorFocus = FocusNode(debugLabel: 'message body');
  final _editorScroll = ScrollController();
  final _toFocus = FocusNode();
  final QuillController _quill = QuillController.basic();

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
  String _ribbonTab = 'MESSAGE';

  /// HTML (rich text editor) or plain text.
  bool _html = true;

  /// The replied-to or forwarded message: sanitized HTML (sent below the
  /// editor's content) and its plain-text version (for the text part).
  String? _quotedHtml;
  String? _quotedText;
  bool _showQuoted = true;

  /// The body as first filled in (signature only, for new messages), to
  /// know whether the signature may be swapped when the account changes.
  String _pristineBody = '';

  @override
  void initState() {
    super.initState();
    final mail = context.read<MailProvider>();
    _account =
        (widget.original != null
            ? mail.accountById(widget.original!.accountId)
            : null) ??
        mail.currentAccount;
    _html = mail.preference(ComposeScreen.htmlPreference, defaultValue: true);
    _showBcc = false;
    _prefill();
  }

  /// Whether the user changed anything since the message was opened or
  /// last saved (programmatic fills such as quoting reset the baseline).
  bool get _dirty => _snapshot() != _initialSnapshot;

  String get _bodySnapshot => _html
      ? jsonEncode(_quill.document.toDelta().toJson())
      : _bodyController.text;

  String _snapshot() => [
    _toController.text,
    _ccController.text,
    _bccController.text,
    _subjectController.text,
    _bodySnapshot,
    _html,
    _attachments.map((a) => a.localPath ?? a.id).join(','),
    _importance.name,
    _account?.id,
  ].join('\u0000');

  void _resetBaseline() => _initialSnapshot = _snapshot();

  // ─── Editor helpers ────────────────────────────────────────────────

  void _setEditor(Delta delta, {int cursor = 0}) {
    _quill.document = Document.fromDelta(delta);
    _quill.updateSelection(
      TextSelection.collapsed(offset: cursor),
      ChangeSource.local,
    );
  }

  /// Signature of [account] for HTML messages.
  static Delta? _signatureDelta(EmailAccount? account) {
    final html = account?.signatureHtml;
    if (html != null && html.trim().isNotEmpty) {
      return RichTextCodec.fromHtml(html);
    }
    final text = account?.signature?.trim();
    if (text == null || text.isEmpty) return null;
    return RichTextCodec.fromPlainText(text);
  }

  /// An empty body with room to type above the signature.
  Delta _signatureBody() {
    final signature = _signatureDelta(_account);
    final blank = Delta()..insert('\n\n');
    // concat returns a new Delta.
    return signature == null ? blank : blank.concat(signature);
  }

  // ─── Prefill ───────────────────────────────────────────────────────

  void _prefill() {
    final original = widget.original;
    switch (widget.mode) {
      case ComposeMode.newMessage:
        _toController.text = _joinAddresses(widget.initialTo);
        _ccController.text = _joinAddresses(widget.initialCc);
        _subjectController.text = widget.initialSubject;
        _attachments.addAll(widget.initialAttachments);
        if (widget.initialBody.isNotEmpty) {
          _bodyController.text = widget.initialBody;
          _setEditor(RichTextCodec.fromPlainText(widget.initialBody));
        } else {
          _bodyController.text = _signatureBlock();
          _setEditor(_signatureBody());
        }
        break;
      case ComposeMode.reply:
      case ComposeMode.replyAll:
        _prefillReply(original!, all: widget.mode == ComposeMode.replyAll);
        break;
      case ComposeMode.forward:
        _subjectController.text = _prefixed(original!.subject, 'FW:');
        _bodyController.text = _signatureBlock();
        _setEditor(_signatureBody());
        _loadOriginal(original, forward: true);
        break;
      case ComposeMode.editDraft:
        _prefillDraft(original!);
        break;
    }
    // Like Outlook, typing starts above the signature and quoted text.
    _bodyController.selection = const TextSelection.collapsed(offset: 0);
    _pristineBody = _bodySnapshot;
    _resetBaseline();
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
      filteredTo.isEmpty ? original.to : filteredTo,
    );
    _ccController.text = _joinAddresses(
      cc.where((a) => !filteredTo.contains(a)).toSet().toList(),
    );
    _subjectController.text = _prefixed(original.subject, 'RE:');
    _bodyController.text = _signatureBlock();
    _setEditor(_signatureBody());
    _loadOriginal(original, forward: false);
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
      _attachments.addAll(outboxItem.attachments.where((a) => !a.isInline));
      _importance = outboxItem.importance;
      _draftMessageId = outboxItem.draftMessageId;
      final delta = outboxItem.editorDelta;
      _html = delta != null;
      if (delta != null) {
        try {
          _setEditor(Delta.fromJson(jsonDecode(delta) as List));
        } catch (_) {
          _setEditor(RichTextCodec.fromPlainText(outboxItem.textBody));
        }
        _quotedHtml = outboxItem.quotedHtml;
        _quotedText = _quotedHtml == null
            ? null
            : '\n\n${htmlToPlainText(_quotedHtml!)}';
      }
      return;
    }
    _draftMessageId = original.id;
    _toController.text = _joinAddresses(original.to);
    _ccController.text = _joinAddresses(original.cc);
    _bccController.text = _joinAddresses(original.bcc);
    _showBcc = original.bcc.isNotEmpty;
    _subjectController.text = original.subject == '(No Subject)'
        ? ''
        : original.subject;
    _importance = original.importance;
    _isLoadingOriginal = true;
    mail.loadFullMessage(original).then((full) async {
      final attachments = await mail.materializeAttachments(
        full,
        includeInline: true,
      );
      if (!mounted) return;
      setState(() {
        final html = full.htmlBody;
        if (html != null && html.trim().isNotEmpty) {
          _html = true;
          final parts = RichTextCodec.splitQuoted(html);
          // Inline pictures come back as cid: references; point them at
          // the files just saved so the editor can show them.
          final byCid = {
            for (final a in attachments)
              if (a.contentId != null) 'cid:${a.contentId}': a.localPath,
          };
          final body = RichTextCodec.replaceImageSources(
            parts.body,
            (src) => byCid[src],
          );
          _setEditor(RichTextCodec.fromHtml(body));
          _quotedHtml = parts.quoted;
          _quotedText = parts.quoted == null
              ? null
              : '\n\n${htmlToPlainText(parts.quoted!)}';
        } else {
          _html = false;
          _bodyController.text = full.textBody ?? '';
        }
        _attachments
          ..clear()
          ..addAll(attachments.where((a) => !a.isInline));
        _isLoadingOriginal = false;
        _resetBaseline();
      });
    });
  }

  /// Downloads the original's body (and attachments for forwards) and adds
  /// it below the editor (HTML) or below the cursor area (plain text).
  void _loadOriginal(EmailMessage original, {required bool forward}) {
    final mail = context.read<MailProvider>();
    setState(() => _isLoadingOriginal = true);
    mail.loadFullMessage(original).then((full) async {
      // Forwards carry all attachments; replies only the pictures shown
      // in the quoted original.
      final attachments = await mail.materializeAttachments(
        full,
        includeInline: true,
      );
      if (!mounted) return;
      final wasDirty = _dirty;
      final wasPristine = _bodySnapshot == _pristineBody;
      setState(() {
        _quotedText = _quotedOriginal(full);
        _quotedHtml = _quotedOriginalHtml(full);
        _bodyController.text = '${_bodyController.text}$_quotedText';
        _attachments.addAll(
          attachments.where((a) => forward ? true : a.isInline),
        );
        _isLoadingOriginal = false;
        if (wasPristine) _pristineBody = _bodySnapshot;
        if (!wasDirty) _resetBaseline();
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
    final pattern = RegExp(
      '^${RegExp.escape(prefix)}\\s*',
      caseSensitive: false,
    );
    final alt = prefix == 'FW:'
        ? RegExp(r'^fwd?:\s*', caseSensitive: false)
        : RegExp(r'^re:\s*', caseSensitive: false);
    if (pattern.hasMatch(clean) || alt.hasMatch(clean)) return clean;
    return '$prefix $clean';
  }

  static String _joinAddresses(List<EmailAddress> list) =>
      list.map((a) => a.toString()).join('; ');

  static String _sentDate(DateTime date) =>
      DateFormat('EEEE, MMMM d, yyyy h:mm a').format(date);

  String _quotedOriginal(EmailMessage msg) {
    final body = msg.textBody?.trim().isNotEmpty == true
        ? msg.textBody!
        : htmlToPlainText(msg.htmlBody ?? '');
    final buffer = StringBuffer('\n\n')
      ..writeln('-----Original Message-----')
      ..writeln('From: ${msg.from}')
      ..writeln('Sent: ${_sentDate(msg.date)}');
    if (msg.to.isNotEmpty) buffer.writeln('To: ${_joinAddresses(msg.to)}');
    if (msg.cc.isNotEmpty) buffer.writeln('Cc: ${_joinAddresses(msg.cc)}');
    buffer
      ..writeln('Subject: ${msg.subject}')
      ..writeln()
      ..write(body.trimRight());
    return buffer.toString();
  }

  /// Outlook's header block above the original, then the original's
  /// sanitized HTML (remote pictures kept for the recipients).
  String _quotedOriginalHtml(EmailMessage msg) {
    const escape = HtmlEscape();
    String row(String label, String value) =>
        '<b>$label:</b> ${escape.convert(value)}<br>';
    final original = msg.htmlBody?.trim().isNotEmpty == true
        ? sanitizeEmailHtml(msg.htmlBody!, allowRemoteImages: true).html
        : '<div style="white-space: pre-wrap">'
              '${plainTextToHtml(msg.textBody ?? '')}</div>';
    return '<div style="border:none;border-top:solid #E1E1E1 1pt;'
        'padding:3pt 0 0 0;font-family:Calibri,Arial,sans-serif;'
        'font-size:11pt"><p style="margin:0">'
        '${row('From', msg.from.toString())}'
        '${row('Sent', _sentDate(msg.date))}'
        '${msg.to.isEmpty ? '' : row('To', _joinAddresses(msg.to))}'
        '${msg.cc.isEmpty ? '' : row('Cc', _joinAddresses(msg.cc))}'
        '${row('Subject', msg.subject)}</p></div><br>$original';
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
    _editorFocus.dispose();
    _editorScroll.dispose();
    _toFocus.dispose();
    _quill.dispose();
    super.dispose();
  }

  // ─── Format ────────────────────────────────────────────────────────

  Future<void> _setHtml(bool html) async {
    if (html == _html) return;
    if (!html) {
      final hasFormatting = _quill.document.toDelta().toList().any(
        (op) => op.attributes != null || op.data is! String,
      );
      if (hasFormatting &&
          !await showConfirmDialog(
            context,
            title: 'Plain Text',
            message:
                'Converting this message to plain text removes its '
                'formatting and pictures. Continue?',
            confirmLabel: 'Continue',
          )) {
        return;
      }
      setState(() {
        _bodyController.text =
            '${RichTextCodec.toPlainText(_quill.document.toDelta().toJson().cast())}'
            '${_quotedText ?? ''}';
        _quotedHtml = null;
        _html = false;
      });
      _bodyFocus.requestFocus();
    } else {
      setState(() {
        _setEditor(RichTextCodec.fromPlainText(_bodyController.text));
        _quotedHtml = null;
        _quotedText = null;
        _html = true;
      });
      _editorFocus.requestFocus();
    }
  }

  /// Replaces an untouched signature when another From account is chosen.
  void _changeAccount(EmailAccount account) {
    final untouched = _bodySnapshot == _pristineBody;
    setState(() {
      _account = account;
      if (untouched && widget.mode != ComposeMode.editDraft) {
        if (_html) {
          _setEditor(_signatureBody());
        } else {
          final quote = _quotedText ?? '';
          _bodyController.text = '${_signatureBlock()}$quote';
        }
        _pristineBody = _bodySnapshot;
      }
    });
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
          contacts.groupAddresses(group).map((a) => EmailAddress(address: a)),
        );
        continue;
      }
      // A bare name matching exactly one contact resolves to that contact.
      final matches = contacts.allContacts
          .where(
            (c) =>
                c.primaryEmail != null &&
                c.displayName.toLowerCase() == token.display.toLowerCase(),
          )
          .toList();
      if (matches.length == 1) {
        valid.add(
          EmailAddress(
            address: matches.first.primaryEmail!,
            displayName: matches.first.displayName,
          ),
        );
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
      setState(
        () => _error =
            'Outlook does not recognize: ${problems.join(', ')}. '
            'Enter full email addresses.',
      );
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

  // ─── Attachments and pictures ──────────────────────────────────────

  List<Attachment> get _visibleAttachments =>
      _attachments.where((a) => !a.isInline).toList();

  Future<void> _attachFiles() async {
    final paths = await FileDialogs.pickFiles(context, title: 'Insert File');
    if (paths.isEmpty || !mounted) return;
    setState(() {
      for (final path in paths) {
        final file = File(path);
        if (!file.existsSync()) continue;
        _attachments.add(
          Attachment(
            id: const Uuid().v4(),
            fileName: p.basename(path),
            mimeType: MimeConverter.guessMimeType(path),
            size: file.lengthSync(),
            localPath: path,
          ),
        );
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

  Future<void> _insertPictures() async {
    if (!_html) {
      await _setHtml(true);
      if (!_html) return;
    }
    if (!mounted) return;
    final paths = await FileDialogs.pickFiles(context, title: 'Insert Picture');
    if (!mounted) return;
    for (final path in paths) {
      final type = MimeConverter.guessMimeType(path);
      if (!type.startsWith('image/')) {
        showStatusMessage(
          context,
          '${p.basename(path)} is not a picture',
          isError: true,
        );
        continue;
      }
      TextFormatting.insertImage(_quill, path);
    }
    _editorFocus.requestFocus();
  }

  void _insertSignature() {
    if (_html) {
      final signature = _signatureDelta(_account);
      if (signature == null) {
        showStatusMessage(
          context,
          'No signature set. Add one in File > Options > Signatures.',
        );
        return;
      }
      TextFormatting.insertDelta(
        _quill,
        (Delta()..insert('\n')).concat(signature),
      );
      _editorFocus.requestFocus();
      return;
    }
    final signature = _account?.signature?.trim();
    if (signature == null || signature.isEmpty) {
      showStatusMessage(
        context,
        'No signature set. Add one in File > Options > Signatures.',
      );
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

  void _insertLink() {
    if (!_html) return;
    TextFormatting.insertLink(
      context,
      _quill,
    ).then((_) => _editorFocus.requestFocus());
  }

  // ─── Send / save ───────────────────────────────────────────────────

  /// Body parts for the message: HTML with inline pictures as cid:
  /// attachments, and the plain-text alternative.
  ({String text, String? html, List<Attachment> inline, String? delta})
  _bodyParts() {
    if (!_html) {
      return (
        text: _bodyController.text,
        html: null,
        inline: const [],
        delta: null,
      );
    }
    final ops = _quill.document.toDelta().toJson().cast<Map<String, dynamic>>();
    final inline = <String, Attachment>{};
    final existing = {
      for (final a in _attachments)
        if (a.isInline && a.contentId != null) 'cid:${a.contentId}': a,
    };
    for (final src in RichTextCodec.imageSources(ops)) {
      if (inline.containsKey(src)) continue;
      if (existing[src] case final Attachment att) {
        inline[src] = att;
        continue;
      }
      final path = src.startsWith('file:') ? Uri.parse(src).toFilePath() : src;
      final file = File(path);
      if (src.contains('://') && !src.startsWith('file:')) continue;
      if (!file.existsSync()) continue;
      final id = const Uuid().v4();
      inline[src] = Attachment(
        id: id,
        fileName: p.basename(path),
        mimeType: MimeConverter.guessMimeType(path),
        size: file.lengthSync(),
        localPath: path,
        contentId: '$id@lookin',
        isInline: true,
      );
    }
    // Pictures of the local file are sent as cid: references.
    final byPath = {
      for (final e in inline.entries) e.key: 'cid:${e.value.contentId}',
    };
    var body = RichTextCodec.toHtml(ops);
    body = RichTextCodec.replaceImageSources(body, (src) => byPath[src]);
    final quoted = _quotedHtml;
    final html =
        '${RichTextCodec.wrapBody(body)}'
        '${quoted == null ? '' : '<div id="${RichTextCodec.quotedMarker}"><br>$quoted</div>'}';
    final text = '${RichTextCodec.toPlainText(ops)}${_quotedText ?? ''}';
    // Keep inline parts of the quoted original that it still refers to.
    final quotedInline = [
      for (final a in _attachments)
        if (a.isInline &&
            a.contentId != null &&
            (quoted?.contains('cid:${a.contentId}') ?? false) &&
            !inline.values.contains(a))
          a,
    ];
    return (
      text: text,
      html: html,
      inline: [...inline.values, ...quotedInline],
      delta: jsonEncode(ops),
    );
  }

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
        setState(
          () => _error =
              'Outlook does not recognize: ${invalid.join(', ')}. '
              'Enter full email addresses.',
        );
        return null;
      }
      if (to.valid.isEmpty && cc.valid.isEmpty && bcc.valid.isEmpty) {
        setState(
          () => _error =
              'There must be at least one name or '
              'contact group in the To, Cc, or Bcc box.',
        );
        return null;
      }
    }
    final original = widget.original;
    final isReply =
        widget.mode == ComposeMode.reply || widget.mode == ComposeMode.replyAll;
    final refs = [
      if (isReply && original?.references != null) original!.references!,
    ].join(' ');
    final body = _bodyParts();
    return OutgoingMessage(
      id: _outboxId ?? const Uuid().v4(),
      accountId: account.id,
      to: to.valid,
      cc: cc.valid,
      bcc: bcc.valid,
      subject: _subjectController.text.trim(),
      textBody: body.text,
      htmlBody: body.html,
      editorDelta: body.delta,
      quotedHtml: _html ? _quotedHtml : null,
      attachments: [..._visibleAttachments, ...body.inline],
      inReplyTo: isReply ? original?.messageId : null,
      references: refs.isEmpty ? null : refs,
      importance: _importance,
      createdAt: DateTime.now(),
      draftMessageId: _draftMessageId,
    );
  }

  /// The text the user wrote, without the quoted original.
  String get _ownText => _html
      ? RichTextCodec.toPlainText(
          _quill.document.toDelta().toJson().cast<Map<String, dynamic>>(),
        )
      : _bodyController.text.split('-----Original Message-----').first;

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
    final mentionsAttachment = RegExp(
      r'\battach(ed|ment|ments)?\b',
      caseSensitive: false,
    ).hasMatch(_ownText);
    if (mentionsAttachment && _visibleAttachments.isEmpty) {
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
        _close(
          message:
              'You are offline. The message is in your Outbox and '
              'will be sent when you are back online.',
        );
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
        _resetBaseline();
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
      messenger?.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          width: 520,
        ),
      );
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

  Future<void> _discard() async {
    if (!_dirty ||
        await showConfirmDialog(
          context,
          title: 'Discard Message',
          message: 'Discard this message?',
          confirmLabel: 'Discard',
          destructive: true,
        )) {
      if (mounted) _close();
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────

  String get _windowTitle {
    final subject = _subjectController.text.trim();
    return '${subject.isEmpty ? 'Untitled' : subject} - Message';
  }

  List<RibbonTabDefinition> _ribbonTabs() {
    final basicText = BasicTextGroup(
      controller: _quill,
      editorFocus: _editorFocus,
      enabled: _html,
    );
    final names = RibbonGroupDefinition(
      label: 'Names',
      items: [
        RibbonItem(
          label: 'Address\nBook',
          icon: Icons.contacts_outlined,
          isLarge: true,
          onTap: _openAddressBook,
        ),
        RibbonItem(
          label: 'Check\nNames',
          icon: Icons.how_to_reg_outlined,
          isLarge: true,
          tooltip: 'Check Names (Ctrl+K in an address box)',
          onTap: () {
            if (_checkNames()) showStatusMessage(context, 'All names resolved');
          },
        ),
      ],
    );
    RibbonItem attach() => RibbonItem(
      label: 'Attach\nFile',
      icon: Icons.attach_file,
      isLarge: true,
      onTap: _attachFiles,
    );
    RibbonItem signature() => RibbonItem(
      label: 'Signature',
      icon: Icons.draw_outlined,
      isLarge: true,
      onTap: _insertSignature,
    );
    final tags = RibbonGroupDefinition(
      label: 'Tags',
      items: [
        RibbonItem(
          label: 'High Importance',
          icon: Icons.priority_high,
          iconColor: OutlookTheme.flaggedColor,
          isChecked: _importance == MessageImportance.high,
          onTap: () => _toggleImportance(MessageImportance.high),
        ),
        RibbonItem(
          label: 'Low Importance',
          icon: Icons.arrow_downward,
          isChecked: _importance == MessageImportance.low,
          onTap: () => _toggleImportance(MessageImportance.low),
        ),
      ],
    );
    final format = RibbonGroupDefinition(
      label: 'Format',
      items: [
        RibbonItem(
          label: 'HTML',
          icon: Icons.text_format,
          isLarge: true,
          isChecked: _html,
          tooltip: 'Format this message as HTML',
          onTap: () => _setHtml(true),
        ),
        RibbonItem(
          label: 'Plain\nText',
          icon: Icons.notes,
          isLarge: true,
          isChecked: !_html,
          tooltip: 'Format this message as plain text',
          onTap: () => _setHtml(false),
        ),
      ],
    );
    return [
      RibbonTabDefinition(
        label: 'MESSAGE',
        groups: [
          RibbonGroupDefinition(label: 'Basic Text', custom: basicText),
          names,
          RibbonGroupDefinition(
            label: 'Include',
            items: [attach(), signature()],
          ),
          tags,
          RibbonGroupDefinition(
            label: 'Draft',
            items: [
              RibbonItem(
                label: 'Save',
                icon: Icons.save_outlined,
                isLarge: true,
                tooltip: 'Save to Drafts (Ctrl+S)',
                onTap: () => _saveDraft(),
              ),
              RibbonItem(
                label: 'Discard',
                icon: Icons.delete_outline,
                isLarge: true,
                onTap: _discard,
              ),
            ],
          ),
        ],
      ),
      RibbonTabDefinition(
        label: 'INSERT',
        groups: [
          RibbonGroupDefinition(
            label: 'Include',
            items: [attach(), signature()],
          ),
          RibbonGroupDefinition(
            label: 'Illustrations',
            items: [
              RibbonItem(
                label: 'Pictures',
                icon: Icons.image_outlined,
                isLarge: true,
                onTap: _insertPictures,
              ),
            ],
          ),
          RibbonGroupDefinition(
            label: 'Links',
            items: [
              RibbonItem(
                label: 'Hyperlink',
                icon: Icons.link,
                isLarge: true,
                tooltip: 'Insert Hyperlink (Ctrl+K)',
                enabled: _html,
                onTap: _insertLink,
              ),
            ],
          ),
        ],
      ),
      RibbonTabDefinition(
        label: 'OPTIONS',
        groups: [
          RibbonGroupDefinition(
            label: 'Show Fields',
            items: [
              RibbonItem(
                label: 'Bcc',
                icon: Icons.person_add_alt_outlined,
                isLarge: true,
                isChecked: _showBcc,
                onTap: () => setState(() => _showBcc = !_showBcc),
              ),
            ],
          ),
          format,
          tags,
        ],
      ),
      RibbonTabDefinition(
        label: 'FORMAT TEXT',
        groups: [
          format,
          RibbonGroupDefinition(label: 'Basic Text', custom: basicText),
        ],
      ),
    ];
  }

  void _toggleImportance(MessageImportance value) => setState(() {
    _importance = _importance == value ? MessageImportance.normal : value;
  });

  Widget _plainBody() => Padding(
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
        fontFamilyFallback: OutlookTheme.fontFamilyFallback,
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
  );

  Widget _richBody() {
    final quoted = _quotedHtml;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GestureDetector(
            // Clicks below the text put the cursor in the editor.
            behavior: HitTestBehavior.translucent,
            onTap: () => _editorFocus.requestFocus(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: RichBodyEditor(
                controller: _quill,
                focusNode: _editorFocus,
                scrollController: _editorScroll,
                autofocus: widget.mode != ComposeMode.newMessage,
                shortcuts: {
                  const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                      _insertLink,
                  const SingleActivator(
                    LogicalKeyboardKey.enter,
                    control: true,
                  ): _send,
                  const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    control: true,
                  ): () =>
                      _saveDraft(),
                },
              ),
            ),
          ),
        ),
        if (quoted != null)
          _QuotedOriginal(
            html: quoted,
            expanded: _showQuoted,
            onToggle: () => setState(() => _showQuoted = !_showQuoted),
            onEdit: _editQuoted,
          ),
      ],
    );
  }

  /// Moves the quoted original into the editor (losing what the editor
  /// can't show, such as tables).
  Future<void> _editQuoted() async {
    final quoted = _quotedHtml;
    if (quoted == null) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Edit Original Message',
      message:
          'The original message moves into the editor. Some of its '
          'layout, such as tables, may not be kept.',
      confirmLabel: 'Edit',
    );
    if (!ok || !mounted) return;
    setState(() {
      // Append below the editor's content, as it was shown.
      final end = _quill.document.length - 1;
      _quill.updateSelection(
        TextSelection.collapsed(offset: end),
        ChangeSource.local,
      );
      TextFormatting.insertDelta(
        _quill,
        (Delta()..insert('\n')).concat(RichTextCodec.fromHtml(quoted)),
      );
      _quotedHtml = null;
    });
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
          // As in Outlook: a hyperlink in the message, Check Names elsewhere.
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              _html && _editorFocus.hasFocus ? _insertLink() : _checkNames(),
          const SingleActivator(LogicalKeyboardKey.escape): _requestClose,
        },
        // No autofocus here: the To field (new message) or the body
        // (reply/forward) takes focus; shortcuts bubble up from there.
        child: Focus(
          child: Scaffold(
            body: Column(
              children: [
                _TitleStrip(title: _windowTitle, onClose: _requestClose),
                // The ribbon never takes focus from the message.
                ExcludeFocus(
                  child: RibbonToolbar(
                    tabs: _ribbonTabs(),
                    showFileTab: false,
                    activeTab: _ribbonTab,
                    onTabChanged: (tab) => setState(() => _ribbonTab = tab),
                  ),
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
                          onAccountChanged: _changeAccount,
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
                        if (_visibleAttachments.isNotEmpty)
                          _AttachmentStrip(
                            attachments: _visibleAttachments,
                            onRemove: (a) =>
                                setState(() => _attachments.remove(a)),
                          ),
                        Expanded(child: _html ? _richBody() : _plainBody()),
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

/// The replied-to or forwarded message below the editor.
class _QuotedOriginal extends StatelessWidget {
  final String html;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  const _QuotedOriginal({
    required this.html,
    required this.expanded,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    // Shown without remote pictures; they are still sent.
    final display = sanitizeEmailHtml(html, allowRemoteImages: false).html;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: OutlookTheme.folderPaneBackground,
            border: Border(
              top: BorderSide(color: OutlookTheme.dividerColor),
              bottom: BorderSide(color: OutlookTheme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: onToggle,
                canRequestFocus: false,
                child: Row(
                  children: [
                    Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: OutlookTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Original message',
                      style: TextStyle(
                        fontSize: 12,
                        color: OutlookTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onEdit,
                child: const Text(
                  'Edit Original',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        if (expanded)
          SizedBox(
            height: 260,
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: EmailHtmlView(html: display),
              ),
            ),
          ),
      ],
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
            child: Text(
              title,
              style: OutlookTheme.titleBarStyle,
              overflow: TextOverflow.ellipsis,
            ),
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
          bottom: BorderSide(color: OutlookTheme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 14,
            color: isError
                ? OutlookTheme.flaggedColor
                : OutlookTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
          if (onDismiss != null)
            InkWell(
              onTap: onDismiss,
              child: const Icon(
                Icons.close,
                size: 14,
                color: OutlookTheme.textSecondary,
              ),
            ),
        ],
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
                              fontSize: 13,
                              color: OutlookTheme.textPrimary,
                            ),
                            items: [
                              for (final a in accounts)
                                DropdownMenuItem(
                                  value: a.id,
                                  child: Text(
                                    a.fromDisplay,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (id) {
                              final a = accounts
                                  .where((x) => x.id == id)
                                  .firstOrNull;
                              if (a != null) onAccountChanged(a);
                            },
                          ),
                        )
                      : Text(
                          account?.fromDisplay ?? '(no account)',
                          style: const TextStyle(fontSize: 13),
                        ),
                ),
                _FieldRow(
                  label: 'To...',
                  onLabelTap: onAddressBook,
                  trailing: showBcc
                      ? null
                      : ExcludeFocus(
                          child: TextButton(
                            onPressed: onShowBcc,
                            child: const Text(
                              'Bcc',
                              style: TextStyle(fontSize: 12),
                            ),
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
                          horizontal: 10,
                          vertical: 6,
                        ),
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
          const Text(
            'Attached',
            style: TextStyle(fontSize: 12, color: OutlookTheme.textSecondary),
          ),
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
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    size: 14,
                    color: OutlookTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${a.fileName} (${a.sizeFormatted})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  IconButton(
                    tooltip: 'Remove attachment',
                    onPressed: () => onRemove(a),
                    icon: const Icon(Icons.close, size: 12),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
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
