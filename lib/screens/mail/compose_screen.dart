import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/outlook_theme.dart';
import '../../models/email_message.dart';
import '../../providers/mail_provider.dart';
import '../../providers/account_provider.dart';

/// Email compose screen, styled like Outlook 2013's compose window.
class ComposeScreenRoute extends StatefulWidget {
  final EmailMessage? replyTo;
  final bool replyAll;
  final EmailMessage? forwardFrom;

  const ComposeScreenRoute({
    super.key,
    this.replyTo,
    this.replyAll = false,
    this.forwardFrom,
  });

  @override
  State<ComposeScreenRoute> createState() => _ComposeScreenRouteState();
}

class _ComposeScreenRouteState extends State<ComposeScreenRoute> {
  final _toController = TextEditingController();
  final _ccController = TextEditingController();
  final _bccController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _showCc = false;
  bool _showBcc = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _prefillFields();
  }

  void _prefillFields() {
    if (widget.replyTo != null) {
      final msg = widget.replyTo!;
      _toController.text = msg.from.address;
      _subjectController.text = msg.subject.startsWith('Re:')
          ? msg.subject
          : 'Re: ${msg.subject}';

      if (widget.replyAll) {
        final ccAddresses = [
          ...msg.to.map((a) => a.address),
          ...msg.cc.map((a) => a.address),
        ];
        // Remove the current user's address (we'll handle this when we know the account)
        _ccController.text = ccAddresses.join('; ');
        _showCc = ccAddresses.isNotEmpty;
      }

      _bodyController.text = _buildReplyBody(msg);
    } else if (widget.forwardFrom != null) {
      final msg = widget.forwardFrom!;
      _subjectController.text = msg.subject.startsWith('Fwd:')
          ? msg.subject
          : 'Fwd: ${msg.subject}';
      _bodyController.text = _buildForwardBody(msg);
    }
  }

  String _buildReplyBody(EmailMessage msg) {
    final body = msg.textBody ?? '';
    return '\n\n'
        '________________________________\n'
        'From: ${msg.from}\n'
        'Sent: ${msg.date}\n'
        'To: ${msg.to.map((a) => a.toString()).join('; ')}\n'
        'Subject: ${msg.subject}\n'
        '\n'
        '$body';
  }

  String _buildForwardBody(EmailMessage msg) {
    final body = msg.textBody ?? '';
    return '\n\n'
        '________________________________\n'
        'From: ${msg.from}\n'
        'Sent: ${msg.date}\n'
        'To: ${msg.to.map((a) => a.toString()).join('; ')}\n'
        'Subject: ${msg.subject}\n'
        '\n'
        '$body';
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final to = _toController.text
        .split(RegExp(r'[;,]\s*'))
        .where((s) => s.isNotEmpty)
        .toList();

    if (to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one recipient')),
      );
      return;
    }

    setState(() => _isSending = true);

    final account = context.read<AccountProvider>().activeAccount;
    if (account == null) {
      setState(() => _isSending = false);
      return;
    }

    final cc = _ccController.text
        .split(RegExp(r'[;,]\s*'))
        .where((s) => s.isNotEmpty)
        .toList();

    final bcc = _bccController.text
        .split(RegExp(r'[;,]\s*'))
        .where((s) => s.isNotEmpty)
        .toList();

    final success = await context.read<MailProvider>().sendMessage(
          from: account.emailAddress,
          to: to,
          cc: cc,
          bcc: bcc,
          subject: _subjectController.text,
          textBody: _bodyController.text,
          inReplyTo: widget.replyTo?.messageId,
        );

    setState(() => _isSending = false);

    if (success && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Compose title bar
          Container(
            height: 30,
            color: OutlookTheme.primaryBlue,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.edit, size: 14, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  _getTitle(),
                  style: OutlookTheme.titleBarStyle,
                ),
                const Spacer(),
                _CloseButton(onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          // Compose ribbon
          _ComposeRibbon(
            onSend: _send,
            isSending: _isSending,
            onAttach: () {},
          ),
          // Compose form
          Expanded(
            child: _ComposeForm(
              toController: _toController,
              ccController: _ccController,
              bccController: _bccController,
              subjectController: _subjectController,
              bodyController: _bodyController,
              showCc: _showCc,
              showBcc: _showBcc,
              onToggleCc: () => setState(() => _showCc = !_showCc),
              onToggleBcc: () => setState(() => _showBcc = !_showBcc),
            ),
          ),
        ],
      ),
    );
  }

  String _getTitle() {
    if (widget.replyTo != null) {
      return widget.replyAll ? 'Reply All' : 'Reply';
    }
    if (widget.forwardFrom != null) return 'Forward';
    return 'New Message';
  }
}

