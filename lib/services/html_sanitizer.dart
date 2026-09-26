import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

// Preparing email HTML for display, converting between plain text and HTML,
// and quoting for replies. Everything here is pure Dart and never throws.

/// The result of [sanitizeEmailHtml].
class SanitizedHtml {
  /// The sanitized markup (see [sanitizeEmailHtml] for what it contains).
  final String html;

  /// Number of remote resources (images, backgrounds, CSS `url()`s and
  /// `@import`s) that were blocked.
  final int blockedImageCount;

  const SanitizedHtml({required this.html, required this.blockedImageCount});

  /// Whether any remote resource was blocked, i.e. whether to offer a
  /// "download pictures" action.
  bool get hasBlockedImages => blockedImageCount > 0;
}

/// Elements removed together with their content.
const _removedElements = [
  'script',
  'iframe',
  'frame',
  'frameset',
  'object',
  'embed',
  'applet',
  'input',
  'button',
  'select',
  'textarea',
  'meta',
  'link',
  'base',
];

/// Attributes holding URLs that could run script.
const _urlAttributes = {
  'href',
  'src',
  'action',
  'formaction',
  'background',
  'poster',
  'data',
  'lowsrc',
  'dynsrc',
  'cite',
  'longdesc',
  'usemap',
  'xlink:href',
};

/// SVG elements whose `href` loads a resource rather than being a link.
const _svgResourceElements = {'image', 'use', 'feimage'};

final _remoteUrlInCss = RegExp(
  r'''url\(\s*(['"]?)\s*((?:https?:)?//[^)'"]*?)\s*\1\s*\)''',
  caseSensitive: false,
);
final _remoteImportInCss = RegExp(
  r'''@import\s+(?:url\(\s*)?['"]?\s*(?:https?:)?//[^;]*;?''',
  caseSensitive: false,
);

/// Makes untrusted email HTML safe to render.
///
/// * Removes `script`, `iframe`, `frame`, `frameset`, `object`, `embed`,
///   `applet`, `input`, `button`, `select`, `textarea`, `meta`, `link` and
///   `base` elements with their content. `form` elements are unwrapped:
///   the form goes, its content (minus any controls) stays.
/// * Removes every `on*` event-handler attribute and `srcdoc`.
/// * Removes URL attributes (`href`, `src`, `action`, ...) whose value uses
///   `javascript:`, `vbscript:` or `livescript:`, or `data:` for anything
///   but images, and `style` attributes using `expression()`, script URLs,
///   `-moz-binding` or `behavior`.
/// * Unless [allowRemoteImages] is true, blocks remote (`http:`, `https:`
///   and protocol-relative `//`) resources and counts each one:
///   `img`/`source`/`video` `src` (the original is kept in
///   `data-blocked-src`), `srcset`, `poster`, `background` attributes (kept
///   in `data-blocked-background`), SVG `image`/`use` hrefs, and CSS
///   `url(...)` and `@import` in `style` attributes and `<style>` elements
///   (replaced with `none` or removed).
/// * Replaces `cid:` image sources and backgrounds with [resolveCid]'s
///   result (typically a `data:` URI); when it returns null, or no resolver
///   is given, the attribute is removed.
///
/// Returns the `<style>` elements from the document head (the HTML parser
/// moves a leading `<style>` of a fragment there) followed by the inner
/// HTML of the body. Styles are kept so the renderer may use them.
SanitizedHtml sanitizeEmailHtml(
  String html, {
  bool allowRemoteImages = false,
  String? Function(String cid)? resolveCid,
}) {
  try {
    final document = html_parser.parse(html);
    for (final element
        in document.querySelectorAll(_removedElements.join(','))) {
      element.remove();
    }
    for (final form in document.querySelectorAll('form')) {
      final parent = form.parentNode;
      if (parent == null) continue;
      while (form.nodes.isNotEmpty) {
        parent.insertBefore(form.nodes.first, form);
      }
      form.remove();
    }

    var blocked = 0;
    for (final element in document.querySelectorAll('*')) {
      blocked += _sanitizeElement(
        element,
        allowRemoteImages: allowRemoteImages,
        resolveCid: resolveCid,
      );
    }

    final head = document.head;
    final styles = head == null
        ? ''
        : head.querySelectorAll('style').map((s) => s.outerHtml).join();
    final body = document.body;
    final content =
        body?.innerHtml ?? document.documentElement?.innerHtml ?? '';
    return SanitizedHtml(html: styles + content, blockedImageCount: blocked);
  } catch (_) {
    return SanitizedHtml(
      html: plainTextToHtml(html.replaceAll(RegExp(r'<[^>]*>'), '')),
      blockedImageCount: 0,
    );
  }
}

