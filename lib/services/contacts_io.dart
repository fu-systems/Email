import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/contact.dart';

// Contact import and export in CSV (Outlook / Google / simple layouts) and
// vCard formats. Every function is pure; importers never throw and skip
// records they cannot use.

/// The Outlook CSV column headers written by [exportContactsCsv].
const List<String> outlookCsvHeaders = [
  'First Name',
  'Last Name',
  'Company',
  'Job Title',
  'E-mail Address',
  'E-mail 2 Address',
  'E-mail 3 Address',
  'Business Phone',
  'Home Phone',
  'Mobile Phone',
  'Business Street',
  'Business City',
  'Business State',
  'Business Postal Code',
  'Business Country/Region',
  'Notes',
];

// ─── CSV export ──────────────────────────────────────────────────────

/// Serializes [contacts] as RFC 4180 CSV with Outlook's column headers
/// ([outlookCsvHeaders]).
///
/// Fields containing a comma, quote, CR or LF are quoted, with embedded
/// quotes doubled; rows end with CRLF. Only the first three email addresses
/// are written. Phones go to a column by label: Business/Work/Office →
/// Business Phone, Home → Home Phone, Mobile/Cell → Mobile Phone. Other
/// labels, and phones whose column is already taken, fill the first empty
/// phone column; phones that do not fit are dropped.
String exportContactsCsv(List<Contact> contacts) {
  final rows = <List<String>>[outlookCsvHeaders];
  for (final contact in contacts) {
    final phones = _assignPhoneColumns(contact.phones);
    final address = contact.address;
    String email(int i) =>
        i < contact.emails.length ? contact.emails[i].address : '';
    rows.add([
      contact.firstName ?? '',
      contact.lastName ?? '',
      contact.company ?? '',
      contact.jobTitle ?? '',
      email(0),
      email(1),
      email(2),
      ...phones,
      address?.street ?? '',
      address?.city ?? '',
      address?.state ?? '',
      address?.zipCode ?? '',
      address?.country ?? '',
      contact.notes ?? '',
    ]);
  }
  final buffer = StringBuffer();
  for (final row in rows) {
    buffer
      ..write(row.map(_csvField).join(','))
      ..write('\r\n');
  }
  return buffer.toString();
}

