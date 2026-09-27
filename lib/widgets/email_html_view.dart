import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';

import '../theme/outlook_theme.dart';

/// Renders sanitized email HTML (see sanitizeEmailHtml) with Look In's
/// reading styles. Used by the reading pane and for quoted originals in
/// the message window.
class EmailHtmlView extends StatelessWidget {
  final String html;
  final void Function(String? url)? onLinkTap;

  const EmailHtmlView({super.key, required this.html, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    return Html(
      data: html,
      extensions: const [TableHtmlExtension()],
      onLinkTap: onLinkTap == null ? null : (url, _, _) => onLinkTap!(url),
      style: {
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontFamily: OutlookTheme.fontFamily,
          fontSize: FontSize(14),
          color: OutlookTheme.textPrimary,
          lineHeight: const LineHeight(1.45),
        ),
        'a': Style(color: OutlookTheme.textLink),
        'blockquote': Style(
          margin: Margins.only(left: 4),
          padding: HtmlPaddings.only(left: 10),
          border: const Border(
              left: BorderSide(color: OutlookTheme.dividerColor, width: 2)),
          color: OutlookTheme.textSecondary,
        ),
        'img': Style(width: Width.auto()),
        // flutter_html ignores the cellpadding attribute.
        'td': Style(padding: HtmlPaddings.symmetric(horizontal: 6, vertical: 3)),
        'th': Style(
            padding: HtmlPaddings.symmetric(horizontal: 6, vertical: 3),
            textAlign: TextAlign.left),
      },
    );
  }
}