/// Sanitizes one element in place; returns the number of blocked resources.
int _sanitizeElement(
  Element element, {
  required bool allowRemoteImages,
  required String? Function(String cid)? resolveCid,
}) {
  final tag = element.localName?.toLowerCase() ?? '';
  final attributes = element.attributes;
  var blocked = 0;

  for (final key in attributes.keys.toList()) {
    final name = key.toString().toLowerCase();
    final value = attributes[key] ?? '';
    if (name.startsWith('on') || name == 'srcdoc') {
      attributes.remove(key);
      continue;
    }
    if (_urlAttributes.contains(name) || name.endsWith(':href')) {
      if (_isScriptUrl(value) ||
          (_isDataUrl(value) && !_isImageDataUrl(value))) {
        attributes.remove(key);
        continue;
      }
    }
    if (name == 'style') {
      final lower = value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (lower.contains('expression(') ||
          lower.contains('javascript:') ||
          lower.contains('vbscript:') ||
          lower.contains('-moz-binding') ||
          lower.contains('behavior:')) {
        attributes.remove(key);
        continue;
      }
      if (!allowRemoteImages) {
        final result = _stripRemoteCss(value);
        if (result.count > 0) {
          attributes[key] = result.css;
          blocked += result.count;
        }
      }
    }
  }

  // Images and other embedded resources.
  var elementBlocked = false;
  final src = attributes['src']?.trim();
  if (src != null) {
    if (_isRemote(src)) {
      if (!allowRemoteImages) {
        attributes.remove('src');
        attributes['data-blocked-src'] = src;
        blocked++;
        elementBlocked = true;
      }
    } else if (src.toLowerCase().startsWith('cid:')) {
      final resolved = resolveCid?.call(_normalizeCid(src.substring(4)));
      if (resolved != null) {
        attributes['src'] = resolved;
      } else {
        attributes.remove('src');
      }
    }
  }
  final srcset = attributes['srcset'];
  if (srcset != null && !allowRemoteImages && _containsRemote(srcset)) {
    attributes.remove('srcset');
    if (!elementBlocked) {
      blocked++;
      elementBlocked = true;
    }
  }
  final poster = attributes['poster']?.trim();
  if (poster != null && !allowRemoteImages && _isRemote(poster)) {
    attributes.remove('poster');
    blocked++;
  }
  final background = attributes['background']?.trim();
  if (background != null) {
    if (_isRemote(background)) {
      if (!allowRemoteImages) {
        attributes.remove('background');
        attributes['data-blocked-background'] = background;
        blocked++;
      }
    } else if (background.toLowerCase().startsWith('cid:')) {
      final resolved = resolveCid?.call(_normalizeCid(background.substring(4)));
      if (resolved != null) {
        attributes['background'] = resolved;
      } else {
        attributes.remove('background');
      }
    }
  }
  if (_svgResourceElements.contains(tag) && !allowRemoteImages) {
    for (final key in attributes.keys.toList()) {
      final name = key.toString().toLowerCase();
      if ((name == 'href' || name.endsWith(':href')) &&
          _isRemote(attributes[key] ?? '')) {
        attributes.remove(key);
        blocked++;
      }
    }
  }
  if (tag == 'style' && !allowRemoteImages) {
    final css = element.text;
    final result = _stripRemoteCss(css);
    if (result.count > 0) {
      element.text = result.css;
      blocked += result.count;
    }
  }
  return blocked;
}

