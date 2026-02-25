import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../models/email_account.dart';

/// OAuth 2.0 provider configuration.
class OAuthConfig {
  final OAuthProvider provider;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String clientId;
  final String? clientSecret;
  final List<String> scopes;
  final String providerName;
  final String imapHost;
  final int imapPort;
  final String smtpHost;
  final int smtpPort;

  const OAuthConfig({
    required this.provider,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.clientId,
    this.clientSecret,
    required this.scopes,
    required this.providerName,
    required this.imapHost,
    required this.imapPort,
    required this.smtpHost,
    required this.smtpPort,
  });
}

/// Result of an OAuth authentication flow.
class OAuthResult {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiry;
  final String email;

  const OAuthResult({
    required this.accessToken,
    this.refreshToken,
    this.expiry,
    required this.email,
  });
}

/// Handles OAuth 2.0 authorization code flows for email providers.
///
/// Uses a loopback redirect (local HTTP server) to intercept the
/// authorization callback, which works on both desktop and mobile.
class OAuthService {
  // ─── Provider Configurations ────────────────────────────────────────
  //
  // To use OAuth, register your app with each provider and replace the
  // client IDs below with your own:
  //
  //   Google: https://console.cloud.google.com/apis/credentials
  //   Microsoft: https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps
  //   Yahoo: https://developer.yahoo.com/apps/

  static const _configs = <OAuthProvider, OAuthConfig>{
    OAuthProvider.google: OAuthConfig(
      provider: OAuthProvider.google,
      providerName: 'Google',
      authorizationEndpoint:
          'https://accounts.google.com/o/oauth2/v2/auth',
      tokenEndpoint: 'https://oauth2.googleapis.com/token',
      // Replace with your registered Google OAuth client ID
      clientId: 'YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com',
      scopes: [
        'https://mail.google.com/',
        'email',
        'profile',
      ],
      imapHost: 'imap.gmail.com',
      imapPort: 993,
      smtpHost: 'smtp.gmail.com',
      smtpPort: 587,
    ),
    OAuthProvider.microsoft: OAuthConfig(
      provider: OAuthProvider.microsoft,
      providerName: 'Microsoft',
      authorizationEndpoint:
          'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
      tokenEndpoint:
          'https://login.microsoftonline.com/common/oauth2/v2.0/token',
      // Replace with your registered Azure AD application (client) ID
      clientId: 'YOUR_MICROSOFT_CLIENT_ID',
      scopes: [
        'https://outlook.office.com/IMAP.AccessAsUser.All',
        'https://outlook.office.com/SMTP.Send',
        'offline_access',
        'email',
        'profile',
        'openid',
      ],
      imapHost: 'outlook.office365.com',
      imapPort: 993,
      smtpHost: 'smtp.office365.com',
      smtpPort: 587,
    ),
    OAuthProvider.yahoo: OAuthConfig(
      provider: OAuthProvider.yahoo,
      providerName: 'Yahoo',
      authorizationEndpoint:
          'https://api.login.yahoo.com/oauth2/request_auth',
      tokenEndpoint:
          'https://api.login.yahoo.com/oauth2/get_token',
      // Replace with your registered Yahoo app client ID
      clientId: 'YOUR_YAHOO_CLIENT_ID',
      clientSecret: 'YOUR_YAHOO_CLIENT_SECRET',
      scopes: ['mail-w'],
      imapHost: 'imap.mail.yahoo.com',
      imapPort: 993,
      smtpHost: 'smtp.mail.yahoo.com',
      smtpPort: 587,
    ),
  };

  static OAuthConfig? getConfig(OAuthProvider provider) => _configs[provider];

