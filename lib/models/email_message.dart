/// Represents an email message.
class EmailMessage {
  final String id;
  final String accountId;
  final String folderId;

  // Envelope
  final String subject;
  final EmailAddress from;
  final List<EmailAddress> to;
  final List<EmailAddress> cc;
  final List<EmailAddress> bcc;
  final DateTime date;
  final String? inReplyTo;
  final String? messageId;

  // Content
  final String? textBody;
  final String? htmlBody;
  final String preview;
  final List<Attachment> attachments;

  // Flags
  final bool isRead;
  final bool isFlagged;
  final bool isDraft;
  final bool isDeleted;
  final bool hasAttachments;

  // IMAP
  final int? uid;
  final int? sequenceNumber;

  const EmailMessage({
    required this.id,
    required this.accountId,
    required this.folderId,
    required this.subject,
    required this.from,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    required this.date,
    this.inReplyTo,
    this.messageId,
    this.textBody,
    this.htmlBody,
    this.preview = '',
    this.attachments = const [],
    this.isRead = false,
    this.isFlagged = false,
    this.isDraft = false,
    this.isDeleted = false,
    this.hasAttachments = false,
    this.uid,
    this.sequenceNumber,
  });

  EmailMessage copyWith({
    String? id,
    String? accountId,
    String? folderId,
    String? subject,
    EmailAddress? from,
    List<EmailAddress>? to,
    List<EmailAddress>? cc,
    List<EmailAddress>? bcc,
    DateTime? date,
    String? inReplyTo,
    String? messageId,
    String? textBody,
    String? htmlBody,
    String? preview,
    List<Attachment>? attachments,
    bool? isRead,
    bool? isFlagged,
    bool? isDraft,
    bool? isDeleted,
    bool? hasAttachments,
    int? uid,
    int? sequenceNumber,
  }) {
    return EmailMessage(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      folderId: folderId ?? this.folderId,
      subject: subject ?? this.subject,
      from: from ?? this.from,
      to: to ?? this.to,
      cc: cc ?? this.cc,
      bcc: bcc ?? this.bcc,
      date: date ?? this.date,
      inReplyTo: inReplyTo ?? this.inReplyTo,
      messageId: messageId ?? this.messageId,
      textBody: textBody ?? this.textBody,
      htmlBody: htmlBody ?? this.htmlBody,
      preview: preview ?? this.preview,
      attachments: attachments ?? this.attachments,
      isRead: isRead ?? this.isRead,
      isFlagged: isFlagged ?? this.isFlagged,
      isDraft: isDraft ?? this.isDraft,
      isDeleted: isDeleted ?? this.isDeleted,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      uid: uid ?? this.uid,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'accountId': accountId,
        'folderId': folderId,
        'subject': subject,
        'fromAddress': from.address,
        'fromName': from.displayName,
        'toAddresses': to.map((a) => a.toMapString()).join(';'),
        'ccAddresses': cc.map((a) => a.toMapString()).join(';'),
        'bccAddresses': bcc.map((a) => a.toMapString()).join(';'),
        'date': date.toIso8601String(),
        'inReplyTo': inReplyTo,
        'messageId': messageId,
        'textBody': textBody,
        'htmlBody': htmlBody,
        'preview': preview,
        'isRead': isRead ? 1 : 0,
        'isFlagged': isFlagged ? 1 : 0,
        'isDraft': isDraft ? 1 : 0,
        'isDeleted': isDeleted ? 1 : 0,
        'hasAttachments': hasAttachments ? 1 : 0,
        'uid': uid,
      };

  factory EmailMessage.fromMap(Map<String, dynamic> map) => EmailMessage(
        id: map['id'] as String,
        accountId: map['accountId'] as String,
        folderId: map['folderId'] as String,
        subject: map['subject'] as String? ?? '(No Subject)',
        from: EmailAddress(
          address: map['fromAddress'] as String? ?? '',
          displayName: map['fromName'] as String?,
        ),
        to: _parseAddressList(map['toAddresses'] as String?),
        cc: _parseAddressList(map['ccAddresses'] as String?),
        bcc: _parseAddressList(map['bccAddresses'] as String?),
        date: DateTime.parse(map['date'] as String),
        inReplyTo: map['inReplyTo'] as String?,
        messageId: map['messageId'] as String?,
        textBody: map['textBody'] as String?,
        htmlBody: map['htmlBody'] as String?,
        preview: map['preview'] as String? ?? '',
        isRead: (map['isRead'] as int?) == 1,
        isFlagged: (map['isFlagged'] as int?) == 1,
        isDraft: (map['isDraft'] as int?) == 1,
        isDeleted: (map['isDeleted'] as int?) == 1,
        hasAttachments: (map['hasAttachments'] as int?) == 1,
        uid: map['uid'] as int?,
      );

  static List<EmailAddress> _parseAddressList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    return raw.split(';').where((s) => s.isNotEmpty).map((s) {
      final parts = s.split('|');
      return EmailAddress(
        address: parts[0],
        displayName: parts.length > 1 ? parts[1] : null,
      );
    }).toList();
  }
}

class EmailAddress {
  final String address;
  final String? displayName;

  const EmailAddress({required this.address, this.displayName});

  String get display => displayName ?? address;

  String toMapString() =>
      displayName != null ? '$address|$displayName' : address;

  @override
  String toString() =>
      displayName != null ? '$displayName <$address>' : address;
}

class Attachment {
  final String id;
  final String fileName;
  final String mimeType;
  final int size;
  final String? localPath;

  const Attachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.size,
    this.localPath,
  });

  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
