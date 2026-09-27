/// Represents a configured email account with incoming (IMAP or POP3) and
/// outgoing (SMTP) server settings.
class EmailAccount {
  final String id;
  final String displayName;
  final String emailAddress;

  // Incoming server (IMAP or POP3)
  final IncomingProtocol protocol;
  final String incomingHost;
  final int incomingPort;
  final ConnectionSecurity incomingSecurity;

  // Outgoing server (SMTP)
  final String smtpHost;
  final int smtpPort;
  final ConnectionSecurity smtpSecurity;

  // Credentials
  final String username;

  /// The password, unless [authMethod] is [AuthMethod.oauth2]. Kept in the
  /// secret store, never in the account document.
  final String password;

  /// Password or "Sign in with Microsoft". OAuth tokens live in the secret
  /// store under `oauth:<id>` (see TokenManager), never in the account.
  final AuthMethod authMethod;

  /// OAuth provider (`microsoft`) and the app registration the tokens were
  /// issued to, so refreshing keeps working if the default one changes.
  final String? oauthProvider;
  final String? oauthClientId;
  final String? oauthTenant;

  // Account state
  final bool isDefault;
  final bool isEnabled;

  /// Plain-text signature (for plain-text messages).
  final String? signature;

  /// Formatted signature (for HTML messages); [signature] is its text.
  final String? signatureHtml;

  /// How often the account's folders are checked for new mail.
  final int syncIntervalMinutes;

  /// POP3 only: keep messages on the server after downloading them.
  final bool leaveMessagesOnServer;

  /// Accept TLS certificates that cannot be verified (self-signed servers).
  final bool acceptInvalidCertificates;

  const EmailAccount({
    required this.id,
    required this.displayName,
    required this.emailAddress,
    this.protocol = IncomingProtocol.imap,
    required this.incomingHost,
    required this.incomingPort,
    this.incomingSecurity = ConnectionSecurity.ssl,
    required this.smtpHost,
    required this.smtpPort,
    this.smtpSecurity = ConnectionSecurity.starttls,
    required this.username,
    required this.password,
    this.authMethod = AuthMethod.password,
    this.oauthProvider,
    this.oauthClientId,
    this.oauthTenant,
    this.isDefault = false,
    this.isEnabled = true,
    this.signature,
    this.signatureHtml,
    this.syncIntervalMinutes = 5,
    this.leaveMessagesOnServer = true,
    this.acceptInvalidCertificates = false,
  });

  bool get isPop3 => protocol == IncomingProtocol.pop3;

  bool get usesOAuth => authMethod == AuthMethod.oauth2;

  /// "Name <address>" form used for the From header.
  String get fromDisplay =>
      displayName.isNotEmpty && displayName != emailAddress
          ? '$displayName <$emailAddress>'
          : emailAddress;

  EmailAccount copyWith({
    String? id,
    String? displayName,
    String? emailAddress,
    IncomingProtocol? protocol,
    String? incomingHost,
    int? incomingPort,
    ConnectionSecurity? incomingSecurity,
    String? smtpHost,
    int? smtpPort,
    ConnectionSecurity? smtpSecurity,
    String? username,
    String? password,
    AuthMethod? authMethod,
    String? oauthProvider,
    String? oauthClientId,
    String? oauthTenant,
    bool? isDefault,
    bool? isEnabled,
    String? signature,
    String? signatureHtml,
    bool clearSignature = false,
    int? syncIntervalMinutes,
    bool? leaveMessagesOnServer,
    bool? acceptInvalidCertificates,
  }) {
    return EmailAccount(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      emailAddress: emailAddress ?? this.emailAddress,
      protocol: protocol ?? this.protocol,
      incomingHost: incomingHost ?? this.incomingHost,
      incomingPort: incomingPort ?? this.incomingPort,
      incomingSecurity: incomingSecurity ?? this.incomingSecurity,
      smtpHost: smtpHost ?? this.smtpHost,
      smtpPort: smtpPort ?? this.smtpPort,
      smtpSecurity: smtpSecurity ?? this.smtpSecurity,
      username: username ?? this.username,
      password: password ?? this.password,
      authMethod: authMethod ?? this.authMethod,
      oauthProvider: oauthProvider ?? this.oauthProvider,
      oauthClientId: oauthClientId ?? this.oauthClientId,
      oauthTenant: oauthTenant ?? this.oauthTenant,
      isDefault: isDefault ?? this.isDefault,
      isEnabled: isEnabled ?? this.isEnabled,
      signature: clearSignature ? null : (signature ?? this.signature),
      signatureHtml:
          clearSignature ? null : (signatureHtml ?? this.signatureHtml),
      syncIntervalMinutes: syncIntervalMinutes ?? this.syncIntervalMinutes,
      leaveMessagesOnServer:
          leaveMessagesOnServer ?? this.leaveMessagesOnServer,
      acceptInvalidCertificates:
          acceptInvalidCertificates ?? this.acceptInvalidCertificates,
    );
  }