({String css, int count}) _stripRemoteCss(String css) {
  var count = 0;
  var result = css.replaceAllMapped(_remoteImportInCss, (_) {
    count++;
    return '';
  });
  result = result.replaceAllMapped(_remoteUrlInCss, (_) {
    count++;
    return 'none';
  });
  return (css: result, count: count);
}

String _compactUrl(String value) =>
    value.replaceAll(RegExp(r'[\x00-\x20]'), '').toLowerCase();

bool _isScriptUrl(String value) {
  final v = _compactUrl(value);
  return v.startsWith('javascript:') ||
      v.startsWith('vbscript:') ||
      v.startsWith('livescript:');
}

bool _isDataUrl(String value) => _compactUrl(value).startsWith('data:');

bool _isImageDataUrl(String value) =>
    _compactUrl(value).startsWith('data:image/');

bool _isRemote(String value) {
  final v = _compactUrl(value);
  return v.startsWith('http://') ||
      v.startsWith('https://') ||
      v.startsWith('//');
}

bool _containsRemote(String srcset) =>
    srcset.split(',').any((candidate) => _isRemote(candidate.trim()));

String _normalizeCid(String raw) {
  var cid = raw.trim();
  try {
    cid = Uri.decodeComponent(cid).trim();
  } catch (_) {
    // Keep the raw value when it is not valid percent-encoding.
  }
  if (cid.startsWith('<') && cid.endsWith('>') && cid.length >= 2) {
    cid = cid.substring(1, cid.length - 1);
  }
  return cid;
}

// ─── Plain text → HTML ───────────────────────────────────────────────

final _linkPattern = RegExp(
  r'((?:https?://|www\.)[^\s<>"]+)|'
  r'([A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,})',
  caseSensitive: false,
);

const _quoteStyle =
    'margin:0 0 0 .8ex;border-left:2px solid #b5c4df;padding-left:1ex';

/// Converts plain text to HTML for display or for an HTML reply.
///
/// HTML special characters are escaped, `http://`, `https://` and `www.`
/// URLs and email addresses become links (trailing punctuation stays
/// outside the link), line breaks become `<br>`, runs of spaces and tabs
/// are kept with `&nbsp;`, and consecutive lines starting with `>` are
/// wrapped (one level per `>`) in `<blockquote type="cite">`.
///
/// The result contains no literal newlines, so it renders the same inside
/// a `white-space: pre-wrap` container.
String plainTextToHtml(String text) {
  final lines =
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  return _renderLines(lines);
}

String _renderLines(List<String> lines) {
  final out = StringBuffer();
  var i = 0;
  while (i < lines.length) {
    if (lines[i].startsWith('>')) {
      final quoted = <String>[];
      while (i < lines.length && lines[i].startsWith('>')) {
        var line = lines[i].substring(1);
        if (line.startsWith(' ')) line = line.substring(1);
        quoted.add(line);
        i++;
      }
      out.write('<blockquote type="cite" style="$_quoteStyle">'
          '${_renderLines(quoted)}</blockquote>');
    } else {
      out.write(_renderLine(lines[i]));
      i++;
      if (i < lines.length) out.write('<br>');
    }
  }
  return out.toString();
}

String _renderLine(String rawLine) {
  final line = rawLine.replaceAll('\t', '    ');
  final out = StringBuffer();
  var position = 0;
  for (final match in _linkPattern.allMatches(line)) {
    var text = match.group(0)!;
    final isUrl = match.group(1) != null;
    if (isUrl) text = _trimUrlPunctuation(text);
    if (text.isEmpty || (isUrl && text.toLowerCase() == 'www.')) continue;
    out.write(_textChunk(line.substring(position, match.start), position == 0));
    final String href;
    if (!isUrl) {
      href = 'mailto:$text';
    } else if (text.toLowerCase().startsWith('www.')) {
      href = 'http://$text';
    } else {
      href = text;
    }
    out.write('<a href="${_escapeHtml(href)}">${_escapeHtml(text)}</a>');
    position = match.start + text.length;
  }
  out.write(_textChunk(line.substring(position), position == 0));
  return out.toString();
}

