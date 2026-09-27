import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../theme/outlook_theme.dart';
import 'spelling.dart';

/// Base size of message text: 11 pt, like Outlook.
const double composeFontSize = 15;

/// The editor's text style, matching the HTML body font.
const composeTextStyle = TextStyle(
  fontFamily: OutlookTheme.fontFamily,
  fontFamilyFallback: ['Carlito', 'Calibri', ...OutlookTheme.fontFamilyFallback],
  fontSize: composeFontSize,
  height: 1.35,
  color: Color(0xFF000000),
);

/// The message body editor (and the compact signature editor).
class RichBodyEditor extends StatelessWidget {
  final QuillController controller;
  final FocusNode focusNode;
  final ScrollController? scrollController;
  final String? placeholder;
  final bool autofocus;

  /// When false the editor sizes to its content inside an outer scroll
  /// view (the message window scrolls editor and quoted text together).
  final bool scrollable;
  final double? minHeight;
  final EdgeInsets padding;

  /// Shortcuts handled by the window (send, save, insert link) that the
  /// editor would otherwise take for itself.
  final Map<SingleActivator, VoidCallback> shortcuts;

  /// Underlines misspelled words and offers suggestions on right-click.
  final SpellingHighlighter? spelling;

  /// Gives access to the editor's layout (e.g. to place a dropped picture).
  final GlobalKey<EditorState>? editorKey;

  const RichBodyEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    this.scrollController,
    this.placeholder,
    this.autofocus = false,
    this.scrollable = true,
    this.minHeight,
    this.padding = EdgeInsets.zero,
    this.shortcuts = const {},
    this.spelling,
    this.editorKey,
  });

  static DefaultStyles styles() {
    const block = DefaultTextBlockStyle(composeTextStyle,
        HorizontalSpacing.zero, VerticalSpacing.zero, VerticalSpacing.zero, null);
    return DefaultStyles(
      paragraph: block,
      placeHolder: DefaultTextBlockStyle(
          composeTextStyle.copyWith(color: OutlookTheme.textMuted),
          HorizontalSpacing.zero,
          VerticalSpacing.zero,
          VerticalSpacing.zero,
          null),
      link: const TextStyle(
          color: Color(0xFF0563C1), decoration: TextDecoration.underline),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spelling = this.spelling;
    if (spelling == null) return _editor(null);
    // Rebuilds the text (and its underlines) after each check.
    return ListenableBuilder(
      listenable: spelling,
      builder: (context, _) => _editor(spelling),
    );
  }

  Widget _editor(SpellingHighlighter? spelling) {
    return QuillEditor(
      controller: controller,
      focusNode: focusNode,
      scrollController: scrollController ?? ScrollController(),
      config: QuillEditorConfig(
        placeholder: placeholder,
        autoFocus: autofocus,
        scrollable: scrollable,
        expands: false,
        minHeight: minHeight,
        padding: padding,
        customStyles: styles(),
        embedBuilders: const [ImageEmbedBuilder()],
        unknownEmbedBuilder: const _UnknownEmbedBuilder(),
        textCapitalization: TextCapitalization.sentences,
        editorKey: editorKey,
        textSpanBuilder: spelling?.buildSpan ?? defaultSpanBuilder,
        contextMenuBuilder: spelling?.contextMenu,
        customShortcuts: {
          for (final key in shortcuts.keys) key: _CallbackIntent(key),
        },
        customActions: {
          _CallbackIntent: CallbackAction<_CallbackIntent>(
              onInvoke: (intent) => shortcuts[intent.activator]?.call()),
        },
      ),
    );
  }
}

class _CallbackIntent extends Intent {
  final SingleActivator activator;
  const _CallbackIntent(this.activator);
}

/// Shows image embeds: local files, `data:` URIs, and a placeholder for
/// images the editor can't load (remote or `cid:` pictures).
class ImageEmbedBuilder extends EmbedBuilder {
  const ImageEmbedBuilder();

  @override
  String get key => BlockEmbed.imageType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final src = embedContext.node.value.data as String;
    Widget image;
    if (src.startsWith('data:')) {
      final comma = src.indexOf(',');
      try {
        image = Image.memory(base64Decode(src.substring(comma + 1)),
            fit: BoxFit.contain);
      } catch (_) {
        image = _placeholder(src);
      }
    } else if (!src.contains(':') || src.startsWith('file:')) {
      final path = src.startsWith('file:') ? Uri.parse(src).toFilePath() : src;
      image = File(path).existsSync()
          ? Image.file(File(path), fit: BoxFit.contain)
          : _placeholder(src);
    } else {
      image = _placeholder(src);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
      child: image,
    );
  }

  static Widget _placeholder(String src) => Tooltip(
        message: src,
        child: Container(
          width: 120,
          height: 72,
          color: const Color(0xFFF2F2F2),
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined,
              color: OutlookTheme.textMuted, size: 28),
        ),
      );
}

class _UnknownEmbedBuilder extends EmbedBuilder {
  const _UnknownEmbedBuilder();

  @override
  String get key => 'unknown';

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) =>
      const SizedBox.shrink();
}