  /// Serializes the account. The password is only included when
  /// [includePassword] is true; the database stores it encrypted separately.
  Map<String, dynamic> toMap({bool includePassword = true}) => {
        'id': id,
        'displayName': displayName,
        'emailAddress': emailAddress,
        'protocol': protocol.name,
        'incomingHost': incomingHost,
        'incomingPort': incomingPort,
        'incomingSecurity': incomingSecurity.name,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        'smtpSecurity': smtpSecurity.name,
        'username': username,
        if (includePassword) 'password': password,
        'authMethod': authMethod.name,
        'oauthProvider': ?oauthProvider,
        'oauthClientId': ?oauthClientId,
        'oauthTenant': ?oauthTenant,
        'isDefault': isDefault ? 1 : 0,
        'isEnabled': isEnabled ? 1 : 0,
        'signature': signature,
        'signatureHtml': ?signatureHtml,
        'syncIntervalMinutes': syncIntervalMinutes,
        'leaveMessagesOnServer': leaveMessagesOnServer ? 1 : 0,
        'acceptInvalidCertificates': acceptInvalidCertificates ? 1 : 0,
      };

  /// Deserializes an account. Also accepts the pre-0.2 format that used
  /// `imapHost`/`imapPort`/`imapSecurity` keys (SharedPreferences storage).
  factory EmailAccount.fromMap(Map<String, dynamic> map) => EmailAccount(
        id: map['id'] as String,
        displayName: map['displayName'] as String? ?? '',
        emailAddress: map['emailAddress'] as String,
        protocol: IncomingProtocol.values
                .asNameMap()[map['protocol'] as String? ?? 'imap'] ??
            IncomingProtocol.imap,
        incomingHost:
            (map['incomingHost'] ?? map['imapHost']) as String? ?? '',
        incomingPort: (map['incomingPort'] ?? map['imapPort']) as int? ?? 993,
        incomingSecurity: ConnectionSecurity.parse(
            (map['incomingSecurity'] ?? map['imapSecurity']) as String?,
            ConnectionSecurity.ssl),
        smtpHost: map['smtpHost'] as String? ?? '',
        smtpPort: map['smtpPort'] as int? ?? 587,
        smtpSecurity: ConnectionSecurity.parse(
            map['smtpSecurity'] as String?, ConnectionSecurity.starttls),
        username: map['username'] as String? ?? '',
        password: map['password'] as String? ?? '',
        authMethod: AuthMethod.values
                .asNameMap()[map['authMethod'] as String? ?? 'password'] ??
            AuthMethod.password,
        oauthProvider: map['oauthProvider'] as String?,
        oauthClientId: map['oauthClientId'] as String?,
        oauthTenant: map['oauthTenant'] as String?,
        isDefault: (map['isDefault'] as int? ?? 0) == 1,
        isEnabled: (map['isEnabled'] as int? ?? 1) == 1,
        signature: map['signature'] as String?,
        signatureHtml: map['signatureHtml'] as String?,
        syncIntervalMinutes: map['syncIntervalMinutes'] as int? ?? 5,
        leaveMessagesOnServer:
            (map['leaveMessagesOnServer'] as int? ?? 1) == 1,
        acceptInvalidCertificates:
            (map['acceptInvalidCertificates'] as int? ?? 0) == 1,
      );
}

