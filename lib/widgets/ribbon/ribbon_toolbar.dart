import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/navigation_provider.dart';
import '../../theme/outlook_theme.dart';

/// Outlook 2013-style ribbon toolbar with tabs and grouped action buttons.
class RibbonToolbar extends StatelessWidget {
  final List<RibbonTabDefinition> tabs;
  final VoidCallback? onFileTab;

  const RibbonToolbar({
    super.key,
    required this.tabs,
    this.onFileTab,
  });

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();
    final activeTab = tabs.any((t) => t.label == nav.currentRibbonTab)
        ? nav.currentRibbonTab
        : tabs.first.label;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: OutlookTheme.ribbonTabHeight,
          color: OutlookTheme.primaryBlue,
          child: Row(
            children: [
              _FileTab(onTap: onFileTab),
              ...tabs.map((tab) => _RibbonTab(
                    label: tab.label,
                    isActive: activeTab == tab.label,
                    onTap: () => nav.switchRibbonTab(tab.label),
                  )),
              const Spacer(),
            ],
          ),
        ),
        Container(
          height: OutlookTheme.ribbonHeight - OutlookTheme.ribbonTabHeight,
          width: double.infinity,
          decoration: OutlookTheme.ribbonDecoration,
          child: _buildActiveTabContent(activeTab),
        ),
      ],
    );
  }

  Widget _buildActiveTabContent(String activeTab) {
    final tab = tabs.where((t) => t.label == activeTab).firstOrNull;
    if (tab == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < tab.groups.length; i++) ...[
              _RibbonGroup(group: tab.groups[i]),
              if (i < tab.groups.length - 1) const _RibbonGroupSeparator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _FileTab extends StatefulWidget {
  final VoidCallback? onTap;

  const _FileTab({this.onTap});

  @override
  State<_FileTab> createState() => _FileTabState();
}

class _FileTabState extends State<_FileTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          color: _hovered ? OutlookTheme.lightBlue : OutlookTheme.darkBlue,
          child: const Text(
            'FILE',
            style: TextStyle(
              fontFamily: OutlookTheme.fontFamily,
              fontFamilyFallback: OutlookTheme.fontFamilyFallback,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _RibbonTab extends StatefulWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _RibbonTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_RibbonTab> createState() => _RibbonTabState();
}

class _RibbonTabState extends State<_RibbonTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.isActive
                ? OutlookTheme.ribbonBackground
                : _isHovered
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.transparent,
          ),
          child: Text(
            widget.label.toUpperCase(),
            style: TextStyle(
              fontFamily: OutlookTheme.fontFamily,
              fontFamilyFallback: OutlookTheme.fontFamilyFallback,
              fontSize: 12,
              fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
              color: widget.isActive ? OutlookTheme.primaryBlue : Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _RibbonGroup extends StatelessWidget {
  final RibbonGroupDefinition group;

  const _RibbonGroup({required this.group});

  @override
  Widget build(BuildContext context) {
    // Large buttons stand alone; consecutive small buttons stack in
    // columns of three, as in Office.
    final children = <Widget>[];
    var smallRun = <RibbonItem>[];
    void flush() {
      if (smallRun.isEmpty) return;
      for (var i = 0; i < smallRun.length; i += 3) {
        final column = smallRun.sublist(i, (i + 3).clamp(0, smallRun.length));
        children.add(Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final item in column) _SmallRibbonButton(item: item)],
        ));
      }
      smallRun = [];
    }

    for (final item in group.items) {
      if (item.isLarge) {
        flush();
        children.add(_LargeRibbonButton(item: item));
      } else {
        smallRun.add(item);
      }
    }
    flush();

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(group.label, style: OutlookTheme.ribbonGroupLabel),
        ),
      ],
    );
  }
}

Future<void> _showItemMenu(BuildContext context, RibbonItem item) async {
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;
  final origin = box.localToGlobal(Offset(0, box.size.height), ancestor: overlay);
  final selected = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(origin.dx, origin.dy, box.size.width, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      for (var i = 0; i < item.menu!.length; i++)
        CheckedPopupMenuItem<int>(
          value: i,
          checked: item.menu![i].isChecked,
          height: 30,
          child: Text(item.menu![i].label, style: const TextStyle(fontSize: 12.5)),
        ),
    ],
  );
  if (selected != null) item.menu![selected].onTap();
}

