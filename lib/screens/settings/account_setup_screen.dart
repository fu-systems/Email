import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/email_account.dart';
import '../../models/email_message.dart';
import '../../providers/account_provider.dart';
import '../../services/autoconfig_service.dart';
import '../../services/mail_backend.dart';
import '../../theme/outlook_theme.dart';

/// Add Account wizard (first run or File > Add Account), or the Account
/// Settings page when opened with an account id as route argument.
class AccountSetupScreen extends StatefulWidget {
  final bool isFirstRun;

  /// Account to edit; may also be passed as the route argument.
  final String? accountId;

  const AccountSetupScreen({super.key, this.isFirstRun = false, this.accountId});

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  int _currentStep = 0;
  bool _isTesting = false;
  bool _isDiscovering = false;
  String? _testError;
  bool _testSuccess = false;
  String? _detectedName;
  String? _providerNote;
  EmailAccount? _editing;
  bool _initialized = false;

  final _emailController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _incomingHostController = TextEditingController();
  final _incomingPortController = TextEditingController(text: '993');
  final _smtpHostController = TextEditingController();
  final _smtpPortController = TextEditingController(text: '587');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _signatureController = TextEditingController();

  IncomingProtocol _protocol = IncomingProtocol.imap;
  ConnectionSecurity _incomingSecurity = ConnectionSecurity.ssl;
  ConnectionSecurity _smtpSecurity = ConnectionSecurity.starttls;
  bool _obscurePassword = true;
  bool _acceptInvalidCerts = false;
  bool _leaveOnServer = true;
  bool _isEnabled = true;
  bool _isDefault = false;
  int _syncInterval = 5;

  bool get _isEditMode => _editing != null;

