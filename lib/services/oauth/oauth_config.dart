import 'dart:convert';
import 'dart:io';

/// Which Microsoft accounts an app registration signs in, i.e. the
/// "authority" path segment of the Microsoft identity platform.
enum MicrosoftAudience {
  /// Work or school and personal accounts (`common`).
  any('common', 'Work or school, and personal Microsoft accounts'),

  /// Work or school accounts in any organization (`organizations`).
  work('organizations', 'Work or school accounts (any organization)'),

  /// Personal accounts: Outlook.com, Hotmail, Live (`consumers`).
  personal('consumers', 'Personal Microsoft accounts only'),

  /// One organization, identified by its tenant ID or domain.
  singleTenant('', 'Accounts in one organization only');

  final String authority;
  final String label;

  const MicrosoftAudience(this.authority, this.label);

  static MicrosoftAudience fromTenant(String tenant) {
    for (final a in values) {
      if (a.authority.isNotEmpty && a.authority == tenant) return a;
    }
    return tenant.isEmpty ? any : singleTenant;
  }
}

/// An app registration the user or their organization created in
/// Microsoft Entra ("bring your own"): Look In ships no client ID.
class OAuthRegistration {
  final String clientId;

  /// `common`, `organizations`, `consumers`, or a tenant ID/domain.
  final String tenant;

  /// Where it came from, for the Options page (`settings`, a file path,
  /// or `build`).
  final String source;

  const OAuthRegistration({
    required this.clientId,
    this.tenant = 'common',
    this.source = 'settings',
  });

  bool get isValid => isValidClientId(clientId) && tenant.trim().isNotEmpty;

  MicrosoftAudience get audience => MicrosoftAudience.fromTenant(tenant);

  Map<String, dynamic> toMap() => {'clientId': clientId, 'tenant': tenant};

  static OAuthRegistration? fromMap(Object? map, {String source = 'settings'}) {
    if (map is! Map) return null;
    final clientId = (map['clientId'] as String?)?.trim() ?? '';
    final tenant = (map['tenant'] as String?)?.trim();
    final registration = OAuthRegistration(
      clientId: clientId,
      tenant: tenant == null || tenant.isEmpty ? 'common' : tenant,
      source: source,
    );
    return registration.isValid ? registration : null;
  }

  /// Application (client) IDs are GUIDs.
  static bool isValidClientId(String id) => RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          caseSensitive: false)
      .hasMatch(id.trim());
}

/// Endpoints and scopes of one OAuth 2.0 provider.
class OAuthProviderConfig {
  /// `microsoft` (and later `google`).
  final String id;
  final String name;
  final Uri authorizeUrl;
  final Uri tokenUrl;
  final String clientId;

  /// Extra authorization parameters, e.g. `prompt=select_account`.
  final Map<String, String> authorizeParameters;

  const OAuthProviderConfig({
    required this.id,
    required this.name,
    required this.authorizeUrl,
    required this.tokenUrl,
    required this.clientId,
    this.authorizeParameters = const {},
  });

  static const microsoftId = 'microsoft';

  /// The Microsoft identity platform's address; tests point it at a local
  /// fake server.
  static String microsoftLoginBase = 'https://login.microsoftonline.com';

  /// The Microsoft identity platform (v2.0 endpoints) for [registration].
  factory OAuthProviderConfig.microsoft(OAuthRegistration registration) {
    final base =
        '$microsoftLoginBase/${registration.tenant}/oauth2/v2.0';
    return OAuthProviderConfig(
      id: microsoftId,
      name: 'Microsoft',
      authorizeUrl: Uri.parse('$base/authorize'),
      tokenUrl: Uri.parse('$base/token'),
      clientId: registration.clientId,
      authorizeParameters: const {'prompt': 'select_account'},
    );
  }

