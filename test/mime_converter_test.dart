import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart' as enough;
import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/email_account.dart';
import 'package:look_in/models/email_message.dart';
import 'package:look_in/models/outgoing_message.dart';
import 'package:look_in/services/mime_converter.dart';

const _account = EmailAccount(
  id: 'a',
  displayName: 'Ann Example',
  emailAddress: 'ann@example.com',
  incomingHost: 'imap.example.com',
  incomingPort: 993,
  smtpHost: 'smtp.example.com',
  smtpPort: 587,
  username: 'ann',
  password: 'x',
);

OutgoingMessage _message({
  String text = 'Hello',
  String? html,
  List<Attachment> attachments = const [],
  MessageImportance importance = MessageImportance.normal,
  String? inReplyTo,
  String? references,
}) =>
    OutgoingMessage(
      id: 'm',
      accountId: 'a',
      to: const [EmailAddress(address: 'bob@example.com', displayName: 'Bob')],
      cc: const [EmailAddress(address: 'carol@example.com')],
      subject: 'Grüße and a long subject line that goes on and on for testing',
      textBody: text,
      htmlBody: html,
      attachments: attachments,
      importance: importance,
      inReplyTo: inReplyTo,
      references: references,
      createdAt: DateTime(2026, 1, 1),
    );

/// Renders and re-parses, as a receiving client would.
Future<EmailMessage> _roundTrip(OutgoingMessage m) async {
  final mime = await MimeConverter.buildMimeMessage(m, _account);
  final parsed = enough.MimeMessage.parseFromText(mime.renderMessage());
  return MimeConverter.toEmailMessage(parsed,
      id: 'x', accountId: 'a', folderId: 'f');
}

void main() {
  test('long ASCII HTML and text lines survive unchanged', () async {
    final html = '<table border="1" cellpadding="6" style="border-collapse:collapse">'
        '${List.filled(20, '<tr><td>Ribbon refresh</td><td>Done</td></tr>').join()}'
        '</table>';
    final text = List.filled(40, 'word').join(' ');
    final result = await _roundTrip(_message(text: text, html: html));
    expect(result.htmlBody, html);
    expect(result.textBody, text);
  });

  test('non-ASCII text, subject and names are encoded and decoded', () async {
    final result = await _roundTrip(_message(text: 'Grüße aus Köln – 👋'));
    expect(result.textBody, 'Grüße aus Köln – 👋');
    expect(result.subject, startsWith('Grüße'));
    expect(result.from.displayName, 'Ann Example');
    expect(result.to.single.displayName, 'Bob');
    expect(result.cc.single.address, 'carol@example.com');
  });

  test('HTML alternative is generated from plain text when missing', () async {
    final result = await _roundTrip(_message(text: 'Line 1\nhttps://example.com'));
    expect(result.htmlBody, contains('<a href="https://example.com"'));
  });

  test('attachments, importance and threading headers', () async {
    final dir = await Directory.systemTemp.createTemp('mime_test_');
    final file = File('${dir.path}/data.bin');
    final bytes = List<int>.generate(3000, (i) => i % 256);
    await file.writeAsBytes(bytes);
    final m = _message(
      attachments: [
        Attachment(
          id: '1',
          fileName: 'data.bin',
          mimeType: 'application/octet-stream',
          size: bytes.length,
          localPath: file.path,
        ),
      ],
      importance: MessageImportance.high,
      inReplyTo: '<orig@example.com>',
      references: '<root@example.com>',
    );
    final mime = await MimeConverter.buildMimeMessage(m, _account);
    final raw = mime.renderMessage();
    final parsed = enough.MimeMessage.parseFromText(raw);
    final result = MimeConverter.toEmailMessage(parsed,
        id: 'x', accountId: 'a', folderId: 'f');
    expect(result.importance, MessageImportance.high);
    expect(result.inReplyTo, '<orig@example.com>');
    expect(result.references, contains('<root@example.com>'));
    expect(result.references, contains('<orig@example.com>'));
    final att = result.visibleAttachments.single;
    expect(att.fileName, 'data.bin');
    final extracted = MimeConverter.extractPart(
        Uint8List.fromList(utf8.encode(raw)), att.id);
    expect(extracted, bytes);
    await dir.delete(recursive: true);
  });

  test('Bcc is never part of the transmitted message', () async {
    final m = OutgoingMessage(
      id: 'b',
      accountId: 'a',
      to: const [EmailAddress(address: 'bob@example.com')],
      bcc: const [EmailAddress(address: 'secret@example.com')],
      subject: 's',
      createdAt: DateTime(2026),
    );
    final raw = (await MimeConverter.buildMimeMessage(m, _account)).renderMessage();
    expect(raw, isNot(contains('secret@example.com')));
  });

  test('calendar reply part carries METHOD', () async {
    const ics = 'BEGIN:VCALENDAR\r\nMETHOD:REPLY\r\nEND:VCALENDAR\r\n';
    final mime = await MimeConverter.buildMimeMessage(_message(), _account,
        calendarPart: (ics: ics, method: 'REPLY'));
    final raw = mime.renderMessage();
    expect(raw, contains('text/calendar'));
    expect(raw.toLowerCase(), contains('method=reply'));
    final parsed = MimeConverter.toEmailMessage(
        enough.MimeMessage.parseFromText(raw),
        id: 'x', accountId: 'a', folderId: 'f');
    expect(parsed.calendarInvite, isNotNull);
  });

  test('previews skip quoted lines and fall back to HTML', () {
    expect(MimeConverter.makePreview('> old\nNew text', null), 'New text');
    expect(MimeConverter.makePreview(null, '<p>Hello <b>there</b></p>'),
        'Hello there');
  });
}
