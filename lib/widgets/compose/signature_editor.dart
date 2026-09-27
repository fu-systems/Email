import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:path/path.dart' as p;

import '../../models/email_account.dart';
import '../../services/file_dialogs.dart';
import '../../services/mime_converter.dart';
import '../../services/rich_text_codec.dart';
import '../../theme/outlook_theme.dart';
import '../common.dart';
import 'format_controls.dart';
import 'rich_body_editor.dart';

/// Signature text for an account: the formatted signature when there is
/// one, else the plain one.
QuillController signatureController(EmailAccount? account) {
  final html = account?.signatureHtml;
  final text = account?.signature;
  final delta = html != null && html.trim().isNotEmpty
      ? RichTextCodec.fromHtml(html)
      : RichTextCodec.fromPlainText(text ?? '');
  return QuillController(
    document: Document.fromDelta(delta),
    selection: const TextSelection.collapsed(offset: 0),
  );
}

/// The signature in both formats, or nulls when it is empty.
({String? html, String? text}) signatureValues(QuillController controller) {
  final ops = controller.document.toDelta().toJson().cast<Map<String, dynamic>>();
  if (RichTextCodec.isEmpty(ops)) return (html: null, text: null);
  final text = RichTextCodec.toPlainText(ops).trimRight();
  return (html: RichTextCodec.toHtml(ops), text: text.isEmpty ? null : text);
}

/// A small formatted-text editor for signatures, with its own toolbar.
class SignatureEditor extends StatefulWidget {
  final QuillController controller;
  final double height;

  const SignatureEditor({super.key, required this.controller, this.height = 150});

  @override
  State<SignatureEditor> createState() => _SignatureEditorState();
}

class _SignatureEditorState extends State<SignatureEditor> {
  final _focus = FocusNode(debugLabel: 'signature');
  final _scroll = ScrollController();

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _picture() async {
    final paths = await FileDialogs.pickFiles(context, title: 'Insert Picture');
    if (!mounted) return;
    for (final path in paths) {
      if (!MimeConverter.guessMimeType(path).startsWith('image/')) {
        showStatusMessage(context, '${p.basename(path)} is not a picture',
            isError: true);
        continue;
      }
      TextFormatting.insertImage(widget.controller, path);
    }
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeFocus(
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) {
              Widget toggle(IconData icon, String tip, Attribute a) =>
                  FormatButton(
                    icon: icon,
                    tooltip: tip,
                    active: TextFormatting.isActive(c, a),
                    onPressed: () {
                      TextFormatting.toggle(c, a);
                      _focus.requestFocus();
                    },
                  );
              return Wrap(
                children: [
                  toggle(Icons.format_bold, 'Bold', Attribute.bold),
                  toggle(Icons.format_italic, 'Italic', Attribute.italic),
                  toggle(Icons.format_underlined, 'Underline',
                      Attribute.underline),
                  for (final e in const {
                    'Black': '#000000',
                    'Gray': '#7f7f7f',
                    'Blue': '#0070c0',
                    'Dark Blue': '#002060',
                    'Red': '#c00000',
                    'Green': '#00b050',
                  }.entries)
                    FormatButton(
                      icon: Icons.circle,
                      tooltip: 'Color: ${e.key}',
                      iconColor: Color(
                          int.parse(e.value.substring(1), radix: 16) |
                              0xFF000000),
                      onPressed: () {
                        TextFormatting.setColor(
                            c, e.key == 'Black' ? null : e.value);
                        _focus.requestFocus();
                      },
                    ),
                  FormatButton(
                    icon: Icons.link,
                    tooltip: 'Hyperlink',
                    onPressed: () => TextFormatting.insertLink(context, c)
                        .then((_) => _focus.requestFocus()),
                  ),
                  FormatButton(
                    icon: Icons.image_outlined,
                    tooltip: 'Picture',
                    onPressed: _picture,
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: widget.height,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: OutlookTheme.dividerColor),
          ),
          child: RichBodyEditor(
            controller: c,
            focusNode: _focus,
            scrollController: _scroll,
            placeholder: 'Your signature',
          ),
        ),
      ],
    );
  }
}
