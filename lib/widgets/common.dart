import 'package:flutter/material.dart';

import '../theme/outlook_theme.dart';

/// Outlook 2013-style dialog: blue title strip, content, and a button row.
class OutlookDialog extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final EdgeInsetsGeometry padding;

  const OutlookDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.width = 420,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height - 80;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 36,
                padding: const EdgeInsets.only(left: 16, right: 6),
                color: OutlookTheme.primaryBlue,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: OutlookTheme.titleBarStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close,
                          size: 14, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: padding,
                  child: child,
                ),
              ),
              if (actions.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        actions[i],
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks a yes/no question. Returns true when confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => OutlookDialog(
      title: title,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          autofocus: true,
          style: destructive
              ? ElevatedButton.styleFrom(
                  backgroundColor: OutlookTheme.flaggedColor)
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
      child: Text(message, style: const TextStyle(fontSize: 13)),
    ),
  );
  return result ?? false;
}

/// Asks for a single line of text. Returns null when cancelled.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initialValue = '',
  String confirmLabel = 'OK',
  String? hint,
}) {
  final controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        final value = controller.text.trim();
        if (value.isNotEmpty) Navigator.of(ctx).pop(value);
      }

      return OutlookDialog(
        title: title,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(onPressed: submit, child: Text(confirmLabel)),
        ],
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onSubmitted: (_) => submit(),
        ),
      );
    },
  ).whenComplete(controller.dispose);
}

/// An entry of a right-click context menu.
class MenuAction<T> {
  final T value;
  final String label;
  final IconData? icon;
  final bool enabled;
  final bool dividerBefore;
  final String? shortcut;

  const MenuAction(
    this.value,
    this.label, {
    this.icon,
    this.enabled = true,
    this.dividerBefore = false,
    this.shortcut,
  });
}

/// Shows a context menu at [globalPosition] and returns the chosen value.
Future<T?> showContextMenu<T>(
  BuildContext context,
  Offset globalPosition,
  List<MenuAction<T>> actions,
) {
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(globalPosition);
  final items = <PopupMenuEntry<T>>[];
  for (final a in actions) {
    if (a.dividerBefore && items.isNotEmpty) {
      items.add(const PopupMenuDivider(height: 8));
    }
    items.add(PopupMenuItem<T>(
      value: a.value,
      enabled: a.enabled,
      height: 30,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: a.icon == null
                ? null
                : Icon(a.icon,
                    size: 16,
                    color: a.enabled
                        ? OutlookTheme.textSecondary
                        : OutlookTheme.textMuted),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(a.label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: a.enabled
                      ? OutlookTheme.textPrimary
                      : OutlookTheme.textMuted,
                )),
          ),
          if (a.shortcut != null) ...[
            const SizedBox(width: 24),
            Text(a.shortcut!,
                style: const TextStyle(
                    fontSize: 11, color: OutlookTheme.textMuted)),
          ],
        ],
      ),
    ));
  }
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(local.dx, local.dy, 1, 1),
      Offset.zero & overlay.size,
    ),
    items: items,
    shape: const RoundedRectangleBorder(
      side: BorderSide(color: OutlookTheme.dividerColor),
    ),
    elevation: 4,
  );
}

/// A flat Outlook-style button that highlights on hover.
class HoverButton extends StatefulWidget {
  final IconData? icon;
  final String? label;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? color;
  final double iconSize;
  final EdgeInsetsGeometry padding;
  final bool selected;

  const HoverButton({
    super.key,
    this.icon,
    this.label,
    this.onTap,
    this.tooltip,
    this.color,
    this.iconSize = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.selected = false,
  });

  @override
  State<HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<HoverButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final color = !enabled
        ? OutlookTheme.textMuted
        : widget.color ?? OutlookTheme.primaryBlue;
    Widget button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.selected
                ? OutlookTheme.selectedItemBackground
                : (_hovered && enabled)
                    ? OutlookTheme.hoverColor
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: (_hovered && enabled) || widget.selected
                  ? OutlookTheme.selectedItemBorder
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null)
                Icon(widget.icon, size: widget.iconSize, color: color),
              if (widget.icon != null && widget.label != null)
                const SizedBox(width: 4),
              if (widget.label != null)
                Text(widget.label!,
                    style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// Shows a short message at the bottom of the window.
void showStatusMessage(BuildContext context, String message,
    {bool isError = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? OutlookTheme.flaggedColor : null,
      duration: Duration(seconds: isError ? 5 : 3),
      behavior: SnackBarBehavior.floating,
      width: 480,
    ));
}

/// Circular avatar with initials, colored deterministically by [seed].
class InitialsAvatar extends StatelessWidget {
  final String initials;
  final String seed;
  final double size;

  const InitialsAvatar({
    super.key,
    required this.initials,
    required this.seed,
    this.size = 36,
  });

  static const _palette = [
    Color(0xFF2B579A),
    Color(0xFF107C10),
    Color(0xFF5C2D91),
    Color(0xFFD83B01),
    Color(0xFF008272),
    Color(0xFFB4009E),
    Color(0xFF0078D7),
    Color(0xFF8E562E),
  ];

  static Color colorFor(String seed) {
    var hash = 0;
    for (final unit in seed.toLowerCase().codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  /// Initials for a display name or address.
  static String initialsFor(String name) {
    final cleaned = name.replaceAll(RegExp(r'[<>"()]'), ' ').trim();
    if (cleaned.isEmpty) return '?';
    final parts = cleaned.contains('@')
        ? [cleaned.split('@').first]
        : cleaned.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts.first.isNotEmpty && parts.last.isNotEmpty) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.first[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorFor(seed),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
