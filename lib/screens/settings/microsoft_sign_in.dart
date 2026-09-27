import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/data_store.dart';
import '../../services/oauth/oauth_config.dart';
import '../../services/oauth/oauth_flow.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';

/// Step-by-step instructions for creating the app registration.
final registrationGuideUrl = Uri.parse(
    'https://github.com/fu-systems/Email/blob/HEAD/docs/microsoft-app-registration.md');

/// The redirect URI to enter in the app registration.
const registrationRedirectUri = 'http://localhost';

/// Result of a successful "Sign in with Microsoft".
typedef MicrosoftSignIn = ({
  OAuthTokens tokens,
  OAuthRegistration registration,
});

/// The Microsoft app registration to sign in with: from Options, an
/// administrator's configuration file or the build.
OAuthRegistration? currentMicrosoftRegistration(DataStore store) =>
    OAuthRegistrations.microsoft(
        setting: store.getString(OAuthRegistrations.settingKey));

/// Signs in with Microsoft in the system browser. Asks for the app
/// registration first when none is set up. Returns null when cancelled.
Future<MicrosoftSignIn?> signInWithMicrosoft(
  BuildContext context, {
  required DataStore store,
  String? loginHint,
  OAuthRegistration? registration,
  OAuthResource resource = OAuthResource.outlookMail,
  Future<bool> Function(Uri url)? launch,
}) async {
  registration ??= currentMicrosoftRegistration(store);
  if (registration == null) {
    registration = await showMicrosoftRegistrationDialog(context, store: store);
    if (registration == null || !context.mounted) return null;
  }
  final tokens = await showDialog<OAuthTokens>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BrowserSignInDialog(
      registration: registration!,
      loginHint: loginHint,
      scopes: resource.signInScopes,
      launch: launch,
      store: store,
    ),
  );
  if (tokens == null) return null;
  return (tokens: tokens, registration: registration);
}

/// Edits the install-wide Microsoft app registration. Returns the saved
/// registration, or null when cancelled.
Future<OAuthRegistration?> showMicrosoftRegistrationDialog(
  BuildContext context, {
  required DataStore store,
}) =>
    showDialog<OAuthRegistration>(
      context: context,
      builder: (_) => _RegistrationDialog(store: store),
    );

class _RegistrationDialog extends StatefulWidget {
  final DataStore store;

  const _RegistrationDialog({required this.store});

  @override
  State<_RegistrationDialog> createState() => _RegistrationDialogState();
}

