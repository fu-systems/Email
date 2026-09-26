import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/contact.dart';
import 'package:look_in/services/contacts_io.dart';

final now = DateTime(2026, 1, 1, 12);

String Function() ids() {
  var n = 0;
  return () => 'c${++n}';
}

Contact contact({
  String id = 'x',
  String? firstName,
  String? lastName,
  String? company,
  String? jobTitle,
  List<ContactEmail> emails = const [],
  List<ContactPhone> phones = const [],
  ContactAddress? address,
  String? notes,
}) =>
    Contact(
      id: id,
      firstName: firstName,
      lastName: lastName,
      company: company,
      jobTitle: jobTitle,
      emails: emails,
      phones: phones,
      address: address,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );

final jane = contact(
  id: 'jane',
  firstName: 'Jane',
  lastName: 'Doe',
  company: 'Acme, Inc.',
  jobTitle: 'Chief "Everything" Officer',
  emails: const [
    ContactEmail(label: 'Email', address: 'jane@acme.com'),
    ContactEmail(label: 'Email 2', address: 'jane.doe@gmail.com'),
  ],
  phones: const [
    ContactPhone(label: 'Mobile', number: '+1 555 0100'),
    ContactPhone(label: 'Business', number: '+1 555 0101'),
    ContactPhone(label: 'Home', number: '+1 555 0102'),
  ],
  address: const ContactAddress(
    street: '1 Main St\nSuite 5',
    city: 'Springfield',
    state: 'IL',
    zipCode: '62701',
    country: 'USA',
  ),
  notes: 'Met at the conference; likes "quotes", commas,\nand line breaks.\r\n'
      'Second line — ünïcödé ✓',
);

final bob = contact(
  id: 'bob',
  firstName: 'Bob',
  emails: const [ContactEmail(label: 'Email', address: 'bob@example.com')],
);

final acme = contact(
  id: 'acme',
  company: 'Acme Support',
  emails: const [ContactEmail(label: 'Email', address: 'support@acme.com')],
  phones: const [ContactPhone(label: 'Phone', number: '800-555-0000')],
);

/// Compares the fields both formats carry. vCard stores line breaks as
/// `\n`, so [normalizeNewlines] compares notes with CRLF turned into LF.
void expectSameContact(Contact actual, Contact expected,
    {bool normalizeNewlines = false}) {
  expect(actual.firstName, expected.firstName);
  expect(actual.lastName, expected.lastName);
  expect(actual.company, expected.company);
  expect(actual.jobTitle, expected.jobTitle);
  expect(actual.emails.map((e) => e.address),
      expected.emails.map((e) => e.address));
  expect(
    actual.notes,
    normalizeNewlines
        ? expected.notes?.replaceAll('\r\n', '\n')
        : expected.notes,
  );
  final a = actual.address;
  final b = expected.address;
  if (b == null || b.isEmpty) {
    expect(a, isNull);
  } else {
    expect(a, isNotNull);
    expect(a!.street, b.street);
    expect(a.city, b.city);
    expect(a.state, b.state);
    expect(a.zipCode, b.zipCode);
    expect(a.country, b.country);
  }
}