  /// URL an administrator opens to approve the app for their organization.
  static Uri microsoftAdminConsentUrl(OAuthRegistration registration,
      {String? tenant}) {
    final t = tenant ??
        (registration.audience == MicrosoftAudience.singleTenant
            ? registration.tenant
            : 'organizations');
    return Uri.parse('https://login.microsoftonline.com/$t/adminconsent'
        '?client_id=${Uri.encodeComponent(registration.clientId)}');
  }
}

/// The APIs Look In gets access tokens for. One sign-in (refresh token)
/// serves all of them; each needs its own access token.
enum OAuthResource {
  /// IMAP and SMTP on outlook.office.com (both account types).
  outlookMail([
    'https://outlook.office.com/IMAP.AccessAsUser.All',
    'https://outlook.office.com/SMTP.Send',
  ]),

  /// Microsoft Graph: mail, calendar and contacts.
  graph([
    'https://graph.microsoft.com/User.Read',
    'https://graph.microsoft.com/Mail.ReadWrite',
    'https://graph.microsoft.com/Mail.Send',
    'https://graph.microsoft.com/Calendars.ReadWrite',
    'https://graph.microsoft.com/Contacts.ReadWrite',
  ]);

  final List<String> scopes;

  const OAuthResource(this.scopes);

  /// Scopes for the initial sign-in: this resource plus a refresh token and
  /// the user's name and address in the ID token.
  List<String> get signInScopes =>
      [...scopes, 'offline_access', 'openid', 'profile', 'email'];
}

/// Finds the Microsoft app registration to use, in this order:
///
/// 1. What the user entered in Options (the `oauth.microsoft` setting).
/// 2. `$XDG_CONFIG_HOME/look-in/oauth.json` (per user) and
///    `/etc/look-in/oauth.json` (for administrators), with the content
///    `{"microsoft": {"clientId": "…", "tenant": "…"}}`.
/// 3. A build-time default:
///    `--dart-define=LOOKIN_MS_CLIENT_ID=… --dart-define=LOOKIN_MS_TENANT=…`.
class OAuthRegistrations {
  OAuthRegistrations._();

  static const settingKey = 'oauth.microsoft';

  static const _buildClientId = String.fromEnvironment('LOOKIN_MS_CLIENT_ID');
  static const _buildTenant =
      String.fromEnvironment('LOOKIN_MS_TENANT', defaultValue: 'common');

  static OAuthRegistration? microsoft({
    String? setting,
    List<String>? configFiles,
    String buildClientId = _buildClientId,
    String buildTenant = _buildTenant,
  }) {
    if (setting != null && setting.isNotEmpty) {
      try {
        final r = OAuthRegistration.fromMap(jsonDecode(setting));
        if (r != null) return r;
      } catch (_) {}
    }
    final fromFiles = provisioned(configFiles: configFiles);
    if (fromFiles != null) return fromFiles;
    if (buildClientId.isNotEmpty) {
      return OAuthRegistration.fromMap(
          {'clientId': buildClientId, 'tenant': buildTenant},
          source: 'build');
    }
    return null;
  }

  /// A registration provided by a configuration file, if any.
  static OAuthRegistration? provisioned({List<String>? configFiles}) {
    for (final path in configFiles ?? defaultConfigFiles()) {
      try {
        final file = File(path);
        if (!file.existsSync()) continue;
        final json = jsonDecode(file.readAsStringSync());
        if (json is Map) {
          final r = OAuthRegistration.fromMap(json['microsoft'], source: path);
          if (r != null) return r;
        }
      } catch (_) {
        // Unreadable or malformed: try the next file.
      }
    }
    return null;
  }

  static List<String> defaultConfigFiles() {
    final env = Platform.environment;
    final configHome = env['XDG_CONFIG_HOME']?.isNotEmpty == true
        ? env['XDG_CONFIG_HOME']!
        : '${env['HOME'] ?? ''}/.config';
    return ['$configHome/look-in/oauth.json', '/etc/look-in/oauth.json'];
  }
}
