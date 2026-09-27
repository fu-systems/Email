import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../theme/outlook_theme.dart';
import '../common.dart';

/// Formatting commands on a Quill controller, shared by the ribbon, the
/// keyboard shortcuts and the signature editor.
class TextFormatting {
  TextFormatting._();

  static Map<String, Attribute> _attrs(QuillController c) =>
      c.getSelectionStyle().attributes;

  static bool isActive(QuillController c, Attribute a) {
    final current = _attrs(c)[a.key];
    if (current == null) return false;
    return a.value is bool || current.value == a.value;
  }

  /// Turns [a] on, or off when the selection already has it.
  static void toggle(QuillController c, Attribute a) =>
      c.formatSelection(isActive(c, a) ? Attribute.clone(a, null) : a);

  static void setAlign(QuillController c, Attribute? align) =>
      c.formatSelection(align ?? Attribute.clone(Attribute.align, null));

  static void setColor(QuillController c, String? hex) => c.formatSelection(
      hex == null ? Attribute.clone(Attribute.color, null) : ColorAttribute(hex));

  static void setHighlight(QuillController c, String? hex) =>
      c.formatSelection(hex == null
          ? Attribute.clone(Attribute.background, null)
          : BackgroundAttribute(hex));

  static void setFont(QuillController c, String? family) => c.formatSelection(
      family == null ? Attribute.clone(Attribute.font, null) : FontAttribute(family));

  /// Sets the size in points (stored in pixels, as the editor draws it).
  static void setSizePt(QuillController c, int? pt) => c.formatSelection(
      pt == null || pt == 11
          ? Attribute.clone(Attribute.size, null)
          : SizeAttribute('${(pt * 4 / 3).round()}'));

  static String currentFont(QuillController c) =>
      (_attrs(c)[Attribute.font.key]?.value as String?) ?? 'Calibri';

  static int currentSizePt(QuillController c) {
    final px = double.tryParse('${_attrs(c)[Attribute.size.key]?.value}');
    return px == null ? 11 : (px * 3 / 4).round();
  }

  /// Removes character formatting (and links) from the selection.
  static void clear(QuillController c) {
    final keys = <String>{};
    for (final style in c.getAllSelectionStyles()) {
      keys.addAll(style.attributes.keys);
    }
    for (final key in keys) {
      final attribute = Attribute.fromKeyValue(key, null);
      if (attribute != null && attribute.scope == AttributeScope.inline) {
        c.formatSelection(attribute);
      }
    }
  }

  /// Inserts [delta] (e.g. a signature) at the cursor.
  static void insertDelta(QuillController c, Delta delta) {
    final index = c.selection.baseOffset < 0 ? 0 : c.selection.baseOffset;
    final length = c.selection.extentOffset - index;
    // concat returns a new Delta.
    final change = (Delta()
          ..retain(index)
          ..delete(length < 0 ? 0 : length))
        .concat(delta);
    c.compose(change, TextSelection.collapsed(offset: index + delta.length),
        ChangeSource.local);
  }

  static void insertImage(QuillController c, String source) {
    final index = c.selection.baseOffset < 0 ? 0 : c.selection.baseOffset;
    final length = c.selection.extentOffset - index;
    c.replaceText(index, length < 0 ? 0 : length, BlockEmbed.image(source),
        TextSelection.collapsed(offset: index + 1));
  }

  /// Asks for a link address (and text when nothing is selected).
  static Future<void> insertLink(BuildContext context, QuillController c) async {
    final selection = c.selection;
    final selectedText = selection.isCollapsed
        ? ''
        : c.document.getPlainText(selection.start, selection.end - selection.start);
    final existing = _attrs(c)[Attribute.link.key]?.value as String?;
    final result = await showDialog<({String text, String url})>(
      context: context,
      builder: (_) => _LinkDialog(
          initialText: selectedText, initialUrl: existing ?? ''),
    );
    if (result == null) return;
    var url = result.url.trim();
    if (url.isEmpty) {
      if (!selection.isCollapsed) {
        c.formatSelection(Attribute.clone(Attribute.link, null));
      }
      return;
    }
    if (!RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(url)) {
      url = url.contains('@') && !url.contains('/') ? 'mailto:$url' : 'https://$url';
    }
    if (selection.isCollapsed) {
      final text = result.text.trim().isEmpty ? result.url.trim() : result.text;
      c.replaceText(selection.start, 0, text,
          TextSelection.collapsed(offset: selection.start + text.length));
      c.formatText(selection.start, text.length, LinkAttribute(url));
    } else {
      c.formatSelection(LinkAttribute(url));
    }
  }
}

class _LinkDialog extends StatefulWidget {
  final String initialText;
  final String initialUrl;

  const _LinkDialog({required this.initialText, required this.initialUrl});

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final _text = TextEditingController(text: widget.initialText);
  late final _url = TextEditingController(text: widget.initialUrl);

