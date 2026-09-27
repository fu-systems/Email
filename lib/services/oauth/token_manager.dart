import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/email_account.dart';
import '../data_store.dart';
import '../mail_backend.dart';
import 'oauth_config.dart';
import 'oauth_flow.dart';

/// What is kept for a signed-in account: the refresh token and the
/// resources it was granted. Access tokens stay in memory only.
class OAuthGrant {
  final String provider;
  final String refreshToken;
  final String? username;
  final Set<OAuthResource> resources;

  const OAuthGrant({
    required this.provider,
    required this.refreshToken,
    this.username,
    this.resources = const {},
  });

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'refreshToken': refreshToken,
        'username': ?username,
        'resources': [for (final r in resources) r.name],
      };

  static OAuthGrant? fromJson(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      final refreshToken = map['refreshToken'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) return null;
      return OAuthGrant(
        provider: map['provider'] as String? ?? OAuthProviderConfig.microsoftId,
        refreshToken: refreshToken,
        username: map['username'] as String?,
        resources: {
          for (final name in (map['resources'] as List? ?? const []))
            ?OAuthResource.values.asNameMap()[name],
        },
      );
    } catch (_) {
      return null;
    }
  }
}

/// Hands out OAuth access tokens for accounts that sign in with Microsoft,
/// refreshing them as needed.
///
/// The refresh token is stored with the account's other secrets
/// (`oauth:<accountId>`, system keyring or encrypted file). Refreshes for an
/// account are serialized, and a rotated refresh token is saved right away.
class TokenManager {
  final DataStore store;
  final HttpClient? httpClient;
  final DateTime Function() _now;

  final Map<String, ({String token, DateTime expiresAt})> _access = {};
  final Map<String, AsyncLock> _locks = {};

  TokenManager(
    this.store, {
    this.httpClient,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static TokenManager? _instance;

  /// The app-wide manager for [DataStore.instance] (replaced when the
  /// store changes, as between tests) unless set explicitly.
  static TokenManager get instance {
    final current = _instance;
    final store = DataStore.instance;
    if (current != null && identical(current.store, store)) return current;
    return _instance = TokenManager(store);
  }

  static set instance(TokenManager? manager) => _instance = manager;

  /// Refresh this long before an access token expires.
  static const refreshMargin = Duration(minutes: 5);

  static String secretKey(String accountId) => 'oauth:$accountId';

  OAuthGrant? grantFor(String accountId) =>
      OAuthGrant.fromJson(store.secret(secretKey(accountId)));

  bool isSignedIn(String accountId) => grantFor(accountId) != null;

  /// Stores the result of an interactive sign-in for [accountId].
  void saveSignIn(String accountId, OAuthTokens tokens,
      {required OAuthResource resource, String? provider}) {
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null) {
      throw const OAuthException('no_refresh_token',
          'The sign-in did not allow offline access (offline_access).');
    }
    final previous = grantFor(accountId);
    store.setSecret(
      secretKey(accountId),
      jsonEncode(OAuthGrant(
        provider: provider ?? OAuthProviderConfig.microsoftId,
        refreshToken: refreshToken,
        username: tokens.username ?? previous?.username,
        resources: {...?previous?.resources, resource},
      ).toJson()),
    );
    _access['$accountId|${resource.name}'] =
        (token: tokens.accessToken, expiresAt: tokens.expiresAt);
  }

  /// Forgets the account's tokens (sign out, or account removed).
  void signOut(String accountId) {
    store.setSecret(secretKey(accountId), null);
    _access.removeWhere((key, _) => key.startsWith('$accountId|'));
  }

  /// The provider configuration the account's tokens belong to.
  OAuthProviderConfig providerFor(EmailAccount account) {
    final clientId = account.oauthClientId;
    if (clientId == null || clientId.isEmpty) {
      throw const MailAuthenticationException(
          'This account has no Microsoft app registration. Sign in again in '
          'Account Settings.');
    }
    return OAuthProviderConfig.microsoft(OAuthRegistration(
        clientId: clientId, tenant: account.oauthTenant ?? 'common'));
  }

  /// A valid access token for [resource], refreshing it when it expires
  /// within [refreshMargin].
  ///
  /// Throws [MailAuthenticationException] when the user must sign in again,
  /// and [MailConnectionException] when the sign-in server can't be reached.
  Future<String> accessToken(EmailAccount account,
      {OAuthResource resource = OAuthResource.outlookMail}) {
    final key = '${account.id}|${resource.name}';
    final cached = _access[key];
    if (cached != null &&
        cached.expiresAt.isAfter(_now().add(refreshMargin))) {
      return Future.value(cached.token);
    }
    final lock = _locks.putIfAbsent(account.id, AsyncLock.new);
    return lock.run(() async {
      // Another caller may have refreshed while we waited.
      final fresh = _access[key];
      if (fresh != null && fresh.expiresAt.isAfter(_now().add(refreshMargin))) {
        return fresh.token;
      }
      final grant = grantFor(account.id);
      if (grant == null) {
        throw const MailAuthenticationException(
            'You are signed out of Microsoft. Sign in again in Account '
            'Settings.');
      }
      final OAuthTokens tokens;
      try {
        tokens = await OAuthFlow.refresh(providerFor(account), grant.refreshToken,
            scopes: [...resource.scopes, 'offline_access'],
            httpClient: httpClient);
      } on OAuthException catch (e) {
        if (e.isInvalidGrant || e.error == 'interaction_required') {
          throw MailAuthenticationException(
              'Your Microsoft sign-in has expired or was revoked. Sign in '
              'again in Account Settings. ($e)');
        }
        if (e.error == 'invalid_response' || e.error.startsWith('http_5')) {
          throw MailConnectionException('Microsoft sign-in: $e', e);
        }
        throw MailAuthenticationException('Microsoft sign-in: $e');
      } on SocketException catch (e) {
        throw MailConnectionException('Microsoft sign-in: ${e.message}', e);
      } on TimeoutException catch (e) {
        throw MailConnectionException('Microsoft sign-in timed out', e);
      } on HandshakeException catch (e) {
        throw MailConnectionException('Microsoft sign-in: ${e.message}', e);
      } on HttpException catch (e) {
        throw MailConnectionException('Microsoft sign-in: ${e.message}', e);
      }
      final rotated = tokens.refreshToken;
      if (rotated != null && rotated != grant.refreshToken) {
        store.setSecret(
          secretKey(account.id),
          jsonEncode(OAuthGrant(
            provider: grant.provider,
            refreshToken: rotated,
            username: grant.username,
            resources: {...grant.resources, resource},
          ).toJson()),
        );
      }
      _access[key] = (token: tokens.accessToken, expiresAt: tokens.expiresAt);
      return tokens.accessToken;
    });
  }
}
