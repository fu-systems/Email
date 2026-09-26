import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/contact.dart';
import '../../models/email_message.dart';
import '../../providers/contacts_provider.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';
import 'contacts_common.dart';

/// Create/edit dialog for a contact group (distribution list).
///
/// Has a required group name, notes, a searchable checkbox list of the
/// contacts that have an email address, and a field for adding one-off
/// email addresses, which are listed as removable chips. Saving stores the
/// group with [ContactsProvider.saveGroup] (a new group is created with
/// [ContactsProvider.createGroup] first) and pops with the saved group.
class ContactGroupEditorDialog extends StatefulWidget {
  /// The group to edit, or null to create a new one.
  final ContactGroup? group;

  const ContactGroupEditorDialog({super.key, this.group});

  @override
  State<ContactGroupEditorDialog> createState() =>
      _ContactGroupEditorDialogState();
}

class _ContactGroupEditorDialogState extends State<ContactGroupEditorDialog> {
  final _name = TextEditingController();
  final _notes = TextEditingController();
  final _search = TextEditingController();
  final _newAddress = TextEditingController();
  final _newAddressFocus = FocusNode();

  /// Member contact ids, in the order they were added.
  final List<String> _memberIds = [];

  /// One-off member addresses.
  final List<String> _extraAddresses = [];

  String? _nameError;
  String? _addressError;

