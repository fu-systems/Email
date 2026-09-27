import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

import 'oauth_config.dart';

/// Tokens from a token endpoint response.
class OAuthTokens {
  final String accessToken;
  final DateTime expiresAt;
  final String? refreshToken;
  final String? idToken;
  final List<String> scopes;

  const OAuthTokens({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
    this.idToken,
    this.scopes = const [],
  });

  /// Parses a token response received at [now].
  factory OAuthTokens.fromResponse(Map<String, dynamic> json, DateTime now) {
    final accessToken = json['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const OAuthException('invalid_response',
          'The sign-in server returned no access token.');
    }
    final expiresIn = switch (json['expires_in']) {
      final int v => v,
      final String v => int.tryParse(v) ?? 3600,
      _ => 3600,
    };
    return OAuthTokens(
      accessToken: accessToken,
      expiresAt: now.add(Duration(seconds: expiresIn)),
      refreshToken: json['refresh_token'] as String?,
      idToken: json['id_token'] as String?,
      scopes: (json['scope'] as String? ?? '')
          .split(' ')
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }

  /// Claims of the ID token. The token comes straight from the token
  /// endpoint over TLS, so its signature isn't checked.
  Map<String, dynamic> get idClaims => decodeJwtPayload(idToken);

  /// The sign-in name (UPN or email address) from the ID token.
  String? get username {
    final c = idClaims;
    for (final key in const ['preferred_username', 'email', 'upn']) {
      final v = c[key];
      if (v is String && v.contains('@')) return v;
    }
    return null;
  }

  String? get displayName => idClaims['name'] as String?;

  static Map<String, dynamic> decodeJwtPayload(String? jwt) {
    if (jwt == null) return const {};
    final parts = jwt.split('.');
    if (parts.length < 2) return const {};
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final json = jsonDecode(payload);
      return json is Map<String, dynamic> ? json : const {};
    } catch (_) {
      return const {};
    }
  }
}

/// An OAuth error (`error` code plus the server's description).
class OAuthException implements Exception {
  final String error;
  final String? description;

  const OAuthException(this.error, [this.description]);

  /// Microsoft's AADSTS error number, e.g. `65001` (consent required).
  String? get aadstsCode =>
      RegExp(r'AADSTS(\d+)').firstMatch(description ?? '')?.group(1);

  /// The sign-in is no longer valid (expired, revoked, password changed).
  bool get isInvalidGrant => error == 'invalid_grant';

  /// An administrator must approve the app for the organization.
  bool get needsAdminConsent =>
      const {'65001', '90094', '90095', '900941', '50105'}
          .contains(aadstsCode) ||
      (description ?? '').toLowerCase().contains('admin approval') ||
      (description ?? '').toLowerCase().contains('administrator');

  @override
  String toString() {
    final text = description?.split(RegExp(r'\r?\n')).first.trim();
    return text == null || text.isEmpty ? 'Sign-in failed ($error)' : text;
  }
}

/// A sign-in in progress: the browser is open and the local redirect
/// listener waits for the result.
class OAuthSignIn {
  final Uri authorizeUrl;
  final Future<OAuthTokens> result;
  final void Function() _cancel;

  OAuthSignIn._(this.authorizeUrl, this.result, this._cancel);

  /// Stops waiting; [result] completes with `OAuthException('cancelled')`.
  void cancel() => _cancel();
}

/// OAuth 2.0 authorization code flow with PKCE for a public (desktop)
/// client: the system browser signs in and redirects to a one-shot HTTP
/// listener on the loopback interface (`http://localhost:<port>`).
class OAuthFlow {
  OAuthFlow._();

  /// Replaces the browser in tests: receives the authorization URL and
  /// plays the user's part.
  static Future<bool> Function(Uri url)? launchOverride;

