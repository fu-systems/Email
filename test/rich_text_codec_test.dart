import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/services/rich_text_codec.dart';

List<Map<String, dynamic>> ops(String html) =>
    RichTextCodec.fromHtml(html).toJson().cast<Map<String, dynamic>>();

/// [list] as a Delta would hold it (adjacent plain inserts merged).
List<dynamic> normalized(List<Map<String, dynamic>> list) {
  final delta = Delta();
  for (final op in list) {
    delta.insert(op['insert'], op['attributes'] as Map<String, dynamic>?);
  }
  return delta.toJson();
}

void main() {
  group('toHtml', () {
    test('formatting uses inline styles and div paragraphs', () {
      final html = RichTextCodec.toHtml([
        {'insert': 'Hi '},
        {'insert': 'bold', 'attributes': {'bold': true}},
        {'insert': ' '},
        {
          'insert': 'red',
          'attributes': {'color': '#ff0000', 'size': '18', 'font': 'Arial'},
        },
        {'insert': '\n'},
        {'insert': 'one'},
        {'insert': '\n', 'attributes': {'list': 'bullet'}},
        {'insert': 'two'},
        {'insert': '\n', 'attributes': {'list': 'ordered'}},
        {'insert': 'site', 'attributes': {'link': 'https://example.com'}},
        {'insert': '\n', 'attributes': {'align': 'center'}},
        {'insert': 'a < b & c'},
        {'insert': '\n'},
      ]);
      expect(html, startsWith('<div>Hi <strong>bold</strong>'));
      expect(html, contains('style="color:#ff0000;font-family:Arial;'
          'font-size: 18px"'));
      expect(html, contains('<ul><li>one</li></ul><ol><li>two</li></ol>'));
      expect(html, contains('<div style="text-align:center">'
          '<a href="https://example.com" target="_blank">site</a></div>'));
      expect(html, contains('a &lt; b &amp; c'));
      expect(html, isNot(contains('class=')),
          reason: 'mail clients drop style sheets');
    });

    test('images keep their source until mapped to cid', () {
      final html = RichTextCodec.toHtml([
        {'insert': {'image': '/tmp/logo.png'}},
        {'insert': '\n'},
      ]);
      expect(html, contains('src="/tmp/logo.png"'));
      final mapped = RichTextCodec.replaceImageSources(
          html, (src) => src == '/tmp/logo.png' ? 'cid:img1@lookin' : null);
      expect(mapped, contains('src="cid:img1@lookin"'));
    });

    test('wraps the body in the default font', () {
      expect(RichTextCodec.wrapBody('<div>x</div>'),
          contains('font-family: Calibri'));
    });
  });

  group('fromHtml', () {
    test('paragraphs, line breaks and empty lines', () {
      expect(ops('<p>Alice Adams</p><p><b>Product</b> Manager</p>'), [
        {'insert': 'Alice Adams\n'},
        {'insert': 'Product', 'attributes': {'bold': true}},
        {'insert': ' Manager\n'},
      ]);
      expect(ops('Alice Adams<br>Product Manager<br>+1 555'),
          [{'insert': 'Alice Adams\nProduct Manager\n+1 555\n'}]);
      expect(ops('<div>a</div><div><br></div><div>b<br></div>'),
          [{'insert': 'a\n\nb\n'}]);
      expect(ops(''), [{'insert': '\n'}]);
    });

    test('inline styles and legacy tags', () {
      final result = ops('<span style="color: rgb(255, 0, 0); font-size: 12pt; '
          'font-family: \'Times New Roman\', serif">x</span>'
          '<font color="blue" face="Arial">y</font><i>z</i><u>u</u><s>s</s>');
      expect(result[0], {
        'insert': 'x',
        'attributes': {'color': '#ff0000', 'font': 'Times New Roman', 'size': '16'},
      });
      expect(result[1]['attributes'], {'color': '#0000ff', 'font': 'Arial'});
      expect(result[2]['attributes'], {'italic': true});
      expect(result[3]['attributes'], {'underline': true});
      expect(result[4]['attributes'], {'strike': true});
    });

    test('lists, nesting, alignment, quotes and headings', () {
      expect(ops('<ul><li>a</li><li>b<ol><li>c</li></ol></li></ul>'), [
        {'insert': 'a'},
        {'insert': '\n', 'attributes': {'list': 'bullet'}},
        {'insert': 'b'},
        {'insert': '\n', 'attributes': {'list': 'bullet'}},
        {'insert': 'c'},
        {'insert': '\n', 'attributes': {'list': 'ordered', 'indent': 1}},
      ]);
      expect(ops('<div style="text-align:center">mid</div><div>x</div>'), [
        {'insert': 'mid'},
        {'insert': '\n', 'attributes': {'align': 'center'}},
        {'insert': 'x\n'},
      ]);
      expect(ops('<blockquote>q</blockquote><h2>T</h2>'), [
        {'insert': 'q'},
        {'insert': '\n', 'attributes': {'blockquote': true}},
        {'insert': 'T'},
        {'insert': '\n', 'attributes': {'header': 2}},
      ]);
    });

    test('links, images, scripts and whitespace', () {
      final result =
          ops('<p>  see   <a href="https://x.org">here</a>\n now</p>'
              '<img src="cid:a@b"><script>alert(1)</script>');
      expect(result, [
        {'insert': 'see '},
        {'insert': 'here', 'attributes': {'link': 'https://x.org'}},
        {'insert': ' now\n'},
        {'insert': {'image': 'cid:a@b'}},
        {'insert': '\n'},
      ]);
    });

    test('round trip keeps the formatting the editor supports', () {
      final original = [
        {'insert': 'Hello '},
        {'insert': 'world', 'attributes': {'bold': true, 'color': '#0000ff'}},
        {'insert': '\n'},
        {'insert': 'item'},
        {'insert': '\n', 'attributes': {'list': 'bullet'}},
        {'insert': 'right'},
        {'insert': '\n', 'attributes': {'align': 'right'}},
        {'insert': 'end\n'},
      ];
      expect(ops(RichTextCodec.toHtml(original)), normalized(original));
    });
  });

  test('plain text, emptiness and images', () {
    final doc = [
      {'insert': 'Line one\n'},
      {'insert': {'image': '/tmp/a.png'}},
      {'insert': '\n'},
    ];
    expect(RichTextCodec.toPlainText(doc), startsWith('Line one'));
    expect(RichTextCodec.imageSources(doc), ['/tmp/a.png']);
    expect(RichTextCodec.isEmpty(doc), isFalse);
    expect(RichTextCodec.isEmpty([{'insert': '\n\n'}]), isTrue);
    expect(RichTextCodec.fromPlainText('a\nb').toJson(),
        [{'insert': 'a\nb\n'}]);
  });

  test('splits the quoted original from Look In HTML', () {
    final html = RichTextCodec.wrapBody('<div>Reply</div>'
        '<div id="${RichTextCodec.quotedMarker}"><table><tr><td>x</td></tr>'
        '</table></div>');
    final parts = RichTextCodec.splitQuoted(html);
    expect(parts.body, '<div>Reply</div>');
    expect(parts.quoted, contains('<table>'));
    expect(RichTextCodec.splitQuoted('<div>plain</div>').quoted, isNull);
  });
}