String _csvField(String value) {
  if (value.contains(RegExp('[,"\r\n]'))) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// Business, Home and Mobile phone column values for [phones].
List<String> _assignPhoneColumns(List<ContactPhone> phones) {
  final columns = List<String>.filled(3, '');
  final leftovers = <String>[];
  for (final phone in phones) {
    final number = phone.number.trim();
    if (number.isEmpty) continue;
    final column = _phoneColumn(phone.label);
    if (column != null && columns[column].isEmpty) {
      columns[column] = number;
    } else {
      leftovers.add(number);
    }
  }
  for (final number in leftovers) {
    final free = columns.indexWhere((c) => c.isEmpty);
    if (free < 0) break;
    columns[free] = number;
  }
  return columns;
}

int? _phoneColumn(String label) {
  final l = label.trim().toLowerCase();
  if (l.contains('fax') || l.contains('pager')) return null;
  if (l.contains('business') || l.contains('work') || l.contains('office')) {
    return 0;
  }
  if (l.contains('home')) return 1;
  if (l.contains('mobile') || l.contains('cell')) return 2;
  return null;
}

// ─── CSV import ──────────────────────────────────────────────────────

/// Parses contacts from CSV text.
///
/// The first non-empty row is the header. Headers are matched
/// case-insensitively and accept Outlook exports ("First Name",
/// "E-mail 2 Address", "Business Phone", "Business Street", ...), Google
/// exports ("Given Name", "Family Name", "E-mail 1 - Value",
/// "Phone 1 - Value" with "Phone 1 - Type", "Organization 1 - Name",
/// "Address 1 - Street", ...) and simple layouts ("Name", "Email",
/// "Phone"). A single "Name" column is split into first and last name at
/// the last space. Unknown columns are ignored.
///
/// The parser accepts quoted fields with embedded commas, quotes and line
/// breaks, a UTF-8 byte order mark, CRLF, LF or CR line endings, and a
/// semicolon or tab delimiter when the header row has no commas.
///
/// Rows with neither a name nor an email address are skipped. Emails are
/// labelled 'Email', 'Email 2', 'Email 3', ...; phones from the Outlook
/// columns are labelled 'Business', 'Home' and 'Mobile', and a generic
/// "Phone" column is labelled 'Phone'. An address is set only when one of
/// its fields is non-empty. New contacts get ids from [idGenerator]
/// (default: UUID v4) and [now] (default: the current time) as timestamps.
List<Contact> importContactsCsv(
  String csvText, {
  String Function()? idGenerator,
  DateTime? now,
}) {
  try {
    final nextId = idGenerator ?? const Uuid().v4;
    final timestamp = now ?? DateTime.now();
    var text = csvText;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final rows = _parseCsv(text, _detectDelimiter(text))
        .where((r) => r.any((f) => f.trim().isNotEmpty))
        .toList();
    if (rows.isEmpty) return <Contact>[];
    final columns = rows.first.map(_classifyHeader).toList();
    final contacts = <Contact>[];
    for (final row in rows.skip(1)) {
      try {
        final contact = _contactFromCsvRow(row, columns, nextId, timestamp);
        if (contact != null) contacts.add(contact);
      } catch (_) {
        // Skip malformed rows.
      }
    }
    return contacts;
  } catch (_) {
    return <Contact>[];
  }
}

String _detectDelimiter(String text) {
  final newline = text.indexOf(RegExp('[\r\n]'));
  final header = newline < 0 ? text : text.substring(0, newline);
  if (header.contains(',')) return ',';
  if (header.contains(';')) return ';';
  if (header.contains('\t')) return '\t';
  return ',';
}

List<List<String>> _parseCsv(String text, String delimiter) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var fieldQuoted = false;

  void endField() {
    row.add(field.toString());
    field.clear();
    fieldQuoted = false;
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
      continue;
    }
    if (ch == '"' && field.isEmpty && !fieldQuoted) {
      inQuotes = true;
      fieldQuoted = true;
    } else if (ch == delimiter) {
      endField();
    } else if (ch == '\r') {
      if (i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else if (ch == '\n') {
      endRow();
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty || fieldQuoted) endRow();
  return rows;
}

enum _CsvField {
  first,
  middle,
  last,
  fullName,
  company,
  jobTitle,
  email,
  phone,
  googlePhoneValue,
  googlePhoneType,
  notes,
  street,
  city,
  state,
  zip,
  country,
  ignore,
}

class _CsvColumn {
  final _CsvField field;

  /// Phone label, address group, or Google item number, depending on field.
  final String key;

  const _CsvColumn(this.field, [this.key = '']);
}

const _ignoredColumn = _CsvColumn(_CsvField.ignore);

_CsvColumn _classifyHeader(String raw) {
  final h = raw
      .replaceAll('\uFEFF', '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
  if (h.isEmpty) return _ignoredColumn;

  const exact = <String, _CsvField>{
    'first name': _CsvField.first,
    'firstname': _CsvField.first,
    'given name': _CsvField.first,
    'first': _CsvField.first,
    'forename': _CsvField.first,
    'middle name': _CsvField.middle,
    'additional name': _CsvField.middle,
    'last name': _CsvField.last,
    'lastname': _CsvField.last,
    'family name': _CsvField.last,
    'surname': _CsvField.last,
    'last': _CsvField.last,
    'name': _CsvField.fullName,
    'full name': _CsvField.fullName,
    'fullname': _CsvField.fullName,
    'display name': _CsvField.fullName,
    'contact name': _CsvField.fullName,
    'company': _CsvField.company,
    'company name': _CsvField.company,
    'organization': _CsvField.company,
    'organisation': _CsvField.company,
    'organization name': _CsvField.company,
    'job title': _CsvField.jobTitle,
    'jobtitle': _CsvField.jobTitle,
    'position': _CsvField.jobTitle,
    'organization title': _CsvField.jobTitle,
    'notes': _CsvField.notes,
    'note': _CsvField.notes,
    'comments': _CsvField.notes,
  };
  final direct = exact[h];
  if (direct != null) return _CsvColumn(direct);

  if (RegExp(r'^organi[sz]ation \d+ - name$').hasMatch(h)) {
    return const _CsvColumn(_CsvField.company);
  }
  if (RegExp(r'^organi[sz]ation \d+ - title$').hasMatch(h)) {
    return const _CsvColumn(_CsvField.jobTitle);
  }
  if (RegExp(r'^e-?mail(?: \d+)?(?: address)?(?: \d+)?$').hasMatch(h) ||
      RegExp(r'^e-?mail \d+ - value$').hasMatch(h) ||
      h == 'primary email') {
    return const _CsvColumn(_CsvField.email);
  }

  final googlePhone =
      RegExp(r'^phone (\d+) - (value|type|label)$').firstMatch(h);
  if (googlePhone != null) {
    return _CsvColumn(
      googlePhone.group(2) == 'value'
          ? _CsvField.googlePhoneValue
          : _CsvField.googlePhoneType,
      googlePhone.group(1)!,
    );
  }
  const simplePhones = <String, String>{
    'phone': 'Phone',
    'telephone': 'Phone',
    'phone number': 'Phone',
    'tel': 'Phone',
    'primary phone': 'Phone',
    'mobile': 'Mobile',
    'cell': 'Mobile',
    'mobile number': 'Mobile',
  };
  final simplePhone = simplePhones[h];
  if (simplePhone != null) return _CsvColumn(_CsvField.phone, simplePhone);
  final phone = RegExp(r"^([a-z' ]*?) ?(phone|fax)(?: \d+)?$").firstMatch(h);
  if (phone != null) {
    final prefix = phone.group(1)!.trim();
    final isFax = phone.group(2) == 'fax';
    String label;
    if (prefix.isEmpty) {
      label = isFax ? 'Fax' : 'Phone';
    } else if (prefix == 'business' || prefix == 'work') {
      label = isFax ? 'Business Fax' : 'Business';
    } else if (prefix == 'home') {
      label = isFax ? 'Home Fax' : 'Home';
    } else if (prefix == 'mobile' || prefix == 'cell') {
      label = 'Mobile';
    } else {
      label = _titleCase(prefix) + (isFax ? ' Fax' : '');
    }
    return _CsvColumn(_CsvField.phone, label);
  }
  if (h == 'pager') return const _CsvColumn(_CsvField.phone, 'Pager');

  final outlookAddress = RegExp(
          r'^(business|home|other) (street(?: \d)?|city|state|postal code|country/region|country|po box)$')
      .firstMatch(h);
  if (outlookAddress != null) {
    final field = _addressField(outlookAddress.group(2)!);
    if (field != null) return _CsvColumn(field, outlookAddress.group(1)!);
  }
  final googleAddress = RegExp(
          r'^address (\d+) - (street|city|region|postal code|country|po box)$')
      .firstMatch(h);
  if (googleAddress != null) {
    final field = _addressField(googleAddress.group(2)!);
    if (field != null) {
      return _CsvColumn(field, 'google${googleAddress.group(1)}');
    }
  }
  const simpleAddress = <String, _CsvField>{
    'street': _CsvField.street,
    'street address': _CsvField.street,
    'address': _CsvField.street,
    'city': _CsvField.city,
    'town': _CsvField.city,
    'state': _CsvField.state,
    'province': _CsvField.state,
    'region': _CsvField.state,
    'zip': _CsvField.zip,
    'zip code': _CsvField.zip,
    'postal code': _CsvField.zip,
    'postcode': _CsvField.zip,
    'country': _CsvField.country,
    'country/region': _CsvField.country,
  };
  final simple = simpleAddress[h];
  if (simple != null) return _CsvColumn(simple, 'simple');
  return _ignoredColumn;
}

_CsvField? _addressField(String part) {
  if (part.startsWith('street') || part == 'po box') return _CsvField.street;
  switch (part) {
    case 'city':
      return _CsvField.city;
    case 'state':
    case 'region':
      return _CsvField.state;
    case 'postal code':
      return _CsvField.zip;
    case 'country':
    case 'country/region':
      return _CsvField.country;
  }
  return null;
}

String _titleCase(String s) => s
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

Contact? _contactFromCsvRow(
  List<String> row,
  List<_CsvColumn> columns,
  String Function() nextId,
  DateTime now,
) {
  String? first;
  String? middle;
  String? last;
  String? fullName;
  String? company;
  String? jobTitle;
  String? notes;
  final emails = <String>[];
  final phones = <ContactPhone>[];
  final googlePhones = <String, String>{};
  final googlePhoneTypes = <String, String>{};
  final addressGroups = <String, Map<_CsvField, List<String>>>{};

  for (var i = 0; i < columns.length && i < row.length; i++) {
    final column = columns[i];
    final value = row[i].trim();
    if (value.isEmpty) continue;
    switch (column.field) {
      case _CsvField.first:
        first ??= value;
      case _CsvField.middle:
        middle ??= value;
      case _CsvField.last:
        last ??= value;
      case _CsvField.fullName:
        fullName ??= value;
      case _CsvField.company:
        company ??= value;
      case _CsvField.jobTitle:
        jobTitle ??= value;
      case _CsvField.notes:
        notes ??= row[i];
      case _CsvField.email:
        for (final part in value.split(':::')) {
          final address = part.trim();
          if (address.isNotEmpty &&
              !emails.any((e) => e.toLowerCase() == address.toLowerCase())) {
            emails.add(address);
          }
        }
      case _CsvField.phone:
        phones.add(ContactPhone(label: column.key, number: value));
      case _CsvField.googlePhoneValue:
        googlePhones[column.key] = value;
      case _CsvField.googlePhoneType:
        googlePhoneTypes[column.key] = value;
      case _CsvField.street:
      case _CsvField.city:
      case _CsvField.state:
      case _CsvField.zip:
      case _CsvField.country:
        addressGroups
            .putIfAbsent(column.key, () => {})
            .putIfAbsent(column.field, () => [])
            .add(value);
      case _CsvField.ignore:
        break;
    }
  }

  final googleKeys = googlePhones.keys.toList()
    ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
  for (final key in googleKeys) {
    final label = _labelForPhoneType(googlePhoneTypes[key]);
    for (final part in googlePhones[key]!.split(':::')) {
      final number = part.trim();
      if (number.isNotEmpty) {
        phones.add(ContactPhone(label: label, number: number));
      }
    }
  }

  if (first == null && last == null && fullName != null) {
    final split = _splitName(fullName);
    first = split.$1;
    last = split.$2;
  }
  if (first != null && middle != null) first = '$first $middle';
  if (first == null && last == null && emails.isEmpty) return null;

  return Contact(
    id: nextId(),
    firstName: first,
    lastName: last,
    company: company,
    jobTitle: jobTitle,
    emails: _labelEmails(emails),
    phones: phones,
    address: _pickAddress(addressGroups),
    notes: notes == null || notes.trim().isEmpty ? null : notes,
    createdAt: now,
    updatedAt: now,
  );
}

String _labelForPhoneType(String? type) {
  final t = (type ?? '').replaceAll('*', '').trim().toLowerCase();
  if (t.isEmpty) return 'Phone';
  if (t.contains('fax')) {
    if (t.contains('work') || t.contains('business')) return 'Business Fax';
    if (t.contains('home')) return 'Home Fax';
    return 'Fax';
  }
  if (t.contains('mobile') || t.contains('cell')) return 'Mobile';
  if (t.contains('work') || t.contains('business')) return 'Business';
  if (t.contains('home')) return 'Home';
  if (t == 'main' || t == 'other') return 'Phone';
  return _titleCase(t);
}

/// Splits "Mary Ann Smith" into ("Mary Ann", "Smith").
(String?, String?) _splitName(String name) {
  final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (n.isEmpty) return (null, null);
  final space = n.lastIndexOf(' ');
  if (space < 0) return (n, null);
  return (n.substring(0, space), n.substring(space + 1));
}

List<ContactEmail> _labelEmails(List<String> addresses) => [
      for (var i = 0; i < addresses.length; i++)
        ContactEmail(
          label: i == 0 ? 'Email' : 'Email ${i + 1}',
          address: addresses[i],
        ),
    ];

ContactAddress? _pickAddress(Map<String, Map<_CsvField, List<String>>> groups) {
  final googleKeys = groups.keys.where((k) => k.startsWith('google')).toList()
    ..sort();
  final order = ['business', 'simple', ...googleKeys, 'home', 'other'];
  for (final key in order) {
    final group = groups[key];
    if (group == null || group.isEmpty) continue;
    String? part(_CsvField f) {
      final values = group[f];
      return values == null || values.isEmpty ? null : values.join('\n');
    }

    final address = ContactAddress(
      street: part(_CsvField.street),
      city: part(_CsvField.city),
      state: part(_CsvField.state),
      zipCode: part(_CsvField.zip),
      country: part(_CsvField.country),
    );
    if (!address.isEmpty) return address;
  }
  return null;
}

// ─── vCard export ────────────────────────────────────────────────────

/// Serializes [contacts] as vCard 3.0 (RFC 2426), one card per contact.
///
/// Writes N, FN, ORG, TITLE, EMAIL;TYPE=INTERNET, TEL (TYPE=WORK, HOME,
/// CELL, FAX, PAGER or VOICE from the phone label), ADR;TYPE=WORK and NOTE.
/// Text is escaped, lines end with CRLF and are folded at 75 octets.
String exportVCard(List<Contact> contacts) {
  final lines = <String>[];
  for (final c in contacts) {
    lines
      ..add('BEGIN:VCARD')
      ..add('VERSION:3.0')
      ..add('N:${_vEscape(c.lastName ?? '')};${_vEscape(c.firstName ?? '')};;;')
      ..add('FN:${_vEscape(c.displayName)}');
    final company = c.company?.trim() ?? '';
    if (company.isNotEmpty) lines.add('ORG:${_vEscape(company)}');
    final title = c.jobTitle?.trim() ?? '';
    if (title.isNotEmpty) lines.add('TITLE:${_vEscape(title)}');
    for (final email in c.emails) {
      final address = email.address.trim();
      if (address.isEmpty) continue;
      lines.add('EMAIL;TYPE=INTERNET:${_vEscape(address)}');
    }
    for (final phone in c.phones) {
      final number = phone.number.trim();
      if (number.isEmpty) continue;
      lines.add('TEL;TYPE=${_telTypes(phone.label)}:${_vEscape(number)}');
    }
    final a = c.address;
    if (a != null && !a.isEmpty) {
      final parts = [
        '',
        '',
        a.street ?? '',
        a.city ?? '',
        a.state ?? '',
        a.zipCode ?? '',
        a.country ?? '',
      ];
      lines.add('ADR;TYPE=WORK:${parts.map(_vEscape).join(';')}');
    }
    final notes = c.notes ?? '';
    if (notes.trim().isNotEmpty) lines.add('NOTE:${_vEscape(notes)}');
    lines.add('END:VCARD');
  }
  return lines.map(_foldLine).map((l) => '$l\r\n').join();
}

String _telTypes(String label) {
  final l = label.toLowerCase();
  final types = <String>[];
  if (l.contains('business') || l.contains('work') || l.contains('office')) {
    types.add('WORK');
  }
  if (l.contains('home')) types.add('HOME');
  if (l.contains('mobile') || l.contains('cell')) types.add('CELL');
  if (l.contains('fax')) types.add('FAX');
  if (l.contains('pager')) types.add('PAGER');
  if (types.isEmpty) types.add('VOICE');
  return types.join(',');
}

String _vEscape(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll('\r\n', r'\n')
    .replaceAll('\r', r'\n')
    .replaceAll('\n', r'\n');

String _foldLine(String line) {
  if (utf8.encode(line).length <= 75) return line;
  final out = StringBuffer();
  var used = 0;
  for (final rune in line.runes) {
    final size = rune < 0x80
        ? 1
        : rune < 0x800
            ? 2
            : rune < 0x10000
                ? 3
                : 4;
    if (used + size > 75) {
      out.write('\r\n ');
      used = 1;
    }
    out.writeCharCode(rune);
    used += size;
  }
  return out.toString();
}

// ─── vCard import ────────────────────────────────────────────────────

/// Parses every card in vCard text (versions 2.1, 3.0 and 4.0).
///
/// Supports folded lines, several cards per file, grouped property names
/// (`item1.EMAIL`), type parameters written as `TYPE=CELL`, `TYPE=work,voice`,
/// `TYPE="work,voice"` or bare `CELL` (2.1), `tel:`/`mailto:` URIs (4.0),
/// and quoted-printable values (2.1, UTF-8 or ISO-8859-1).
///
/// N gives the first and last name (the middle name is appended to the first
/// name). Without N, FN is split at the last space unless it just repeats
/// ORG. The first ORG component is the company. Emails are labelled like
/// [importContactsCsv] ('Email', 'Email 2', ...; a PREF email comes first).
/// Phones are labelled 'Mobile' (CELL), 'Business' (WORK), 'Home', 'Fax',
/// 'Pager' or 'Phone'. The first work ADR, else the first ADR, is the
/// address. Cards without a name, email, company or phone are skipped.
List<Contact> importVCard(
  String text, {
  String Function()? idGenerator,
  DateTime? now,
}) {
  try {
    final nextId = idGenerator ?? const Uuid().v4;
    final timestamp = now ?? DateTime.now();
    final contacts = <Contact>[];
    List<_VProperty>? current;
    for (final line in _vcardLines(text)) {
      final prop = _parseVLine(line);
      if (prop == null) continue;
      if (prop.name == 'BEGIN' && prop.value.trim().toUpperCase() == 'VCARD') {
        current = <_VProperty>[];
      } else if (prop.name == 'END' &&
          prop.value.trim().toUpperCase() == 'VCARD') {
        if (current != null) {
          try {
            final contact = _contactFromVCard(current, nextId, timestamp);
            if (contact != null) contacts.add(contact);
          } catch (_) {
            // Skip malformed cards.
          }
        }
        current = null;
      } else {
        current?.add(prop);
      }
    }
    return contacts;
  } catch (_) {
    return <Contact>[];
  }
}

List<String> _vcardLines(String text) {
  var t = text;
  if (t.startsWith('\uFEFF')) t = t.substring(1);
  t = t.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final out = <String>[];
  for (final line in t.split('\n')) {
    final upper = line.trim().toUpperCase();
    final isCardBoundary =
        upper == 'END:VCARD' || upper.startsWith('BEGIN:VCARD');
    if (out.isNotEmpty && !isCardBoundary && _isSoftBreak(out.last)) {
      out[out.length - 1] =
          out.last.substring(0, out.last.length - 1) + line.trimLeft();
    } else if (out.isNotEmpty &&
        (line.startsWith(' ') || line.startsWith('\t'))) {
      out[out.length - 1] = out.last + line.substring(1);
    } else {
      out.add(line);
    }
  }
  return out;
}

/// Whether [line] is a quoted-printable value ending in a soft line break.
bool _isSoftBreak(String line) {
  if (!line.endsWith('=')) return false;
  final colon = line.indexOf(':');
  return colon > 0 &&
      line.substring(0, colon).toUpperCase().contains('QUOTED-PRINTABLE');
}

class _VProperty {
  final String name;
  final Set<String> types;
  final Map<String, String> params;
  final String value;

  const _VProperty(this.name, this.types, this.params, this.value);
}

_VProperty? _parseVLine(String line) {
  final n = line.length;
  var i = 0;
  while (i < n && line[i] != ';' && line[i] != ':') {
    i++;
  }
  if (i >= n) return null;
  var name = line.substring(0, i).trim().toUpperCase();
  final dot = name.lastIndexOf('.');
  if (dot >= 0) name = name.substring(dot + 1);
  if (name.isEmpty) return null;
  final types = <String>{};
  final params = <String, String>{};
  while (i < n && line[i] == ';') {
    i++;
    final start = i;
    while (i < n && line[i] != '=' && line[i] != ';' && line[i] != ':') {
      i++;
    }
    final paramName = line.substring(start, i).trim().toUpperCase();
    final values = <String>[];
    if (i < n && line[i] == '=') {
      i++;
      while (true) {
        if (i < n && line[i] == '"') {
          final close = line.indexOf('"', i + 1);
          if (close < 0) return null;
          values.add(line.substring(i + 1, close));
          i = close + 1;
          while (i < n && line[i] != ',' && line[i] != ';' && line[i] != ':') {
            i++;
          }
        } else {
          final start = i;
          while (i < n && line[i] != ',' && line[i] != ';' && line[i] != ':') {
            i++;
          }
          values.add(line.substring(start, i));
        }
        if (i < n && line[i] == ',') {
          i++;
          continue;
        }
        break;
      }
      if (paramName == 'TYPE') {
        for (final v in values) {
          types.addAll(v
              .split(',')
              .map((t) => t.trim().toUpperCase())
              .where((t) => t.isNotEmpty));
        }
      } else if (paramName.isNotEmpty) {
        params[paramName] = values.join(',');
      }
    } else if (paramName.isNotEmpty) {
      // vCard 2.1 bare parameter, e.g. TEL;CELL or NOTE;QUOTED-PRINTABLE.
      if (paramName == 'QUOTED-PRINTABLE' || paramName == 'BASE64') {
        params['ENCODING'] = paramName;
      } else {
        types.add(paramName);
      }
    }
  }
  if (i >= n || line[i] != ':') return null;
  var value = line.substring(i + 1);
  if (params['ENCODING']?.toUpperCase() == 'QUOTED-PRINTABLE') {
    value = _decodeQuotedPrintable(value, params['CHARSET']);
  }
  return _VProperty(name, types, params, value);
}

String _decodeQuotedPrintable(String input, String? charset) {
  final bytes = <int>[];
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (ch == '=' && i + 2 < input.length) {
      final code = int.tryParse(input.substring(i + 1, i + 3), radix: 16);
      if (code != null) {
        bytes.add(code);
        i += 2;
        continue;
      }
    }
    if (ch == '=' && i == input.length - 1) continue;
    bytes.addAll(utf8.encode(ch));
  }
  final cs = (charset ?? 'utf-8').toLowerCase();
  if (cs.contains('8859') || cs.contains('latin') || cs.contains('1252')) {
    return latin1.decode(bytes, allowInvalid: true);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// Splits [value] on [separator] characters that are not backslash-escaped.
List<String> _splitUnescaped(String value, String separator) {
  final parts = <String>[];
  final current = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final ch = value[i];
    if (ch == r'\' && i + 1 < value.length) {
      current
        ..write(ch)
        ..write(value[i + 1]);
      i++;
    } else if (ch == separator) {
      parts.add(current.toString());
      current.clear();
    } else {
      current.write(ch);
    }
  }
  parts.add(current.toString());
  return parts;
}

String _vUnescape(String s) {
  if (!s.contains(r'\')) return s;
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == r'\' && i + 1 < s.length) {
      final next = s[i + 1];
      b.write(next == 'n' || next == 'N' ? '\n' : next);
      i++;
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

String? _clean(String? s) {
  if (s == null) return null;
  final t = s.trim();
  return t.isEmpty ? null : t;
}

Contact? _contactFromVCard(
  List<_VProperty> props,
  String Function() nextId,
  DateTime now,
) {
  _VProperty? first(String name) {
    for (final p in props) {
      if (p.name == name) return p;
    }
    return null;
  }

  String? firstName;
  String? lastName;
  final n = first('N');
  if (n != null) {
    final parts = _splitUnescaped(n.value, ';').map(_vUnescape).toList();
    String? part(int i) => i < parts.length ? _clean(parts[i]) : null;
    lastName = part(0);
    firstName = part(1);
    final middle = part(2);
    if (firstName != null && middle != null) firstName = '$firstName $middle';
  }

  String? company;
  final org = first('ORG');
  if (org != null) {
    company = _clean(_vUnescape(_splitUnescaped(org.value, ';').first));
  }

  if (firstName == null && lastName == null) {
    final fn = _clean(_vUnescape(first('FN')?.value ?? ''));
    if (fn != null && fn != company) {
      final split = _splitName(fn);
      firstName = split.$1;
      lastName = split.$2;
    }
  }

  final emails = <String>[];
  for (final p in props.where((p) => p.name == 'EMAIL')) {
    var address = _vUnescape(p.value).trim();
    if (address.toLowerCase().startsWith('mailto:')) {
      address = address.substring(7).trim();
    }
    if (address.isEmpty ||
        emails.any((e) => e.toLowerCase() == address.toLowerCase())) {
      continue;
    }
    final preferred = p.types.contains('PREF') || p.params.containsKey('PREF');
    if (preferred) {
      emails.insert(0, address);
    } else {
      emails.add(address);
    }
  }

  final phones = <ContactPhone>[];
  for (final p in props.where((p) => p.name == 'TEL')) {
    var number = _vUnescape(p.value).trim();
    if (number.toLowerCase().startsWith('tel:')) {
      number = number.substring(4).trim();
    }
    if (number.isEmpty) continue;
    phones.add(ContactPhone(label: _labelForTelTypes(p.types), number: number));
  }

  ContactAddress? address;
  final adrs = props.where((p) => p.name == 'ADR').toList();
  final adr = adrs.where((p) => p.types.contains('WORK')).firstOrNull ??
      adrs.firstOrNull;
  if (adr != null) {
    final parts = _splitUnescaped(adr.value, ';').map(_vUnescape).toList();
    String? part(int i) => i < parts.length ? _clean(parts[i]) : null;
    final candidate = ContactAddress(
      street: part(2) ?? part(0),
      city: part(3),
      state: part(4),
      zipCode: part(5),
      country: part(6),
    );
    if (!candidate.isEmpty) address = candidate;
  }

  final noteValue = first('NOTE')?.value;
  final notes = noteValue == null ? null : _vUnescape(noteValue);
  final title = _clean(_vUnescape(first('TITLE')?.value ?? ''));

  if (firstName == null &&
      lastName == null &&
      emails.isEmpty &&
      company == null &&
      phones.isEmpty) {
    return null;
  }

  return Contact(
    id: nextId(),
    firstName: firstName,
    lastName: lastName,
    company: company,
    jobTitle: title,
    emails: _labelEmails(emails),
    phones: phones,
    address: address,
    notes: notes == null || notes.trim().isEmpty ? null : notes,
    createdAt: now,
    updatedAt: now,
  );
}

String _labelForTelTypes(Set<String> types) {
  if (types.contains('CELL') || types.contains('MOBILE')) return 'Mobile';
  if (types.contains('FAX')) {
    if (types.contains('WORK')) return 'Business Fax';
    if (types.contains('HOME')) return 'Home Fax';
    return 'Fax';
  }
  if (types.contains('PAGER')) return 'Pager';
  if (types.contains('WORK')) return 'Business';
  if (types.contains('HOME')) return 'Home';
  return 'Phone';
}