/// How Look In signs in to the account's servers.
enum AuthMethod {
  password,

  /// OAuth 2.0 (XOAUTH2 for IMAP and SMTP), e.g. "Sign in with Microsoft".
  oauth2,
}

enum IncomingProtocol {
  imap,
  pop3;

  String get label => this == IncomingProtocol.imap ? 'IMAP' : 'POP3';

  int defaultPort(ConnectionSecurity security) {
    switch (this) {
      case IncomingProtocol.imap:
        return security == ConnectionSecurity.ssl ? 993 : 143;
      case IncomingProtocol.pop3:
        return security == ConnectionSecurity.ssl ? 995 : 110;
    }
  }
}

enum ConnectionSecurity {
  none,
  ssl,
  starttls;

  String get label {
    switch (this) {
      case ConnectionSecurity.none:
        return 'None';
      case ConnectionSecurity.ssl:
        return 'SSL/TLS';
      case ConnectionSecurity.starttls:
        return 'STARTTLS';
    }
  }

  static ConnectionSecurity parse(String? name, ConnectionSecurity fallback) =>
      ConnectionSecurity.values.asNameMap()[name] ?? fallback;
}

/// Well-known email provider configurations for auto-detection.
class EmailProviderConfig {
  final String name;
  final List<String> domains;
  final String imapHost;
  final int imapPort;
  final ConnectionSecurity imapSecurity;
  final String smtpHost;
  final int smtpPort;
  final ConnectionSecurity smtpSecurity;
  final String? popHost;

  /// Shown in the setup wizard, e.g. that an app password is required.
  final String? note;

  /// Sign-in provider when the service uses OAuth (`microsoft`).
  final String? oauthProvider;

  const EmailProviderConfig({
    required this.name,
    required this.domains,
    required this.imapHost,
    required this.imapPort,
    required this.imapSecurity,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSecurity,
    this.popHost,
    this.note,
    this.oauthProvider,
  });

  static const _outlookImapNote = 'If sign-in works but no mail arrives, '
      'check that IMAP is allowed for the mailbox (Outlook.com: Settings > '
      'Mail > Forwarding and IMAP; Microsoft 365: ask your administrator).';

  /// Exchange Online mailboxes on custom domains, recognized by their MX
  /// records (see [isMicrosoftMx]).
  static const microsoft365 = EmailProviderConfig(
    name: 'Microsoft 365',
    domains: [],
    imapHost: 'outlook.office365.com',
    imapPort: 993,
    imapSecurity: ConnectionSecurity.ssl,
    smtpHost: 'smtp.office365.com',
    smtpPort: 587,
    smtpSecurity: ConnectionSecurity.starttls,
    note: _outlookImapNote,
    oauthProvider: 'microsoft',
  );

  /// Whether an MX host belongs to Exchange Online / Outlook.com.
  static bool isMicrosoftMx(String host) {
    final h = host.toLowerCase().replaceAll(RegExp(r'\.$'), '');
    return h.endsWith('.mail.protection.outlook.com') ||
        h.endsWith('.olc.protection.outlook.com') ||
        h.endsWith('.mail.eo.outlook.com');
  }

  /// Whether a server name is Microsoft's IMAP/POP/SMTP endpoint.
  static bool isMicrosoftHost(String host) => const {
        'outlook.office365.com',
        'outlook.office.com',
        'smtp.office365.com',
        'smtp-mail.outlook.com',
        'imap-mail.outlook.com',
      }.contains(host.trim().toLowerCase());