  @override
  void dispose() {
    _text.dispose();
    _url.dispose();
    super.dispose();
  }

  void _ok() => Navigator.of(context).pop((text: _text.text, url: _url.text));

  @override
  Widget build(BuildContext context) {
    return OutlookDialog(
      title: 'Insert Hyperlink',
      width: 460,
      actions: [
        OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _ok, child: const Text('OK')),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _text,
            decoration: const InputDecoration(labelText: 'Text to display'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Address', hintText: 'https://example.com'),
            onSubmitted: (_) => _ok(),
          ),
        ],
      ),
    );
  }
}

// ─── Ribbon controls ──────────────────────────────────────────────────

const composeFonts = [
  'Calibri',
  'Arial',
  'Cambria',
  'Courier New',
  'Georgia',
  'Segoe UI',
  'Tahoma',
  'Times New Roman',
  'Verdana',
];

const composeSizesPt = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36];

/// Office's standard font colors.
const fontColors = {
  'Dark Red': '#c00000',
  'Red': '#ff0000',
  'Orange': '#ffc000',
  'Yellow': '#ffff00',
  'Light Green': '#92d050',
  'Green': '#00b050',
  'Light Blue': '#00b0f0',
  'Blue': '#0070c0',
  'Dark Blue': '#002060',
  'Purple': '#7030a0',
  'Gray': '#7f7f7f',
  'Black': '#000000',
};

const highlightColors = {
  'Yellow': '#ffff00',
  'Bright Green': '#00ff00',
  'Turquoise': '#00ffff',
  'Pink': '#ff00ff',
  'Red': '#ff0000',
  'Gray': '#c0c0c0',
};

/// The ribbon's "Basic Text" group: font, size, character formatting,
/// colors, lists, indentation and alignment.
class BasicTextGroup extends StatelessWidget {
  final QuillController controller;
  final FocusNode editorFocus;

  /// False in plain-text mode: the controls show but do nothing.
  final bool enabled;

  const BasicTextGroup({
    super.key,
    required this.controller,
    required this.editorFocus,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        void run(void Function() action) {
          if (!enabled) return;
          action();
          editorFocus.requestFocus();
        }

        Widget toggle(IconData icon, String tip, Attribute a) => FormatButton(
              icon: icon,
              tooltip: tip,
              active: enabled && TextFormatting.isActive(c, a),
              enabled: enabled,
              onPressed: () => run(() => TextFormatting.toggle(c, a)),
            );
        Widget align(IconData icon, String tip, Attribute? a) => FormatButton(
              icon: icon,
              tooltip: tip,
              enabled: enabled,
              active: enabled &&
                  (a == null
                      ? !c.getSelectionStyle().attributes
                          .containsKey(Attribute.align.key)
                      : TextFormatting.isActive(c, a)),
              onPressed: () => run(() => TextFormatting.setAlign(c, a)),
            );

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Picker<String>(
                      width: 128,
                      enabled: enabled,
                      tooltip: 'Font',
                      value: TextFormatting.currentFont(c),
                      items: {for (final f in composeFonts) f: f},
                      itemStyle: (f) => TextStyle(fontFamily: f, fontSize: 13),
                      onSelected: (f) => run(() =>
                          TextFormatting.setFont(c, f == 'Calibri' ? null : f)),
                    ),
                    const SizedBox(width: 4),
                    _Picker<int>(
                      width: 48,
                      enabled: enabled,
                      tooltip: 'Font Size',
                      value: TextFormatting.currentSizePt(c),
                      items: {for (final s in composeSizesPt) s: '$s'},
                      onSelected: (s) =>
                          run(() => TextFormatting.setSizePt(c, s)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    toggle(Icons.format_bold, 'Bold (Ctrl+B)', Attribute.bold),
                    toggle(Icons.format_italic, 'Italic (Ctrl+I)',
                        Attribute.italic),
                    toggle(Icons.format_underlined, 'Underline (Ctrl+U)',
                        Attribute.underline),
                    toggle(Icons.strikethrough_s, 'Strikethrough',
                        Attribute.strikeThrough),
                    const SizedBox(width: 4),
                    _ColorButton(
                      icon: Icons.format_color_text,
                      tooltip: 'Font Color',
                      enabled: enabled,
                      colors: fontColors,
                      noneLabel: 'Automatic',
                      onSelected: (hex) =>
                          run(() => TextFormatting.setColor(c, hex)),
                    ),
                    _ColorButton(
                      icon: Icons.border_color,
                      tooltip: 'Text Highlight Color',
                      enabled: enabled,
                      colors: highlightColors,
                      noneLabel: 'No Color',
                      onSelected: (hex) =>
                          run(() => TextFormatting.setHighlight(c, hex)),
                    ),
                    FormatButton(
                      icon: Icons.format_clear,
                      tooltip: 'Clear All Formatting',
                      enabled: enabled,
                      onPressed: () => run(() => TextFormatting.clear(c)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Row(
                  children: [
                    toggle(Icons.format_list_bulleted, 'Bullets', Attribute.ul),
                    toggle(Icons.format_list_numbered, 'Numbering',
                        Attribute.ol),
                    FormatButton(
                      icon: Icons.format_indent_decrease,
                      tooltip: 'Decrease Indent',
                      enabled: enabled,
                      onPressed: () => run(() => c.indentSelection(false)),
                    ),
                    FormatButton(
                      icon: Icons.format_indent_increase,
                      tooltip: 'Increase Indent',
                      enabled: enabled,
                      onPressed: () => run(() => c.indentSelection(true)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    align(Icons.format_align_left, 'Align Left', null),
                    align(Icons.format_align_center, 'Center',
                        Attribute.centerAlignment),
                    align(Icons.format_align_right, 'Align Right',
                        Attribute.rightAlignment),
                    toggle(Icons.format_quote, 'Quote', Attribute.blockQuote),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A small icon button for formatting toggles; never takes the focus away
/// from the editor.
class FormatButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final bool enabled;
  final VoidCallback onPressed;
  final Color? iconColor;

  const FormatButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.enabled = true,
    this.iconColor,
  });

  @override
  State<FormatButton> createState() => _FormatButtonState();
}

class _FormatButtonState extends State<FormatButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.active || (_hovered && widget.enabled);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.enabled ? widget.onPressed : null,
          child: Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: widget.active
                  ? OutlookTheme.selectedItemBackground
                  : highlighted
                      ? OutlookTheme.hoverColor
                      : null,
              border: Border.all(
                  color: highlighted
                      ? OutlookTheme.selectedItemBorder
                      : Colors.transparent),
            ),
            child: Icon(widget.icon,
                size: 16,
                color: widget.enabled
                    ? (widget.iconColor ?? OutlookTheme.textPrimary)
                    : OutlookTheme.textMuted),
          ),
        ),
      ),
    );
  }
}

class _Picker<T> extends StatelessWidget {
  final double width;
  final bool enabled;
  final String tooltip;
  final T value;
  final Map<T, String> items;
  final TextStyle Function(T)? itemStyle;
  final ValueChanged<T> onSelected;

