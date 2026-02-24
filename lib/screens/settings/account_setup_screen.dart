import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/outlook_theme.dart';
import '../../models/email_account.dart';
import '../../providers/account_provider.dart';
import '../../services/email_service.dart';

/// Account setup wizard — shown on first run or via File > Account Settings.
class AccountSetupScreen extends StatefulWidget {
  final bool isFirstRun;

  const AccountSetupScreen({super.key, this.isFirstRun = false});

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  int _currentStep = 0;
  bool _isTesting = false;
  String? _testError;
  bool _testSuccess = false;
  EmailProviderConfig? _detectedProvider;

  // Form controllers
  final _emailController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _imapHostController = TextEditingController();
  final _imapPortController = TextEditingController(text: '993');
  final _smtpHostController = TextEditingController();
  final _smtpPortController = TextEditingController(text: '587');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  ImapSecurity _imapSecurity = ImapSecurity.ssl;
  SmtpSecurity _smtpSecurity = SmtpSecurity.starttls;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _displayNameController.dispose();
    _imapHostController.dispose();
    _imapPortController.dispose();
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _detectProvider() {
    final email = _emailController.text.trim();
    final provider = EmailProviderConfig.detectFromEmail(email);
    setState(() {
      _detectedProvider = provider;
      if (provider != null) {
        _imapHostController.text = provider.imapHost;
        _imapPortController.text = provider.imapPort.toString();
        _imapSecurity = provider.imapSecurity;
        _smtpHostController.text = provider.smtpHost;
        _smtpPortController.text = provider.smtpPort.toString();
        _smtpSecurity = provider.smtpSecurity;
      }
      // Default username to email address
      if (_usernameController.text.isEmpty) {
        _usernameController.text = email;
      }
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testError = null;
      _testSuccess = false;
    });

    final account = _buildAccount();
    final error = await EmailService.testConnection(account);

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testError = error;
      _testSuccess = error == null;
    });
  }

  EmailAccount _buildAccount() {
    return EmailAccount(
      id: context.read<AccountProvider>().generateAccountId(),
      displayName: _displayNameController.text.trim().isNotEmpty
          ? _displayNameController.text.trim()
          : _emailController.text.trim(),
      emailAddress: _emailController.text.trim(),
      imapHost: _imapHostController.text.trim(),
      imapPort: int.tryParse(_imapPortController.text) ?? 993,
      imapSecurity: _imapSecurity,
      smtpHost: _smtpHostController.text.trim(),
      smtpPort: int.tryParse(_smtpPortController.text) ?? 587,
      smtpSecurity: _smtpSecurity,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      isDefault: true,
    );
  }

  Future<void> _saveAccount() async {
    final account = _buildAccount();
    await context.read<AccountProvider>().addAccount(account);
    if (!mounted) return;

    if (widget.isFirstRun) {
      // Pop is not needed — _AppRoot in app.dart will rebuild and show HomeScreen
      // when accounts list is no longer empty
    } else {
      Navigator.of(context).pop();
    }
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (_emailController.text.trim().isEmpty) return;
      _detectProvider();
    }
    if (_currentStep < 3) {
      setState(() => _currentStep++);
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Title bar
          Container(
            height: 30,
            color: OutlookTheme.primaryBlue,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.settings, size: 14, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  widget.isFirstRun
                      ? 'Welcome to Look In'
                      : 'Add Email Account',
                  style: OutlookTheme.titleBarStyle,
                ),
                const Spacer(),
                if (!widget.isFirstRun)
                  _HeaderButton(
                    icon: Icons.close,
                    onTap: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Container(
              color: OutlookTheme.folderPaneBackground,
              child: Center(
                child: Container(
                  width: 520,
                  margin: const EdgeInsets.symmetric(vertical: 32),
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
                  child: Column(
                    children: [
                      // Step indicator
                      _StepIndicator(currentStep: _currentStep),
                      const Divider(height: 1),
                      // Step content
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: _buildStepContent(),
                        ),
                      ),
                      // Navigation buttons
                      const Divider(height: 1),
                      _buildNavButtons(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildEmailStep();
      case 1:
        return _buildServerStep();
      case 2:
        return _buildCredentialsStep();
      case 3:
        return _buildTestStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isFirstRun) ...[
          Text(
            'Set up your email',
            style: OutlookTheme.readingPaneSubject,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your email address to get started. We\'ll try to detect your server settings automatically.',
            style: TextStyle(
              fontFamily: OutlookTheme.fontFamily,
              fontFamilyFallback: OutlookTheme.fontFamilyFallback,
              fontSize: 13,
              color: OutlookTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
        ],
        _buildLabel('Display Name'),
        const SizedBox(height: 4),
        TextField(
          controller: _displayNameController,
          decoration: const InputDecoration(
            hintText: 'Your Name',
          ),
        ),
        const SizedBox(height: 16),
        _buildLabel('Email Address'),
        const SizedBox(height: 4),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'you@example.com',
          ),
        ),
      ],
    );
  }

  Widget _buildServerStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_detectedProvider != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: OutlookTheme.hoverColor,
              border: Border.all(color: OutlookTheme.selectedItemBorder),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 16, color: OutlookTheme.calendarEventGreen),
                const SizedBox(width: 8),
                Text(
                  'Detected: ${_detectedProvider!.name}',
                  style: const TextStyle(
                    fontFamily: OutlookTheme.fontFamily,
                    fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        _buildLabel('Incoming Mail (IMAP)'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _imapHostController,
                decoration: const InputDecoration(
                  hintText: 'imap.example.com',
                  labelText: 'Server',
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _imapPortController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: DropdownButtonFormField<ImapSecurity>(
                value: _imapSecurity,
                decoration: const InputDecoration(labelText: 'Security'),
                items: ImapSecurity.values.map((s) {
                  return DropdownMenuItem(
                    value: s,
                    child: Text(s.name.toUpperCase(),
                        style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _imapSecurity = v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildLabel('Outgoing Mail (SMTP)'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _smtpHostController,
                decoration: const InputDecoration(
                  hintText: 'smtp.example.com',
                  labelText: 'Server',
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _smtpPortController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: DropdownButtonFormField<SmtpSecurity>(
                value: _smtpSecurity,
                decoration: const InputDecoration(labelText: 'Security'),
                items: SmtpSecurity.values.map((s) {
                  return DropdownMenuItem(
                    value: s,
                    child: Text(s.name.toUpperCase(),
                        style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _smtpSecurity = v);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCredentialsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Username'),
        const SizedBox(height: 4),
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            hintText: 'Usually your email address',
          ),
        ),
        const SizedBox(height: 16),
        _buildLabel('Password'),
        const SizedBox(height: 4),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: 'Enter your password',
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                size: 18,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your credentials are stored locally on this device.',
          style: TextStyle(
            fontFamily: OutlookTheme.fontFamily,
            fontFamilyFallback: OutlookTheme.fontFamilyFallback,
            fontSize: 11,
            color: OutlookTheme.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildTestStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Test Connection',
          style: OutlookTheme.readingPaneSubject,
        ),
        const SizedBox(height: 8),
        Text(
          'Verify that your email settings work correctly.',
          style: TextStyle(
            fontFamily: OutlookTheme.fontFamily,
            fontFamilyFallback: OutlookTheme.fontFamilyFallback,
            fontSize: 13,
            color: OutlookTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        // Summary
        _buildSummaryRow('Email', _emailController.text),
        _buildSummaryRow('IMAP',
            '${_imapHostController.text}:${_imapPortController.text} (${_imapSecurity.name})'),
        _buildSummaryRow('SMTP',
            '${_smtpHostController.text}:${_smtpPortController.text} (${_smtpSecurity.name})'),
        _buildSummaryRow('Username', _usernameController.text),
        const SizedBox(height: 24),
        // Test button + result
        Center(
          child: Column(
            children: [
              ElevatedButton.icon(
                onPressed: _isTesting ? null : _testConnection,
                icon: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.wifi_tethering, size: 16),
                label: Text(_isTesting
                    ? 'Testing...'
                    : 'Test Connection'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              if (_testSuccess)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDFF6DD),
                    border: Border.all(
                        color: OutlookTheme.calendarEventGreen),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: 16,
                          color: OutlookTheme.calendarEventGreen),
                      SizedBox(width: 8),
                      Text('Connection successful!'),
                    ],
                  ),
                ),
              if (_testError != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDE7E9),
                    border:
                        Border.all(color: OutlookTheme.flaggedColor),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error,
                          size: 16,
                          color: OutlookTheme.flaggedColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testError!,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontFamily: OutlookTheme.fontFamily,
                fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: OutlookTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: OutlookTheme.fontFamily,
                fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                fontSize: 13,
                color: OutlookTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_currentStep > 0)
            OutlinedButton(
              onPressed: _previousStep,
              child: const Text('Back'),
            ),
          const SizedBox(width: 8),
          if (_currentStep < 3)
            ElevatedButton(
              onPressed: _nextStep,
              child: const Text('Next'),
            ),
          if (_currentStep == 3)
            ElevatedButton(
              onPressed: (_testSuccess || _testError != null)
                  ? _saveAccount
                  : null,
              child: const Text('Add Account'),
            ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: OutlookTheme.fontFamily,
        fontFamilyFallback: OutlookTheme.fontFamilyFallback,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: OutlookTheme.textPrimary,
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
                fontFamily: OutlookTheme.fontFamily,
                fontFamilyFallback: OutlookTheme.fontFamilyFallback,
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

class _HeaderButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderButton({required this.icon, required this.onTap});

  @override
  State<_HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<_HeaderButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 28,
          height: 20,
          color: _isHovered
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.transparent,
          child: Icon(widget.icon, size: 12, color: Colors.white),
        ),
      ),
    );
  }
}
