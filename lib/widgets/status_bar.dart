import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/outlook_theme.dart';
import '../providers/mail_provider.dart';
import '../providers/navigation_provider.dart';

/// Outlook 2013-style status bar at the bottom of the window.
class StatusBar extends StatefulWidget {
  const StatusBar({super.key});

  @override
  State<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<StatusBar> {
  bool _isOnline = true;
  Timer? _connectivityTimer;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    // Poll connectivity every 30 seconds
    _connectivityTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkConnectivity(),
    );
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 5));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (mounted && online != _isOnline) {
        setState(() => _isOnline = online);
      }
    } catch (_) {
      if (mounted && _isOnline) {
        setState(() => _isOnline = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();
    final mail = context.watch<MailProvider>();

    return Container(
      height: OutlookTheme.statusBarHeight,
      decoration: OutlookTheme.statusBarDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Left: connectivity / sync status
          if (!_isOnline)
            const _StatusItem(
              icon: Icons.cloud_off,
              text: 'Working Offline',
            )
          else if (nav.currentSection == NavigationSection.mail) ...[
            if (mail.isSyncing)
              const _StatusItem(
                icon: Icons.sync,
                text: 'Syncing...',
              )
            else if (mail.isLoading)
              const _StatusItem(
                icon: Icons.hourglass_empty,
                text: 'Loading...',
              )
            else if (mail.error != null)
              _StatusItem(
                icon: Icons.error_outline,
                text: mail.error!,
              )
            else
              const _StatusItem(
                icon: Icons.check_circle_outline,
                text: 'Connected',
              ),
            const SizedBox(width: 16),
            if (mail.selectedFolder != null)
              _StatusItem(
                text:
                    '${mail.messages.length} items, ${mail.unreadCount} unread',
              ),
          ],
          const Spacer(),
          // Right: view controls
          const _StatusItem(
            icon: Icons.view_agenda_outlined,
            text: '',
          ),
        ],
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final IconData? icon;
  final String text;

  const _StatusItem({this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: OutlookTheme.textOnPrimary),
          if (text.isNotEmpty) const SizedBox(width: 4),
        ],
        if (text.isNotEmpty) Text(text, style: OutlookTheme.statusBarStyle),
      ],
    );
  }
}