class _LargeRibbonButton extends StatefulWidget {
  final RibbonItem item;

  const _LargeRibbonButton({required this.item});

  @override
  State<_LargeRibbonButton> createState() => _LargeRibbonButtonState();
}

class _LargeRibbonButtonState extends State<_LargeRibbonButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final enabled = item.isEnabled;
    final highlighted = (_isHovered && enabled) || item.isChecked;
    return Tooltip(
      message: item.tooltip ?? item.label.replaceAll('\n', ' '),
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: !enabled
              ? null
              : item.menu != null
                  ? () => _showItemMenu(context, item)
                  : item.onTap,
          child: Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
            decoration: BoxDecoration(
              color: item.isChecked
                  ? OutlookTheme.selectedItemBackground
                  : highlighted
                      ? OutlookTheme.hoverColor
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: highlighted
                    ? OutlookTheme.selectedItemBorder
                    : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Icon(
                  item.icon,
                  size: 28,
                  color: enabled
                      ? item.iconColor ?? OutlookTheme.primaryBlue
                      : OutlookTheme.textMuted.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 2),
                Text(
                  item.menu != null ? '${item.label} ▾' : item.label,
                  style: OutlookTheme.ribbonButtonLabel.copyWith(
                    color: enabled ? null : OutlookTheme.textMuted,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallRibbonButton extends StatefulWidget {
  final RibbonItem item;

  const _SmallRibbonButton({required this.item});

  @override
  State<_SmallRibbonButton> createState() => _SmallRibbonButtonState();
}

class _SmallRibbonButtonState extends State<_SmallRibbonButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final enabled = item.isEnabled;
    final highlighted = (_isHovered && enabled) || item.isChecked;
    return Tooltip(
      message: item.tooltip ?? item.label,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: !enabled
              ? null
              : item.menu != null
                  ? () => _showItemMenu(context, item)
                  : item.onTap,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: item.isChecked
                  ? OutlookTheme.selectedItemBackground
                  : highlighted
                      ? OutlookTheme.hoverColor
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: highlighted
                    ? OutlookTheme.selectedItemBorder
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item.icon,
                  size: 15,
                  color: enabled
                      ? item.iconColor ?? OutlookTheme.textPrimary
                      : OutlookTheme.textMuted.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  item.menu != null ? '${item.label} ▾' : item.label,
                  style: OutlookTheme.ribbonButtonLabel.copyWith(
                    color: enabled ? null : OutlookTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RibbonGroupSeparator extends StatelessWidget {
  const _RibbonGroupSeparator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Container(width: 1, color: OutlookTheme.dividerColor),
    );
  }
}

// ─── Data Models ───────────────────────────────────────────────────

class RibbonTabDefinition {
  final String label;
  final List<RibbonGroupDefinition> groups;

  const RibbonTabDefinition({required this.label, required this.groups});
}

class RibbonGroupDefinition {
  final String label;
  final List<RibbonItem> items;

  const RibbonGroupDefinition({required this.label, required this.items});
}

/// An entry of a ribbon button's drop-down menu.
class RibbonMenuItem {
  final String label;
  final VoidCallback onTap;
  final bool isChecked;

  const RibbonMenuItem({
    required this.label,
    required this.onTap,
    this.isChecked = false,
  });
}

class RibbonItem {
  final String label;
  final IconData icon;
  final Color? iconColor;
  final bool isLarge;
  final String? tooltip;
  final VoidCallback? onTap;

  /// Shows the button as pressed (toggle buttons such as Work Offline).
  final bool isChecked;

  /// When set, the button opens this drop-down menu instead of [onTap].
  final List<RibbonMenuItem>? menu;

  /// Disables the button even when [onTap] is set.
  final bool enabled;

  const RibbonItem({
    required this.label,
    required this.icon,
    this.iconColor,
    this.isLarge = false,
    this.tooltip,
    this.onTap,
    this.isChecked = false,
    this.menu,
    this.enabled = true,
  });

  bool get isEnabled => enabled && (onTap != null || menu != null);
}
