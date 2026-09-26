import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/mail_provider.dart';
import '../providers/navigation_provider.dart';
import '../theme/outlook_theme.dart';

/// Outlook 2013 navigation bar: large "Mail  Calendar  People" labels along
/// the bottom of the window, above the status bar.
class OutlookNavigationBar extends StatelessWidget {
  const OutlookNavigationBar({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();
    final unread = context.select<MailProvider, int>((m) => m.totalInboxUnread);

    return Container(
      height: OutlookTheme.navigationBarHeight,
      decoration: const BoxDecoration(
        color: OutlookTheme.navBarBackground,
        border: Border(top: BorderSide(color: OutlookTheme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (final section in NavigationSection.values)
            _NavButton(
              section: section,
              isActive: nav.currentSection == section,
              badge: section == NavigationSection.mail && unread > 0
                  ? unread
                  : null,
              onTap: () => nav.switchSection(section),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  final NavigationSection section;
  final bool isActive;
  final int? badge;
  final VoidCallback onTap;

  const _NavButton({
    required this.section,
    required this.isActive,
    required this.onTap,
    this.badge,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive
        ? OutlookTheme.primaryBlue
        : _isHovered
            ? OutlookTheme.lightBlue
            : OutlookTheme.navBarInactiveText;
    return Tooltip(
      message: '${widget.section.label} (Ctrl+${widget.section.index + 1})',
      waitDuration: const Duration(milliseconds: 800),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Row(
              children: [
                Text(
                  widget.section.label,
                  style: TextStyle(
                    fontFamily: OutlookTheme.fontFamily,
                    fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                    fontSize: 15,
                    fontWeight:
                        widget.isActive ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                  ),
                ),
                if (widget.badge != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    '${widget.badge}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: OutlookTheme.primaryBlue,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
