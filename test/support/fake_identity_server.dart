import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// A stand-in for the Microsoft identity platform: a token endpoint that
/// checks PKCE, and a "browser" ([browse]) that signs the user in and
/// redirects to the app's loopback listener.
class FakeIdentityServer {
  final HttpServer _server;

  FakeIdentityServer._(this._server);

  /// Base URL to use as `OAuthProviderConfig.microsoftLoginBase`.
  String get base => 'http://127.0.0.1:${_server.port}';

  /// Values handed out by the token endpoint.
  String accessToken = 'access-1';
  String? refreshToken = 'refresh-1';
  int expiresIn = 3600;
  String username = 'ann@contoso.com';
  String displayName = 'Ann Example';

  /// When set, refresh requests fail with this OAuth error code.
  String? failRefreshWith;

  /// Form fields of every token request, in order.
  final List<Map<String, String>> tokenRequests = [];

  /// The tenant path segment of the last token request.
  String? lastTenant;

  /// HTML of the page the app showed in the "browser".
  String? lastPage;

  final Map<String, String> _challenges = {};

  static Future<FakeIdentityServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeIdentityServer._(server);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  static String _jwt(Map<String, dynamic> claims) {
    String part(Object json) =>
        base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
    return '${part({'alg': 'none'})}.${part(claims)}.sig';
  }

  Future<void> _handle(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (request.method == 'GET' &&
        segments.length == 4 &&
        segments.last == 'authorize') {
      // A real browser: the user "signs in" at once and is sent back.
      final q = request.uri.queryParameters;
      final code = 'code-${_challenges.length + 1}-${q['state']}';
      _challenges[code] = q['code_challenge'] ?? '';
      final back = Uri.parse(q['redirect_uri']!)
          .replace(queryParameters: {'code': code, 'state': q['state']!});
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, back.toString());
      await request.response.close();
      return;
    }
    if (request.method != 'POST' ||
        segments.length != 4 ||
        segments.last != 'token') {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }
    lastTenant = segments.first;
    final form = Uri.splitQueryString(
        await utf8.decoder.bind(request).join());
    tokenRequests.add(form);

    Future<void> error(String code, String description) async {
      request.response
        ..statusCode = 400
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(
            {'error': code, 'error_description': description}));
      await request.response.close();
    }

    switch (form['grant_type']) {
      case 'authorization_code':
        final challenge = _challenges.remove(form['code']);
        final verifier = form['code_verifier'] ?? '';
        final expected = base64Url
            .encode(sha256.convert(ascii.encode(verifier)).bytes)
            .replaceAll('=', '');
        if (challenge == null || challenge != expected) {
          return error('invalid_grant', 'AADSTS501481: The Code_Verifier '
              'does not match the code_challenge.');
        }
      case 'refresh_token':
        if (failRefreshWith != null) {
          return error(failRefreshWith!, 'AADSTS700082: The refresh token '
              'has expired due to inactivity.');
        }
      default:
        return error('unsupported_grant_type', 'Unsupported grant type.');
    }
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'token_type': 'Bearer',
        'access_token': accessToken,
        'refresh_token': ?refreshToken,
        'expires_in': expiresIn,
        'scope': form['scope'] ?? '',
        'id_token': _jwt({
          'preferred_username': username,
          'name': displayName,
        }),
      }));
    await request.response.close();
  }

  /// Plays the browser for [authorizeUrl]: the user signs in (or the
  /// server reports [error]) and is redirected back to the app.
  Future<bool> browse(Uri authorizeUrl,
      {String? error, String? errorDescription, bool wrongState = false}) async {
    final q = authorizeUrl.queryParameters;
    final code = 'code-${_challenges.length + 1}-${q['state']}';
    _challenges[code] = q['code_challenge'] ?? '';
    final redirect = Uri.parse(q['redirect_uri']!).replace(queryParameters: {
      if (error == null) 'code': code,
      'error': ?error,
      'error_description': ?errorDescription,
      'state': wrongState ? 'forged' : q['state']!,
    });
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(redirect)).close();
      lastPage = await utf8.decoder.bind(response).join();
    } finally {
      client.close(force: true);
    }
    return true;
  }
}
