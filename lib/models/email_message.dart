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
  final List<EmailAddress> replyTo;
  final DateTime date;
  final String? inReplyTo;
  final String? messageId;
  final String? references;
  final MessageImportance importance;

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
  final bool isAnswered;
  final bool hasAttachments;

  // Server identifiers
  final int? uid;
  final int? sequenceNumber;

  /// POP3 unique id (UIDL) for messages from POP3 accounts.
  final String? popUid;

  /// Size of the message on the server in bytes, when known.
  final int? size;

  const EmailMessage({
    required this.id,
    required this.accountId,
    required this.folderId,
    required this.subject,
    required this.from,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.replyTo = const [],
    required this.date,
    this.inReplyTo,
    this.messageId,
    this.references,
    this.importance = MessageImportance.normal,
    this.textBody,
    this.htmlBody,
    this.preview = '',
    this.attachments = const [],
    this.isRead = false,
    this.isFlagged = false,
    this.isDraft = false,
    this.isDeleted = false,
    this.isAnswered = false,
    this.hasAttachments = false,
    this.uid,
    this.sequenceNumber,
    this.popUid,
    this.size,
  });

  /// Whether the full body has been downloaded.
  bool get hasBody => textBody != null || htmlBody != null;

  /// Calendar invitations (text/calendar parts) attached to this message.
  Attachment? get calendarInvite => attachments
      .where((a) => a.mimeType.toLowerCase().startsWith('text/calendar'))
      .firstOrNull;

  /// Attachments that should be listed to the user (not inline images
  /// referenced from the HTML body).
  List<Attachment> get visibleAttachments =>
      attachments.where((a) => !a.isInline || a.contentId == null).toList();

  /// Addresses a reply should go to: Reply-To if present, otherwise From.
  List<EmailAddress> get replyAddresses =>
      replyTo.isNotEmpty ? replyTo : [from];

  EmailMessage copyWith({
    String? id,
    String? accountId,
    String? folderId,
    String? subject,
    EmailAddress? from,
    List<EmailAddress>? to,
    List<EmailAddress>? cc,
    List<EmailAddress>? bcc,
    List<EmailAddress>? replyTo,
    DateTime? date,
    String? inReplyTo,
    String? messageId,
    String? references,
    MessageImportance? importance,
    String? textBody,
    String? htmlBody,
    String? preview,
    List<Attachment>? attachments,
    bool? isRead,
    bool? isFlagged,
    bool? isDraft,
    bool? isDeleted,
    bool? isAnswered,
    bool? hasAttachments,
    int? uid,
    int? sequenceNumber,
    String? popUid,
    int? size,
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
      replyTo: replyTo ?? this.replyTo,
      date: date ?? this.date,
      inReplyTo: inReplyTo ?? this.inReplyTo,
      messageId: messageId ?? this.messageId,
      references: references ?? this.references,
      importance: importance ?? this.importance,
      textBody: textBody ?? this.textBody,
      htmlBody: htmlBody ?? this.htmlBody,
      preview: preview ?? this.preview,
      attachments: attachments ?? this.attachments,
      isRead: isRead ?? this.isRead,
      isFlagged: isFlagged ?? this.isFlagged,
      isDraft: isDraft ?? this.isDraft,
      isDeleted: isDeleted ?? this.isDeleted,
      isAnswered: isAnswered ?? this.isAnswered,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      uid: uid ?? this.uid,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      popUid: popUid ?? this.popUid,
      size: size ?? this.size,
    );
  }

  /// JSON-compatible representation (nested lists/maps, no custom encoding).
  Map<String, dynamic> toMap() => {
        'id': id,
        'accountId': accountId,
        'folderId': folderId,
        'subject': subject,
        'from': from.toMap(),
        'to': to.map((a) => a.toMap()).toList(),
        'cc': cc.map((a) => a.toMap()).toList(),
        'bcc': bcc.map((a) => a.toMap()).toList(),
        'replyTo': replyTo.map((a) => a.toMap()).toList(),
        'date': date.toIso8601String(),
        'inReplyTo': inReplyTo,
        'messageId': messageId,
        'references': references,
        'importance': importance.name,
        'textBody': textBody,
        'htmlBody': htmlBody,
        'preview': preview,
        'attachments': attachments.map((a) => a.toMap()).toList(),
        'isRead': isRead,
        'isFlagged': isFlagged,
        'isDraft': isDraft,
        'isDeleted': isDeleted,
        'isAnswered': isAnswered,
        'hasAttachments': hasAttachments,
        'uid': uid,
        'sequenceNumber': sequenceNumber,
        'popUid': popUid,
        'size': size,
      };

  factory EmailMessage.fromMap(Map<String, dynamic> map) => EmailMessage(
        id: map['id'] as String,
        accountId: map['accountId'] as String,
        folderId: map['folderId'] as String,
        subject: map['subject'] as String? ?? '(No Subject)',
        from: EmailAddress.fromMap(
            (map['from'] as Map?)?.cast<String, dynamic>() ?? const {}),
        to: _addressList(map['to']),
        cc: _addressList(map['cc']),
        bcc: _addressList(map['bcc']),
        replyTo: _addressList(map['replyTo']),
        date: DateTime.parse(map['date'] as String),
        inReplyTo: map['inReplyTo'] as String?,
        messageId: map['messageId'] as String?,
        references: map['references'] as String?,
        importance: MessageImportance.values
                .asNameMap()[map['importance'] as String? ?? 'normal'] ??
            MessageImportance.normal,
        textBody: map['textBody'] as String?,
        htmlBody: map['htmlBody'] as String?,
        preview: map['preview'] as String? ?? '',
        attachments: (map['attachments'] as List? ?? const [])
            .map((a) => Attachment.fromMap((a as Map).cast<String, dynamic>()))
            .toList(),
        isRead: map['isRead'] == true,
        isFlagged: map['isFlagged'] == true,
        isDraft: map['isDraft'] == true,
        isDeleted: map['isDeleted'] == true,
        isAnswered: map['isAnswered'] == true,
        hasAttachments: map['hasAttachments'] == true,
        uid: map['uid'] as int?,
        sequenceNumber: map['sequenceNumber'] as int?,
        popUid: map['popUid'] as String?,
        size: map['size'] as int?,
      );

  static List<EmailAddress> _addressList(Object? raw) =>
      (raw as List? ?? const [])
          .map((a) => EmailAddress.fromMap((a as Map).cast<String, dynamic>()))
          .toList();
}

