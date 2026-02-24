import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/outlook_theme.dart';
import '../../models/contact.dart';
import '../../providers/contacts_provider.dart';

/// Contacts module — Outlook 2013-style People view with alphabet index,
/// contact list, and detail pane.
class ContactsView extends StatelessWidget {
  const ContactsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        // Alphabet index rail
        _AlphabetIndex(),
        VerticalDivider(width: 1),
        // Contact list (with search)
        SizedBox(
          width: OutlookTheme.messageListWidth,
          child: _ContactListPane(),
        ),
        VerticalDivider(width: 1),
        // Detail pane
        Expanded(child: _ContactDetailPane()),
      ],
    );
  }
}

/// Narrow alphabet rail on the far left.
class _AlphabetIndex extends StatelessWidget {
  const _AlphabetIndex();

  static const _letters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ContactsProvider>();
    final available = contacts.availableLetters;
    final selected = contacts.selectedLetter;

    return Container(
      width: 28,
      color: OutlookTheme.folderPaneBackground,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          // "All" button to clear filter
          _LetterButton(
            letter: '#',
            isActive: selected == null,
            isAvailable: true,
            onTap: () => contacts.setLetterFilter(null),
          ),
          ..._letters.map((letter) {
            return _LetterButton(
              letter: letter,
              isActive: selected == letter,
              isAvailable: available.contains(letter),
              onTap: () {
                contacts.setLetterFilter(
                    selected == letter ? null : letter);
              },
            );
          }),
        ],
      ),
    );
  }
}

class _LetterButton extends StatefulWidget {
  final String letter;
  final bool isActive;
  final bool isAvailable;
  final VoidCallback onTap;

  const _LetterButton({
    required this.letter,
    required this.isActive,
    required this.isAvailable,
    required this.onTap,
  });

  @override
  State<_LetterButton> createState() => _LetterButtonState();
}

class _LetterButtonState extends State<_LetterButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.isAvailable ? widget.onTap : null,
        child: Container(
          height: 22,
          alignment: Alignment.center,
          color: widget.isActive
              ? OutlookTheme.primaryBlue
              : _isHovered && widget.isAvailable
                  ? OutlookTheme.hoverColor
                  : Colors.transparent,
          child: Text(
            widget.letter,
            style: TextStyle(
              fontFamily: OutlookTheme.fontFamily,
              fontFamilyFallback: OutlookTheme.fontFamilyFallback,
              fontSize: 11,
              fontWeight: widget.isActive ? FontWeight.w700 : FontWeight.w400,
              color: widget.isActive
                  ? Colors.white
                  : widget.isAvailable
                      ? OutlookTheme.textPrimary
                      : OutlookTheme.textMuted.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}

/// Center pane — search bar + contact list.
class _ContactListPane extends StatelessWidget {
  const _ContactListPane();

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ContactsProvider>();
    final list = contacts.contacts;

    return Container(
      decoration: OutlookTheme.messageListDecoration,
      child: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: OutlookTheme.dividerColor),
              ),
            ),
            child: TextField(
              onChanged: (q) => contacts.setSearchQuery(q),
              decoration: const InputDecoration(
                hintText: 'Search People',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          // Contact list
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      contacts.searchQuery.isNotEmpty
                          ? 'No contacts found'
                          : 'No contacts yet',
                      style: TextStyle(
                        fontFamily: OutlookTheme.fontFamily,
                        fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                        fontSize: 13,
                        color: OutlookTheme.textMuted,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final contact = list[index];
                      final isSelected =
                          contacts.selectedContact?.id == contact.id;
                      return _ContactTile(
                        contact: contact,
                        isSelected: isSelected,
                        onTap: () => contacts.selectContact(contact),
                      );
                    },
                  ),
          ),
          // New contact button
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: OutlookTheme.dividerColor),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showContactDialog(context),
                icon: const Icon(Icons.person_add, size: 14),
                label: const Text('New Contact'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showContactDialog(BuildContext context, {Contact? contact}) {
    showDialog(
      context: context,
      builder: (_) => ContactEditorDialog(contact: contact),
    );
  }
}

class _ContactTile extends StatefulWidget {
  final Contact contact;
  final bool isSelected;
  final VoidCallback onTap;

