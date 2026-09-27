import 'package:flutter_quill/flutter_quill.dart' show Document;
import 'package:flutter_quill/quill_delta.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import 'html_sanitizer.dart';

/// Default body font of new messages, like Outlook's Calibri 11 pt.
const defaultComposeFont = 'Calibri, Carlito, Arial, sans-serif';
const defaultComposeFontSize = '11pt';

/// Converts between the compose editor's document (a Quill Delta) and
/// email HTML.
///
/// Email clients ignore style sheets, so the HTML uses inline styles only.
/// Paragraphs are `<div>`s, as other mail programs write them.
class RichTextCodec {
  RichTextCodec._();

  /// Inline styles for fonts, numeric sizes (in px, as the editor uses),
  /// indents and checklists.
  static final _inlineStyles = InlineStyles({
    ...defaultInlineStyles.attrs,
    'size': InlineStyleType(fn: (value, _) {
      const named = {
        'small': 'font-size: 0.75em',
        'large': 'font-size: 1.5em',
        'huge': 'font-size: 2.5em',
      };
      final number = double.tryParse(value);
      return named[value] ??
          (number == null ? null : 'font-size: ${_trim(number)}px');
    }),
  });

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// HTML for the editor's content, without the outer font wrapper.
  static String toHtml(List<Map<String, dynamic>> ops) {
    if (ops.isEmpty) return '';
    final converter = QuillDeltaToHtmlConverter(
      [for (final op in ops) Map<String, dynamic>.from(op)],
      ConverterOptions(
        converterOptions: OpConverterOptions(
          inlineStylesFlag: true,
          inlineStyles: _inlineStyles,
          paragraphTag: 'div',
          linkTarget: '_blank',
          customCssStyles: (op) {
            if (op.isImage()) return ['max-width: 100%'];
            if (op.isBlockquote()) {
              return ['border-left: 2px solid #ccc', 'margin: 0 0 0 8px',
                  'padding-left: 12px', 'color: #555'];
            }
            return null;
          },
        ),
      ),
    );
    return converter.convert();
  }

  /// Wraps body HTML in the default font, as Outlook does.
  static String wrapBody(String bodyHtml,
          {String font = defaultComposeFont,
          String size = defaultComposeFontSize}) =>
      '<div style="font-family: $font; font-size: $size; color: #000000;">'
      '$bodyHtml</div>';

  /// Editor content from HTML (a signature, a draft, a quoted original).
  /// Keeps what the editor can show: paragraphs and line breaks, bold,
  /// italic, underline, strikethrough, colors, fonts, sizes, links, lists,
  /// alignment, quotes, headings and images.
  static Delta fromHtml(String html) {
    if (html.trim().isEmpty) return Delta()..insert('\n');
    try {
      return _HtmlToDelta().convert(html);
    } catch (_) {
      return fromPlainText(htmlToPlainText(html));
    }
  }

  static Delta fromPlainText(String text) {
    final body = text.endsWith('\n') ? text : '$text\n';
    return Delta()..insert(body);
  }

  static String toPlainText(List<Map<String, dynamic>> ops) {
    if (ops.isEmpty) return '';
    try {
      return Document.fromJson(ops).toPlainText().trimRight();
    } catch (_) {
      return '';
    }
  }

  /// Whether the document has no text or images.
  static bool isEmpty(List<Map<String, dynamic>> ops) =>
      toPlainText(ops).trim().isEmpty && imageSources(ops).isEmpty;

  /// Sources of the image embeds, in order.
  static List<String> imageSources(List<Map<String, dynamic>> ops) => [
        for (final op in ops)
          if (op['insert'] case {'image': final String src}) src,
      ];

  /// Replaces image `src` values (e.g. local paths with `cid:` URLs).
  static String replaceImageSources(
      String html, String? Function(String src) replace) {
    if (!html.contains('<img')) return html;
    final fragment = html_parser.parseFragment(html);
    for (final img in fragment.querySelectorAll('img')) {
      final src = img.attributes['src'];
      if (src == null) continue;
      final replacement = replace(src);
      if (replacement != null) img.attributes['src'] = replacement;
    }
    return fragment.outerHtml;
  }

  /// Splits HTML written by Look In into the editor part and the quoted
  /// original (see [quotedMarker]).
  static ({String body, String? quoted}) splitQuoted(String html) {
    final fragment = html_parser.parseFragment(html);
    final marker = fragment.querySelector('#$quotedMarker');
    if (marker == null) return (body: html, quoted: null);
    final quoted = marker.innerHtml;
    marker.remove();
    return (body: _unwrapBody(fragment), quoted: quoted);
  }

