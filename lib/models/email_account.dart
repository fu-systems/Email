/// Represents a configured email account with IMAP and SMTP settings.
class EmailAccount {
  final String id;
  final String displayName;
  final String emailAddress;

  // IMAP settings
  final String imapHost;
  final int imapPort;
  final ImapSecurity imapSecurity;

  // SMTP settings
  final String smtpHost;
  final int smtpPort;
  final SmtpSecurity smtpSecurity;

  // Credentials
  final String username;
  final String password;

  // Account state
  final bool isDefault;
  final bool isEnabled;
  final String? signature;

  const EmailAccount({
    required this.id,
    required this.displayName,
    required this.emailAddress,
    required this.imapHost,
    required this.imapPort,
    this.imapSecurity = ImapSecurity.ssl,
    required this.smtpHost,
    required this.smtpPort,
    this.smtpSecurity = SmtpSecurity.starttls,
    required this.username,
    required this.password,
    this.isDefault = false,
    this.isEnabled = true,
    this.signature,
  });

  EmailAccount copyWith({
    String? id,
    String? displayName,
    String? emailAddress,
    String? imapHost,
    int? imapPort,
    ImapSecurity? imapSecurity,
    String? smtpHost,
    int? smtpPort,
    SmtpSecurity? smtpSecurity,
    String? username,
    String? password,
    bool? isDefault,
    bool? isEnabled,
    String? signature,
  }) {
    return EmailAccount(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      emailAddress: emailAddress ?? this.emailAddress,
      imapHost: imapHost ?? this.imapHost,
      imapPort: imapPort ?? this.imapPort,
      imapSecurity: imapSecurity ?? this.imapSecurity,
      smtpHost: smtpHost ?? this.smtpHost,
      smtpPort: smtpPort ?? this.smtpPort,
      smtpSecurity: smtpSecurity ?? this.smtpSecurity,
      username: username ?? this.username,
      password: password ?? this.password,
      isDefault: isDefault ?? this.isDefault,
      isEnabled: isEnabled ?? this.isEnabled,
      signature: signature ?? this.signature,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'displayName': displayName,
        'emailAddress': emailAddress,
        'imapHost': imapHost,
        'imapPort': imapPort,
        'imapSecurity': imapSecurity.name,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        'smtpSecurity': smtpSecurity.name,
        'username': username,
        'password': password,
        'isDefault': isDefault ? 1 : 0,
        'isEnabled': isEnabled ? 1 : 0,
        'signature': signature,
      };

  factory EmailAccount.fromMap(Map<String, dynamic> map) => EmailAccount(
        id: map['id'] as String,
        displayName: map['displayName'] as String,
        emailAddress: map['emailAddress'] as String,
        imapHost: map['imapHost'] as String,
        imapPort: map['imapPort'] as int,
        imapSecurity: ImapSecurity.values.byName(map['imapSecurity'] as String),
        smtpHost: map['smtpHost'] as String,
        smtpPort: map['smtpPort'] as int,
        smtpSecurity:
            SmtpSecurity.values.byName(map['smtpSecurity'] as String),
        username: map['username'] as String,
        password: map['password'] as String,
        isDefault: (map['isDefault'] as int) == 1,
        isEnabled: (map['isEnabled'] as int) == 1,
        signature: map['signature'] as String?,
      );
}

enum ImapSecurity { none, ssl, starttls }

enum SmtpSecurity { none, ssl, starttls }

/// Well-known email provider configurations for auto-detection.
class EmailProviderConfig {
  final String name;
  final String domain;
  final String imapHost;
  final int imapPort;
  final ImapSecurity imapSecurity;
  final String smtpHost;
  final int smtpPort;
  final SmtpSecurity smtpSecurity;

  const EmailProviderConfig({
    required this.name,
    required this.domain,
    required this.imapHost,
    required this.imapPort,
    required this.imapSecurity,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSecurity,
  });

  static const List<EmailProviderConfig> knownProviders = [
    EmailProviderConfig(
      name: 'Gmail',
      domain: 'gmail.com',
      imapHost: 'imap.gmail.com',
      imapPort: 993,
      imapSecurity: ImapSecurity.ssl,
      smtpHost: 'smtp.gmail.com',
      smtpPort: 587,
      smtpSecurity: SmtpSecurity.starttls,
    ),
    EmailProviderConfig(
      name: 'Outlook.com',
      domain: 'outlook.com',
      imapHost: 'outlook.office365.com',
      imapPort: 993,
      imapSecurity: ImapSecurity.ssl,
      smtpHost: 'smtp.office365.com',
      smtpPort: 587,
      smtpSecurity: SmtpSecurity.starttls,
    ),
    EmailProviderConfig(
      name: 'Outlook.com',
      domain: 'hotmail.com',
      imapHost: 'outlook.office365.com',
      imapPort: 993,
      imapSecurity: ImapSecurity.ssl,
      smtpHost: 'smtp.office365.com',
      smtpPort: 587,
      smtpSecurity: SmtpSecurity.starttls,
    ),
    EmailProviderConfig(
      name: 'Yahoo Mail',
      domain: 'yahoo.com',
      imapHost: 'imap.mail.yahoo.com',
      imapPort: 993,
      imapSecurity: ImapSecurity.ssl,
      smtpHost: 'smtp.mail.yahoo.com',
      smtpPort: 587,
      smtpSecurity: SmtpSecurity.starttls,
    ),
    EmailProviderConfig(
      name: 'iCloud',
      domain: 'icloud.com',
      imapHost: 'imap.mail.me.com',
      imapPort: 993,
      imapSecurity: ImapSecurity.ssl,
      smtpHost: 'smtp.mail.me.com',
      smtpPort: 587,
      smtpSecurity: SmtpSecurity.starttls,
    ),
    EmailProviderConfig(
      name: 'Fastmail',
      domain: 'fastmail.com',
      imapHost: 'imap.fastmail.com',
      imapPort: 993,
      imapSecurity: ImapSecurity.ssl,
      smtpHost: 'smtp.fastmail.com',
      smtpPort: 587,
      smtpSecurity: SmtpSecurity.starttls,
    ),
    EmailProviderConfig(
      name: 'ProtonMail Bridge',
      domain: 'protonmail.com',
      imapHost: '127.0.0.1',
      imapPort: 1143,
      imapSecurity: ImapSecurity.starttls,
      smtpHost: '127.0.0.1',
      smtpPort: 1025,
      smtpSecurity: SmtpSecurity.starttls,
    ),
  ];

  static EmailProviderConfig? detectFromEmail(String email) {
    final domain = email.split('@').lastOrNull?.toLowerCase();
    if (domain == null) return null;
    try {
      return knownProviders.firstWhere((p) => p.domain == domain);
    } catch (_) {
      return null;
    }
  }
}