  const _ContactTile({
    required this.contact,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_ContactTile> createState() => _ContactTileState();
}

class _ContactTileState extends State<_ContactTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.contact;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? OutlookTheme.selectedItemBackground
                : _isHovered
                    ? OutlookTheme.hoverColor
                    : Colors.transparent,
            border: widget.isSelected
                ? const Border(
                    left: BorderSide(
                        color: OutlookTheme.primaryBlue, width: 3),
                  )
                : null,
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: OutlookTheme.primaryBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    c.initials,
                    style: const TextStyle(
                      fontFamily: OutlookTheme.fontFamily,
                      fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: OutlookTheme.primaryBlue,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Name + company
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.displayName,
                      style: const TextStyle(
                        fontFamily: OutlookTheme.fontFamily,
                        fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: OutlookTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (c.company != null && c.company!.isNotEmpty)
                      Text(
                        c.company!,
                        style: OutlookTheme.messagePreview,
                        overflow: TextOverflow.ellipsis,
                      ),
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

/// Right pane — contact detail card.
class _ContactDetailPane extends StatelessWidget {
  const _ContactDetailPane();

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ContactsProvider>();
    final contact = contacts.selectedContact;

    if (contact == null) {
      return Container(
        color: OutlookTheme.readingPaneBackground,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline,
                  size: 48,
                  color: OutlookTheme.textMuted.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(
                'Select a contact to view details',
                style: TextStyle(
                  fontFamily: OutlookTheme.fontFamily,
                  fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                  fontSize: 14,
                  color: OutlookTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: OutlookTheme.readingPaneBackground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: avatar + name + actions
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Large avatar
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: OutlookTheme.primaryBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      contact.initials,
                      style: const TextStyle(
                        fontFamily: OutlookTheme.fontFamily,
                        fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: OutlookTheme.primaryBlue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.displayName,
                        style: OutlookTheme.readingPaneSubject,
                      ),
                      if (contact.jobTitle != null &&
                          contact.jobTitle!.isNotEmpty)
                        Text(
                          contact.jobTitle!,
                          style: const TextStyle(
                            fontFamily: OutlookTheme.fontFamily,
                            fontFamilyFallback:
                                OutlookTheme.fontFamilyFallback,
                            fontSize: 13,
                            color: OutlookTheme.textSecondary,
                          ),
                        ),
                      if (contact.company != null &&
                          contact.company!.isNotEmpty)
                        Text(
                          contact.company!,
                          style: const TextStyle(
                            fontFamily: OutlookTheme.fontFamily,
                            fontFamilyFallback:
                                OutlookTheme.fontFamilyFallback,
                            fontSize: 13,
                            color: OutlookTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                // Actions
                _DetailAction(
                  icon: Icons.edit,
                  tooltip: 'Edit',
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) =>
                          ContactEditorDialog(contact: contact),
                    );
                  },
                ),
                _DetailAction(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete',
                  onTap: () {
                    contacts.removeContact(contact.id);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            // Email addresses
            if (contact.emails.isNotEmpty) ...[
              _SectionHeader(icon: Icons.email, label: 'Email'),
              ...contact.emails.map((e) => _DetailRow(
                    label: e.label,
                    value: e.address,
                  )),
              const SizedBox(height: 16),
            ],
            // Phone numbers
            if (contact.phones.isNotEmpty) ...[
              _SectionHeader(icon: Icons.phone, label: 'Phone'),
              ...contact.phones.map((p) => _DetailRow(
                    label: p.label,
                    value: p.number,
                  )),
              const SizedBox(height: 16),
            ],
            // Address
            if (contact.address != null) ...[
              _SectionHeader(icon: Icons.location_on, label: 'Address'),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(
                  contact.address!.formatted,
                  style: const TextStyle(
                    fontFamily: OutlookTheme.fontFamily,
                    fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                    fontSize: 13,
                    color: OutlookTheme.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Notes
            if (contact.notes != null && contact.notes!.isNotEmpty) ...[
              _SectionHeader(icon: Icons.notes, label: 'Notes'),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(
                  contact.notes!,
                  style: const TextStyle(
                    fontFamily: OutlookTheme.fontFamily,
                    fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                    fontSize: 13,
                    color: OutlookTheme.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailAction extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _DetailAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_DetailAction> createState() => _DetailActionState();
}

class _DetailActionState extends State<_DetailAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: _isHovered
                  ? OutlookTheme.hoverColor
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
              border: _isHovered
                  ? Border.all(color: OutlookTheme.selectedItemBorder)
                  : null,
            ),
            child: Icon(widget.icon,
                size: 16, color: OutlookTheme.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: OutlookTheme.primaryBlue),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontFamily: OutlookTheme.fontFamily,
              fontFamilyFallback: OutlookTheme.fontFamilyFallback,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: OutlookTheme.primaryBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: OutlookTheme.fontFamily,
                fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                fontSize: 12,
                color: OutlookTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: OutlookTheme.fontFamily,
                fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                fontSize: 13,
                color: OutlookTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Contact create/edit dialog.
class ContactEditorDialog extends StatefulWidget {
  final Contact? contact;

  const ContactEditorDialog({super.key, this.contact});

  @override
  State<ContactEditorDialog> createState() => _ContactEditorDialogState();
}

class _ContactEditorDialogState extends State<ContactEditorDialog> {
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _companyController;
  late TextEditingController _jobTitleController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _streetController;
  late TextEditingController _cityController;
  late TextEditingController _stateController;
  late TextEditingController _zipController;
  late TextEditingController _notesController;

  bool get _isEditing => widget.contact != null;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _firstNameController = TextEditingController(text: c?.firstName ?? '');
    _lastNameController = TextEditingController(text: c?.lastName ?? '');
    _companyController = TextEditingController(text: c?.company ?? '');
    _jobTitleController = TextEditingController(text: c?.jobTitle ?? '');
    _emailController = TextEditingController(
        text: c?.emails.firstOrNull?.address ?? '');
    _phoneController = TextEditingController(
        text: c?.phones.firstOrNull?.number ?? '');
    _streetController =
        TextEditingController(text: c?.address?.street ?? '');
    _cityController = TextEditingController(text: c?.address?.city ?? '');
    _stateController =
        TextEditingController(text: c?.address?.state ?? '');
    _zipController =
        TextEditingController(text: c?.address?.zipCode ?? '');
    _notesController = TextEditingController(text: c?.notes ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _companyController.dispose();
    _jobTitleController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    final contacts = context.read<ContactsProvider>();
    final now = DateTime.now();

    final emails = _emailController.text.trim().isNotEmpty
        ? [ContactEmail(label: 'Email', address: _emailController.text.trim())]
        : <ContactEmail>[];

    final phones = _phoneController.text.trim().isNotEmpty
        ? [ContactPhone(label: 'Phone', number: _phoneController.text.trim())]
        : <ContactPhone>[];

    final hasAddress = _streetController.text.trim().isNotEmpty ||
        _cityController.text.trim().isNotEmpty;
    final address = hasAddress
        ? ContactAddress(
            street: _streetController.text.trim().isNotEmpty
                ? _streetController.text.trim()
                : null,
            city: _cityController.text.trim().isNotEmpty
                ? _cityController.text.trim()
                : null,
            state: _stateController.text.trim().isNotEmpty
                ? _stateController.text.trim()
                : null,
            zipCode: _zipController.text.trim().isNotEmpty
                ? _zipController.text.trim()
                : null,
          )
        : null;

    if (_isEditing) {
      contacts.updateContact(widget.contact!.copyWith(
        firstName: _firstNameController.text.trim().isNotEmpty
            ? _firstNameController.text.trim()
            : null,
        lastName: _lastNameController.text.trim().isNotEmpty
            ? _lastNameController.text.trim()
            : null,
        company: _companyController.text.trim().isNotEmpty
            ? _companyController.text.trim()
            : null,
        jobTitle: _jobTitleController.text.trim().isNotEmpty
            ? _jobTitleController.text.trim()
            : null,
        emails: emails,
        phones: phones,
        address: address,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        updatedAt: now,
      ));
    } else {
      final newContact = contacts.createEmpty().copyWith(
            firstName: _firstNameController.text.trim().isNotEmpty
                ? _firstNameController.text.trim()
                : null,
            lastName: _lastNameController.text.trim().isNotEmpty
                ? _lastNameController.text.trim()
                : null,
            company: _companyController.text.trim().isNotEmpty
                ? _companyController.text.trim()
                : null,
            jobTitle: _jobTitleController.text.trim().isNotEmpty
                ? _jobTitleController.text.trim()
                : null,
            emails: emails,
            phones: phones,
            address: address,
            notes: _notesController.text.trim().isNotEmpty
                ? _notesController.text.trim()
                : null,
            createdAt: now,
            updatedAt: now,
          );
      contacts.addContact(newContact);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: OutlookTheme.primaryBlue,
              child: Row(
                children: [
                  Text(
                    _isEditing ? 'Edit Contact' : 'New Contact',
                    style: OutlookTheme.titleBarStyle,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 14, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                ],
              ),
            ),
            // Form
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _firstNameController,
                          autofocus: true,
                          decoration:
                              const InputDecoration(labelText: 'First Name'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _lastNameController,
                          decoration:
                              const InputDecoration(labelText: 'Last Name'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Company + Job title
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _companyController,
                          decoration:
                              const InputDecoration(labelText: 'Company'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _jobTitleController,
                          decoration:
                              const InputDecoration(labelText: 'Job Title'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Email + Phone
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email, size: 16),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone, size: 16),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  // Address
                  const Text('Address',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: OutlookTheme.textSecondary,
                      )),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _streetController,
                    decoration: const InputDecoration(labelText: 'Street'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _cityController,
                          decoration:
                              const InputDecoration(labelText: 'City'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _stateController,
                          decoration:
                              const InputDecoration(labelText: 'State'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _zipController,
                          decoration:
                              const InputDecoration(labelText: 'ZIP'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Notes
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            // Actions
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _save,
                    child: Text(_isEditing ? 'Save' : 'Create'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
