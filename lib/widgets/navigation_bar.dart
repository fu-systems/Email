import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/outlook_theme.dart';
import '../providers/navigation_provider.dart';

/// Bottom navigation bar for switching between Mail, Calendar, and People.
/// Mimics the Outlook 2013 compact navigation bar at the bottom of the
/// folder pane.
class OutlookNavigationBar extends StatelessWidget {
  const OutlookNavigationBar({super.key});

  void _showNavigationOptions(BuildContext context, NavigationProvider nav) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(button.size.width - 120, 0),
            ancestor: overlay),
        button.localToGlobal(
            Offset(button.size.width, button.size.height),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<NavigationSection>(
      context: context,
      position: position,
      items: NavigationSection.values.map((section) {
        return PopupMenuItem<NavigationSection>(
          value: section,
          height: 32,
          child: Row(
            children: [
              Icon(section.icon, size: 16,
                  color: nav.currentSection == section
                      ? OutlookTheme.primaryBlue
                      : OutlookTheme.textSecondary),
              const SizedBox(width: 8),
              Text(
                section.label,
                style: TextStyle(
                  fontFamily: OutlookTheme.fontFamily,
                  fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                  fontSize: 12,
                  fontWeight: nav.currentSection == section
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: OutlookTheme.textPrimary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((section) {
      if (section != null) {
        nav.switchSection(section);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();

    return Container(
      height: OutlookTheme.navigationBarHeight,
      decoration: const BoxDecoration(
        color: OutlookTheme.navBarBackground,
        border: Border(
          top: BorderSide(color: OutlookTheme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          for (final section in NavigationSection.values)
            _NavButton(
              section: section,
              isActive: nav.currentSection == section,
              onTap: () => nav.switchSection(section),
            ),
          const Spacer(),
          // Overflow "..." menu
          _OverflowButton(
            onTap: () {
              _showNavigationOptions(context, nav);
            },
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  final NavigationSection section;
  final bool isActive;
  final VoidCallback onTap;

  const _NavButton({
    required this.section,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.isActive
                ? OutlookTheme.navBarActiveBackground
                : _isHovered
                    ? OutlookTheme.hoverColor
                    : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.section.icon,
                size: OutlookTheme.sidebarIconSize,
                color: widget.isActive
                    ? OutlookTheme.navBarActiveText
                    : OutlookTheme.navBarInactiveText,
              ),
              const SizedBox(width: 6),
              Text(
                widget.section.label,
                style: TextStyle(
                  fontFamily: OutlookTheme.fontFamily,
                  fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                  fontSize: 12,
                  fontWeight: widget.isActive
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: widget.isActive
                      ? OutlookTheme.navBarActiveText
                      : OutlookTheme.navBarInactiveText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverflowButton extends StatefulWidget {
  final VoidCallback onTap;

  const _OverflowButton({required this.onTap});

  @override
  State<_OverflowButton> createState() => _OverflowButtonState();
}

class _OverflowButtonState extends State<_OverflowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: _isHovered ? OutlookTheme.hoverColor : Colors.transparent,
          child: const Icon(
            Icons.more_horiz,
            size: 16,
            color: OutlookTheme.navBarInactiveText,
          ),
        ),
      ),
    );
  }
}