  const _Picker({
    super.key,
    required this.width,
    required this.enabled,
    required this.tooltip,
    required this.value,
    required this.items,
    required this.onSelected,
    this.itemStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: !enabled
            ? null
            : () async {
                final box = context.findRenderObject() as RenderBox;
                final origin = box.localToGlobal(Offset(0, box.size.height));
                final picked = await showMenu<T>(
                  context: context,
                  position: RelativeRect.fromLTRB(
                      origin.dx, origin.dy, origin.dx + width, origin.dy),
                  items: [
                    for (final e in items.entries)
                      PopupMenuItem(
                        value: e.key,
                        height: 30,
                        child: Text(e.value,
                            style: itemStyle?.call(e.key) ??
                                const TextStyle(fontSize: 13)),
                      ),
                  ],
                );
                if (picked != null) onSelected(picked);
              },
        child: Container(
          width: width,
          height: 22,
          padding: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: OutlookTheme.dividerColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(items[value] ?? '$value',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: enabled
                            ? OutlookTheme.textPrimary
                            : OutlookTheme.textMuted)),
              ),
              const Icon(Icons.arrow_drop_down,
                  size: 16, color: OutlookTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final Map<String, String> colors;
  final String noneLabel;
  final ValueChanged<String?> onSelected;

  const _ColorButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.colors,
    required this.noneLabel,
    required this.onSelected,
  });

  static Color _parse(String hex) =>
      Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => FormatButton(
        icon: icon,
        tooltip: tooltip,
        enabled: enabled,
        iconColor: _parse(colors.values.first),
        onPressed: () async {
          final box = context.findRenderObject() as RenderBox;
          final origin = box.localToGlobal(Offset(0, box.size.height));
          const none = '__none__';
          final picked = await showMenu<String>(
            context: context,
            position: RelativeRect.fromLTRB(
                origin.dx, origin.dy, origin.dx + 160, origin.dy),
            items: [
              PopupMenuItem(
                value: none,
                height: 28,
                child: Text(noneLabel, style: const TextStyle(fontSize: 13)),
              ),
              for (final e in colors.entries)
                PopupMenuItem(
                  value: e.value,
                  height: 28,
                  child: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _parse(e.value),
                          border: Border.all(color: OutlookTheme.dividerColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(e.key, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
            ],
          );
          if (picked == null) return;
          onSelected(picked == none ? null : picked);
        },
      ),
    );
  }
}