  /// Returns the inner HTML of Look In's font wrapper, when present.
  static String _unwrapBody(dom.DocumentFragment fragment) {
    final nodes = fragment.nodes.where((n) =>
        n is! dom.Text || n.text.trim().isNotEmpty).toList();
    if (nodes.length == 1 &&
        nodes.first is dom.Element &&
        (nodes.first as dom.Element).localName == 'div' &&
        ((nodes.first as dom.Element).attributes['style'] ?? '')
            .contains('font-family')) {
      return (nodes.first as dom.Element).innerHtml;
    }
    return fragment.outerHtml;
  }

  /// id of the element holding the quoted original in sent HTML.
  static const quotedMarker = 'lookin-quoted';
}

/// A DOM walk that turns HTML into Quill operations.
class _HtmlToDelta {
  final _delta = Delta();
  bool _lineHasContent = false;
  Map<String, dynamic> _lineAttrs = const {};

  static const _blocks = {
    'address', 'article', 'aside', 'blockquote', 'dd', 'div', 'dl', 'dt',
    'figcaption', 'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5',
    'h6', 'header', 'hr', 'li', 'main', 'nav', 'ol', 'p', 'pre', 'section',
    'table', 'tbody', 'thead', 'tfoot', 'tr', 'ul', 'center',
  };
  static const _skip = {'head', 'script', 'style', 'title', 'meta', 'link'};

  Delta convert(String html) {
    final fragment = html_parser.parseFragment(html);
    for (final node in fragment.nodes) {
      _node(node, const {}, const {}, pre: false);
    }
    if (_lineHasContent) _newline(_lineAttrs);
    if (_delta.isEmpty) _delta.insert('\n');
    return _delta;
  }

  void _newline(Map<String, dynamic> attrs) {
    _delta.insert('\n', attrs.isEmpty ? null : Map.of(attrs));
    _lineHasContent = false;
    _lineAttrs = const {};
  }