String _trimUrlPunctuation(String url) {
  var u = url;
  while (u.isNotEmpty) {
    final last = u[u.length - 1];
    if (last == ')') {
      final opens = '('.allMatches(u).length;
      final closes = ')'.allMatches(u).length;
      if (closes <= opens) break;
    } else if (!'.,;:!?\'"]}*'.contains(last)) {
      break;
    }
    u = u.substring(0, u.length - 1);
  }
  return u;
}

/// Escapes [text], keeping runs of spaces visible.
String _textChunk(String text, bool atLineStart) {
  if (text.isEmpty) return '';
  final escaped = _escapeHtml(text);
  return escaped.replaceAllMapped(RegExp(r' {2,}|^ '), (m) {
    final n = m.group(0)!.length;
    if (m.start == 0 && atLineStart) return '&nbsp;' * n;
    return ' ${'&nbsp;' * (n - 1)}';
  });
}

String _escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

// ─── HTML → plain text ───────────────────────────────────────────────

const _skippedElements = {
  'script',
  'style',
  'head',
  'title',
  'template',
  'noscript',
  'object',
  'iframe',
  'svg',
  'img',
};

/// Elements surrounded by a blank line.
const _paragraphElements = {'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

/// Elements that start and end on their own line.
const _blockElements = {
  'div',
  'tr',
  'table',
  'ul',
  'ol',
  'dl',
  'dt',
  'dd',
  'section',
  'article',
  'header',
  'footer',
  'nav',
  'aside',
  'main',
  'address',
  'center',
  'figure',
  'figcaption',
  'caption',
  'form',
  'fieldset',
  'hr',
  'tbody',
  'thead',
  'tfoot',
};

/// Converts HTML to readable plain text, for reply quoting and previews.
///
/// Scripts, styles, the head, images and hidden elements (`display:none`,
/// `hidden`) are dropped. `p` and headings are separated by blank lines;
/// `div`, `li`, `tr`, `br` and other block elements start new lines. List
/// items are prefixed with "- " (nested items are indented) and blockquote
/// lines with "> ". Links render as `text (url)` when the text differs
/// from the URL. Entities are decoded, whitespace is collapsed outside
/// `pre`, runs of more than one blank line are reduced to one, and the
/// result is trimmed.
String htmlToPlainText(String html) {
  try {
    final document = html_parser.parse(html);
    final root = document.body ?? document.documentElement;
    if (root == null) return '';
    return _finishText(_convertChildren(root));
  } catch (_) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }
}

String _convertChildren(Node node) {
  final out = _TextBuilder();
  for (final child in node.nodes) {
    _convertNode(child, out);
  }
  return out.toString();
}

void _convertNode(Node node, _TextBuilder out) {
  if (node is Text) {
    out.text(node.data);
    return;
  }
  if (node is! Element) return;
  final tag = node.localName?.toLowerCase() ?? '';
  if (_skippedElements.contains(tag) || _isHidden(node)) return;

  switch (tag) {
    case 'br':
      out.lineBreak();
      return;
    case 'pre':
      out.ensureNewlines(1);
      out.raw(node.text.replaceAll('\r\n', '\n'));
      out.ensureNewlines(1);
      return;
    case 'a':
      _convertLink(node, out);
      return;
    case 'li':
      final inner = _finishText(_convertChildren(node));
      out.ensureNewlines(1);
      final lines = inner.split('\n');
      out.raw([
        '- ${lines.first}',
        for (final line in lines.skip(1)) line.isEmpty ? '' : '  $line',
      ].join('\n'));
      out.ensureNewlines(1);
      return;
    case 'blockquote':
      final inner = _finishText(_convertChildren(node));
      out.ensureNewlines(1);
      if (inner.isNotEmpty) {
        out.raw(inner
            .split('\n')
            .map((line) => line.isEmpty ? '>' : '> $line')
            .join('\n'));
      }
      out.ensureNewlines(1);
      return;
  }

  final newlines = _paragraphElements.contains(tag)
      ? 2
      : _blockElements.contains(tag)
          ? 1
          : 0;
  if (newlines > 0) out.ensureNewlines(newlines);
  for (final child in node.nodes) {
    _convertNode(child, out);
  }
  if (newlines > 0) out.ensureNewlines(newlines);
  if (tag == 'td' || tag == 'th') out.separate();
}

