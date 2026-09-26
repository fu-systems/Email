import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/contact.dart';
import '../../providers/contacts_provider.dart';
import '../../services/contacts_io.dart';
import '../../services/file_dialogs.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';
import 'contacts_common.dart';

/// File formats offered by [exportContactsToFile].
enum ContactsFileFormat {
  /// Outlook-compatible comma separated values.
  csv,

  /// vCard 3.0 (.vcf).
  vCard,
}

/// Lets the user pick .csv, .vcf or .vcard files and imports the contacts in
/// them. The format is detected from the file extension, or from the
/// content (`BEGIN:VCARD`) for other extensions.
///
/// Contacts whose primary email address is already in the address book (or
/// earlier in the same import) are skipped. The result is reported with
/// [showStatusMessage].
Future<void> importContactsFromFile(BuildContext context) async {
  final provider = context.read<ContactsProvider>();
  final paths = await FileDialogs.pickFiles(
    context,
    title: 'Import Contacts',
    extensions: const ['csv', 'vcf', 'vcard'],
    multiple: true,
  );
  if (paths.isEmpty || !context.mounted) return;

  var added = 0;
  var skipped = 0;
  final failures = <String>[];
  for (final path in paths) {
    try {
      final parsed = parseContactsFile(path, await _readText(path));
      if (parsed.isEmpty) {
        failures.add(p.basename(path));
        continue;
      }
      final unique = _withoutInternalDuplicates(parsed);
      final count = provider.importContacts(unique);
      added += count;
      skipped += parsed.length - count;
    } catch (_) {
      failures.add(p.basename(path));
    }
  }
  if (!context.mounted) return;

  if (failures.isNotEmpty && added == 0 && skipped == 0) {
    showStatusMessage(
      context,
      'No contacts could be imported from ${failures.join(', ')}.',
      isError: true,
    );
    return;
  }
  final summary = 'Imported $added ${added == 1 ? 'contact' : 'contacts'} '
      '($skipped ${skipped == 1 ? 'duplicate' : 'duplicates'} skipped)';
  showStatusMessage(
    context,
    failures.isEmpty
        ? summary
        : '$summary. Could not read ${failures.join(', ')}.',
    isError: failures.isNotEmpty,
  );
}

/// Parses [text] read from [path] as vCard or CSV contacts.
///
/// `.vcf`/`.vcard` files are read as vCard and `.csv` files as CSV; any
/// other file is read as vCard when it contains `BEGIN:VCARD`.
List<Contact> parseContactsFile(String path, String text) {
  final extension = p.extension(path).toLowerCase();
  final isVCard = extension == '.vcf' ||
      extension == '.vcard' ||
      (extension != '.csv' && text.toUpperCase().contains('BEGIN:VCARD'));
  return isVCard ? importVCard(text) : importContactsCsv(text);
}

/// Asks for a format (Outlook CSV or vCard), then saves every contact to a
/// file chosen by the user.
Future<void> exportContactsToFile(BuildContext context) async {
  final contacts = context.read<ContactsProvider>().allContacts;
  if (contacts.isEmpty) {
    showStatusMessage(context, 'There are no contacts to export.');
    return;
  }
  final format = await showDialog<ContactsFileFormat>(
    context: context,
    builder: (_) => const _ExportFormatDialog(),
  );
  if (format == null || !context.mounted) return;

  final isCsv = format == ContactsFileFormat.csv;
  final text = isCsv ? exportContactsCsv(contacts) : exportVCard(contacts);
  // A byte order mark lets Excel and Outlook detect UTF-8 in CSV files.
  final bytes = utf8.encode(isCsv ? '﻿$text' : text);
  try {
    final path = await FileDialogs.saveFile(
      context,
      fileName: isCsv ? 'Contacts.csv' : 'Contacts.vcf',
      bytes: bytes,
      title: 'Export Contacts',
      mimeType: isCsv ? 'text/csv' : 'text/vcard',
      extensions: [isCsv ? 'csv' : 'vcf'],
    );
    if (path == null || !context.mounted) return;
    final count = contacts.length;
    showStatusMessage(context,
        'Exported $count ${count == 1 ? 'contact' : 'contacts'} to $path');
  } catch (e) {
    if (context.mounted) {
      showStatusMessage(context, 'Could not export contacts: $e',
          isError: true);
    }
  }
}

/// Reads a text file as UTF-8, falling back to Latin-1 (e.g. Windows CSV
/// exports).
Future<String> _readText(String path) async {
  final bytes = await File(path).readAsBytes();
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Drops contacts whose primary email already appeared earlier in
/// [contacts] (the provider only checks against saved contacts).
List<Contact> _withoutInternalDuplicates(List<Contact> contacts) {
  final seen = <String>{};
  return [
    for (final c in contacts)
      if (c.primaryEmail == null || seen.add(c.primaryEmail!.toLowerCase())) c,
  ];
}

/// Asks which file format to export to.
class _ExportFormatDialog extends StatelessWidget {
  const _ExportFormatDialog();

  @override
  Widget build(BuildContext context) {
    return OutlookDialog(
      title: 'Export Contacts',
      width: 460,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Choose a file type to export to:', style: PeopleStyles.body),
          SizedBox(height: 12),
          _FormatOption(
            format: ContactsFileFormat.csv,
            icon: Icons.table_chart_outlined,
            title: 'Comma Separated Values (Outlook CSV)',
            description: 'Opens in Outlook, Excel and most email programs.',
          ),
          SizedBox(height: 8),
          _FormatOption(
            format: ContactsFileFormat.vCard,
            icon: Icons.contact_mail_outlined,
            title: 'vCard (.vcf)',
            description:
                'Standard business card format for phones and address books.',
          ),
        ],
      ),
    );
  }
}

class _FormatOption extends StatefulWidget {
  final ContactsFileFormat format;
  final IconData icon;
  final String title;
  final String description;

  const _FormatOption({
    required this.format,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  State<_FormatOption> createState() => _FormatOptionState();
}

class _FormatOptionState extends State<_FormatOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(widget.format),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hovered ? OutlookTheme.hoverColor : Colors.white,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: _hovered
                  ? OutlookTheme.selectedItemBorder
                  : OutlookTheme.dividerColor,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 28, color: OutlookTheme.primaryBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: PeopleStyles.itemName),
                    const SizedBox(height: 2),
                    Text(widget.description, style: PeopleStyles.muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