  void _text(String text, Map<String, dynamic> inline,
      Map<String, dynamic> block, {required bool pre}) {
    var t = text;
    if (!pre) {
      t = t.replaceAll(RegExp(r'\s+'), ' ');
      if (!_lineHasContent) t = t.trimLeft();
    }
    if (t.isEmpty) return;
    if (pre && t.contains('\n')) {
      final lines = t.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].isNotEmpty) _insert(lines[i], inline, block);
        if (i < lines.length - 1) _newline(block);
      }
      return;
    }
    _insert(t, inline, block);
  }

  void _insert(Object data, Map<String, dynamic> inline,
      Map<String, dynamic> block) {
    if (!_lineHasContent) _lineAttrs = block;
    _delta.insert(data, inline.isEmpty ? null : Map.of(inline));
    _lineHasContent = true;
  }

  void _node(dom.Node node, Map<String, dynamic> inline,
      Map<String, dynamic> block, {required bool pre, int listDepth = 0,
      String? listType}) {
    if (node is dom.Text) {
      _text(node.text, inline, block, pre: pre);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    if (_skip.contains(tag)) return;

    if (tag == 'br') {
      // A line break closing a block adds no empty line.
      final parent = node.parent;
      final isLast = parent != null &&
          _blocks.contains(parent.localName) &&
          parent.nodes.lastWhere((n) => n is! dom.Text || n.text.trim().isNotEmpty,
                  orElse: () => node) ==
              node;
      if (isLast && _lineHasContent) return;
      if (!_lineHasContent) _lineAttrs = block;
      _newline(_lineAttrs.isEmpty ? block : _lineAttrs);
      return;
    }
    if (tag == 'img') {
      final src = node.attributes['src'];
      if (src != null && src.isNotEmpty) _insert({'image': src}, const {}, block);
      return;
    }
    if (tag == 'hr') {
      if (_lineHasContent) _newline(_lineAttrs);
      return;
    }

    final childInline = _inlineAttrs(node, inline);
    var childBlock = block;
    var depth = listDepth;
    var type = listType;
    final isBlock = _blocks.contains(tag);
    if (isBlock) {
      if (_lineHasContent) _newline(_lineAttrs);
      childBlock = _blockAttrs(node, block, listDepth, listType);
      if (tag == 'ul' || tag == 'ol') {
        depth = listDepth + 1;
        type = tag == 'ol' ? 'ordered' : 'bullet';
      }
    }
    final isPre = pre || tag == 'pre';
    var first = true;
    for (final child in node.nodes) {
      if (tag == 'tr' && child is dom.Element && !first) {
        _insert('  ', const {}, childBlock);
      }
      if (child is dom.Element) first = false;
      _node(child, childInline, childBlock,
          pre: isPre, listDepth: depth, listType: type);
    }
    if (isBlock && _lineHasContent) _newline(_lineAttrs);
  }

  Map<String, dynamic> _blockAttrs(dom.Element e, Map<String, dynamic> parent,
      int listDepth, String? listType) {
    final tag = e.localName;
    final attrs = <String, dynamic>{
      // Quotes and alignment carry over to nested blocks; lists don't.
      for (final k in const ['blockquote', 'align', 'code-block'])
        if (parent[k] != null) k: parent[k],
    };
    if (tag == 'li' && listType != null) {
      attrs['list'] = listType;
      if (listDepth > 1) attrs['indent'] = listDepth - 1;
    }
    if (tag == 'blockquote') attrs['blockquote'] = true;
    if (tag == 'pre') attrs['code-block'] = true;
    if (tag == 'center') attrs['align'] = 'center';
    final header = RegExp(r'^h([1-3])$').firstMatch(tag ?? '');
    if (header != null) attrs['header'] = int.parse(header.group(1)!);
    final align = (_style(e)['text-align'] ?? e.attributes['align'])
        ?.toLowerCase();
    if (align == 'center' || align == 'right' || align == 'justify') {
      attrs['align'] = align;
    } else if (align == 'left') {
      attrs.remove('align');
    }
    return attrs;
  }

  Map<String, dynamic> _inlineAttrs(dom.Element e, Map<String, dynamic> parent) {
    final attrs = Map<String, dynamic>.of(parent);
    switch (e.localName) {
      case 'b' || 'strong':
        attrs['bold'] = true;
      case 'i' || 'em':
        attrs['italic'] = true;
      case 'u' || 'ins':
        attrs['underline'] = true;
      case 's' || 'strike' || 'del':
        attrs['strike'] = true;
      case 'a':
        final href = e.attributes['href'];
        if (href != null && href.isNotEmpty) attrs['link'] = href;
      case 'font':
        final color = _color(e.attributes['color']);
        if (color != null) attrs['color'] = color;
        final face = _fontFamily(e.attributes['face']);
        if (face != null) attrs['font'] = face;
    }
    final style = _style(e);
    final weight = style['font-weight'];
    if (weight == 'bold' || (int.tryParse(weight ?? '') ?? 0) >= 600) {
      attrs['bold'] = true;
    }
    if (style['font-style'] == 'italic') attrs['italic'] = true;
    final decoration = style['text-decoration'] ?? '';
    if (decoration.contains('underline')) attrs['underline'] = true;
    if (decoration.contains('line-through')) attrs['strike'] = true;
    final color = _color(style['color']);
    if (color != null) attrs['color'] = color;
    final background = _color(style['background-color'] ?? style['background']);
    if (background != null) attrs['background'] = background;
    final font = _fontFamily(style['font-family']);
    if (font != null) attrs['font'] = font;
    final size = _fontSize(style['font-size']);
    if (size != null) attrs['size'] = size;
    return attrs;
  }

  static Map<String, String> _style(dom.Element e) {
    final result = <String, String>{};
    for (final part in (e.attributes['style'] ?? '').split(';')) {
      final colon = part.indexOf(':');
      if (colon <= 0) continue;
      result[part.substring(0, colon).trim().toLowerCase()] =
          part.substring(colon + 1).trim();
    }
    return result;
  }

  static String? _color(String? value) {
    if (value == null) return null;
    final v = value.trim().toLowerCase();
    if (RegExp(r'^#[0-9a-f]{6}$').hasMatch(v)) return v;
    if (RegExp(r'^#[0-9a-f]{3}$').hasMatch(v)) {
      return '#${v[1]}${v[1]}${v[2]}${v[2]}${v[3]}${v[3]}';
    }
    final rgb = RegExp(r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(v);
    if (rgb != null) {
      String hex(String n) =>
          int.parse(n).clamp(0, 255).toRadixString(16).padLeft(2, '0');
      return '#${hex(rgb.group(1)!)}${hex(rgb.group(2)!)}${hex(rgb.group(3)!)}';
    }
    const named = {
      'black': '#000000', 'white': '#ffffff', 'red': '#ff0000',
      'green': '#008000', 'blue': '#0000ff', 'gray': '#808080',
      'grey': '#808080', 'yellow': '#ffff00', 'orange': '#ffa500',
      'purple': '#800080', 'navy': '#000080', 'maroon': '#800000',
    };
    return named[v];
  }

  static String? _fontFamily(String? value) {
    if (value == null) return null;
    final first = value.split(',').first.trim().replaceAll(RegExp('["\']'), '');
    if (first.isEmpty) return null;
    // The editor's default font needs no attribute.
    if (first.toLowerCase() == 'calibri' || first == 'inherit') return null;
    return first;
  }

  static String? _fontSize(String? value) {
    if (value == null) return null;
    final m = RegExp(r'^([\d.]+)\s*(px|pt)$').firstMatch(value.trim());
    if (m == null) return null;
    var px = double.parse(m.group(1)!);
    if (m.group(2) == 'pt') px = px * 4 / 3;
    final rounded = px.round();
    // 11pt is the default size; leave it unset.
    if (rounded == 15 && m.group(2) == 'pt') return null;
    return '$rounded';
  }
}