  /// Starts a sign-in. [launch] opens the URL (default: the system
  /// browser); [httpClient] is for tests.
  static Future<OAuthSignIn> start(
    OAuthProviderConfig config, {
    required List<String> scopes,
    String? loginHint,
    Future<bool> Function(Uri url)? launch,
    Duration timeout = const Duration(minutes: 5),
    HttpClient? httpClient,
  }) async {
    final verifier = randomUrlSafe(32);
    final state = randomUrlSafe(16);
    final servers = await _bindLoopback();
    final port = servers.first.port;
    final redirectUri = 'http://localhost:$port';
    final url = config.authorizeUrl.replace(queryParameters: {
      ...config.authorizeUrl.queryParameters,
      'client_id': config.clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'response_mode': 'query',
      'scope': scopes.join(' '),
      'state': state,
      'code_challenge': pkceChallenge(verifier),
      'code_challenge_method': 'S256',
      ...config.authorizeParameters,
      if (loginHint != null && loginHint.isNotEmpty) 'login_hint': loginHint,
    });

    final completer = Completer<OAuthTokens>();
    // The redirect may fail before the caller listens: don't report that as
    // an unhandled error (listeners still see it).
    completer.future.ignore();
    Timer? timer;
    Future<void> finish() async {
      timer?.cancel();
      for (final s in servers) {
        await s.close(force: true);
      }
    }

    void fail(Object error) {
      if (!completer.isCompleted) completer.completeError(error);
      unawaited(finish());
    }

    timer = Timer(timeout, () => fail(const OAuthException(
        'timeout', 'Sign-in timed out. Try again.')));

    for (final server in servers) {
      server.listen((request) async {
        final query = request.uri.queryParameters;
        if (request.uri.path != '/' ||
            (!query.containsKey('code') && !query.containsKey('error'))) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        if (completer.isCompleted) {
          await _respond(request, ok: false, text: 'This sign-in has ended.');
          return;
        }
        if (query['state'] != state) {
          await _respond(request,
              ok: false, text: 'The sign-in response did not match.');
          fail(const OAuthException(
              'state_mismatch', 'The sign-in response did not match.'));
          return;
        }
        final error = query['error'];
        if (error != null) {
          final e = OAuthException(error, query['error_description']);
          await _respond(request, ok: false, text: e.toString());
          fail(e);
          return;
        }
        // Redeem the code before answering so the page tells the truth.
        try {
          final tokens = await _tokenRequest(
            config,
            {
              'grant_type': 'authorization_code',
              'code': query['code']!,
              'redirect_uri': redirectUri,
              'code_verifier': verifier,
              'scope': scopes.join(' '),
            },
            httpClient: httpClient,
          );
          await _respond(request,
              ok: true,
              text: 'You are signed in to Look In. You can close this tab.');
          if (!completer.isCompleted) completer.complete(tokens);
          unawaited(finish());
        } catch (e) {
          await _respond(request, ok: false, text: e.toString());
          fail(e);
        }
      });
    }

    final opener = launch ??
        launchOverride ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    try {
      if (!await opener(url)) {
        // The dialog shows the link so it can be opened by hand.
      }
    } catch (_) {}

    return OAuthSignIn._(url, completer.future,
        () => fail(const OAuthException('cancelled', 'Sign-in cancelled.')));
  }

  /// Gets new tokens with a refresh token. Microsoft may rotate the
  /// refresh token; the result then carries the new one.
  static Future<OAuthTokens> refresh(
    OAuthProviderConfig config,
    String refreshToken, {
    required List<String> scopes,
    HttpClient? httpClient,
  }) =>
      _tokenRequest(
        config,
        {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'scope': scopes.join(' '),
        },
        httpClient: httpClient,
      );

  static Future<OAuthTokens> _tokenRequest(
    OAuthProviderConfig config,
    Map<String, String> form, {
    HttpClient? httpClient,
  }) async {
    final client =
        httpClient ?? (HttpClient()..connectionTimeout = const Duration(seconds: 20));
    try {
      final request = await client.postUrl(config.tokenUrl);
      request.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(Uri(queryParameters: {
        'client_id': config.clientId,
        ...form,
      }).query);
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final body = await response.transform(utf8.decoder).join();
      Map<String, dynamic> json;
      try {
        json = (jsonDecode(body) as Map).cast<String, dynamic>();
      } catch (_) {
        throw OAuthException('invalid_response',
            'The sign-in server answered with HTTP ${response.statusCode}.');
      }
      if (response.statusCode != 200 || json['error'] != null) {
        throw OAuthException(json['error'] as String? ?? 'http_${response.statusCode}',
            json['error_description'] as String?);
      }
      return OAuthTokens.fromResponse(json, DateTime.now());
    } finally {
      if (httpClient == null) client.close(force: true);
    }
  }

  /// Listeners on 127.0.0.1 and, on the same port, ::1: browsers may
  /// resolve `localhost` to either.
  static Future<List<HttpServer>> _bindLoopback() async {
    final v4 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final servers = [v4];
    try {
      servers.add(await HttpServer.bind(InternetAddress.loopbackIPv6, v4.port,
          v6Only: true));
    } catch (_) {
      // No IPv6 loopback: IPv4 alone is fine.
    }
    return servers;
  }

  static Future<void> _respond(HttpRequest request,
      {required bool ok, required String text}) async {
    final escaped = const HtmlEscape().convert(text);
    request.response
      ..statusCode = ok ? HttpStatus.ok : HttpStatus.badRequest
      ..headers.contentType = ContentType.html
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..write('<!doctype html><html><head><meta charset="utf-8">'
          '<title>Look In</title><style>body{font-family:"Segoe UI",'
          'Cantarell,sans-serif;margin:15vh auto;max-width:32em;color:#333}'
          'h1{font-weight:300;color:${ok ? '#2B579A' : '#A4262C'}}</style>'
          '</head><body><h1>${ok ? 'Signed in' : 'Sign-in failed'}</h1>'
          '<p>$escaped</p></body></html>');
    await request.response.close();
  }

  /// PKCE S256 challenge for [verifier] (RFC 7636).
  static String pkceChallenge(String verifier) =>
      base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');

  /// [bytes] random bytes as unpadded base64url.
  static String randomUrlSafe(int bytes) {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(bytes, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}
