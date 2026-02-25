import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/outlook_theme.dart';
import '../../models/email_account.dart';
import '../../providers/account_provider.dart';
import '../../services/email_service.dart';
import '../../services/oauth_service.dart';

/// Account setup wizard — shown on first run or via File > Account Settings.
///
/// Presents OAuth sign-in buttons (Google, Microsoft, Yahoo) followed by
/// a manual setup option. OAuth accounts auto-configure IMAP/SMTP settings
/// and use XOAUTH2 for authentication.
class AccountSetupScreen extends StatefulWidget {
  final bool isFirstRun;

  const AccountSetupScreen({super.key, this.isFirstRun = false});

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  // -1 = provider chooser, 0..3 = manual setup steps
  int _currentStep = -1;
  bool _isTesting = false;
  bool _isAuthenticating = false;
  String? _testError;
  bool _testSuccess = false;
  String? _authError;
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

  // ─── OAuth Sign-In ────────────────────────────────────────────────────

  Future<void> _signInWithOAuth(OAuthProvider provider) async {
    setState(() {
      _isAuthenticating = true;
      _authError = null;
    });

    try {
      final result = await OAuthService.authenticate(provider);
      if (!mounted) return;

      final config = OAuthService.getConfig(provider)!;
      final accountProvider = context.read<AccountProvider>();

      final account = EmailAccount(
        id: accountProvider.generateAccountId(),
        displayName: result.email.split('@').first,
        emailAddress: result.email,
        imapHost: config.imapHost,
        imapPort: config.imapPort,
        imapSecurity: ImapSecurity.ssl,
        smtpHost: config.smtpHost,
        smtpPort: config.smtpPort,
        smtpSecurity: SmtpSecurity.starttls,
        username: result.email,
        authType: AuthType.oauth2,
        oauthProvider: provider,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        tokenExpiry: result.expiry,
        isDefault: true,
      );

      await accountProvider.addAccount(account);
      if (!mounted) return;

      if (!widget.isFirstRun) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    }
  }

