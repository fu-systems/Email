import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/outlook_theme.dart';
import '../../providers/navigation_provider.dart';

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
    final activeTab = nav.currentRibbonTab;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tab row
        Container(
          height: OutlookTheme.ribbonTabHeight,
          color: OutlookTheme.primaryBlue,
          child: Row(
            children: [
              // File tab (always present, styled differently)
              _FileTab(onTap: onFileTab),
              // Content tabs
              ...tabs.map((tab) => _RibbonTab(
                    label: tab.label,
                    isActive: activeTab == tab.label,
                    onTap: () => nav.switchRibbonTab(tab.label),
                  )),
              const Spacer(),
            ],
          ),
        ),
        // Ribbon content area
        Container(
          height: OutlookTheme.ribbonHeight - OutlookTheme.ribbonTabHeight,
          decoration: OutlookTheme.ribbonDecoration,
          child: _buildActiveTabContent(activeTab),
        ),
      ],
    );
  }

  Widget _buildActiveTabContent(String activeTab) {
    final tab = tabs.where((t) => t.label == activeTab).firstOrNull;
    if (tab == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < tab.groups.length; i++) ...[
            _RibbonGroup(group: tab.groups[i]),
            if (i < tab.groups.length - 1) const _RibbonGroupSeparator(),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}

class _FileTab extends StatelessWidget {
  final VoidCallback? onTap;

  const _FileTab({this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: OutlookTheme.darkBlue,
          border: Border.all(color: Colors.transparent),
        ),
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
                    ? OutlookTheme.primaryBlue.withOpacity( 0.8)
                    : Colors.transparent,
            border: widget.isActive
                ? const Border(
                    left: BorderSide(color: OutlookTheme.dividerColor),
                    right: BorderSide(color: OutlookTheme.dividerColor),
                  )
                : null,
          ),
          child: Text(
            widget.label.toUpperCase(),
            style: TextStyle(
              fontFamily: OutlookTheme.fontFamily,
              fontFamilyFallback: OutlookTheme.fontFamilyFallback,
              fontSize: 12,
              fontWeight:
                  widget.isActive ? FontWeight.w600 : FontWeight.w400,
              color: widget.isActive
                  ? OutlookTheme.primaryBlue
                  : Colors.white,
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
    return Column(
      children: [
        // Buttons area
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: group.items.map((item) {
                if (item.isLarge) {
                  return _LargeRibbonButton(item: item);
                }
                return _SmallRibbonButton(item: item);
              }).toList(),
            ),
          ),
        ),
        // Group label
        Container(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(group.label, style: OutlookTheme.ribbonGroupLabel),
        ),
      ],
    );
  }
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
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.item.onTap,
        child: Container(
          width: 60,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          decoration: BoxDecoration(
            color: _isHovered ? OutlookTheme.hoverColor : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
            border: _isHovered
                ? Border.all(color: OutlookTheme.selectedItemBorder)
                : Border.all(color: Colors.transparent),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.item.icon,
                size: 28,
                color: widget.item.iconColor ?? OutlookTheme.primaryBlue,
              ),
              const SizedBox(height: 2),
              Text(
                widget.item.label,
                style: OutlookTheme.ribbonButtonLabel,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.item.tooltip ?? widget.item.label,
        child: GestureDetector(
          onTap: widget.item.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color:
                  _isHovered ? OutlookTheme.hoverColor : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
              border: _isHovered
                  ? Border.all(color: OutlookTheme.selectedItemBorder)
                  : Border.all(color: Colors.transparent),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.item.icon,
                  size: 16,
                  color: widget.item.iconColor ?? OutlookTheme.textPrimary,
                ),
                const SizedBox(width: 4),
                Text(widget.item.label, style: OutlookTheme.ribbonButtonLabel),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: 1,
        color: OutlookTheme.dividerColor,
      ),
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

class RibbonItem {
  final String label;
  final IconData icon;
  final Color? iconColor;
  final bool isLarge;
  final String? tooltip;
  final VoidCallback? onTap;

  const RibbonItem({
    required this.label,
    required this.icon,
    this.iconColor,
    this.isLarge = false,
    this.tooltip,
    this.onTap,
  });
}