  static bool _isValidEmail(String address) =>
      EmailAddress(address: address).isValid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final id = widget.accountId ??
        ModalRoute.of(context)?.settings.arguments as String?;
    if (id != null) {
      final account = context.read<AccountProvider>().byId(id);
      if (account != null) _load(account);
    }
  }

  void _load(EmailAccount a) {
    _editing = a;
    _emailController.text = a.emailAddress;
    _displayNameController.text = a.displayName;
    _protocol = a.protocol;
    _incomingHostController.text = a.incomingHost;
    _incomingPortController.text = '${a.incomingPort}';
    _incomingSecurity = a.incomingSecurity;
    _smtpHostController.text = a.smtpHost;
    _smtpPortController.text = '${a.smtpPort}';
    _smtpSecurity = a.smtpSecurity;
    _usernameController.text = a.username;
    _passwordController.text = a.password;
    _signatureController.text = a.signature ?? '';
    _acceptInvalidCerts = a.acceptInvalidCertificates;
    _leaveOnServer = a.leaveMessagesOnServer;
    _isEnabled = a.isEnabled;
    _isDefault = a.isDefault;
    _syncInterval = a.syncIntervalMinutes;
  }

  @override
  void dispose() {
    for (final c in [
      _emailController,
      _displayNameController,
      _incomingHostController,
      _incomingPortController,
      _smtpHostController,
      _smtpPortController,
      _usernameController,
      _passwordController,
      _signatureController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── Discovery ─────────────────────────────────────────────────────

  Future<void> _detectSettings() async {
    final email = _emailController.text.trim();
    final domain = email.contains('@') ? email.split('@').last : '';
    if (_usernameController.text.isEmpty) _usernameController.text = email;

    final known = EmailProviderConfig.detectFromEmail(email);
    if (known != null) {
      setState(() {
        _detectedName = known.name;
        _providerNote = known.note;
        _protocol = IncomingProtocol.imap;
        _incomingHostController.text = known.imapHost;
        _incomingPortController.text = '${known.imapPort}';
        _incomingSecurity = known.imapSecurity;
        _smtpHostController.text = known.smtpHost;
        _smtpPortController.text = '${known.smtpPort}';
        _smtpSecurity = known.smtpSecurity;
      });
      return;
    }

    setState(() => _isDiscovering = true);
    final found = await AutoconfigService.discover(email);
    if (!mounted) return;
    setState(() {
      _isDiscovering = false;
      if (found != null) {
        _detectedName = 'settings found (${Uri.tryParse(found.source)?.host ?? found.source})';
        _providerNote = null;
        _protocol = found.protocol;
        _incomingHostController.text = found.incomingHost;
        _incomingPortController.text = '${found.incomingPort}';
        _incomingSecurity = found.incomingSecurity;
        _smtpHostController.text = found.smtpHost;
        _smtpPortController.text = '${found.smtpPort}';
        _smtpSecurity = found.smtpSecurity;
        if (found.usernameIsLocalPart && email.contains('@')) {
          _usernameController.text = email.split('@').first;
        }
      } else {
        _detectedName = null;
        if (_incomingHostController.text.isEmpty && domain.isNotEmpty) {
          _incomingHostController.text = 'imap.$domain';
          _smtpHostController.text = 'smtp.$domain';
        }
      }
    });
  }

  // ─── Actions ───────────────────────────────────────────────────────

  EmailAccount _buildAccount() {
    final email = _emailController.text.trim();
    final name = _displayNameController.text.trim();
    final base = _editing;
    return EmailAccount(
      id: base?.id ?? context.read<AccountProvider>().generateAccountId(),
      displayName: name.isNotEmpty ? name : email,
      emailAddress: email,
      protocol: _protocol,
      incomingHost: _incomingHostController.text.trim(),
      incomingPort: int.tryParse(_incomingPortController.text.trim()) ??
          _protocol.defaultPort(_incomingSecurity),
      incomingSecurity: _incomingSecurity,
      smtpHost: _smtpHostController.text.trim(),
      smtpPort: int.tryParse(_smtpPortController.text.trim()) ?? 587,
      smtpSecurity: _smtpSecurity,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      isDefault: base == null ? _isDefault : _isDefault,
      isEnabled: _isEnabled,
      signature: _signatureController.text.trim().isEmpty
          ? null
          : _signatureController.text.trimRight(),
      syncIntervalMinutes: _syncInterval,
      leaveMessagesOnServer: _leaveOnServer,
      acceptInvalidCertificates: _acceptInvalidCerts,
    );
  }

  String? _validate() {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) return 'Enter a valid email address.';
    if (_incomingHostController.text.trim().isEmpty) {
      return 'Enter the incoming mail server.';
    }
    if (_smtpHostController.text.trim().isEmpty) {
      return 'Enter the outgoing mail server.';
    }
    if (int.tryParse(_incomingPortController.text.trim()) == null ||
        int.tryParse(_smtpPortController.text.trim()) == null) {
      return 'Ports must be numbers.';
    }
    return null;
  }

  Future<void> _testConnection() async {
    final problem = _validate();
    if (problem != null) {
      setState(() {
        _testError = problem;
        _testSuccess = false;
      });
      return;
    }
    setState(() {
      _isTesting = true;
      _testError = null;
      _testSuccess = false;
    });
    final error = await testAccountConnection(_buildAccount());
    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testError = error;
      _testSuccess = error == null;
    });
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _testError = problem);
      return;
    }
    final accounts = context.read<AccountProvider>();
    final account = _buildAccount();
    if (_isEditMode) {
      await accounts.updateAccount(account);
    } else {
      await accounts.addAccount(account);
    }
    if (!mounted) return;
    // On first run _AppRoot swaps to the home screen by itself.
    if (!widget.isFirstRun && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (!_isValidEmail(_emailController.text.trim())) {
        setState(() => _testError = 'Enter a valid email address.');
        return;
      }
      _testError = null;
      _detectSettings();
    }
    if (_currentStep == 1) {
      final problem = _validate();
      if (problem != null) {
        setState(() => _testError = problem);
        return;
      }
      _testError = null;
    }
    if (_currentStep < 3) setState(() => _currentStep++);
    if (_currentStep == 3) _testConnection();
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _testError = null;
      });
    }
  }

  void _setProtocol(IncomingProtocol protocol) {
    setState(() {
      final oldDefault = _protocol.defaultPort(_incomingSecurity);
      _protocol = protocol;
      if (int.tryParse(_incomingPortController.text) == oldDefault ||
          _incomingPortController.text.isEmpty) {
        _incomingPortController.text =
            '${protocol.defaultPort(_incomingSecurity)}';
      }
      final host = _incomingHostController.text;
      if (protocol == IncomingProtocol.pop3 && host.startsWith('imap.')) {
        _incomingHostController.text = 'pop.${host.substring(5)}';
      } else if (protocol == IncomingProtocol.imap && host.startsWith('pop.')) {
        _incomingHostController.text = 'imap.${host.substring(4)}';
      }
    });
  }

  void _setIncomingSecurity(ConnectionSecurity security) {
    setState(() {
      final oldDefault = _protocol.defaultPort(_incomingSecurity);
      _incomingSecurity = security;
      if (int.tryParse(_incomingPortController.text) == oldDefault) {
        _incomingPortController.text = '${_protocol.defaultPort(security)}';
      }
    });
  }

  void _setSmtpSecurity(ConnectionSecurity security) {
    setState(() {
      const defaults = {
        ConnectionSecurity.ssl: 465,
        ConnectionSecurity.starttls: 587,
        ConnectionSecurity.none: 25,
      };
      if (int.tryParse(_smtpPortController.text) == defaults[_smtpSecurity]) {
        _smtpPortController.text = '${defaults[security]}';
      }
      _smtpSecurity = security;
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = widget.isFirstRun
        ? 'Welcome to Look In'
        : _isEditMode
            ? 'Account Settings - ${_editing!.emailAddress}'
            : 'Add Account';
    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 30,
            color: OutlookTheme.primaryBlue,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.settings, size: 14, color: Colors.white),
                const SizedBox(width: 8),
                Text(title, style: OutlookTheme.titleBarStyle),
                const Spacer(),
                if (!widget.isFirstRun)
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, size: 14, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 24),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: OutlookTheme.folderPaneBackground,
              child: Center(
                child: Container(
                  width: 600,
                  margin: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: OutlookTheme.dividerColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _isEditMode ? _buildEditPage() : _buildWizard(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWizard() {
    return Column(
      children: [
        _StepIndicator(currentStep: _currentStep),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: switch (_currentStep) {
              0 => _buildEmailStep(),
              1 => _buildServerStep(),
              2 => _buildCredentialsStep(),
              _ => _buildTestStep(),
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              if (_testError != null && _currentStep < 3)
                Expanded(
                  child: Text(_testError!,
                      style: const TextStyle(
                          fontSize: 12, color: OutlookTheme.flaggedColor)),
                )
              else
                const Spacer(),
              if (_currentStep > 0)
                OutlinedButton(
                    onPressed: _previousStep, child: const Text('Back')),
              const SizedBox(width: 8),
              if (_currentStep < 3)
                ElevatedButton(
                  onPressed: _isDiscovering ? null : _nextStep,
                  child: const Text('Next'),
                )
              else
                ElevatedButton(
                  onPressed: _isTesting ? null : _save,
                  child: Text(_testSuccess ? 'Finish' : 'Add Anyway'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditPage() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('User Information'),
                _identityFields(),
                const SizedBox(height: 20),
                _sectionTitle('Server Information'),
                _serverFields(),
                const SizedBox(height: 20),
                _sectionTitle('Logon Information'),
                _credentialFields(),
                const SizedBox(height: 20),
                _sectionTitle('Options'),
                _optionFields(),
                const SizedBox(height: 20),
                _sectionTitle('Signature'),
                const Text(
                  'Added to new messages, replies and forwards from this account.',
                  style: TextStyle(fontSize: 12, color: OutlookTheme.textSecondary),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _signatureController,
                  maxLines: 5,
                  minLines: 3,
                  decoration: const InputDecoration(hintText: 'Your signature'),
                ),
                const SizedBox(height: 16),
                _testResult(),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _isTesting ? null : _testConnection,
                icon: const Icon(Icons.wifi_tethering, size: 16),
                label: const Text('Test Account Settings...'),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: OutlookTheme.primaryBlue)),
      );

  Widget _identityFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              labelText: 'Your Name',
              hintText: 'Example: Ellen Adams',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              hintText: 'Example: ellen@contoso.com',
            ),
            onSubmitted: (_) => _isEditMode ? null : _nextStep(),
          ),
        ],
      );

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.isFirstRun ? 'Set up your email' : 'Add an email account',
            style: OutlookTheme.readingPaneSubject),
        const SizedBox(height: 8),
        const Text(
          'Enter your name and email address. Look In looks up the server '
          'settings for you.',
          style: TextStyle(fontSize: 13, color: OutlookTheme.textSecondary),
        ),
        const SizedBox(height: 24),
        _identityFields(),
      ],
    );
  }

  Widget _buildServerStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isDiscovering)
          const _Banner(
            icon: Icons.search,
            text: 'Searching for your mail server settings...',
          )
        else if (_detectedName != null)
          _Banner(
            icon: Icons.check_circle,
            color: OutlookTheme.calendarEventGreen,
            text: 'Detected: $_detectedName. Check the settings below.',
          )
        else
          const _Banner(
            icon: Icons.info_outline,
            text: 'Settings could not be detected automatically. Enter the '
                'server names from your email provider.',
          ),
        const SizedBox(height: 16),
        _serverFields(),
      ],
    );
  }

  Widget _serverFields() {
    Widget securityDropdown(
            ConnectionSecurity value, ValueChanged<ConnectionSecurity> onChanged) =>
        SizedBox(
          width: 130,
          child: DropdownButtonFormField<ConnectionSecurity>(
            initialValue: value,
            key: ValueKey(value),
            decoration: const InputDecoration(labelText: 'Encryption'),
            items: [
              for (final s in ConnectionSecurity.values)
                DropdownMenuItem(
                  value: s,
                  child: Text(s.label, style: const TextStyle(fontSize: 13)),
                ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Account Type:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 12),
            SegmentedButton<IncomingProtocol>(
              segments: [
                for (final p in IncomingProtocol.values)
                  ButtonSegment(value: p, label: Text(p.label)),
              ],
              selected: {_protocol},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _setProtocol(s.first),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _incomingHostController,
                decoration: InputDecoration(
                  labelText: 'Incoming mail server (${_protocol.label})',
                  hintText: _protocol == IncomingProtocol.imap
                      ? 'imap.example.com'
                      : 'pop.example.com',
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _incomingPortController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port'),
              ),
            ),
            const SizedBox(width: 8),
            securityDropdown(_incomingSecurity, _setIncomingSecurity),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _smtpHostController,
                decoration: const InputDecoration(
                  labelText: 'Outgoing mail server (SMTP)',
                  hintText: 'smtp.example.com',
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _smtpPortController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port'),
              ),
            ),
            const SizedBox(width: 8),
            securityDropdown(_smtpSecurity, _setSmtpSecurity),
          ],
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _acceptInvalidCerts,
          onChanged: (v) => setState(() => _acceptInvalidCerts = v ?? false),
          title: const Text(
            'Accept untrusted certificates (self-signed servers only)',
            style: TextStyle(fontSize: 13),
          ),
        ),
        if (_protocol == IncomingProtocol.pop3)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _leaveOnServer,
            onChanged: (v) => setState(() => _leaveOnServer = v ?? true),
            title: const Text('Leave a copy of messages on the server',
                style: TextStyle(fontSize: 13)),
          ),
      ],
    );
  }

  Widget _credentialFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'User Name',
              hintText: 'Usually your email address',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            onSubmitted: (_) => _isEditMode ? null : _nextStep(),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your password is stored encrypted on this computer.',
            style: TextStyle(fontSize: 11.5, color: OutlookTheme.textMuted),
          ),
        ],
      );

  Widget _buildCredentialsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_providerNote != null) ...[
          _Banner(icon: Icons.info_outline, text: _providerNote!),
          const SizedBox(height: 16),
        ],
        _credentialFields(),
      ],
    );
  }

  Widget _optionFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Check for new messages every',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _syncInterval,
                isDense: true,
                items: [
                  for (final m in const [1, 2, 5, 10, 15, 30, 60])
                    DropdownMenuItem(value: m, child: Text('$m')),
                ],
                onChanged: (v) => setState(() => _syncInterval = v ?? 5),
              ),
              const SizedBox(width: 8),
              const Text('minutes', style: TextStyle(fontSize: 13)),
            ],
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _isEnabled,
            onChanged: (v) => setState(() => _isEnabled = v ?? true),
            title: const Text('Include this account in Send/Receive',
                style: TextStyle(fontSize: 13)),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _isDefault,
            onChanged: (v) => setState(() => _isDefault = v ?? false),
            title: const Text('Use as the default account for new messages',
                style: TextStyle(fontSize: 13)),
          ),
        ],
      );

  Widget _testResult() {
    if (_isTesting) {
      return const Row(
        children: [
          SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Testing incoming and outgoing servers...',
              style: TextStyle(fontSize: 13)),
        ],
      );
    }
    if (_testSuccess) {
      return const _Banner(
        icon: Icons.check_circle,
        color: OutlookTheme.calendarEventGreen,
        text: 'Congratulations! All tests completed successfully.',
      );
    }
    if (_testError != null) {
      return _Banner(
        icon: Icons.error,
        color: OutlookTheme.flaggedColor,
        text: _testError!,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildTestStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Test Account Settings', style: OutlookTheme.readingPaneSubject),
        const SizedBox(height: 8),
        const Text(
          'Look In logs in to the incoming server and connects to the outgoing '
          'server to make sure the settings work.',
          style: TextStyle(fontSize: 13, color: OutlookTheme.textSecondary),
        ),
        const SizedBox(height: 20),
        _summaryRow('Email', _emailController.text),
        _summaryRow(_protocol.label,
            '${_incomingHostController.text}:${_incomingPortController.text} (${_incomingSecurity.label})'),
        _summaryRow('SMTP',
            '${_smtpHostController.text}:${_smtpPortController.text} (${_smtpSecurity.label})'),
        _summaryRow('User name', _usernameController.text),
        const SizedBox(height: 20),
        _testResult(),
        const SizedBox(height: 12),
        if (!_isTesting)
          OutlinedButton.icon(
            onPressed: _testConnection,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Test Again'),
          ),
        if (_testError != null && !_isTesting)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'You can go back to correct the settings, or add the account '
              'anyway (for example, when you are offline right now).',
              style: TextStyle(fontSize: 12, color: OutlookTheme.textSecondary),
            ),
          ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text('$label:',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: OutlookTheme.textSecondary)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Banner({
    required this.icon,
    required this.text,
    this.color = OutlookTheme.primaryBlue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int currentStep;

  const _StepIndicator({required this.currentStep});

  static const _steps = ['Email', 'Server', 'Login', 'Test'];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: OutlookTheme.ribbonBackground,
      child: Row(
        children: List.generate(_steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.chevron_right,
                  size: 16, color: OutlookTheme.textMuted),
            );
          }
          final stepIndex = i ~/ 2;
          final isActive = stepIndex == currentStep;
          final isDone = stepIndex < currentStep;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? OutlookTheme.primaryBlue
                  : isDone
                      ? OutlookTheme.selectedItemBackground
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              _steps[stepIndex],
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? Colors.white
                    : isDone
                        ? OutlookTheme.primaryBlue
                        : OutlookTheme.textSecondary,
              ),
            ),
          );
        }),
      ),
    );
  }
}