class _CloseButton extends StatefulWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 28,
          height: 20,
          color: _hovered
              ? Colors.white.withOpacity( 0.2)
              : Colors.transparent,
          child: const Icon(Icons.close, size: 12, color: Colors.white),
        ),
      ),
    );
  }
}

class _ComposeRibbon extends StatelessWidget {
  final VoidCallback onSend;
  final bool isSending;
  final VoidCallback onAttach;

  const _ComposeRibbon({
    required this.onSend,
    required this.isSending,
    required this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: OutlookTheme.ribbonDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Send button
          _ComposeAction(
            icon: Icons.send,
            label: isSending ? 'Sending...' : 'Send',
            isPrimary: true,
            onTap: isSending ? null : onSend,
          ),
          const SizedBox(width: 8),
          const _Separator(),
          const SizedBox(width: 8),
          // Attach
          _ComposeAction(
            icon: Icons.attach_file,
            label: 'Attach File',
            onTap: onAttach,
          ),
          const SizedBox(width: 4),
          _ComposeAction(
            icon: Icons.text_fields,
            label: 'Format',
            onTap: () {},
          ),
          const Spacer(),
          // Discard
          _ComposeAction(
            icon: Icons.delete_outline,
            label: 'Discard',
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _ComposeAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback? onTap;

  const _ComposeAction({
    required this.icon,
    required this.label,
    this.isPrimary = false,
    this.onTap,
  });

  @override
  State<_ComposeAction> createState() => _ComposeActionState();
}

class _ComposeActionState extends State<_ComposeAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? OutlookTheme.primaryBlue
                : _hovered
                    ? OutlookTheme.hoverColor
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
            border: _hovered && !widget.isPrimary
                ? Border.all(color: OutlookTheme.selectedItemBorder)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: widget.isPrimary
                    ? Colors.white
                    : OutlookTheme.textPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: OutlookTheme.fontFamily,
                  fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                  fontSize: 12,
                  color: widget.isPrimary
                      ? Colors.white
                      : OutlookTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      color: OutlookTheme.dividerColor,
    );
  }
}

class _ComposeForm extends StatelessWidget {
  final TextEditingController toController;
  final TextEditingController ccController;
  final TextEditingController bccController;
  final TextEditingController subjectController;
  final TextEditingController bodyController;
  final bool showCc;
  final bool showBcc;
  final VoidCallback onToggleCc;
  final VoidCallback onToggleBcc;

  const _ComposeForm({
    required this.toController,
    required this.ccController,
    required this.bccController,
    required this.subjectController,
    required this.bodyController,
    required this.showCc,
    required this.showBcc,
    required this.onToggleCc,
    required this.onToggleBcc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // To field
          _AddressField(
            label: 'To',
            controller: toController,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!showCc)
                  TextButton(
                    onPressed: onToggleCc,
                    child: const Text('Cc',
                        style: TextStyle(fontSize: 12)),
                  ),
                if (!showBcc)
                  TextButton(
                    onPressed: onToggleBcc,
                    child: const Text('Bcc',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          // Cc field
          if (showCc) _AddressField(label: 'Cc', controller: ccController),
          // Bcc field
          if (showBcc) _AddressField(label: 'Bcc', controller: bccController),
          // Subject field
          Container(
            height: 36,
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: OutlookTheme.dividerColor),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const SizedBox(
                  width: 60,
                  child: Text(
                    'Subject:',
                    style: TextStyle(
                      fontSize: 13,
                      color: OutlookTheme.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: subjectController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Body
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: bodyController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontFamily: OutlookTheme.fontFamily,
                  fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                  fontSize: 14,
                  height: 1.5,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Type your message here...',
                  hintStyle: TextStyle(
                    color: OutlookTheme.textMuted,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final Widget? trailing;

  const _AddressField({
    required this.label,
    required this.controller,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: OutlookTheme.dividerColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 13,
                color: OutlookTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
