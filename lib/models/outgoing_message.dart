import 'email_message.dart';

/// A message composed in Look In that is about to be sent, saved as a
/// draft, or waiting in the Outbox because sending failed (e.g. offline).
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
  });

  List<EmailAddress> get allRecipients => [...to, ...cc, ...bcc];

  OutgoingMessage copyWith({String? lastError, String? draftMessageId}) {
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
    );
  }
}
