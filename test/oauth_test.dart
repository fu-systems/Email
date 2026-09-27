import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/email_account.dart';
import 'package:look_in/services/autoconfig_service.dart';
import 'package:look_in/services/data_store.dart';
import 'package:look_in/services/mail_backend.dart';
import 'package:look_in/services/oauth/oauth_config.dart';
import 'package:look_in/services/oauth/oauth_flow.dart';
import 'package:look_in/services/oauth/token_manager.dart';

import 'support/fake_identity_server.dart';

const _clientId = '11111111-2222-3333-4444-555555555555';

EmailAccount _account({String id = 'ms1'}) => EmailAccount(
      id: id,
      displayName: 'Ann',
      emailAddress: 'ann@contoso.com',
      incomingHost: 'outlook.office365.com',
      incomingPort: 993,
      smtpHost: 'smtp.office365.com',
      smtpPort: 587,
      username: 'ann@contoso.com',
      password: '',
      authMethod: AuthMethod.oauth2,
      oauthProvider: 'microsoft',
      oauthClientId: _clientId,
      oauthTenant: 'organizations',
    );

void main() {
  group('PKCE and tokens', () {
    test('S256 challenge matches RFC 7636 appendix B', () {
      expect(
          OAuthFlow.pkceChallenge(
              'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
          'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });

    test('random values are url-safe and unpadded', () {
      final v = OAuthFlow.randomUrlSafe(32);
      expect(v, hasLength(43));
      expect(v, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(OAuthFlow.randomUrlSafe(32), isNot(v));
    });

    test('ID token claims give the user name', () {
      String part(Object o) =>
          base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
      final tokens = OAuthTokens.fromResponse({
        'access_token': 'a',
        'expires_in': '120',
        'id_token':
            '${part({'alg': 'none'})}.${part({'preferred_username': 'x@y.org', 'name': 'X Y'})}.s',
      }, DateTime(2026));
      expect(tokens.username, 'x@y.org');
      expect(tokens.displayName, 'X Y');
      expect(tokens.expiresAt, DateTime(2026, 1, 1, 0, 2));
      expect(OAuthTokens.decodeJwtPayload('not a jwt'), isEmpty);
    });

    test('errors: admin consent and AADSTS codes', () {
      const consent = OAuthException('invalid_client',
          'AADSTS65001: The user or administrator has not consented.');
      expect(consent.needsAdminConsent, isTrue);
      expect(consent.aadstsCode, '65001');
      expect(const OAuthException('invalid_grant', 'AADSTS70000').isInvalidGrant,
          isTrue);
      expect(const OAuthException('access_denied').needsAdminConsent, isFalse);
    });
  });

  group('app registration', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('oauthcfg'));
    tearDown(() => dir.delete(recursive: true));

    test('client ids must be GUIDs', () {
      expect(OAuthRegistration.isValidClientId(_clientId), isTrue);
      expect(OAuthRegistration.isValidClientId('abc'), isFalse);
      expect(OAuthRegistration.fromMap({'clientId': 'nope'}), isNull);
    });

    test('settings win over config files, which win over the build', () {
      final file = File('${dir.path}/oauth.json')
        ..writeAsStringSync(jsonEncode({
          'microsoft': {'clientId': _clientId, 'tenant': 'contoso.com'},
        }));
      const other = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      final fromSetting = OAuthRegistrations.microsoft(
          setting: jsonEncode({'clientId': other}),
          configFiles: [file.path]);
      expect(fromSetting!.clientId, other);
      expect(fromSetting.tenant, 'common');

      final fromFile = OAuthRegistrations.microsoft(
          setting: null,
          configFiles: ['${dir.path}/missing.json', file.path],
          buildClientId: other);
      expect(fromFile!.clientId, _clientId);
      expect(fromFile.audience, MicrosoftAudience.singleTenant);
      expect(fromFile.source, file.path);

      final fromBuild = OAuthRegistrations.microsoft(
          setting: 'garbage', configFiles: const [], buildClientId: other);
      expect(fromBuild!.source, 'build');
      expect(
          OAuthRegistrations.microsoft(
              setting: null, configFiles: const [], buildClientId: ''),
          isNull);
    });

    test('endpoints and admin consent link follow the tenant', () {
      const r = OAuthRegistration(clientId: _clientId, tenant: 'consumers');
      final config = OAuthProviderConfig.microsoft(r);
      expect(config.tokenUrl.toString(),
          'https://login.microsoftonline.com/consumers/oauth2/v2.0/token');
      expect(
          OAuthProviderConfig.microsoftAdminConsentUrl(
                  const OAuthRegistration(clientId: _clientId, tenant: 'contoso.com'))
              .toString(),
          'https://login.microsoftonline.com/contoso.com/adminconsent'
          '?client_id=$_clientId');
    });
  });

  group('sign-in flow', () {
    late FakeIdentityServer idp;
    late OAuthProviderConfig config;

    setUp(() async {
      idp = await FakeIdentityServer.start();
      OAuthProviderConfig.microsoftLoginBase = idp.base;
      config = OAuthProviderConfig.microsoft(
          const OAuthRegistration(clientId: _clientId, tenant: 'common'));
    });

    tearDown(() async {
      OAuthProviderConfig.microsoftLoginBase =
          'https://login.microsoftonline.com';
      await idp.close();
    });

    test('authorization code with PKCE through the loopback redirect',
        () async {
      Uri? opened;
      final signIn = await OAuthFlow.start(
        config,
        scopes: OAuthResource.outlookMail.signInScopes,
        loginHint: 'ann@contoso.com',
        launch: (url) {
          opened = url;
          return idp.browse(url);
        },
      );
      final tokens = await signIn.result;
      expect(tokens.accessToken, 'access-1');
      expect(tokens.refreshToken, 'refresh-1');
      expect(tokens.username, 'ann@contoso.com');
      expect(idp.lastPage, contains('Signed in'));

      final q = opened!.queryParameters;
      expect(q['client_id'], _clientId);
      expect(q['code_challenge_method'], 'S256');
      expect(q['login_hint'], 'ann@contoso.com');
      expect(q['redirect_uri'], startsWith('http://localhost:'));
      expect(q['scope'], contains('IMAP.AccessAsUser.All'));
      expect(q['scope'], contains('offline_access'));
      final form = idp.tokenRequests.single;
      expect(form['grant_type'], 'authorization_code');
      expect(form.containsKey('client_secret'), isFalse,
          reason: 'public clients never send a secret');
    });

    test('a forged state is rejected', () async {
      final signIn = await OAuthFlow.start(config,
          scopes: const ['openid'],
          launch: (url) => idp.browse(url, wrongState: true));
      await expectLater(
          signIn.result,
          throwsA(isA<OAuthException>()
              .having((e) => e.error, 'error', 'state_mismatch')));
      expect(idp.tokenRequests, isEmpty);
    });

    test('errors from the identity platform are reported', () async {
      final signIn = await OAuthFlow.start(config,
          scopes: const ['openid'],
          launch: (url) => idp.browse(url,
              error: 'consent_required',
              errorDescription: 'AADSTS65001: Need admin approval.'));
      await expectLater(
          signIn.result,
          throwsA(isA<OAuthException>()
              .having((e) => e.needsAdminConsent, 'needsAdminConsent', true)));
      expect(idp.lastPage, contains('Sign-in failed'));
    });

    test('cancel and timeout', () async {
      final signIn = await OAuthFlow.start(config,
          scopes: const ['openid'], launch: (_) async => false);
      signIn.cancel();
      await expectLater(signIn.result, throwsA(isA<OAuthException>()));

      final slow = await OAuthFlow.start(config,
          scopes: const ['openid'],
          launch: (_) async => true,
          timeout: const Duration(milliseconds: 100));
      await expectLater(
          slow.result,
          throwsA(isA<OAuthException>()
              .having((e) => e.error, 'error', 'timeout')));
    });
  });

  group('TokenManager', () {
    late FakeIdentityServer idp;
    late DataStore store;
    late DateTime now;
    late TokenManager tokens;

    setUp(() async {
      idp = await FakeIdentityServer.start();
      OAuthProviderConfig.microsoftLoginBase = idp.base;
      store = DataStore.inMemory();
      now = DateTime(2026, 9, 1, 12);
      tokens = TokenManager(store, now: () => now);
    });

    tearDown(() async {
      OAuthProviderConfig.microsoftLoginBase =
          'https://login.microsoftonline.com';
      store.close();
      await idp.close();
    });

    OAuthTokens signedIn({String access = 'first', String refresh = 'r0'}) =>
        OAuthTokens(
          accessToken: access,
          refreshToken: refresh,
          expiresAt: now.add(const Duration(hours: 1)),
        );

    test('uses the sign-in token, then refreshes near expiry', () async {
      final account = _account();
      tokens.saveSignIn(account.id, signedIn(),
          resource: OAuthResource.outlookMail);
      expect(store.secret('oauth:ms1'), contains('r0'));
      expect(await tokens.accessToken(account), 'first');
      expect(idp.tokenRequests, isEmpty);

      now = now.add(const Duration(minutes: 56));
      idp.accessToken = 'second';
      idp.refreshToken = 'r1';
      expect(await tokens.accessToken(account), 'second');
      final form = idp.tokenRequests.single;
      expect(form['grant_type'], 'refresh_token');
      expect(form['refresh_token'], 'r0');
      expect(idp.lastTenant, 'organizations');
      expect(tokens.grantFor(account.id)!.refreshToken, 'r1',
          reason: 'rotated refresh token is saved');
    });

    test('concurrent requests share one refresh', () async {
      final account = _account();
      tokens.saveSignIn(account.id, signedIn(),
          resource: OAuthResource.outlookMail);
      now = now.add(const Duration(hours: 2));
      final results = await Future.wait(
          [for (var i = 0; i < 5; i++) tokens.accessToken(account)]);
      expect(results.toSet(), {'access-1'});
      expect(idp.tokenRequests, hasLength(1));
    });

    test('a revoked sign-in asks the user to sign in again', () async {
      final account = _account();
      tokens.saveSignIn(account.id, signedIn(),
          resource: OAuthResource.outlookMail);
      now = now.add(const Duration(hours: 2));
      idp.failRefreshWith = 'invalid_grant';
      await expectLater(tokens.accessToken(account),
          throwsA(isA<MailAuthenticationException>()));
    });

    test('an unreachable sign-in server is a connection problem', () async {
      final account = _account();
      tokens.saveSignIn(account.id, signedIn(),
          resource: OAuthResource.outlookMail);
      now = now.add(const Duration(hours: 2));
      await idp.close();
      await expectLater(tokens.accessToken(account),
          throwsA(isA<MailConnectionException>()));
    });

    test('signed out and missing registrations', () async {
      await expectLater(tokens.accessToken(_account()),
          throwsA(isA<MailAuthenticationException>()));
      final account = _account();
      tokens.saveSignIn(account.id, signedIn(),
          resource: OAuthResource.outlookMail);
      tokens.signOut(account.id);
      expect(store.secret('oauth:ms1'), isNull);
      expect(tokens.isSignedIn(account.id), isFalse);
    });

    test('grants survive a restart of the store', () {
      final account = _account();
      tokens.saveSignIn(account.id, signedIn(refresh: 'keep'),
          resource: OAuthResource.outlookMail);
      final grant = OAuthGrant.fromJson(store.secret('oauth:ms1'))!;
      expect(grant.refreshToken, 'keep');
      expect(grant.resources, {OAuthResource.outlookMail});
      expect(OAuthGrant.fromJson('{"broken":true}'), isNull);
    });
  });

  group('detection', () {
    test('Microsoft MX hosts', () {
      expect(
          EmailProviderConfig.isMicrosoftMx(
              'contoso-com.mail.protection.outlook.com.'),
          isTrue);
      expect(
          EmailProviderConfig.isMicrosoftMx(
              'outlook-com.olc.protection.outlook.com'),
          isTrue);
      expect(EmailProviderConfig.isMicrosoftMx('aspmx.l.google.com'), isFalse);
    });

    test('Outlook.com preset signs in with Microsoft', () {
      expect(EmailProviderConfig.detectFromEmail('x@hotmail.com')!.oauthProvider,
          'microsoft');
    });

    test('ISPDB OAuth2 entries for Microsoft servers', () {
      const xml = '''
<clientConfig version="1.1"><emailProvider id="outlook.com">
<incomingServer type="imap"><hostname>outlook.office365.com</hostname>
<port>993</port><socketType>SSL</socketType>
<authentication>OAuth2</authentication>
<authentication>password-cleartext</authentication>
<username>%EMAILADDRESS%</username></incomingServer>
<outgoingServer type="smtp"><hostname>smtp.office365.com</hostname>
<port>587</port><socketType>STARTTLS</socketType>
<authentication>OAuth2</authentication></outgoingServer>
</emailProvider></clientConfig>''';
      final found = AutoconfigService.parseConfig(xml)!;
      expect(found.oauthProvider, 'microsoft');
      expect(found.incomingHost, 'outlook.office365.com');
      final plain = AutoconfigService.parseConfig(
          xml.replaceAll('outlook.office365.com', 'imap.example.org'))!;
      expect(plain.oauthProvider, isNull,
          reason: 'OAuth for other providers is not supported yet');
    });

    test('Microsoft error hints', () {
      expect(
          explainMicrosoftError('535 5.7.139 Authentication unsuccessful, '
              'SmtpClientAuthentication is disabled for the Tenant.'),
          contains('administrator'));
      expect(explainMicrosoftError('User is authenticated but not connected.'),
          contains('IMAP'));
      expect(explainMicrosoftError('other'), 'other');
    });
  });

  test('accounts keep their sign-in method and registration', () {
    final map = _account().toMap(includePassword: false);
    final back = EmailAccount.fromMap(map);
    expect(back.usesOAuth, isTrue);
    expect(back.oauthClientId, _clientId);
    expect(back.oauthTenant, 'organizations');
    expect(EmailAccount.fromMap({...map}..remove('authMethod')).usesOAuth,
        isFalse,
        reason: 'older accounts use passwords');
  });
}