  // ─── Manual Setup Helpers ─────────────────────────────────────────────

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
    try {
      final account = _buildAccount();
      await context.read<AccountProvider>().addAccount(account);
      if (!mounted) return;

      if (widget.isFirstRun) {
        // _AppRoot watches AccountProvider and will swap to HomeScreen
        // automatically when accounts list becomes non-empty. But on some
        // platforms the rebuild races, so force a navigation as fallback.
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testError = 'Failed to save account: $e';
        _testSuccess = false;
      });
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
    if (_currentStep > -1) {
      setState(() {
        _currentStep--;
        _authError = null;
      });
    }
  }

  void _startManualSetup() {
    setState(() => _currentStep = 0);
  }

  // ─── Build ────────────────────────────────────────────────────────────

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
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Step indicator (hidden on chooser)
                      if (_currentStep >= 0) ...[
                        _StepIndicator(currentStep: _currentStep),
                        const Divider(height: 1),
                      ],
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
      case -1:
        return _buildProviderChooser();
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

  // ─── Step -1: Provider Chooser (OAuth + Manual) ───────────────────────

  Widget _buildProviderChooser() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.isFirstRun ? 'Set up your email' : 'Add an account',
          style: OutlookTheme.readingPaneSubject,
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in with your email provider or set up manually.',
          style: TextStyle(
            fontFamily: OutlookTheme.fontFamily,
            fontFamilyFallback: OutlookTheme.fontFamilyFallback,
            fontSize: 13,
            color: OutlookTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 24),

        // OAuth sign-in buttons
        _OAuthButton(
          label: 'Sign in with Google',
          iconColor: const Color(0xFFDB4437),
          icon: Icons.mail,
          onTap: _isAuthenticating
              ? null
              : () => _signInWithOAuth(OAuthProvider.google),
        ),
        const SizedBox(height: 10),
        _OAuthButton(
          label: 'Sign in with Microsoft',
          iconColor: const Color(0xFF00A4EF),
          icon: Icons.window,
          onTap: _isAuthenticating
              ? null
              : () => _signInWithOAuth(OAuthProvider.microsoft),
        ),
        const SizedBox(height: 10),
        _OAuthButton(
          label: 'Sign in with Yahoo',
          iconColor: const Color(0xFF6001D2),
          icon: Icons.mail_outline,
          onTap: _isAuthenticating
              ? null
              : () => _signInWithOAuth(OAuthProvider.yahoo),
        ),

        if (_isAuthenticating) ...[
          const SizedBox(height: 20),
          const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Waiting for authorization...'),
              ],
            ),
          ),
        ],

        if (_authError != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFDE7E9),
              border: Border.all(color: OutlookTheme.flaggedColor),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              children: [
                const Icon(Icons.error,
                    size: 16, color: OutlookTheme.flaggedColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _authError!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),

        // Manual setup option
        Center(
          child: TextButton.icon(
            onPressed: _isAuthenticating ? null : _startManualSetup,
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('Set up manually (IMAP/SMTP)'),
          ),
        ),
      ],
    );
  }

  // ─── Step 0: Email & Display Name ─────────────────────────────────────

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Display Name'),
        const SizedBox(height: 4),
        TextField(
          controller: _displayNameController,
          decoration: const InputDecoration(hintText: 'Your Name'),
        ),
        const SizedBox(height: 16),
        _buildLabel('Email Address'),
        const SizedBox(height: 4),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'you@example.com'),
        ),
      ],
    );
  }

  // ─── Step 1: Server Configuration ─────────────────────────────────────

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
                decoration: const InputDecoration(labelText: 'Port'),
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
                decoration: const InputDecoration(labelText: 'Port'),
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

  // ─── Step 2: Credentials ──────────────────────────────────────────────

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

  // ─── Step 3: Test Connection ──────────────────────────────────────────

  Widget _buildTestStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Test Connection', style: OutlookTheme.readingPaneSubject),
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
        _buildSummaryRow('Email', _emailController.text),
        _buildSummaryRow('IMAP',
            '${_imapHostController.text}:${_imapPortController.text} (${_imapSecurity.name})'),
        _buildSummaryRow('SMTP',
            '${_smtpHostController.text}:${_smtpPortController.text} (${_smtpSecurity.name})'),
        _buildSummaryRow('Username', _usernameController.text),
        const SizedBox(height: 24),
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
                label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
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
                    border:
                        Border.all(color: OutlookTheme.calendarEventGreen),
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
                    border: Border.all(color: OutlookTheme.flaggedColor),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error,
                          size: 16, color: OutlookTheme.flaggedColor),
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

  // ─── Shared Widgets ───────────────────────────────────────────────────

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
    // Provider chooser has no nav buttons
    if (_currentStep == -1) {
      return const SizedBox(height: 12);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _previousStep,
            child: Text(_currentStep == 0 ? 'Back' : 'Back'),
          ),
          const SizedBox(width: 8),
          if (_currentStep < 3)
            ElevatedButton(
              onPressed: _nextStep,
              child: const Text('Next'),
            ),
          if (_currentStep == 3)
            ElevatedButton(
              onPressed: _testSuccess ? _saveAccount : null,
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

// ─── OAuth Sign-In Button ─────────────────────────────────────────────────

class _OAuthButton extends StatefulWidget {
  final String label;
  final Color iconColor;
  final IconData icon;
  final VoidCallback? onTap;

  const _OAuthButton({
    required this.label,
    required this.iconColor,
    required this.icon,
    this.onTap,
  });

  @override
  State<_OAuthButton> createState() => _OAuthButtonState();
}

class _OAuthButtonState extends State<_OAuthButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: _isHovered && widget.onTap != null
                ? OutlookTheme.hoverColor
                : Colors.white,
            border: Border.all(
              color: _isHovered && widget.onTap != null
                  ? OutlookTheme.selectedItemBorder
                  : OutlookTheme.dividerColor,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: widget.iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(widget.icon, size: 18, color: widget.iconColor),
              ),
              const SizedBox(width: 14),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: OutlookTheme.fontFamily,
                  fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: widget.onTap != null
                      ? OutlookTheme.textPrimary
                      : OutlookTheme.textMuted,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: widget.onTap != null
                    ? OutlookTheme.textSecondary
                    : OutlookTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Step Indicator ───────────────────────────────────────────────────────

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

// ─── Header Button ────────────────────────────────────────────────────────

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
              ? Colors.white.withOpacity(0.2)
              : Colors.transparent,
          child: Icon(widget.icon, size: 12, color: Colors.white),
        ),
      ),
    );
  }
}
