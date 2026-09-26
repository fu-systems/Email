import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/contacts_provider.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';

/// Recipients chosen in the Address Book.
class AddressBookSelection {
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;

  const AddressBookSelection({
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
  });
}

/// Outlook's "Select Names" dialog: search contacts and groups and add them
/// to the To, Cc or Bcc field.
class AddressBookDialog extends StatefulWidget {
  const AddressBookDialog({super.key});

  @override
  State<AddressBookDialog> createState() => _AddressBookDialogState();
}

class _Entry {
  final String label;
  final String detail;
  final String insert;
  final bool isGroup;

  const _Entry(this.label, this.detail, this.insert, {this.isGroup = false});
}

class _AddressBookDialogState extends State<AddressBookDialog> {
  String _query = '';
  _Entry? _selected;
  final List<String> _to = [];
  final List<String> _cc = [];
  final List<String> _bcc = [];

  List<_Entry> _entries(ContactsProvider contacts) {
    final entries = <_Entry>[
      for (final g in contacts.groups)
        _Entry(g.name, '${g.memberCount} members', g.name, isGroup: true),
      for (final c in contacts.allContacts)
        for (final e in c.emails)
          _Entry(
            c.displayName,
            e.address,
            c.displayName == e.address ? e.address : '${c.displayName} <${e.address}>',
          ),
    ];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return entries;
    return entries
        .where((e) =>
            e.label.toLowerCase().contains(q) ||
            e.detail.toLowerCase().contains(q))
        .toList();
  }

  void _add(List<String> target) {
    final entry = _selected;
    if (entry == null || target.contains(entry.insert)) return;
    setState(() => target.add(entry.insert));
  }

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ContactsProvider>();
    final entries = _entries(contacts);

    Widget targetRow(String label, List<String> target) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                child: OutlinedButton(
                  onPressed: _selected == null ? null : () => _add(target),
                  child: Text(label),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: OutlookTheme.dividerColor),
                  ),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final item in target)
                        InputChip(
                          label: Text(item, style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          onDeleted: () => setState(() => target.remove(item)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

    return OutlookDialog(
      title: 'Select Names: Contacts',
      width: 620,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(
              AddressBookSelection(to: _to, cc: _cc, bcc: _bcc)),
          child: const Text('OK'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search names and groups',
              prefixIcon: Icon(Icons.search, size: 16),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          Container(
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: OutlookTheme.dividerColor),
            ),
            child: entries.isEmpty
                ? const Center(
                    child: Text(
                      'No contacts. Add people in the People view.',
                      style: TextStyle(color: OutlookTheme.textMuted),
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemExtent: 30,
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final selected = identical(e, _selected) ||
                          (_selected?.insert == e.insert);
                      return InkWell(
                        onTap: () => setState(() => _selected = e),
                        onDoubleTap: () {
                          setState(() => _selected = e);
                          _add(_to);
                        },
                        child: Container(
                          color: selected
                              ? OutlookTheme.selectedItemBackground
                              : null,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Icon(e.isGroup ? Icons.groups : Icons.person,
                                  size: 16, color: OutlookTheme.textSecondary),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: Text(e.label,
                                    style: const TextStyle(fontSize: 12.5),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Expanded(
                                flex: 4,
                                child: Text(e.detail,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: OutlookTheme.textSecondary),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          targetRow('To ->', _to),
          targetRow('Cc ->', _cc),
          targetRow('Bcc ->', _bcc),
        ],
      ),
    );
  }
}
