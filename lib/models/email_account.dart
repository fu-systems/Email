/// Authentication type for an email account.
enum AuthType { password, oauth2 }

/// OAuth provider identifier.
enum OAuthProvider { google, microsoft, yahoo }

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

  // Credentials (password auth)
  final String username;
  final String password;

  // OAuth fields
  final AuthType authType;
  final OAuthProvider? oauthProvider;
  final String? accessToken;
  final String? refreshToken;
  final DateTime? tokenExpiry;

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
    this.password = '',
    this.authType = AuthType.password,
    this.oauthProvider,
    this.accessToken,
    this.refreshToken,
    this.tokenExpiry,
    this.isDefault = false,
    this.isEnabled = true,
    this.signature,
  });

  bool get isOAuth => authType == AuthType.oauth2;

  bool get isTokenExpired {
    if (tokenExpiry == null) return true;
    return DateTime.now().isAfter(tokenExpiry!.subtract(const Duration(minutes: 5)));
  }

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
    AuthType? authType,
    OAuthProvider? oauthProvider,
    String? accessToken,
    String? refreshToken,
    DateTime? tokenExpiry,
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
      authType: authType ?? this.authType,
      oauthProvider: oauthProvider ?? this.oauthProvider,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenExpiry: tokenExpiry ?? this.tokenExpiry,
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
        'authType': authType.name,
        'oauthProvider': oauthProvider?.name,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'tokenExpiry': tokenExpiry?.toIso8601String(),
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
        password: (map['password'] as String?) ?? '',
        authType: _parseAuthType(map['authType'] as String?),
        oauthProvider: _parseOAuthProvider(map['oauthProvider'] as String?),
        accessToken: map['accessToken'] as String?,
        refreshToken: map['refreshToken'] as String?,
        tokenExpiry: map['tokenExpiry'] != null
            ? DateTime.tryParse(map['tokenExpiry'] as String)
            : null,
        isDefault: (map['isDefault'] as int) == 1,
        isEnabled: (map['isEnabled'] as int) == 1,
        signature: map['signature'] as String?,
      );

  static AuthType _parseAuthType(String? value) {
    if (value == null) return AuthType.password;
    try {
      return AuthType.values.byName(value);
    } catch (_) {
      return AuthType.password;
    }
  }

  static OAuthProvider? _parseOAuthProvider(String? value) {
    if (value == null) return null;
    try {
      return OAuthProvider.values.byName(value);
    } catch (_) {
      return null;
    }
  }
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
  final bool supportsOAuth;
  final OAuthProvider? oauthProvider;

  const EmailProviderConfig({
    required this.name,
    required this.domain,
    required this.imapHost,
    required this.imapPort,
    required this.imapSecurity,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSecurity,
    this.supportsOAuth = false,
    this.oauthProvider,
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
      supportsOAuth: true,
      oauthProvider: OAuthProvider.google,
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
      supportsOAuth: true,
      oauthProvider: OAuthProvider.microsoft,
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
      supportsOAuth: true,
      oauthProvider: OAuthProvider.microsoft,
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
      supportsOAuth: true,
      oauthProvider: OAuthProvider.yahoo,
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
