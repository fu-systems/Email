import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as enough;

import '../models/email_account.dart';
import '../models/email_message.dart';
import '../models/outgoing_message.dart';
import 'html_sanitizer.dart';

/// Converts between enough_mail's MIME representation and the app models.
class MimeConverter {
  MimeConverter._();

  /// Converts a fetched (or parsed) MIME message into an [EmailMessage].
  ///
  /// Works for both envelope/BODYSTRUCTURE fetches (no body) and full
  /// `BODY[]` fetches (body and attachments decoded).
  static EmailMessage toEmailMessage(
    enough.MimeMessage msg, {
    required String id,
    required String accountId,
    required String folderId,
    int? uid,
    String? popUid,
    bool? isRead,
  }) {
    final envelope = msg.envelope;
    final hasFullContent = msg.mimeData != null;

    String? textBody;
    String? htmlBody;
    if (hasFullContent) {
      try {
        textBody = msg.decodeTextPlainPart();
      } catch (_) {}
      try {
        htmlBody = msg.decodeTextHtmlPart();
      } catch (_) {}
      // Single-part messages of unusual types still deserve some text.
      if (textBody == null && htmlBody == null) {
        try {
          final top = msg.mediaType.top;
          if (top == enough.MediaToptype.text) {
            textBody = msg.decodeContentText();
          }
        } catch (_) {}
      }
      textBody ??= htmlBody == null ? '' : null;
      textBody = _normalizeNewlines(textBody);
      htmlBody = _normalizeNewlines(htmlBody);
    }

    final flags = msg.flags ?? const <String>[];
    final attachments = hasFullContent || msg.body != null
        ? attachmentsOf(msg)
        : const <Attachment>[];

    List<EmailAddress> addresses(List<enough.MailAddress>? list) =>
        (list ?? const <enough.MailAddress>[])
            .map((a) => EmailAddress(
                  address: a.email,
                  displayName: (a.personalName?.trim().isEmpty ?? true)
                      ? null
                      : a.personalName!.trim(),
                ))
            .toList();

    final fromList = envelope?.from ?? _safe(() => msg.from);
    final subject = envelope?.subject ?? _safe(() => msg.decodeSubject());
    final date = envelope?.date ?? _safe(() => msg.decodeDate());

    return EmailMessage(
      id: id,
      accountId: accountId,
      folderId: folderId,
      subject: (subject == null || subject.trim().isEmpty)
          ? '(No Subject)'
          : subject.trim(),
      from: addresses(fromList).firstOrNull ??
          const EmailAddress(address: '', displayName: '(Unknown sender)'),
      to: addresses(envelope?.to ?? _safe(() => msg.to)),
      cc: addresses(envelope?.cc ?? _safe(() => msg.cc)),
      bcc: addresses(envelope?.bcc ?? _safe(() => msg.bcc)),
      replyTo: _replyTo(msg, envelope, addresses),
      date: (date ?? DateTime.now()).toLocal(),
      messageId: envelope?.messageId ?? _header(msg, 'message-id'),
      inReplyTo: envelope?.inReplyTo ?? _header(msg, 'in-reply-to'),
      references: _header(msg, 'references'),
      importance: MessageImportance.fromHeaders(
        importance: _header(msg, 'importance'),
        priority: _header(msg, 'x-priority'),
      ),
      textBody: textBody,
      htmlBody: htmlBody,
      preview: makePreview(textBody, htmlBody),
      attachments: attachments,
      isRead: isRead ?? flags.contains(enough.MessageFlags.seen),
      isFlagged: flags.contains(enough.MessageFlags.flagged),
      isDraft: flags.contains(enough.MessageFlags.draft),
      isDeleted: flags.contains(enough.MessageFlags.deleted),
      isAnswered: flags.contains(enough.MessageFlags.answered),
      hasAttachments: attachments.any((a) => !a.isInline) ||
          _safe(() => msg.hasAttachmentsOrInlineNonTextualParts()) == true,
      uid: uid ?? msg.uid,
      sequenceNumber: msg.sequenceId,
      popUid: popUid,
      size: msg.size,
    );
  }

  /// MIME uses CRLF; the app works with LF only and drops the final line
  /// break added by the MIME encoding.
  static String? _normalizeNewlines(String? text) {
    if (text == null) return null;
    var result = text.replaceAll('\r\n', '\n');
    if (result.endsWith('\n')) result = result.substring(0, result.length - 1);
    return result;
  }

  static List<EmailAddress> _replyTo(
    enough.MimeMessage msg,
    enough.Envelope? envelope,
    List<EmailAddress> Function(List<enough.MailAddress>?) convert,
  ) {
    final replyTo = convert(envelope?.replyTo ?? _safe(() => msg.replyTo));
    final from = convert(envelope?.from ?? _safe(() => msg.from));
    // Servers fill Reply-To with From when absent; only keep real ones.
    if (replyTo.length == from.length &&
        replyTo.every((a) => from.contains(a))) {
      return const [];
    }
    return replyTo;
  }

  static T? _safe<T>(T? Function() getter) {
    try {
      return getter();
    } catch (_) {
      return null;
    }
  }