void _convertLink(Element link, _TextBuilder out) {
  final text = _finishText(_convertChildren(link))
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final href = link.attributes['href']?.trim() ?? '';
  if (text.isEmpty) return;
  if (href.isEmpty ||
      href.startsWith('#') ||
      _isScriptUrl(href) ||
      _isDataUrl(href) ||
      _sameUrl(text, href)) {
    out.text(text);
    return;
  }
  final shownHref =
      href.toLowerCase().startsWith('mailto:') ? href.substring(7) : href;
  out.text('$text ($shownHref)');
}

bool _sameUrl(String a, String b) {
  String normalize(String s) {
    var v = s.trim().toLowerCase();
    v = v.replaceFirst(RegExp(r'^mailto:'), '');
    v = v.replaceFirst(RegExp(r'^https?://'), '');
    v = v.replaceFirst(RegExp(r'^www\.'), '');
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  return normalize(a) == normalize(b);
}

bool _isHidden(Element element) {
  if (element.attributes.containsKey('hidden')) return true;
  final style = element.attributes['style'];
  if (style == null) return false;
  return style
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .contains('display:none');
}

String _finishText(String text) {
  final lines = text
      .replaceAll('\u00A0', ' ')
      .split('\n')
      .map((line) => line.trimRight())
      .join('\n');
  return lines.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// Accumulates plain text, collapsing whitespace and tracking line ends.
class _TextBuilder {
  final StringBuffer _buffer = StringBuffer();
  int _trailingNewlines = 0;
  bool _endsWithSpace = false;

  bool get _atLineStart => _buffer.isEmpty || _trailingNewlines > 0;

  /// Appends inline text; HTML whitespace collapses to single spaces.
  void text(String data) {
    var s = data.replaceAll(RegExp(r'[ \t\n\r\f]+'), ' ');
    if (_atLineStart) {
      s = s.replaceFirst(RegExp(r'^ +'), '');
    } else if (_endsWithSpace && s.startsWith(' ')) {
      s = s.substring(1);
    }
    if (s.isEmpty) return;
    _write(s);
  }

  /// Appends text verbatim.
  void raw(String s) {
    if (s.isNotEmpty) _write(s);
  }

  void lineBreak() => _write('\n');

  /// Ensures the output ends with at least [count] line breaks (nothing is
  /// added at the very start).
  void ensureNewlines(int count) {
    if (_buffer.isEmpty) return;
    while (_trailingNewlines < count) {
      _write('\n');
    }
  }

  /// Separates adjacent table cells with a space.
  void separate() {
    if (!_atLineStart && !_endsWithSpace) _write(' ');
  }

  void _write(String s) {
    _buffer.write(s);
    var trailing = 0;
    for (var i = s.length - 1; i >= 0 && s[i] == '\n'; i--) {
      trailing++;
    }
    _trailingNewlines =
        trailing == s.length ? _trailingNewlines + trailing : trailing;
    _endsWithSpace = s.endsWith(' ');
  }

  @override
  String toString() => _buffer.toString();
}

// ─── Reply quoting ───────────────────────────────────────────────────

/// Prefixes every line of [text] with "> " for a plain-text reply.
///
/// Line endings are normalized to `\n` and trailing line breaks are dropped
/// first; empty input gives an empty string.
String quoteForReply(String text) {
  final normalized = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceFirst(RegExp(r'\n+$'), '');
  if (normalized.isEmpty) return '';
  return normalized.split('\n').map((line) => '> $line').join('\n');
}
