import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/calendar_event.dart';
import '../models/contact.dart';
import '../models/email_message.dart';
import 'file_dialogs.dart';
import 'html_sanitizer.dart';

/// Printing via the desktop's web browser: Look In renders a print-ready
/// HTML page (Outlook's "Memo Style") into a temporary file and opens it in
/// the default browser, which provides print preview, printer selection and
/// "Save as PDF". The page asks the browser to open its print dialog.
class PrintService {
  PrintService._();

  static const _css = '''
    body { font-family: "Segoe UI", "Noto Sans", Ubuntu, Arial, sans-serif;
           font-size: 11pt; color: #222; margin: 24px; }
    .owner { font-weight: 600; font-size: 12pt; border-bottom: 3px solid #222;
             padding-bottom: 4px; margin-bottom: 12px; }
    table.hdr td { padding: 2px 12px 2px 0; vertical-align: top; }
    table.hdr td.k { font-weight: 600; white-space: nowrap; }
    hr { border: none; border-top: 1px solid #999; margin: 12px 0; }
    .body { margin-top: 8px; }
    pre.plain { white-space: pre-wrap; font-family: inherit; }
    @media print { body { margin: 0; } }
  ''';

  static String _escape(String s) => const HtmlEscape().convert(s);

  static String _page(String title, String owner, String content) => '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>${_escape(title)}</title>
<style>$_css</style></head>
<body onload="setTimeout(function(){window.print();}, 300)">
<div class="owner">${_escape(owner)}</div>
$content
</body></html>''';

  /// Opens a print view of [message] (with its full body).
  static Future<bool> printMessage(EmailMessage message, {String owner = ''}) {
    final rows = <List<String>>[
      ['From:', message.from.toString()],
      ['Sent:', DateFormat('EEEE, MMMM d, yyyy h:mm a').format(message.date)],
      if (message.to.isNotEmpty)
        ['To:', message.to.map((a) => a.toString()).join('; ')],
      if (message.cc.isNotEmpty)
        ['Cc:', message.cc.map((a) => a.toString()).join('; ')],
      ['Subject:', message.subject],
      if (message.visibleAttachments.isNotEmpty)
        [
          'Attachments:',
          message.visibleAttachments
              .map((a) => '${a.fileName} (${a.sizeFormatted})')
              .join('; ')
        ],
    ];
    final header = StringBuffer('<table class="hdr">');
    for (final r in rows) {
      header.write(
          '<tr><td class="k">${_escape(r[0])}</td><td>${_escape(r[1])}</td></tr>');
    }
    header.write('</table><hr>');
    final String body;
    if (message.htmlBody != null && message.htmlBody!.trim().isNotEmpty) {
      body = sanitizeEmailHtml(message.htmlBody!).html;
    } else {
      body = '<pre class="plain">${_escape(message.textBody ?? '')}</pre>';
    }
    return _open(
      message.subject,
      _page(message.subject, owner, '$header<div class="body">$body</div>'),
    );
  }

  /// Opens a print view of a contact card.
  static Future<bool> printContact(Contact contact) {
    final rows = <List<String>>[
      if (contact.company?.isNotEmpty ?? false) ['Company:', contact.company!],
      if (contact.jobTitle?.isNotEmpty ?? false)
        ['Job title:', contact.jobTitle!],
      for (final e in contact.emails) ['${e.label}:', e.address],
      for (final ph in contact.phones) ['${ph.label}:', ph.number],
      if (contact.address != null && !contact.address!.isEmpty)
        ['Address:', contact.address!.formatted.replaceAll('\n', ', ')],
      if (contact.notes?.isNotEmpty ?? false) ['Notes:', contact.notes!],
    ];
    final table = StringBuffer('<table class="hdr">');
    for (final r in rows) {
      table.write(
          '<tr><td class="k">${_escape(r[0])}</td><td>${_escape(r[1])}</td></tr>');
    }
    table.write('</table>');
    return _open(contact.displayName,
        _page(contact.displayName, contact.displayName, table.toString()));
  }

  /// Opens a print view listing the occurrences in [days].
  static Future<bool> printAgenda(
    String title,
    List<DateTime> days,
    List<EventOccurrence> Function(DateTime day) occurrencesFor,
  ) {
    final buffer = StringBuffer();
    final dayFormat = DateFormat('EEEE, MMMM d, yyyy');
    final time = DateFormat.jm();
    for (final day in days) {
      final items = occurrencesFor(day);
      buffer.write('<h3>${_escape(dayFormat.format(day))}</h3>');
      if (items.isEmpty) {
        buffer.write('<p style="color:#888">No appointments</p>');
        continue;
      }
      buffer.write('<table class="hdr">');
      for (final o in items) {
        final when = o.event.isAllDay
            ? 'All day'
            : '${time.format(o.start)} – ${time.format(o.end)}';
        final where =
            o.event.location?.isNotEmpty ?? false ? ' (${o.event.location})' : '';
        final what = o.event.title.isEmpty ? '(No title)' : o.event.title;
        buffer.write('<tr><td class="k">${_escape(when)}</td>'
            '<td>${_escape('$what$where')}</td></tr>');
      }
      buffer.write('</table>');
    }
    return _open(title, _page(title, title, buffer.toString()));
  }

  static Future<bool> _open(String title, String html) async {
    final dir = await Directory.systemTemp.createTemp('look_in_print_');
    final name = FileDialogs.sanitizeFileName(
        title.isEmpty ? 'print' : title.substring(0, title.length.clamp(0, 60)));
    final file = File(p.join(dir.path, '$name.html'));
    await file.writeAsString(html, flush: true);
    return FileDialogs.openWithDefaultApp(file.path);
  }
}