void main() {
  group('CSV export', () {
    test('writes Outlook headers and CRLF rows', () {
      final csv = exportContactsCsv([bob]);
      expect(csv.endsWith('\r\n'), isTrue);
      final rows = csv.split('\r\n');
      expect(
        rows.first,
        'First Name,Last Name,Company,Job Title,E-mail Address,'
        'E-mail 2 Address,E-mail 3 Address,Business Phone,Home Phone,'
        'Mobile Phone,Business Street,Business City,Business State,'
        'Business Postal Code,Business Country/Region,Notes',
      );
      expect(rows[1], 'Bob,,,,bob@example.com,,,,,,,,,,,');
      expect(rows, hasLength(3));
      expect(outlookCsvHeaders, hasLength(16));
    });

    test('quotes fields with commas, quotes and line breaks', () {
      final csv = exportContactsCsv([jane]);
      expect(csv, contains('"Acme, Inc."'));
      expect(csv, contains('"Chief ""Everything"" Officer"'));
      expect(csv, contains('"1 Main St\nSuite 5"'));
      expect(
          csv,
          contains('"Met at the conference; likes ""quotes"", commas,\n'
              'and line breaks.\r\nSecond line — ünïcödé ✓"'));
      // Plain fields are not quoted.
      expect(csv, contains(',Springfield,IL,62701,USA,'));
    });

    test('maps phones to columns by label', () {
      final csv = exportContactsCsv([jane]);
      final row = csv.split('\r\n')[1];
      expect(row,
          contains('jane.doe@gmail.com,,+1 555 0101,+1 555 0102,+1 555 0100,'));
    });

    test('work/cell labels and other labels fill the first empty column', () {
      final c = contact(firstName: 'P', phones: const [
        ContactPhone(label: 'Other', number: '111'),
        ContactPhone(label: 'Cell', number: '222'),
        ContactPhone(label: 'Work', number: '333'),
        ContactPhone(label: 'Mobile', number: '444'),
        ContactPhone(label: 'Pager', number: '555'),
      ]);
      final row = exportContactsCsv([c]).split('\r\n')[1];
      // Work → Business, Cell → Mobile; Other fills Home; the rest is dropped.
      expect(row, 'P,,,,,,,333,111,222,,,,,,');
    });

    test('only the first three emails are written', () {
      final c = contact(firstName: 'E', emails: const [
        ContactEmail(label: 'Email', address: 'a@x.com'),
        ContactEmail(label: 'Email 2', address: 'b@x.com'),
        ContactEmail(label: 'Email 3', address: 'c@x.com'),
        ContactEmail(label: 'Email 4', address: 'd@x.com'),
      ]);
      final csv = exportContactsCsv([c]);
      expect(csv, contains('a@x.com,b@x.com,c@x.com,'));
      expect(csv.contains('d@x.com'), isFalse);
    });

    test('empty list gives only the header', () {
      expect(exportContactsCsv([]), '${outlookCsvHeaders.join(',')}\r\n');
    });
  });

  group('CSV import', () {
    test('round trip through Outlook CSV', () {
      final csv = exportContactsCsv([jane, bob, acme]);
      final imported = importContactsCsv(csv, idGenerator: ids(), now: now);
      // The company-only contact is kept because it has an email address.
      expect(imported, hasLength(3));
      expectSameContact(imported[0], jane);
      expectSameContact(imported[1], bob);
      expectSameContact(imported[2], acme);
      expect(imported[0].id, 'c1');
      expect(imported[2].id, 'c3');
      expect(imported[0].createdAt, now);
      expect(imported[0].updatedAt, now);
      expect(imported[0].emails.map((e) => e.label), ['Email', 'Email 2']);
      expect(
        imported[0].phones.map((p) => '${p.label}:${p.number}'),
        ['Business:+1 555 0101', 'Home:+1 555 0102', 'Mobile:+1 555 0100'],
      );
      // An unrecognized label is exported to Business Phone.
      expect(imported[2].phones.single.label, 'Business');
      expect(imported[1].address, isNull);
      expect(imported[1].phones, isEmpty);
      expect(imported[1].notes, isNull);
    });

    test('Google Contacts export', () {
      const csv = 'Name,Given Name,Additional Name,Family Name,Nickname,'
          'Birthday,Notes,Group Membership,E-mail 1 - Type,E-mail 1 - Value,'
          'E-mail 2 - Type,E-mail 2 - Value,Phone 1 - Type,Phone 1 - Value,'
          'Phone 2 - Type,Phone 2 - Value,Organization 1 - Type,'
          'Organization 1 - Name,Organization 1 - Title,Address 1 - Type,'
          'Address 1 - Formatted,Address 1 - Street,Address 1 - City,'
          'Address 1 - PO Box,Address 1 - Region,Address 1 - Postal Code,'
          'Address 1 - Country\r\n'
          'Maria Garcia,Maria,Luisa,Garcia,,,Loves "tapas",* myContacts,'
          '* Work,maria@work.es ::: maria@home.es,Home,maria.g@gmail.com,'
          'Mobile,+34 600 000 000,Work,+34 910 000 000 ::: +34 910 000 001,'
          ',Tapas SL,CEO,Work,"Calle Mayor 1, Madrid",Calle Mayor 1,Madrid,,'
          'Madrid,28013,Spain\r\n'
          'Only Name,,,,,,,,,,,,,,,,,,,,,,,,,,\r\n';
      final imported = importContactsCsv(csv, idGenerator: ids(), now: now);
      expect(imported, hasLength(2));
      final m = imported.first;
      expect(m.firstName, 'Maria Luisa');
      expect(m.lastName, 'Garcia');
      expect(m.company, 'Tapas SL');
      expect(m.jobTitle, 'CEO');
      expect(m.notes, 'Loves "tapas"');
      expect(m.emails.map((e) => e.address),
          ['maria@work.es', 'maria@home.es', 'maria.g@gmail.com']);
      expect(m.emails.map((e) => e.label), ['Email', 'Email 2', 'Email 3']);
      expect(m.phones.map((p) => '${p.label}:${p.number}'), [
        'Mobile:+34 600 000 000',
        'Business:+34 910 000 000',
        'Business:+34 910 000 001',
      ]);
      expect(m.address?.street, 'Calle Mayor 1');
      expect(m.address?.city, 'Madrid');
      expect(m.address?.state, 'Madrid');
      expect(m.address?.zipCode, '28013');
      expect(m.address?.country, 'Spain');
      // Only the Name column: split on the last space.
      expect(imported[1].firstName, 'Only');
      expect(imported[1].lastName, 'Name');
    });

    test('newer Google layout with First/Last Name and labels', () {
      const csv = 'First Name,Middle Name,Last Name,Organization Name,'
          'Organization Title,E-mail 1 - Label,E-mail 1 - Value,'
          'Phone 1 - Label,Phone 1 - Value\n'
          'Li,,Wei,Panda Co,Engineer,* Home,li@example.cn,Work Fax,12345\n';
      final c = importContactsCsv(csv).single;
      expect(c.firstName, 'Li');
      expect(c.lastName, 'Wei');
      expect(c.company, 'Panda Co');
      expect(c.jobTitle, 'Engineer');
      expect(c.primaryEmail, 'li@example.cn');
      expect(c.phones.single.label, 'Business Fax');
    });

    test('simple Name/Email/Phone headers', () {
      const csv = 'Name,Email,Phone\n'
          'Mary Ann Smith,mary@example.com,555-1234\n'
          'Prince,prince@example.com,\n'
          ',,555-9999\n'
          ',nobody@example.com,\n';
      final imported = importContactsCsv(csv);
      expect(imported, hasLength(3));
      expect(imported[0].firstName, 'Mary Ann');
      expect(imported[0].lastName, 'Smith');
      expect(imported[0].phones.single.label, 'Phone');
      expect(imported[0].phones.single.number, '555-1234');
      expect(imported[1].firstName, 'Prince');
      expect(imported[1].lastName, isNull);
      expect(imported[1].phones, isEmpty);
      // Email only: kept, displayed by its address.
      expect(imported[2].firstName, isNull);
      expect(imported[2].displayName, 'nobody@example.com');
    });

    test('headers are matched case-insensitively with extra spaces', () {
      const csv = ' FIRST  NAME ,last name,E-MAIL ADDRESS,mobile phone,'
          'Home Street,Home City\n'
          'Ann,Lee,ann@lee.org,0700,5 High St,Leeds\n';
      final c = importContactsCsv(csv).single;
      expect(c.firstName, 'Ann');
      expect(c.lastName, 'Lee');
      expect(c.primaryEmail, 'ann@lee.org');
      expect(c.phones.single.label, 'Mobile');
      expect(c.address?.street, '5 High St');
      expect(c.address?.city, 'Leeds');
    });

    test('byte order mark and LF line endings', () {
      const csv =
          '\uFEFFFirst Name,Last Name,E-mail Address\nZoë,Ångström,zoe@x.se\n';
      final c = importContactsCsv(csv).single;
      expect(c.firstName, 'Zoë');
      expect(c.lastName, 'Ångström');
    });

    test('quoted fields with embedded commas, quotes and newlines', () {
      const csv = 'First Name,Notes,E-mail Address\r\n'
          '"Smith, Jr.","He said ""hi"",\r\nthen left.\nThe end",j@x.com\r\n'
          'Plain,"",p@x.com';
      final imported = importContactsCsv(csv);
      expect(imported, hasLength(2));
      expect(imported[0].firstName, 'Smith, Jr.');
      expect(imported[0].notes, 'He said "hi",\r\nthen left.\nThe end');
      expect(imported[1].firstName, 'Plain');
      expect(imported[1].notes, isNull);
    });

    test('semicolon-separated files', () {
      const csv =
          'First Name;Last Name;E-mail Address\r\nHans;Müller;hans@x.de\r\n';
      final c = importContactsCsv(csv).single;
      expect(c.firstName, 'Hans');
      expect(c.lastName, 'Müller');
      expect(c.primaryEmail, 'hans@x.de');
    });

    test('rows with no name and no email are skipped', () {
      const csv = 'First Name,Company,Business Phone,E-mail Address\n'
          ',Lonely Corp,555,\n'
          ',,,\n'
          '\n'
          'Real,,,\n';
      final imported = importContactsCsv(csv);
      expect(imported.map((c) => c.firstName), ['Real']);
    });

    test('duplicate emails are removed and address only when present', () {
      const csv = 'Name,E-mail Address,E-mail 2 Address,Business City\n'
          'A B,a@x.com,A@X.com,\n';
      final c = importContactsCsv(csv).single;
      expect(c.emails.map((e) => e.address), ['a@x.com']);
      expect(c.address, isNull);
    });

    test('Outlook business address wins over home address', () {
      const csv = 'First Name,Home City,Business City,Business Street 2,'
          'Business Street\n'
          'X,Hometown,Worktown,Floor 3,1 Work Rd\n';
      final c = importContactsCsv(csv).single;
      expect(c.address?.city, 'Worktown');
      expect(c.address?.street, 'Floor 3\n1 Work Rd');
    });

    test('short rows and unknown columns are tolerated', () {
      const csv = 'First Name,Shoe Size,Last Name,E-mail Address\nOnly\n';
      final c = importContactsCsv(csv).single;
      expect(c.firstName, 'Only');
      expect(c.lastName, isNull);
    });

    test('malformed input never throws', () {
      expect(importContactsCsv(''), isEmpty);
      expect(importContactsCsv('\uFEFF'), isEmpty);
      expect(importContactsCsv('First Name,Last Name\n'), isEmpty);
      expect(importContactsCsv('just some text'), isEmpty);
      expect(
          importContactsCsv('Name\n"unterminated, quote\nmore'), hasLength(1));
      expect(importContactsCsv('"""\n,,,\n\r\r\n'), isEmpty);
      expect(
          importContactsCsv('Name,Email\nA,a@x.com',
              idGenerator: () => throw StateError('boom')),
          isEmpty);
    });
  });

  group('vCard export', () {
    test('writes vCard 3.0 properties with CRLF', () {
      final text = exportVCard([jane]);
      expect(text.endsWith('\r\n'), isTrue);
      final lines = text.replaceAll('\r\n ', '').split('\r\n')..removeLast();
      expect(lines.first, 'BEGIN:VCARD');
      expect(lines[1], 'VERSION:3.0');
      expect(lines.last, 'END:VCARD');
      expect(
          lines,
          containsAll([
            'N:Doe;Jane;;;',
            'FN:Jane Doe',
            r'ORG:Acme\, Inc.',
            'TITLE:Chief "Everything" Officer',
            'EMAIL;TYPE=INTERNET:jane@acme.com',
            'EMAIL;TYPE=INTERNET:jane.doe@gmail.com',
            'TEL;TYPE=CELL:+1 555 0100',
            'TEL;TYPE=WORK:+1 555 0101',
            'TEL;TYPE=HOME:+1 555 0102',
            r'ADR;TYPE=WORK:;;1 Main St\nSuite 5;Springfield;IL;62701;USA',
            r'NOTE:Met at the conference\; likes "quotes"\, commas\,\nand line '
                r'breaks.\nSecond line — ünïcödé ✓',
          ]));
    });

    test('folds long lines at 75 octets', () {
      final c = contact(firstName: 'Long', notes: 'ü' * 200);
      final text = exportVCard([c]);
      for (final line in text.split('\r\n')) {
        expect(utf8.encode(line).length, lessThanOrEqualTo(75));
      }
      expect(importVCard(text).single.notes, 'ü' * 200);
    });

    test('other phone labels', () {
      final c = contact(firstName: 'P', phones: const [
        ContactPhone(label: 'Phone', number: '1'),
        ContactPhone(label: 'Business Fax', number: '2'),
        ContactPhone(label: 'Pager', number: '3'),
      ]);
      final text = exportVCard([c]);
      expect(text, contains('TEL;TYPE=VOICE:1'));
      expect(text, contains('TEL;TYPE=WORK,FAX:2'));
      expect(text, contains('TEL;TYPE=PAGER:3'));
    });

    test('several cards', () {
      final text = exportVCard([jane, bob, acme]);
      expect('BEGIN:VCARD'.allMatches(text), hasLength(3));
      expect('END:VCARD'.allMatches(text), hasLength(3));
    });
  });

  group('vCard import', () {
    test('round trip', () {
      final imported = importVCard(exportVCard([jane, bob, acme]),
          idGenerator: ids(), now: now);
      expect(imported, hasLength(3));
      expectSameContact(imported[0], jane, normalizeNewlines: true);
      expectSameContact(imported[1], bob);
      expectSameContact(imported[2], acme);
      expect(imported[0].notes, contains('line breaks.\nSecond line'));
      expect(imported.map((c) => c.id), ['c1', 'c2', 'c3']);
      expect(imported[0].createdAt, now);
      expect(
        imported[0].phones.map((p) => '${p.label}:${p.number}'),
        ['Mobile:+1 555 0100', 'Business:+1 555 0101', 'Home:+1 555 0102'],
      );
      expect(imported[2].phones.single.label, 'Phone');
      expect(imported[2].company, 'Acme Support');
      expect(imported[2].firstName, isNull);
    });

    test('multiple cards of different versions', () {
      const text = 'BEGIN:VCARD\r\n'
          'VERSION:2.1\r\n'
          'N;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:M=C3=BCller;J=C3=BCrgen;;;\r\n'
          'FN:J=C3=BCrgen M=C3=BCller\r\n'
          'TEL;CELL;VOICE:+49 170 1234567\r\n'
          'TEL;WORK:+49 30 1234\r\n'
          'EMAIL;INTERNET;PREF:juergen@example.de\r\n'
          'NOTE;ENCODING=QUOTED-PRINTABLE:Erste Zeile=0D=0AZweite Zeile, sehr lang=\r\n'
          'e Notiz\r\n'
          'END:VCARD\r\n'
          'BEGIN:VCARD\r\n'
          'VERSION:3.0\r\n'
          'PRODID:-//Apple Inc.//macOS 14.0//EN\r\n'
          'N:Appleseed;Johnny;;Mr.;\r\n'
          'FN:Mr. Johnny Appleseed\r\n'
          'ORG:Apple Inc.;Engineering;\r\n'
          'TITLE:Engineer\r\n'
          'item1.EMAIL;type=INTERNET;type=HOME:johnny@me.com\r\n'
          'item2.EMAIL;type=INTERNET;type=WORK;type=pref:johnny@apple.com\r\n'
          'TEL;type=CELL;type=VOICE;type=pref:(408) 555-0199\r\n'
          'TEL;type=HOME;type=VOICE:(408) 555-0100\r\n'
          'item3.ADR;type=HOME;type=pref:;;1 Infinite Loop;Cupertino;CA;95014;USA\r\n'
          'item3.X-ABADR:us\r\n'
          'NOTE:Line one\\nLine two with \\, comma\r\n'
          'END:VCARD\r\n'
          'BEGIN:VCARD\r\n'
          'VERSION:4.0\r\n'
          'FN:Ada Lovelace\r\n'
          'EMAIL;TYPE=work:ada@example.org\r\n'
          'TEL;VALUE=uri;TYPE="voice,cell":tel:+44-20-7946-0000\r\n'
          'TEL;VALUE=uri;TYPE=work:tel:+44-20-7946-0001\r\n'
          'ADR;TYPE=home:;;12 St James Sq;London;;SW1Y 4JH;UK\r\n'
          'ADR;TYPE=work:;;Analytical Engine Ltd;London;;EC1A;UK\r\n'
          'END:VCARD\r\n';
      final imported = importVCard(text);
      expect(imported, hasLength(3));

      final j = imported[0];
      expect(j.firstName, 'Jürgen');
      expect(j.lastName, 'Müller');
      expect(j.primaryEmail, 'juergen@example.de');
      expect(j.phones.map((p) => '${p.label}:${p.number}'),
          ['Mobile:+49 170 1234567', 'Business:+49 30 1234']);
      expect(j.notes, 'Erste Zeile\r\nZweite Zeile, sehr lange Notiz');

      final a = imported[1];
      expect(a.firstName, 'Johnny');
      expect(a.lastName, 'Appleseed');
      expect(a.company, 'Apple Inc.');
      expect(a.jobTitle, 'Engineer');
      // The preferred address comes first.
      expect(a.emails.map((e) => e.address),
          ['johnny@apple.com', 'johnny@me.com']);
      expect(a.emails.map((e) => e.label), ['Email', 'Email 2']);
      expect(a.phones.map((p) => p.label), ['Mobile', 'Home']);
      expect(a.address?.street, '1 Infinite Loop');
      expect(a.address?.city, 'Cupertino');
      expect(a.address?.zipCode, '95014');
      expect(a.notes, 'Line one\nLine two with , comma');

      final ada = imported[2];
      expect(ada.firstName, 'Ada');
      expect(ada.lastName, 'Lovelace');
      expect(ada.primaryEmail, 'ada@example.org');
      expect(ada.phones.map((p) => '${p.label}:${p.number}'),
          ['Mobile:+44-20-7946-0000', 'Business:+44-20-7946-0001']);
      // The work address is preferred.
      expect(ada.address?.street, 'Analytical Engine Ltd');
    });

    test('folded lines with LF endings and tabs', () {
      const text =
          'BEGIN:VCARD\nVERSION:3.0\nN:Lang;Anna\nNOTE:This note is fo\n'
          ' lded over\n\t three lines\nEND:VCARD\n';
      final c = importVCard(text).single;
      expect(c.firstName, 'Anna');
      expect(c.lastName, 'Lang');
      expect(c.notes, 'This note is folded over three lines');
    });

    test('FN is used when N is missing; company cards keep no name', () {
      const text = 'BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Grace Brewster Hopper\r\n'
          'END:VCARD\r\n'
          'BEGIN:VCARD\r\nVERSION:3.0\r\nN:;;;;\r\nFN:Initech\r\nORG:Initech\r\n'
          'TEL:555\r\nEND:VCARD\r\n';
      final imported = importVCard(text);
      expect(imported, hasLength(2));
      expect(imported[0].firstName, 'Grace Brewster');
      expect(imported[0].lastName, 'Hopper');
      expect(imported[1].firstName, isNull);
      expect(imported[1].lastName, isNull);
      expect(imported[1].company, 'Initech');
      expect(imported[1].displayName, 'Initech');
    });

    test('escaped separators inside N and ADR components', () {
      const text = 'BEGIN:VCARD\r\nVERSION:3.0\r\n'
          r'N:O\;Brien;Pat\, Jr.;;;'
          '\r\n'
          r'ADR:;;Unit 4\; Block B;Dublin;;;Ireland'
          '\r\n'
          'END:VCARD\r\n';
      final c = importVCard(text).single;
      expect(c.lastName, 'O;Brien');
      expect(c.firstName, 'Pat, Jr.');
      expect(c.address?.street, 'Unit 4; Block B');
      expect(c.address?.country, 'Ireland');
    });

    test('empty cards are skipped; malformed input never throws', () {
      expect(importVCard(''), isEmpty);
      expect(importVCard('garbage\nmore garbage'), isEmpty);
      expect(
          importVCard('BEGIN:VCARD\r\nVERSION:3.0\r\nEND:VCARD\r\n'), isEmpty);
      expect(importVCard('BEGIN:VCARD\r\nFN:No end'), isEmpty);
      expect(importVCard('END:VCARD\r\nBEGIN:VCARD\r\nFN:A B\r\nEND:VCARD'),
          hasLength(1));
      expect(
          importVCard('BEGIN:VCARD\r\nN;X="unterminated:Doe;John\r\n'
              'EMAIL:j@x.com\r\nNOTE;ENCODING=QUOTED-PRINTABLE:bad=ZZ=\r\n'
              'END:VCARD'),
          hasLength(1));
      expect(
          importVCard('BEGIN:VCARD\r\nFN:A B\r\nEND:VCARD',
              idGenerator: () => throw StateError('boom')),
          isEmpty);
    });
  });
}
