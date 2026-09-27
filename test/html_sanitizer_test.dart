import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/services/html_sanitizer.dart';

String clean(String html, {bool allow = false}) =>
    sanitizeEmailHtml(html, allowRemoteImages: allow).html;

void main() {
  group('sanitizeEmailHtml: dangerous content', () {
    test('removes scripts and event handlers', () {
      final result = sanitizeEmailHtml(
          '<p onclick="steal()" ONMOUSEOVER="x()" class="a">Hi</p>'
          '<script>alert(1)</script><SCRIPT src="http://evil/x.js"></SCRIPT>');
      expect(result.html, '<p class="a">Hi</p>');
      expect(result.blockedImageCount, 0);
      expect(result.hasBlockedImages, isFalse);
    });

    test('removes embedded and form controls, unwraps forms', () {
      final html = clean('<iframe src="https://x"></iframe>'
          '<object data="x.swf"><param name="a"></object>'
          '<embed src="x.swf">'
          '<form action="https://phish.example/login" method="post">'
          '<p>Please log in</p><input name="password" type="password">'
          '<button type="submit">Go</button><select><option>1</option></select>'
          '<textarea>t</textarea></form>'
          '<frameset><frame src="x"></frameset><applet code="x"></applet>');
      expect(html, '<p>Please log in</p>');
    });

    test('removes meta, link and base elements', () {
      final html = clean('<html><head>'
          '<meta http-equiv="refresh" content="0;url=https://evil">'
          '<link rel="stylesheet" href="https://x/style.css">'
          '<base href="https://evil/"></head>'
          '<body><p>Body</p><meta name="x"><link rel="x"></body></html>');
      expect(html, '<p>Body</p>');
    });

    test('removes javascript: and vbscript: URLs', () {
      final html = clean('<a href="javascript:alert(1)">a</a>'
          '<a href=" JaVaScRiPt:alert(1)">b</a>'
          '<a href="java\tscript:alert(1)">c</a>'
          '<a href="vbscript:msgbox(1)">d</a>'
          '<img src="javascript:alert(1)" alt="e">'
          '<a href="data:text/html;base64,PHNjcmlwdD4=">f</a>'
          '<a href="https://example.com/ok">g</a>'
          '<a href="mailto:bob@example.com">h</a>');
      expect(
        html,
        '<a>a</a><a>b</a><a>c</a><a>d</a><img alt="e"><a>f</a>'
        '<a href="https://example.com/ok">g</a>'
        '<a href="mailto:bob@example.com">h</a>',
      );
    });

    test('removes dangerous inline styles', () {
      final html = clean('<p style="width: expression(alert(1))">a</p>'
          '<p style="background: url(javascript:alert(1))">b</p>'
          '<p style="-moz-binding: url(x.xml#y)">c</p>'
          '<p style="color: red">d</p>');
      expect(html, '<p>a</p><p>b</p><p>c</p><p style="color: red">d</p>');
    });

    test('removes srcdoc and SVG script hooks', () {
      final html = clean('<svg><a xlink:href="javascript:alert(1)">x</a>'
          '<circle onload="alert(1)"></circle></svg>');
      expect(html.contains('javascript'), isFalse);
      expect(html.contains('onload'), isFalse);
    });

    test('keeps style elements and ordinary markup', () {
      const input = '<style>p { color: red; }</style>'
          '<table width="100%"><tr><td bgcolor="#fff">'
          '<b>Bold</b> <a href="https://example.com">link</a></td></tr></table>';
      final html = clean(input);
      expect(html, contains('<style>p { color: red; }</style>'));
      expect(
          html,
          contains('<td bgcolor="#fff"><b>Bold</b> '
              '<a href="https://example.com">link</a></td>'));
    });

    test('returns head styles followed by the body content', () {
      final html = clean('<html><head><title>Newsletter</title>'
          '<style>.x { margin: 0 }</style></head>'
          '<body class="b"><div class="x">Content</div></body></html>');
      expect(
          html, '<style>.x { margin: 0 }</style><div class="x">Content</div>');
    });

    test('plain fragments and text', () {
      expect(clean('Just text'), 'Just text');
      expect(clean(''), '');
      expect(clean('<p>Unclosed <b>tags'), '<p>Unclosed <b>tags</b></p>');
    });
  });

  group('sanitizeEmailHtml: remote images', () {
    test('blocks remote images and keeps the original URL', () {
      final result = sanitizeEmailHtml(
          '<img alt="Logo" src="https://cdn.example.com/logo.png" width="10">'
          '<img src="http://tracker.example.com/pixel.gif">'
          '<img src="//cdn.example.com/proto-relative.png">');
      expect(result.blockedImageCount, 3);
      expect(result.hasBlockedImages, isTrue);
      expect(
        result.html,
        '<img alt="Logo" width="10" '
        'data-blocked-src="https://cdn.example.com/logo.png">'
        '<img data-blocked-src="http://tracker.example.com/pixel.gif">'
        '<img data-blocked-src="//cdn.example.com/proto-relative.png">',
      );
    });

    test('allowRemoteImages keeps the sources', () {
      const input = '<img src="https://cdn.example.com/logo.png">'
          '<td background="https://x/bg.png"></td>'
          '<div style="background-image: url(https://x/bg.png)"></div>';
      final result = sanitizeEmailHtml('<table><tr>$input</tr></table>',
          allowRemoteImages: true);
      expect(result.blockedImageCount, 0);
      expect(result.html, contains('src="https://cdn.example.com/logo.png"'));
      expect(result.html, contains('background="https://x/bg.png"'));
      expect(result.html, contains('url(https://x/bg.png)'));
      expect(result.html.contains('data-blocked'), isFalse);
    });

    test('allowRemoteImages still removes scripts', () {
      final result = sanitizeEmailHtml(
          '<img src="https://x/a.png" onerror="alert(1)"><script>x</script>',
          allowRemoteImages: true);
      expect(result.html, '<img src="https://x/a.png">');
    });

    test('data: and relative images are not blocked', () {
      final result =
          sanitizeEmailHtml('<img src="data:image/png;base64,iVBORw0KGgo=">'
              '<img src="images/local.png">');
      expect(result.blockedImageCount, 0);
      expect(result.html, contains('src="data:image/png;base64,iVBORw0KGgo="'));
      expect(result.html, contains('src="images/local.png"'));
    });

    test('blocks remote background attributes', () {
      final result =
          sanitizeEmailHtml('<table background="https://x/bg1.png"><tr>'
              '<td background="http://x/bg2.png">cell</td>'
              '<td background="#ffffff">plain</td></tr></table>');
      expect(result.blockedImageCount, 2);
      expect(result.html.contains(RegExp(r'\sbackground="http')), isFalse);
      expect(
          result.html, contains('data-blocked-background="https://x/bg1.png"'));
      expect(result.html, contains('background="#ffffff"'));
    });

    test('blocks remote url() in inline styles', () {
      final result = sanitizeEmailHtml(
          '<div style="background-image: url(\'https://x/a.png\'); color: red">a</div>'
          '<div style="background: #fff url(&quot;//x/b.png&quot;) no-repeat">b</div>'
          '<div style="background: url(data:image/png;base64,AAAA)">c</div>');
      expect(result.blockedImageCount, 2);
      expect(
          result.html, contains('style="background-image: none; color: red"'));
      expect(result.html, contains('style="background: #fff none no-repeat"'));
      expect(result.html, contains('url(data:image/png;base64,AAAA)'));
    });

    test('blocks remote resources in style elements', () {
      final result = sanitizeEmailHtml('<style>'
          '@import url("https://x/fonts.css");\n'
          'body { background: url(http://x/bg.png) }\n'
          '.logo { background: url(logo.png) }'
          '</style><p>x</p>');
      expect(result.blockedImageCount, 2);
      expect(result.html.contains('https://x/fonts.css'), isFalse);
      expect(result.html.contains('http://x/bg.png'), isFalse);
      expect(result.html, contains('url(logo.png)'));
      expect(result.html, contains('<p>x</p>'));
    });

    test('blocks srcset, poster and SVG image hrefs', () {
      final result = sanitizeEmailHtml(
          '<img srcset="https://x/a.png 1x, https://x/a@2x.png 2x" '
          'src="https://x/a.png">'
          '<picture><source srcset="https://x/b.webp"></picture>'
          '<video poster="https://x/poster.jpg"></video>'
          '<svg><image href="https://x/c.png"></image></svg>');
      // One per image element, plus source, poster and the SVG image.
      expect(result.blockedImageCount, 4);
      expect(result.html.contains('https://x/a@2x.png'), isFalse);
      expect(result.html.contains('srcset'), isFalse);
      expect(result.html.contains('poster'), isFalse);
      expect(result.html.contains('https://x/c.png'), isFalse);
    });
  });

  group('sanitizeEmailHtml: cid images', () {
    test('resolves cid: sources through the callback', () {
      final requested = <String>[];
      final result = sanitizeEmailHtml(
        '<img src="cid:logo@acme.com" alt="Logo">'
        '<img src="CID:%3Cbanner%40acme.com%3E">'
        '<img src="cid:missing@acme.com">',
        resolveCid: (cid) {
          requested.add(cid);
          return cid == 'missing@acme.com'
              ? null
              : 'data:image/png;base64,QUJD';
        },
      );
      expect(
          requested, ['logo@acme.com', 'banner@acme.com', 'missing@acme.com']);
      expect(result.blockedImageCount, 0);
      expect(
        result.html,
        '<img src="data:image/png;base64,QUJD" alt="Logo">'
        '<img src="data:image/png;base64,QUJD">'
        '<img>',
      );
    });

    test('without a resolver cid: sources are removed', () {
      expect(clean('<img src="cid:x@y">'), '<img>');
    });

    test('cid: backgrounds are resolved too', () {
      final result = sanitizeEmailHtml('<table background="cid:bg"></table>',
          resolveCid: (cid) => 'data:image/gif;base64,R0lG');
      expect(result.html,
          '<table background="data:image/gif;base64,R0lG"></table>');
    });

    test('cid images are resolved even when remote images are blocked', () {
      final result = sanitizeEmailHtml(
          '<img src="cid:a"><img src="https://x/b.png">',
          resolveCid: (_) => 'data:image/png;base64,AA==');
      expect(result.blockedImageCount, 1);
      expect(result.html, contains('<img src="data:image/png;base64,AA==">'));
    });
  });

  group('plainTextToHtml', () {
    test('escapes HTML', () {
      expect(plainTextToHtml('Hello <world> & "friends" \'here\''),
          'Hello &lt;world&gt; &amp; &quot;friends&quot; &#39;here&#39;');
      expect(plainTextToHtml('<script>alert(1)</script>'),
          '&lt;script&gt;alert(1)&lt;/script&gt;');
    });

    test('converts line breaks', () {
      expect(plainTextToHtml('one\ntwo\r\nthree\rfour'),
          'one<br>two<br>three<br>four');
      expect(plainTextToHtml('a\n\nb'), 'a<br><br>b');
      expect(plainTextToHtml(''), '');
    });

    test('links URLs and keeps trailing punctuation outside', () {
      expect(
        plainTextToHtml('See https://example.com/path?a=1&b=2.'),
        'See <a href="https://example.com/path?a=1&amp;b=2">'
        'https://example.com/path?a=1&amp;b=2</a>.',
      );
      expect(plainTextToHtml('http://x.org, then'),
          '<a href="http://x.org">http://x.org</a>, then');
      expect(
          plainTextToHtml('(see https://en.wikipedia.org/wiki/Foo_(bar))'),
          '(see <a href="https://en.wikipedia.org/wiki/Foo_(bar)">'
          'https://en.wikipedia.org/wiki/Foo_(bar)</a>)');
      expect(plainTextToHtml('<https://example.com>'),
          '&lt;<a href="https://example.com">https://example.com</a>&gt;');
    });

    test('links www. addresses with an http:// target', () {
      expect(plainTextToHtml('Go to www.example.com!'),
          'Go to <a href="http://www.example.com">www.example.com</a>!');
      expect(plainTextToHtml('www. alone'), 'www. alone');
    });

    test('links email addresses', () {
      expect(
          plainTextToHtml('Mail bob.smith+tag@mail.example.co.uk.'),
          'Mail <a href="mailto:bob.smith+tag@mail.example.co.uk">'
          'bob.smith+tag@mail.example.co.uk</a>.');
      expect(plainTextToHtml('not@an-address'), 'not@an-address');
    });

    test('URLs cannot break out of the attribute', () {
      final html = plainTextToHtml('http://x.com/"onmouseover="alert(1)');
      expect(html, startsWith('<a href="http://x.com/">http://x.com/</a>'));
      expect(html, contains('&quot;onmouseover=&quot;alert(1)'));
      expect(plainTextToHtml('javascript:alert(1)'), 'javascript:alert(1)');
    });

    test('preserves runs of spaces and tabs', () {
      expect(plainTextToHtml('a  b'), 'a &nbsp;b');
      expect(plainTextToHtml('a   b'), 'a &nbsp;&nbsp;b');
      expect(plainTextToHtml('  indented'), '&nbsp;&nbsp;indented');
      expect(plainTextToHtml(' x'), '&nbsp;x');
      expect(plainTextToHtml('a\tb'), 'a &nbsp;&nbsp;&nbsp;b');
      expect(plainTextToHtml('a b'), 'a b');
    });

    test('quoted lines become nested blockquotes', () {
      final html = plainTextToHtml(
          'Thanks!\n\nOn Monday, Bob wrote:\n> Hello\n>> Earlier\n> Bye\nEnd');
      const open = '<blockquote type="cite" style="margin:0 0 0 .8ex;'
          'border-left:2px solid #b5c4df;padding-left:1ex">';
      expect(
        html,
        'Thanks!<br><br>On Monday, Bob wrote:<br>'
        '${open}Hello<br>${open}Earlier</blockquote>Bye</blockquote>End',
      );
    });
  });

  group('htmlToPlainText', () {
    test('paragraphs, divs and line breaks', () {
      expect(htmlToPlainText('<p>Hello</p><p>World</p>'), 'Hello\n\nWorld');
      expect(htmlToPlainText('<div>a</div><div>b</div>'), 'a\nb');
      expect(htmlToPlainText('a<br>b<br><br>c'), 'a\nb\n\nc');
      expect(htmlToPlainText('<h1>Title</h1>Text'), 'Title\n\nText');
    });

    test('collapses whitespace and more than one blank line', () {
      expect(htmlToPlainText('<p>  Hello \n   <b>big</b>\tworld  </p>'),
          'Hello big world');
      expect(htmlToPlainText('<p>a</p><br><br><br><br><p>b</p>'), 'a\n\nb');
      expect(htmlToPlainText('<span>a</span><span>b</span>'), 'ab');
    });

    test('drops script, style, head and hidden elements', () {
      expect(
        htmlToPlainText('<html><head><title>T</title><style>p{}</style></head>'
            '<body><script>var x = 1;</script>'
            '<div style="display: none; max-height: 0">Preheader</div>'
            '<p hidden>Hidden</p><p>Body</p></body></html>'),
        'Body',
      );
    });

    test('list items get a "- " prefix and nested lists are indented', () {
      expect(
          htmlToPlainText('<ul><li>One</li><li>Two</li></ul>'), '- One\n- Two');
      expect(
        htmlToPlainText('<p>Items:</p><ol><li>One<ul><li>Sub</li></ul></li>'
            '<li>Two</li></ol><p>After</p>'),
        'Items:\n\n- One\n  - Sub\n- Two\n\nAfter',
      );
    });

    test('links show their URL when it differs from the text', () {
      expect(htmlToPlainText('<a href="https://example.com/x">Example</a>'),
          'Example (https://example.com/x)');
      expect(
          htmlToPlainText(
              '<a href="https://example.com">https://example.com</a>'),
          'https://example.com');
      expect(
          htmlToPlainText('<a href="https://www.example.com/">example.com</a>'),
          'example.com');
      expect(htmlToPlainText('<a href="mailto:bob@x.com">bob@x.com</a>'),
          'bob@x.com');
      expect(htmlToPlainText('<a href="mailto:bob@x.com">Email Bob</a>'),
          'Email Bob (bob@x.com)');
      expect(htmlToPlainText('<a href="#top">Top</a>'), 'Top');
      expect(htmlToPlainText('<a href="javascript:x()">Click</a>'), 'Click');
      expect(htmlToPlainText('<a>No href</a>'), 'No href');
      expect(
          htmlToPlainText(
              'Visit <a href="https://x.org"><img src="logo.png"></a>.'),
          'Visit .');
    });

    test('decodes entities', () {
      expect(
          htmlToPlainText(
              '&lt;tag&gt; &amp; &quot;q&quot; &copy; &#8364; &euro;'),
          '<tag> & "q" © € €');
      expect(htmlToPlainText('a&nbsp;&nbsp;b'), 'a  b');
    });

    test('tables put cells on one line and rows on separate lines', () {
      expect(
        htmlToPlainText('<table><tr><th>Name</th><th>Value</th></tr>'
            '<tr><td>A</td><td>1</td></tr></table>'),
        'Name Value\nA 1',
      );
    });

    test('blockquotes are prefixed with "> "', () {
      expect(
        htmlToPlainText('<p>Reply</p><blockquote><p>Original</p>'
            '<p>Second</p></blockquote>'),
        'Reply\n\n> Original\n>\n> Second',
      );
      expect(
        htmlToPlainText('<blockquote>a<blockquote>b</blockquote></blockquote>'),
        '> a\n> > b',
      );
    });

    test('pre keeps its formatting', () {
      expect(htmlToPlainText('<p>x</p><pre>  a\n    b</pre><p>y</p>'),
          'x\n\n  a\n    b\n\ny');
    });

    test('plain text and empty input', () {
      expect(htmlToPlainText('just text'), 'just text');
      expect(htmlToPlainText(''), '');
      expect(htmlToPlainText('   '), '');
    });
  });

  group('quoteForReply', () {
    test('prefixes every line', () {
      expect(quoteForReply('a\nb'), '> a\n> b');
      expect(quoteForReply('a\r\n\r\nb\r\n'), '> a\n> \n> b');
      expect(quoteForReply('> earlier'), '> > earlier');
      expect(quoteForReply(''), '');
      expect(quoteForReply('\n\n'), '');
    });

    test('works with htmlToPlainText for HTML replies', () {
      final quoted = quoteForReply(htmlToPlainText('<p>Hi</p><p>Thanks</p>'));
      expect(quoted, '> Hi\n> \n> Thanks');
    });
  });

  test('point sizes become pixels for the renderer', () {
    expect(pointsToPixels('font-size: 11pt; margin: 0 0 7.5pt'),
        'font-size: 14.7px; margin: 0 0 10px');
    expect(pointsToPixels('width: 100%'), 'width: 100%');
    final html = sanitizeEmailHtml(
            '<style>p{font-size:12pt}</style><p style="font-size:9pt">x</p>')
        .html;
    expect(html, contains('font-size:16px'));
    expect(html, contains('font-size:12px'));
  });
}