enum MessageImportance {
  low,
  normal,
  high;

  /// Value for the X-Priority header (1 = highest, 5 = lowest).
  int get xPriority {
    switch (this) {
      case MessageImportance.high:
        return 1;
      case MessageImportance.normal:
        return 3;
      case MessageImportance.low:
        return 5;
    }
  }

  /// Parses the Importance / X-Priority header values.
  static MessageImportance fromHeaders({String? importance, String? priority}) {
    final imp = importance?.trim().toLowerCase();
    if (imp == 'high') return MessageImportance.high;
    if (imp == 'low') return MessageImportance.low;
    final p = int.tryParse(priority?.trim().split(RegExp(r'\s')).first ?? '');
    if (p != null) {
      if (p <= 2) return MessageImportance.high;
      if (p >= 4) return MessageImportance.low;
    }
    return MessageImportance.normal;
  }
}

class EmailAddress {
  final String address;
  final String? displayName;

  const EmailAddress({required this.address, this.displayName});

  String get display =>
      (displayName != null && displayName!.trim().isNotEmpty)
          ? displayName!
          : address;

  Map<String, dynamic> toMap() => {
        'address': address,
        if (displayName != null) 'name': displayName,
      };

  factory EmailAddress.fromMap(Map<String, dynamic> map) => EmailAddress(
        address: map['address'] as String? ?? '',
        displayName: map['name'] as String?,
      );

  /// Parses `Name <addr@host>`, `"Name" <addr>` or a bare address.
  static EmailAddress parse(String input) {
    final text = input.trim();
    final match = RegExp(r'^(.*)<([^<>]+)>\s*$').firstMatch(text);
    if (match != null) {
      var name = match.group(1)!.trim();
      if (name.length >= 2 && name.startsWith('"') && name.endsWith('"')) {
        name = name.substring(1, name.length - 1);
      }
      return EmailAddress(
        address: match.group(2)!.trim(),
        displayName: name.isEmpty ? null : name,
      );
    }
    return EmailAddress(address: text);
  }

  /// Splits a recipient field (separated by `;` or `,`) into addresses,
  /// ignoring separators inside quoted display names.
  static List<EmailAddress> parseList(String input) {
    final result = <EmailAddress>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    var inAngle = false;
    for (final ch in input.split('')) {
      if (ch == '"') inQuotes = !inQuotes;
      if (ch == '<') inAngle = true;
      if (ch == '>') inAngle = false;
      if ((ch == ';' || ch == ',') && !inQuotes && !inAngle) {
        if (buffer.toString().trim().isNotEmpty) {
          result.add(parse(buffer.toString()));
        }
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.toString().trim().isNotEmpty) {
      result.add(parse(buffer.toString()));
    }
    return result;
  }

  bool get isValid =>
      RegExp(r'^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$').hasMatch(address);

  @override
  bool operator ==(Object other) =>
      other is EmailAddress &&
      other.address.toLowerCase() == address.toLowerCase();

  @override
  int get hashCode => address.toLowerCase().hashCode;

  @override
  String toString() =>
      displayName != null && displayName!.isNotEmpty
          ? '$displayName <$address>'
          : address;
}

class Attachment {
  /// The MIME fetch id of the part (e.g. `2` or `1.2`) used to extract the
  /// content from the downloaded message source.
  final String id;
  final String fileName;
  final String mimeType;
  final int size;
  final String? contentId;
  final bool isInline;

  /// Local file path for attachments added in the compose window.
  final String? localPath;

  const Attachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.size,
    this.contentId,
    this.isInline = false,
    this.localPath,
  });

  String get sizeFormatted => formatBytes(size);

  static String formatBytes(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'fileName': fileName,
        'mimeType': mimeType,
        'size': size,
        'contentId': contentId,
        'isInline': isInline,
        'localPath': localPath,
      };

  factory Attachment.fromMap(Map<String, dynamic> map) => Attachment(
        id: map['id'] as String,
        fileName: map['fileName'] as String? ?? 'attachment',
        mimeType: map['mimeType'] as String? ?? 'application/octet-stream',
        size: map['size'] as int? ?? 0,
        contentId: map['contentId'] as String?,
        isInline: map['isInline'] == true,
        localPath: map['localPath'] as String?,
      );
}