class _RegistrationDialogState extends State<_RegistrationDialog> {
  late final OAuthRegistration? _provisioned =
      OAuthRegistrations.microsoft(setting: null);
  final _clientId = TextEditingController();
  final _tenant = TextEditingController();
  MicrosoftAudience _audience = MicrosoftAudience.any;
  bool _showSteps = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = currentMicrosoftRegistration(widget.store);
    if (current != null) {
      _clientId.text = current.clientId;
      _audience = current.audience;
      if (_audience == MicrosoftAudience.singleTenant) {
        _tenant.text = current.tenant;
      }
    } else {
      _showSteps = true;
    }
  }

  @override
  void dispose() {
    _clientId.dispose();
    _tenant.dispose();
    super.dispose();
  }

  void _save() {
    final clientId = _clientId.text.trim();
    final tenant = _audience == MicrosoftAudience.singleTenant
        ? _tenant.text.trim()
        : _audience.authority;
    if (!OAuthRegistration.isValidClientId(clientId)) {
      setState(() => _error = 'The Application (client) ID looks like '
          '00000000-0000-0000-0000-000000000000.');
      return;
    }
    if (tenant.isEmpty) {
      setState(() => _error = 'Enter the Directory (tenant) ID or the '
          'organization\'s domain.');
      return;
    }
    final registration = OAuthRegistration(clientId: clientId, tenant: tenant);
    widget.store.setString(
        OAuthRegistrations.settingKey, jsonEncode(registration.toMap()));
    Navigator.of(context).pop(registration);
  }

  void _useProvisioned() {
    widget.store.setString(OAuthRegistrations.settingKey, null);
    Navigator.of(context).pop(_provisioned);
  }

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 12.5, color: OutlookTheme.textSecondary);
    return OutlookDialog(
      title: 'Microsoft Sign-in Setup',
      width: 580,
      actions: [
        if (_provisioned != null)
          TextButton(
            onPressed: _useProvisioned,
            child: const Text('Use administrator\'s settings'),
          ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Look In signs in to Outlook.com and Microsoft 365 through an app '
            'registration that you or your organization creates in Microsoft '
            'Entra. It is free and takes a few minutes; you only do it once.',
            style: TextStyle(fontSize: 13),
          ),
          if (_provisioned != null) ...[
            const SizedBox(height: 10),
            Text(
              'Your administrator provided a registration '
              '(${_provisioned.source}). Settings entered here replace it.',
              style: small,
            ),
          ],
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _showSteps = !_showSteps),
            child: Row(
              children: [
                Icon(_showSteps ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: OutlookTheme.primaryBlue),
                const Text('How do I create one?',
                    style: TextStyle(
                        fontSize: 13, color: OutlookTheme.primaryBlue)),
              ],
            ),
          ),
          if (_showSteps) _steps(),
          const SizedBox(height: 14),
          TextField(
            controller: _clientId,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Application (client) ID',
              hintText: '00000000-0000-0000-0000-000000000000',
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<MicrosoftAudience>(
            initialValue: _audience,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Accounts that can sign in'),
            items: [
              for (final a in MicrosoftAudience.values)
                DropdownMenuItem(
                    value: a,
                    child: Text(a.label, style: const TextStyle(fontSize: 13))),
            ],
            onChanged: (v) => setState(() => _audience = v ?? _audience),
          ),
          if (_audience == MicrosoftAudience.singleTenant) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _tenant,
              decoration: const InputDecoration(
                labelText: 'Directory (tenant) ID or domain',
                hintText: 'contoso.onmicrosoft.com',
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'Match "Supported account types" in the registration. Use "one '
            'organization" for a registration that only allows accounts in '
            'its own directory.',
            style: small,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(
                    fontSize: 12.5, color: OutlookTheme.flaggedColor)),
          ],
        ],
      ),
    );
  }

  Widget _steps() {
    Widget step(int n, Widget text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 20,
                  child: Text('$n.', style: const TextStyle(fontSize: 12.5))),
              Expanded(child: text),
            ],
          ),
        );
    const style = TextStyle(fontSize: 12.5);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      color: OutlookTheme.folderPaneBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          step(
              1,
              const Text(
                  'Open entra.microsoft.com (or portal.azure.com) > App '
                  'registrations > New registration. Name it "Look In".',
                  style: style)),
          step(
              2,
              const Text(
                  'Supported account types: choose who will sign in (for '
                  'Outlook.com, include personal Microsoft accounts).',
                  style: style)),
          step(
              3,
              Row(
                children: [
                  const Flexible(
                    child: Text(
                        'Redirect URI: platform "Public client/native '
                        '(mobile & desktop)", URI $registrationRedirectUri',
                        style: style),
                  ),
                  IconButton(
                    tooltip: 'Copy',
                    iconSize: 14,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy),
                    onPressed: () => Clipboard.setData(
                        const ClipboardData(text: registrationRedirectUri)),
                  ),
                ],
              )),
          step(
              4,
              const Text(
                  'API permissions > Add > Microsoft Graph > Delegated: '
                  'IMAP.AccessAsUser.All, SMTP.Send, offline_access, openid, '
                  'profile, email.',
                  style: style)),
          step(
              5,
              const Text(
                  'Copy the Application (client) ID from the Overview page '
                  'into the field below.',
                  style: style)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => launchUrl(registrationGuideUrl,
                mode: LaunchMode.externalApplication),
            child: const Text('Detailed guide with screenshots and admin '
                'consent',
                style: TextStyle(
                    fontSize: 12.5,
                    color: OutlookTheme.primaryBlue,
                    decoration: TextDecoration.underline)),
          ),
        ],
      ),
    );
  }
}