  /// Run the full OAuth 2.0 authorization code flow:
  /// 1. Start a local HTTP server to receive the redirect
  /// 2. Open the provider's consent page in the system browser
  /// 3. Wait for the user to authorize
  /// 4. Exchange the authorization code for tokens
  static Future<OAuthResult> authenticate(OAuthProvider provider) async {
    final config = _configs[provider];
    if (config == null) {
      throw Exception('No OAuth configuration for $provider');
    }

    // Find an available port for the loopback redirect server
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final redirectUri = 'http://localhost:$port/callback';

    try {
      // Build the authorization URL
      final authUrl = Uri.parse(config.authorizationEndpoint).replace(
        queryParameters: {
          'client_id': config.clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': config.scopes.join(' '),
          'access_type': 'offline',
          'prompt': 'consent',
        },
      );

      // Open browser for user consent
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open browser for authentication');
      }

      // Wait for the redirect with the authorization code
      final code = await _waitForAuthCode(server);

      // Exchange the code for tokens
      final tokens = await _exchangeCode(config, code, redirectUri);

      return tokens;
    } finally {
      await server.close();
    }
  }

  /// Listen on the local HTTP server for the OAuth redirect.
  static Future<String> _waitForAuthCode(HttpServer server) async {
    final completer = Completer<String>();

    server.listen((request) async {
      try {
        final code = request.uri.queryParameters['code'];
        final error = request.uri.queryParameters['error'];

        if (error != null) {
          // Show error page
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write(_buildHtmlPage(
              'Authentication Failed',
              'Error: $error. You can close this window.',
              isError: true,
            ));
          await request.response.close();
          if (!completer.isCompleted) {
            completer.completeError(Exception('OAuth error: $error'));
          }
          return;
        }

        if (code != null) {
          // Show success page
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write(_buildHtmlPage(
              'Authentication Successful',
              'You can close this window and return to Look In.',
            ));
          await request.response.close();
          if (!completer.isCompleted) {
            completer.complete(code);
          }
        } else {
          request.response
            ..statusCode = 400
            ..write('Missing authorization code');
          await request.response.close();
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      }
    });

    // Timeout after 5 minutes
    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => throw TimeoutException(
        'Authentication timed out. Please try again.',
      ),
    );
  }

  /// Exchange an authorization code for access and refresh tokens.
  static Future<OAuthResult> _exchangeCode(
    OAuthConfig config,
    String code,
    String redirectUri,
  ) async {
    final body = {
      'client_id': config.clientId,
      'code': code,
      'redirect_uri': redirectUri,
      'grant_type': 'authorization_code',
    };

    if (config.clientSecret != null) {
      body['client_secret'] = config.clientSecret!;
    }

    final response = await http.post(
      Uri.parse(config.tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Token exchange failed (${response.statusCode}): ${response.body}',
      );
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final accessToken = data['access_token'] as String;
    final refreshToken = data['refresh_token'] as String?;
    final expiresIn = data['expires_in'] as int?;
    final expiry = expiresIn != null
        ? DateTime.now().add(Duration(seconds: expiresIn))
        : null;

    // Extract email from ID token or userinfo
    final email = await _extractEmail(config, data, accessToken);

    return OAuthResult(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiry: expiry,
      email: email,
    );
  }

  /// Refresh an expired access token using the refresh token.
  static Future<OAuthResult> refreshAccessToken(
    OAuthProvider provider,
    String refreshToken,
    String email,
  ) async {
    final config = _configs[provider];
    if (config == null) {
      throw Exception('No OAuth configuration for $provider');
    }

    final body = {
      'client_id': config.clientId,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    };

    if (config.clientSecret != null) {
      body['client_secret'] = config.clientSecret!;
    }

    final response = await http.post(
      Uri.parse(config.tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Token refresh failed (${response.statusCode}): ${response.body}',
      );
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final accessToken = data['access_token'] as String;
    final newRefreshToken = data['refresh_token'] as String? ?? refreshToken;
    final expiresIn = data['expires_in'] as int?;
    final expiry = expiresIn != null
        ? DateTime.now().add(Duration(seconds: expiresIn))
        : null;

    return OAuthResult(
      accessToken: accessToken,
      refreshToken: newRefreshToken,
      expiry: expiry,
      email: email,
    );
  }

  /// Extract the user's email from the ID token or userinfo endpoint.
  static Future<String> _extractEmail(
    OAuthConfig config,
    Map<String, dynamic> tokenData,
    String accessToken,
  ) async {
    // Try to decode email from ID token (JWT)
    final idToken = tokenData['id_token'] as String?;
    if (idToken != null) {
      try {
        final parts = idToken.split('.');
        if (parts.length == 3) {
          final payload = parts[1];
          // Add padding for base64
          final padded = payload.padRight(
            (payload.length + 3) & ~3,
            '=',
          );
          final decoded = json.decode(
            utf8.decode(base64Url.decode(padded)),
          ) as Map<String, dynamic>;
          final email = decoded['email'] as String?;
          if (email != null && email.isNotEmpty) return email;
        }
      } catch (e) {
        debugPrint('Failed to decode ID token: $e');
      }
    }

    // Fallback: call userinfo endpoint
    try {
      String userinfoUrl;
      switch (config.provider) {
        case OAuthProvider.google:
          userinfoUrl = 'https://www.googleapis.com/oauth2/v3/userinfo';
          break;
        case OAuthProvider.microsoft:
          userinfoUrl = 'https://graph.microsoft.com/v1.0/me';
          break;
        case OAuthProvider.yahoo:
          userinfoUrl =
              'https://api.login.yahoo.com/openid/v1/userinfo';
          break;
      }

      final response = await http.get(
        Uri.parse(userinfoUrl),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final email = (data['email'] ?? data['mail'] ?? data['userPrincipalName']) as String?;
        if (email != null && email.isNotEmpty) return email;
      }
    } catch (e) {
      debugPrint('Failed to fetch userinfo: $e');
    }

    throw Exception(
      'Could not determine email address from OAuth response',
    );
  }

  static String _buildHtmlPage(String title, String message,
      {bool isError = false}) {
    final color = isError ? '#d32f2f' : '#0078d4';
    return '''
<!DOCTYPE html>
<html>
<head><title>$title</title></head>
<body style="font-family: Segoe UI, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #f5f5f5;">
  <div style="text-align: center; padding: 40px; background: white; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
    <h2 style="color: $color;">$title</h2>
    <p style="color: #666;">$message</p>
  </div>
</body>
</html>
''';
  }
}
