import 'package:clock/clock.dart';
import 'package:intl/intl.dart';

import 'email_message.dart';

/// When a scheduled message goes out, for the Outbox and status messages:
/// "at 4:05 PM", "tomorrow at 9:00 AM" or "on Mon 9/28/2026 at 9:00 AM".
String describeSendTime(DateTime at, {DateTime? now}) {
  now ??= clock.now();
  final time = DateFormat('h:mm a').format(at);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = day.difference(today).inDays;
  if (days == 0) return 'at $time';
  if (days == 1) return 'tomorrow at $time';
  return 'on ${DateFormat('EEE M/d/yyyy').format(at)} at $time';
}

/// A message composed in Look In that is about to be sent, saved as a
/// draft, or waiting in the Outbox: because sending failed (e.g. offline),
/// or until its [sendAfter] time (undo send and delayed delivery).
class OutgoingMessage {
  final String id;
  final String accountId;
  final List<EmailAddress> to;
  final List<EmailAddress> cc;
  final List<EmailAddress> bcc;
  final String subject;
  final String textBody;

  /// HTML alternative of [textBody]; generated when not provided.
  final String? htmlBody;

  /// The editor document (Quill Delta JSON) the HTML was made from, so an
  /// Outbox item or local draft reopens without losing formatting.
  final String? editorDelta;

  /// Sanitized HTML of the message being replied to or forwarded, shown
  /// below the editor and appended to [htmlBody] on sending.
  final String? quotedHtml;

  /// Files to attach; each [Attachment.localPath] points to the file.
  final List<Attachment> attachments;
  final String? inReplyTo;
  final String? references;
  final MessageImportance importance;
  final DateTime createdAt;

  /// Error from the last failed send attempt, shown in the Outbox.
  final String? lastError;

  /// When editing an existing draft: the id of the cached draft message,
  /// so it can be replaced when the draft is saved again or sent.
  final String? draftMessageId;

  /// Not sent before this time; the message waits in the Outbox.
  final DateTime? sendAfter;

  const OutgoingMessage({
    required this.id,
    required this.accountId,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.textBody = '',
    this.htmlBody,
    this.editorDelta,
    this.quotedHtml,
    this.attachments = const [],
    this.inReplyTo,
    this.references,
    this.importance = MessageImportance.normal,
    required this.createdAt,
    this.lastError,
    this.draftMessageId,
    this.sendAfter,
  });

  List<EmailAddress> get allRecipients => [...to, ...cc, ...bcc];

  /// Whether the message is waiting for its [sendAfter] time.
  bool isScheduled(DateTime now) => sendAfter?.isAfter(now) ?? false;

  OutgoingMessage copyWith({
    String? lastError,
    String? draftMessageId,
    DateTime? sendAfter,
  }) {
    return OutgoingMessage(
      id: id,
      accountId: accountId,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      textBody: textBody,
      htmlBody: htmlBody,
      editorDelta: editorDelta,
      quotedHtml: quotedHtml,
      attachments: attachments,
      inReplyTo: inReplyTo,
      references: references,
      importance: importance,
      createdAt: createdAt,
      lastError: lastError ?? this.lastError,
      draftMessageId: draftMessageId ?? this.draftMessageId,
      sendAfter: sendAfter ?? this.sendAfter,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'accountId': accountId,
        'to': to.map((a) => a.toMap()).toList(),
        'cc': cc.map((a) => a.toMap()).toList(),
        'bcc': bcc.map((a) => a.toMap()).toList(),
        'subject': subject,
        'textBody': textBody,
        'htmlBody': htmlBody,
        'editorDelta': ?editorDelta,
        'quotedHtml': ?quotedHtml,
        'attachments': attachments.map((a) => a.toMap()).toList(),
        'inReplyTo': inReplyTo,
        'references': references,
        'importance': importance.name,
        'createdAt': createdAt.toIso8601String(),
        'lastError': lastError,
        'draftMessageId': draftMessageId,
        'sendAfter': ?sendAfter?.toIso8601String(),
      };

  factory OutgoingMessage.fromMap(Map<String, dynamic> map) {
    List<EmailAddress> addresses(Object? raw) => (raw as List? ?? const [])
        .map((a) => EmailAddress.fromMap((a as Map).cast<String, dynamic>()))
        .toList();
    return OutgoingMessage(
      id: map['id'] as String,
      accountId: map['accountId'] as String,
      to: addresses(map['to']),
      cc: addresses(map['cc']),
      bcc: addresses(map['bcc']),
      subject: map['subject'] as String? ?? '',
      textBody: map['textBody'] as String? ?? '',
      htmlBody: map['htmlBody'] as String?,
      editorDelta: map['editorDelta'] as String?,
      quotedHtml: map['quotedHtml'] as String?,
      attachments: (map['attachments'] as List? ?? const [])
          .map((a) => Attachment.fromMap((a as Map).cast<String, dynamic>()))
          .toList(),
      inReplyTo: map['inReplyTo'] as String?,
      references: map['references'] as String?,
      importance: MessageImportance.values
              .asNameMap()[map['importance'] as String? ?? 'normal'] ??
          MessageImportance.normal,
      createdAt: DateTime.parse(map['createdAt'] as String),
      lastError: map['lastError'] as String?,
      draftMessageId: map['draftMessageId'] as String?,
      sendAfter: DateTime.tryParse(map['sendAfter'] as String? ?? ''),
    );
  }
}