/// Waits for the browser sign-in and shows what to do when it fails.
class _BrowserSignInDialog extends StatefulWidget {
  final OAuthRegistration registration;
  final String? loginHint;
  final List<String> scopes;
  final Future<bool> Function(Uri url)? launch;
  final DataStore store;

  const _BrowserSignInDialog({
    required this.registration,
    required this.loginHint,
    required this.scopes,
    required this.launch,
    required this.store,
  });

  @override
  State<_BrowserSignInDialog> createState() => _BrowserSignInDialogState();
}

class _BrowserSignInDialogState extends State<_BrowserSignInDialog> {
  OAuthSignIn? _signIn;
  OAuthException? _error;
  Object? _otherError;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _otherError = null;
      _signIn = null;
    });
    try {
      final signIn = await OAuthFlow.start(
        OAuthProviderConfig.microsoft(widget.registration),
        scopes: widget.scopes,
        loginHint: widget.loginHint,
        launch: widget.launch,
      );
      if (!mounted) {
        signIn.cancel();
        return;
      }
      setState(() => _signIn = signIn);
      final tokens = await signIn.result;
      if (mounted) Navigator.of(context).pop(tokens);
    } on OAuthException catch (e) {
      if (e.error == 'cancelled' || !mounted) return;
      setState(() => _error = e);
    } catch (e) {
      if (mounted) setState(() => _otherError = e);
    }
  }

  @override
  void dispose() {
    _signIn?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final failed = _error != null || _otherError != null;
    return OutlookDialog(
      title: 'Sign in with Microsoft',
      width: 520,
      actions: [
        if (failed) ...[
          TextButton(
            onPressed: () async {
              final changed = await showMicrosoftRegistrationDialog(context,
                  store: widget.store);
              if (changed != null && context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Change App Registration...'),
          ),
          OutlinedButton(onPressed: _start, child: const Text('Try Again')),
        ],
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
      child: failed ? _failure() : _waiting(),
    );
  }

  Widget _waiting() {
    final url = _signIn?.authorizeUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Expanded(
              child: Text('Continue in your web browser',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Sign in${widget.loginHint == null ? '' : ' as ${widget.loginHint}'} '
          'and allow Look In to read and send your mail. This window '
          'continues by itself afterwards.',
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (url != null)
          Row(
            children: [
              const Expanded(
                child: Text('Browser didn\'t open?',
                    style: TextStyle(
                        fontSize: 12.5, color: OutlookTheme.textSecondary)),
              ),
              TextButton.icon(
                onPressed: () =>
                    launchUrl(url, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Open Again'),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url.toString()));
                  showStatusMessage(context, 'Sign-in link copied');
                },
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy Link'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _failure() {
    final error = _error;
    final needsConsent = error?.needsAdminConsent ?? false;
    final consentUrl =
        OAuthProviderConfig.microsoftAdminConsentUrl(widget.registration);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline,
                size: 18, color: OutlookTheme.flaggedColor),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                  error?.toString() ?? 'Sign-in failed: $_otherError',
                  style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        if (needsConsent) ...[
          const SizedBox(height: 14),
          const Text(
            'Your organization requires an administrator to approve Look In '
            'first. Send this link to your IT administrator:',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SelectableText(consentUrl.toString(),
                    style: const TextStyle(
                        fontSize: 12, color: OutlookTheme.primaryBlue)),
              ),
              IconButton(
                tooltip: 'Copy',
                iconSize: 16,
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: consentUrl.toString()));
                  showStatusMessage(context, 'Approval link copied');
                },
              ),
            ],
          ),
        ] else if (error?.aadstsCode == '700016' ||
            error?.aadstsCode == '50011' ||
            error?.error == 'invalid_client' ||
            error?.error == 'unauthorized_client') ...[
          const SizedBox(height: 12),
          const Text(
            'Check the app registration: the client ID, the supported account '
            'types, and that http://localhost is a "mobile and desktop" '
            'redirect URI.',
            style: TextStyle(fontSize: 12.5, color: OutlookTheme.textSecondary),
          ),
        ],
      ],
    );
  }
}