  static const List<EmailProviderConfig> knownProviders = [
    EmailProviderConfig(
      name: 'Gmail',
      domains: ['gmail.com', 'googlemail.com'],
      imapHost: 'imap.gmail.com',
      imapPort: 993,
      imapSecurity: ConnectionSecurity.ssl,
      smtpHost: 'smtp.gmail.com',
      smtpPort: 587,
      smtpSecurity: ConnectionSecurity.starttls,
      popHost: 'pop.gmail.com',
      note: 'Gmail only accepts an app password: turn on 2-Step Verification, '
          'then create one under Google Account > Security > App passwords.',
    ),
    EmailProviderConfig(
      name: 'Outlook.com',
      domains: ['outlook.com', 'hotmail.com', 'live.com', 'msn.com'],
      imapHost: 'outlook.office365.com',
      imapPort: 993,
      imapSecurity: ConnectionSecurity.ssl,
      smtpHost: 'smtp.office365.com',
      smtpPort: 587,
      smtpSecurity: ConnectionSecurity.starttls,
      popHost: 'outlook.office365.com',
      note: _outlookImapNote,
      oauthProvider: 'microsoft',
    ),
    EmailProviderConfig(
      name: 'Yahoo Mail',
      domains: ['yahoo.com', 'ymail.com'],
      imapHost: 'imap.mail.yahoo.com',
      imapPort: 993,
      imapSecurity: ConnectionSecurity.ssl,
      smtpHost: 'smtp.mail.yahoo.com',
      smtpPort: 587,
      smtpSecurity: ConnectionSecurity.starttls,
      popHost: 'pop.mail.yahoo.com',
      note: 'Yahoo requires an app password for third-party clients.',
    ),
    EmailProviderConfig(
      name: 'iCloud',
      domains: ['icloud.com', 'me.com', 'mac.com'],
      imapHost: 'imap.mail.me.com',
      imapPort: 993,
      imapSecurity: ConnectionSecurity.ssl,
      smtpHost: 'smtp.mail.me.com',
      smtpPort: 587,
      smtpSecurity: ConnectionSecurity.starttls,
      note: 'iCloud requires an app-specific password.',
    ),
    EmailProviderConfig(
      name: 'Fastmail',
      domains: ['fastmail.com', 'fastmail.fm'],
      imapHost: 'imap.fastmail.com',
      imapPort: 993,
      imapSecurity: ConnectionSecurity.ssl,
      smtpHost: 'smtp.fastmail.com',
      smtpPort: 587,
      smtpSecurity: ConnectionSecurity.starttls,
      popHost: 'pop.fastmail.com',
    ),
    EmailProviderConfig(
      name: 'ProtonMail Bridge',
      domains: ['protonmail.com', 'proton.me', 'pm.me'],
      imapHost: '127.0.0.1',
      imapPort: 1143,
      imapSecurity: ConnectionSecurity.starttls,
      smtpHost: '127.0.0.1',
      smtpPort: 1025,
      smtpSecurity: ConnectionSecurity.starttls,
      note: 'Requires Proton Mail Bridge running locally.',
    ),
    EmailProviderConfig(
      name: 'GMX',
      domains: ['gmx.com', 'gmx.net', 'gmx.de'],
      imapHost: 'imap.gmx.com',
      imapPort: 993,
      imapSecurity: ConnectionSecurity.ssl,
      smtpHost: 'mail.gmx.com',
      smtpPort: 587,
      smtpSecurity: ConnectionSecurity.starttls,
      popHost: 'pop.gmx.com',
    ),
    EmailProviderConfig(
      name: 'Zoho Mail',
      domains: ['zoho.com', 'zohomail.com'],
      imapHost: 'imap.zoho.com',
      imapPort: 993,
      imapSecurity: ConnectionSecurity.ssl,
      smtpHost: 'smtp.zoho.com',
      smtpPort: 587,
      smtpSecurity: ConnectionSecurity.starttls,
      popHost: 'pop.zoho.com',
    ),
  ];

  static EmailProviderConfig? detectFromEmail(String email) {
    final at = email.lastIndexOf('@');
    if (at < 0 || at == email.length - 1) return null;
    final domain = email.substring(at + 1).trim().toLowerCase();
    for (final provider in knownProviders) {
      if (provider.domains.contains(domain)) return provider;
    }
    return null;
  }
}