  static String? _header(enough.MimeMessage msg, String name) {
    try {
      final value = msg.getHeaderValue(name);
      return (value == null || value.trim().isEmpty) ? null : value.trim();
    } catch (_) {
      return null;
    }
  }

  /// A one-line preview (max 200 chars) from the text or HTML body.
  static String makePreview(String? text, String? html) {
    var source = text;
    if ((source == null || source.trim().isEmpty) && html != null) {
      source = htmlToPlainText(html);
    }
    if (source == null) return '';
    // Skip quoted lines so replies preview their new content.
    final lines = source
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('>'))
        .join(' ');
    final collapsed = lines.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.length > 200 ? collapsed.substring(0, 200) : collapsed;
  }

  /// Lists the attachments (and inline non-text parts) of a message.
  static List<Attachment> attachmentsOf(enough.MimeMessage msg) {
    final result = <Attachment>[];
    final seen = <String>{};

    void addInfos(List<enough.ContentInfo> infos, bool inline) {
      for (final info in infos) {
        if (!seen.add(info.fetchId)) continue;
        final mediaType = info.mediaType;
        final isText = mediaType?.top == enough.MediaToptype.text;
        final isCalendar = mediaType?.sub == enough.MediaSubtype.textCalendar;
        // Inline text parts are the message body, not attachments.
        if (inline && isText && !isCalendar) continue;
        if (inline && !isCalendar && info.fileName == null && info.cid == null) {
          continue;
        }
        var size = info.size ?? 0;
        if (size == 0) {
          try {
            size = msg.getPart(info.fetchId)?.decodeContentBinary()?.length ?? 0;
          } catch (_) {}
        }
        result.add(Attachment(
          id: info.fetchId,
          fileName: info.fileName ??
              (isCalendar ? 'invite.ics' : 'attachment-${info.fetchId}'),
          mimeType: mediaType?.text ?? 'application/octet-stream',
          size: size,
          contentId: _stripCid(info.cid),
          isInline: inline,
        ));
      }
    }

    try {
      addInfos(
          msg.findContentInfo(disposition: enough.ContentDisposition.attachment),
          false);
    } catch (_) {}
    try {
      addInfos(
          msg.findContentInfo(disposition: enough.ContentDisposition.inline),
          true);
    } catch (_) {}

    // Calendar invites are often sent as an alternative body part without a
    // Content-Disposition; make them visible as an attachment.
    try {
      final calendarPart =
          msg.getPartWithMediaSubtype(enough.MediaSubtype.textCalendar);
      if (calendarPart != null && !result.any((a) => a.mimeType.startsWith('text/calendar'))) {
        final fetchId = _findFetchId(msg, calendarPart);
        if (fetchId != null) {
          result.add(Attachment(
            id: fetchId,
            fileName: 'invite.ics',
            mimeType: 'text/calendar',
            size: calendarPart.decodeContentBinary()?.length ?? 0,
          ));
        }
      }
    } catch (_) {}
    return result;
  }

  static String? _findFetchId(enough.MimeMessage msg, enough.MimePart target) {
    String? search(enough.MimePart part, String prefix) {
      final parts = part.parts;
      if (parts == null) return null;
      for (var i = 0; i < parts.length; i++) {
        final id = prefix.isEmpty ? '${i + 1}' : '$prefix.${i + 1}';
        if (identical(parts[i], target)) return id;
        final nested = search(parts[i], id);
        if (nested != null) return nested;
      }
      return null;
    }

    if (identical(msg, target)) return '1';
    return search(msg, '');
  }

  static String? _stripCid(String? cid) {
    if (cid == null) return null;
    var value = cid.trim();
    if (value.startsWith('<') && value.endsWith('>')) {
      value = value.substring(1, value.length - 1);
    }
    return value.isEmpty ? null : value;
  }

  /// Decodes the content of the part [fetchId] from a raw message source.
  static Uint8List? extractPart(Uint8List source, String fetchId) {
    try {
      final msg = enough.MimeMessage.parseFromData(source);
      return msg.getPart(fetchId)?.decodeContentBinary();
    } catch (_) {
      return null;
    }
  }

  /// Decodes the text content of the part [fetchId] (e.g. an iCal invite).
  static String? extractTextPart(Uint8List source, String fetchId) {
    try {
      final msg = enough.MimeMessage.parseFromData(source);
      final part = msg.getPart(fetchId);
      if (part == null) return null;
      return part.decodeContentText() ??
          utf8.decode(part.decodeContentBinary() ?? Uint8List(0),
              allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  /// Returns a resolver mapping `cid:` references to `data:` URIs using the
  /// inline parts of [source].
  static String? Function(String cid) cidResolver(
    Uint8List? source,
    List<Attachment> attachments,
  ) {
    enough.MimeMessage? parsed;
    return (String cid) {
      if (source == null) return null;
      final att = attachments
          .where((a) => a.contentId != null && a.contentId == _stripCid(cid))
          .firstOrNull;
      if (att == null) return null;
      try {
        parsed ??= enough.MimeMessage.parseFromData(source);
        final data = parsed!.getPart(att.id)?.decodeContentBinary();
        if (data == null) return null;
        return 'data:${att.mimeType};base64,${base64Encode(data)}';
      } catch (_) {
        return null;
      }
    };
  }

  /// Parses a rendered message.
  static enough.MimeMessage parse(String raw) =>
      enough.MimeMessage.parseFromText(raw);

  /// Raw bytes of a fetched message, for storing as the message source.
  static Uint8List sourceBytes(enough.MimeMessage msg) {
    final data = msg.mimeData;
    if (data is enough.BinaryMimeData) return data.data;
    if (data is enough.TextMimeData) {
      return Uint8List.fromList(utf8.encode(data.text));
    }
    return Uint8List.fromList(utf8.encode(msg.renderMessage()));
  }

  // ─── Outgoing ──────────────────────────────────────────────────────

  static enough.MailAddress _mailAddress(EmailAddress a) =>
      enough.MailAddress(a.displayName, a.address);

  /// Builds the MIME message for [message] sent from [account].
  ///
  /// [calendarPart] adds a `text/calendar` part (used for invite replies)
  /// with the given iCalendar text and METHOD.
  static Future<enough.MimeMessage> buildMimeMessage(
    OutgoingMessage message,
    EmailAccount account, {
    ({String ics, String method})? calendarPart,
  }) async {
    final html = message.htmlBody ?? plainTextToHtml(message.textBody);
    final attachments = <({Attachment info, Uint8List data})>[];
    for (final att in message.attachments) {
      final path = att.localPath;
      if (path == null) continue;
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException('Attachment not found', path);
      }
      attachments.add((info: att, data: await file.readAsBytes()));
    }

    // Inline images (cid: in the HTML) go into multipart/related with the
    // HTML; other files are regular attachments.
    final inline = attachments
        .where((a) => a.info.isInline && a.info.contentId != null)
        .toList();
    final regular = attachments.where((a) => !inline.contains(a)).toList();
    final hasMixed = regular.isNotEmpty || calendarPart != null;
    final builder = hasMixed
        ? enough.MessageBuilder.prepareMultipartMixedMessage()
        : enough.MessageBuilder.prepareMultipartAlternativeMessage();

    builder
      ..from = [enough.MailAddress(account.displayName, account.emailAddress)]
      ..to = message.to.map(_mailAddress).toList()
      ..cc = message.cc.map(_mailAddress).toList()
      // Bcc recipients are given to the SMTP server separately and never
      // written into the transmitted message; callers add a Bcc header
      // only to the copy filed in Sent Items or Drafts.
      ..subject = message.subject
      ..date = DateTime.now();

    // Quoted-printable keeps long lines intact (soft line breaks). The
    // "automatic" encoding picks 7bit for ASCII text and hard-wraps it,
    // which corrupts HTML and reflows plain text.
    const qp = enough.TransferEncoding.quotedPrintable;
    final alternative = hasMixed
        ? builder.addPart(mediaSubtype: enough.MediaSubtype.multipartAlternative)
        : builder;
    alternative.addTextPlain(message.textBody, transferEncoding: qp);
    if (inline.isEmpty) {
      alternative.addTextHtml(html, transferEncoding: qp);
    } else {
      final related = alternative.addPart(
          mediaSubtype: enough.MediaSubtype.multipartRelated);
      related.addTextHtml(html, transferEncoding: qp);
      for (final att in inline) {
        related.addBinary(
          att.data,
          enough.MediaType.fromText(att.info.mimeType),
          filename: att.info.fileName,
          disposition: enough.ContentDispositionHeader.inline(
              filename: att.info.fileName, size: att.data.length),
        ).setHeader('Content-ID', '<${att.info.contentId}>');
      }
    }

    if (calendarPart != null) {
      builder.addPart(
        mediaSubtype: enough.MediaSubtype.textCalendar,
      )
        ..setContentType(
          enough.MediaType.fromSubtype(enough.MediaSubtype.textCalendar),
          characterSet: enough.CharacterSet.utf8,
        )
        ..contentType?.setParameter('method', calendarPart.method)
        ..transferEncoding = enough.TransferEncoding.base64
        ..text = calendarPart.ics;
    }

    for (final att in regular) {
      builder.addBinary(
        att.data,
        enough.MediaType.fromText(att.info.mimeType),
        filename: att.info.fileName,
      );
    }

    if (message.inReplyTo != null) {
      builder.setHeader('In-Reply-To', message.inReplyTo);
      final refs = [
        if (message.references != null) message.references!,
        message.inReplyTo!,
      ].join(' ').trim();
      builder.setHeader('References', refs);
    }
    if (message.importance != MessageImportance.normal) {
      builder.setHeader('X-Priority', '${message.importance.xPriority}');
      builder.setHeader(
        'Importance',
        message.importance == MessageImportance.high ? 'High' : 'Low',
      );
    }
    builder.setHeader('X-Mailer', 'Look In');
    return builder.buildMimeMessage();
  }

  /// Guesses a MIME type from a file name.
  static String guessMimeType(String fileName) {
    try {
      return enough.MediaType.guessFromFileName(fileName).text;
    } catch (_) {
      return 'application/octet-stream';
    }
  }
}