  bool get _isEditing => widget.group != null;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    if (g != null) {
      _name.text = g.name;
      _notes.text = g.notes ?? '';
      _memberIds.addAll(g.memberIds);
      _extraAddresses.addAll(g.extraAddresses);
    }
    _search.addListener(() => setState(() {}));
    _name.addListener(() {
      if (_nameError != null) setState(() => _nameError = null);
    });
    _newAddress.addListener(() {
      if (_addressError != null) setState(() => _addressError = null);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _search.dispose();
    _newAddress.dispose();
    _newAddressFocus.dispose();
    super.dispose();
  }

  int get _memberCount => _memberIds.length + _extraAddresses.length;

  /// Contacts offered in the picker: those with an email address (plus any
  /// current member without one), filtered by the search text.
  List<Contact> _candidates(List<Contact> contacts) {
    final query = _search.text.trim().toLowerCase();
    return contacts.where((c) {
      if (c.emails.isEmpty && !_memberIds.contains(c.id)) return false;
      if (query.isEmpty) return true;
      return c.displayName.toLowerCase().contains(query) ||
          (c.company?.toLowerCase().contains(query) ?? false) ||
          c.emails.any((e) => e.address.toLowerCase().contains(query));
    }).toList();
  }

  void _toggle(Contact contact) {
    setState(() {
      if (!_memberIds.remove(contact.id)) _memberIds.add(contact.id);
    });
  }

  /// Adds the address typed in the "Add email address" field. An address
  /// that is the primary email of a contact selects that contact instead.
  void _addAddress() {
    final text = _newAddress.text.trim();
    if (text.isEmpty) return;
    final parsed = EmailAddress.parse(text);
    if (!parsed.isValid) {
      setState(() =>
          _addressError = 'This doesn\'t look like a valid email address');
      return;
    }
    final address = parsed.address;
    final provider = context.read<ContactsProvider>();
    final contact = provider.findByEmail(address);
    setState(() {
      if (contact != null &&
          contact.primaryEmail?.toLowerCase() == address.toLowerCase()) {
        if (!_memberIds.contains(contact.id)) _memberIds.add(contact.id);
      } else if (!_extraAddresses
          .any((a) => a.toLowerCase() == address.toLowerCase())) {
        _extraAddresses.add(address);
      }
      _newAddress.clear();
      _addressError = null;
    });
    _newAddressFocus.requestFocus();
  }

  void _save() {
    final provider = context.read<ContactsProvider>();
    final name = cleanText(_name.text);
    if (name == null) {
      setState(() => _nameError = 'Enter a name for the group');
      return;
    }
    final existing = provider.groupByName(name);
    if (existing != null && existing.id != widget.group?.id) {
      setState(
          () => _nameError = 'A contact group named "$name" already exists');
      return;
    }
    if (_newAddress.text.trim().isNotEmpty) {
      // Don't silently drop an address that was typed but not added.
      _addAddress();
      if (_addressError != null) return;
    }

    final base = widget.group ?? provider.createGroup(name);
    final group = ContactGroup(
      id: base.id,
      name: name,
      memberIds: List.of(_memberIds),
      extraAddresses: List.of(_extraAddresses),
      notes: cleanText(_notes.text),
      createdAt: base.createdAt,
      updatedAt: DateTime.now(),
    );
    // Show a new group in the groups list.
    if (!_isEditing && !provider.showGroups) provider.setShowGroups(true);
    provider.saveGroup(group);
    Navigator.of(context).pop(group);
  }

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ContactsProvider>().allContacts;
    final candidates = _candidates(contacts);
    final hasPickable = contacts.any((c) => c.emails.isNotEmpty);
    return OutlookDialog(
      title: _isEditing
          ? '${widget.group!.name} - Contact Group'
          : 'New Contact Group',
      width: 520,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Group name',
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Members', style: PeopleStyles.sectionHeader),
              const Spacer(),
              Text('$_memberCount selected', style: PeopleStyles.muted),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Search contacts',
              prefixIcon: Icon(Icons.search, size: 16),
              prefixIconConstraints:
                  BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 220,
            decoration: BoxDecoration(
              border: Border.all(color: OutlookTheme.dividerColor),
              borderRadius: BorderRadius.circular(2),
            ),
            child: candidates.isEmpty
                ? Center(
                    child: Text(
                      hasPickable
                          ? 'No matching contacts'
                          : 'No contacts with an email address yet',
                      style: PeopleStyles.muted,
                    ),
                  )
                : ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final contact = candidates[index];
                      return _MemberCandidateRow(
                        contact: contact,
                        selected: _memberIds.contains(contact.id),
                        onToggle: () => _toggle(contact),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _newAddress,
                  focusNode: _newAddressFocus,
                  style: const TextStyle(fontSize: 13),
                  keyboardType: TextInputType.emailAddress,
                  onSubmitted: (_) => _addAddress(),
                  decoration: InputDecoration(
                    labelText: 'Add email address',
                    hintText: 'name@example.com',
                    errorText: _addressError,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _addAddress,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
          if (_extraAddresses.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final address in _extraAddresses)
                  _AddressChip(
                    address: address,
                    onRemove: () =>
                        setState(() => _extraAddresses.remove(address)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Notes',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// A contact in the member picker: checkbox, avatar, name and email.
class _MemberCandidateRow extends StatelessWidget {
  final Contact contact;
  final bool selected;
  final VoidCallback onToggle;

  const _MemberCandidateRow({
    required this.contact,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? OutlookTheme.selectedItemBackground.withValues(alpha: 0.5)
          : Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        hoverColor: OutlookTheme.hoverColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (_) => onToggle(),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
              ContactAvatar(contact: contact, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contact.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: PeopleStyles.body.copyWith(height: 1.2)),
                    Text(contact.primaryEmail ?? 'No email address',
                        overflow: TextOverflow.ellipsis,
                        style: PeopleStyles.muted),
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

/// A removable chip for a one-off member address.
class _AddressChip extends StatelessWidget {
  final String address;
  final VoidCallback onRemove;

  const _AddressChip({required this.address, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 8, right: 2),
      decoration: BoxDecoration(
        color: OutlookTheme.hoverColor,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: OutlookTheme.selectedItemBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.alternate_email,
              size: 13, color: OutlookTheme.textSecondary),
          const SizedBox(width: 4),
          Text(address, style: const TextStyle(fontSize: 12)),
          HoverButton(
            icon: Icons.close,
            iconSize: 12,
            tooltip: 'Remove $address',
            color: OutlookTheme.textSecondary,
            padding: const EdgeInsets.all(3),
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}
