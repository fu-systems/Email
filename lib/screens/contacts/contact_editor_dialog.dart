import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/contact.dart';
import '../../models/email_message.dart';
import '../../providers/contacts_provider.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';
import 'contacts_common.dart';

/// Create/edit dialog for a contact.
///
/// Shows first/last name, company, job title, three email fields ("Email",
/// "Email 2", "Email 3"), Business/Home/Mobile phones, a postal address and
/// notes. When editing, extra emails and phones with other labels (e.g.
/// "Business Fax") get fields of their own, so nothing is lost, and the
/// original labels are kept.
///
/// Saving is blocked while an email field holds an invalid address, or when
/// there is neither a name, a company nor an email address. A new contact is
/// added with [ContactsProvider.addContact]; an edited one is saved with
/// [ContactsProvider.updateContact]. The dialog pops with the saved contact.
class ContactEditorDialog extends StatefulWidget {
  /// The contact to edit, or null to create a new one.
  final Contact? contact;

  /// Prefills the first email field of a new contact.
  final String? initialEmail;

  /// Prefills the name of a new contact ("First Last" or "Last, First").
  final String? initialName;

  const ContactEditorDialog({
    super.key,
    this.contact,
    this.initialEmail,
    this.initialName,
  });

  @override
  State<ContactEditorDialog> createState() => _ContactEditorDialogState();
}

/// Default labels of the three fixed email fields.
const _emailSlotLabels = ['Email', 'Email 2', 'Email 3'];

/// Labels of the three fixed phone fields.
const _phoneSlotLabels = ['Business', 'Home', 'Mobile'];

/// Which fixed phone field a stored phone label belongs to, or null for
/// labels that get a field of their own (fax, pager, "Phone", ...).
int? _phoneSlotFor(String label) {
  final l = label.trim().toLowerCase();
  if (l.contains('fax') || l.contains('pager')) return null;
  if (l.contains('business') || l.contains('work') || l.contains('office')) {
    return 0;
  }
  if (l.contains('home')) return 1;
  if (l.contains('mobile') || l.contains('cell')) return 2;
  return null;
}

/// Splits a full name into (first, last): "Mary Ann Smith" gives
/// ("Mary Ann", "Smith") and "Smith, Mary" gives ("Mary", "Smith").
(String?, String?) _splitName(String? name) {
  final n = (name ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (n.isEmpty || n.contains('@')) return (null, null);
  final comma = n.indexOf(',');
  if (comma > 0) {
    return (
      cleanText(n.substring(comma + 1)),
      cleanText(n.substring(0, comma))
    );
  }
  final space = n.lastIndexOf(' ');
  if (space < 0) return (n, null);
  return (n.substring(0, space), n.substring(space + 1));
}

/// One email or phone input: its controller, the label shown on the field
/// and the label saved with the value.
class _LabeledField {
  final String fieldLabel;
  final String saveLabel;
  final TextEditingController controller;

  /// Whether the field has lost focus once (validation shows after that).
  bool touched = false;

  _LabeledField({
    required this.fieldLabel,
    required this.saveLabel,
    String text = '',
  }) : controller = TextEditingController(text: text);
}

class _ContactEditorDialogState extends State<ContactEditorDialog> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _company = TextEditingController();
  final _jobTitle = TextEditingController();
  final _street = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _zip = TextEditingController();
  final _country = TextEditingController();
  final _notes = TextEditingController();
  final List<_LabeledField> _emails = [];
  final List<_LabeledField> _phones = [];

  /// Set by a save attempt: shows every validation message.
  bool _saveAttempted = false;

  /// Message shown next to the buttons when saving is refused.
  String? _message;

  bool get _isEditing => widget.contact != null;

  /// Address book of a new contact (null: the local one).
  String? _addressBook;

  /// Whether to show the address book: there are Microsoft ones.
  bool get _showAddressBook =>
      context.read<ContactsProvider>().addressBooks.length > 1;

  /// "Save to" for new contacts, the address book of existing ones.
  List<Widget> _addressBookChoice() {
    if (!_showAddressBook) return const [];
    final provider = context.read<ContactsProvider>();
    return [
      Row(
        children: [
          const Text('Save to:', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(
            child: _isEditing
                ? Text(
                    provider.addressBookLabel(widget.contact!.sourceId),
                    style: const TextStyle(fontSize: 13),
                  )
                : DropdownButton<String>(
                    value: _addressBook ?? 'local',
                    isDense: true,
                    isExpanded: true,
                    items: [
                      for (final book in provider.addressBooks)
                        DropdownMenuItem(
                          value: book.id ?? 'local',
                          child: Text(
                            book.label,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(
                      () => _addressBook = v == null || v == 'local' ? null : v,
                    ),
                  ),
          ),
        ],
      ),
      const SizedBox(height: 6),
    ];
  }

  @override
  void initState() {
    super.initState();
    _addressBook = widget.contact?.sourceId ??
        context.read<ContactsProvider>().createEmpty().sourceId;
    final c = widget.contact;
    if (c != null) {
      _firstName.text = c.firstName ?? '';
      _lastName.text = c.lastName ?? '';
      _company.text = c.company ?? '';
      _jobTitle.text = c.jobTitle ?? '';
      _street.text = c.address?.street ?? '';
      _city.text = c.address?.city ?? '';
      _state.text = c.address?.state ?? '';
      _zip.text = c.address?.zipCode ?? '';
      _country.text = c.address?.country ?? '';
      _notes.text = c.notes ?? '';
    } else {
      final (first, last) = _splitName(widget.initialName);
      _firstName.text = first ?? '';
      _lastName.text = last ?? '';
    }
    _initEmails(c?.emails ?? const []);
    _initPhones(c?.phones ?? const []);
    if (c == null && widget.initialEmail != null) {
      _emails.first.controller.text = widget.initialEmail!.trim();
    }
    // Email fields re-validate as they change; any edit clears the message.
    for (final field in _emails) {
      field.controller.addListener(() => setState(() => _message = null));
    }
    for (final controller in [
      _firstName,
      _lastName,
      _company,
      ..._phones.map((f) => f.controller),
    ]) {
      controller.addListener(_clearMessage);
    }
  }

  /// The first three emails fill the fixed fields (keeping their labels);
  /// any others get extra fields.
  void _initEmails(List<ContactEmail> emails) {
    for (var i = 0; i < _emailSlotLabels.length; i++) {
      final existing = i < emails.length ? emails[i] : null;
      _emails.add(_LabeledField(
        fieldLabel: _emailSlotLabels[i],
        saveLabel: cleanText(existing?.label) ?? _emailSlotLabels[i],
        text: existing?.address ?? '',
      ));
    }
    for (final extra in emails.skip(_emailSlotLabels.length)) {
      final label = cleanText(extra.label) ?? 'Email';
      _emails.add(_LabeledField(
          fieldLabel: label, saveLabel: label, text: extra.address));
    }
  }

  /// The first Business, Home and Mobile phones fill the fixed fields; other
  /// phones get fields labelled with their own label.
  void _initPhones(List<ContactPhone> phones) {
    final slots = List<ContactPhone?>.filled(_phoneSlotLabels.length, null);
    final extras = <ContactPhone>[];
    for (final phone in phones) {
      final slot = _phoneSlotFor(phone.label);
      if (slot != null && slots[slot] == null) {
        slots[slot] = phone;
      } else {
        extras.add(phone);
      }
    }
    for (var i = 0; i < slots.length; i++) {
      _phones.add(_LabeledField(
        fieldLabel: _phoneSlotLabels[i],
        saveLabel: cleanText(slots[i]?.label) ?? _phoneSlotLabels[i],
        text: slots[i]?.number ?? '',
      ));
    }
    for (final extra in extras) {
      final label = cleanText(extra.label) ?? 'Phone';
      _phones.add(_LabeledField(
          fieldLabel: label, saveLabel: label, text: extra.number));
    }
  }

  void _clearMessage() {
    if (_message != null) setState(() => _message = null);
  }

  @override
  void dispose() {
    for (final c in [
      _firstName,
      _lastName,
      _company,
      _jobTitle,
      _street,
      _city,
      _state,
      _zip,
      _country,
      _notes,
    ]) {
      c.dispose();
    }
    for (final field in [..._emails, ..._phones]) {
      field.controller.dispose();
    }
    super.dispose();
  }

  /// Whether [field] holds text that is not a valid email address.
  bool _isInvalidEmail(_LabeledField field) {
    final text = field.controller.text.trim();
    return text.isNotEmpty && !EmailAddress(address: text).isValid;
  }

  /// Another saved contact (from [contacts]) that already uses the address
  /// in [field].
  Contact? _duplicateOwner(Iterable<Contact> contacts, _LabeledField field) {
    final text = field.controller.text.trim();
    if (text.isEmpty || _isInvalidEmail(field)) return null;
    for (final c in contacts) {
      if (c.id != widget.contact?.id && c.hasEmail(text)) return c;
    }
    return null;
  }

  void _save() {
    final provider = context.read<ContactsProvider>();
    setState(() {
      _saveAttempted = true;
      _message = null;
    });
    if (_emails.any(_isInvalidEmail)) {
      setState(() => _message = 'Correct the highlighted email address '
          'before saving.');
      return;
    }

    final emails = [
      for (final f in _emails)
        if (cleanText(f.controller.text) case final address?)
          ContactEmail(label: f.saveLabel, address: address),
    ];
    final phones = [
      for (final f in _phones)
        if (cleanText(f.controller.text) case final number?)
          ContactPhone(label: f.saveLabel, number: number),
    ];
    final firstName = cleanText(_firstName.text);
    final lastName = cleanText(_lastName.text);
    final company = cleanText(_company.text);
    if (firstName == null &&
        lastName == null &&
        company == null &&
        emails.isEmpty) {
      setState(() => _message =
          'Enter a name, company or email address for this contact.');
      return;
    }

    final address = ContactAddress(
      street: cleanText(_street.text),
      city: cleanText(_city.text),
      state: cleanText(_state.text),
      zipCode: cleanText(_zip.text),
      country: cleanText(_country.text),
    );
    var base = widget.contact ?? provider.createEmpty();
    if (!_isEditing && base.sourceId != _addressBook) {
      base = Contact.fromMap({...base.toMap(), 'sourceId': _addressBook});
    }
    final saved = base.withDetails(
      firstName: firstName,
      lastName: lastName,
      company: company,
      jobTitle: cleanText(_jobTitle.text),
      emails: emails,
      phones: phones,
      address: address.isEmpty ? null : address,
      notes: cleanText(_notes.text),
      updatedAt: DateTime.now(),
    );

    if (_isEditing) {
      provider.updateContact(saved);
    } else {
      // Show the new contact in the contacts list rather than the groups.
      if (provider.showGroups) provider.setShowGroups(false);
      provider.addContact(saved);
    }
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    // Unsorted, for the duplicate-address hints under the email fields.
    final savedContacts = context.watch<ContactsProvider>().contactsById.values;
    final title =
        _isEditing ? '${widget.contact!.displayName} - Contact' : 'New Contact';
    return OutlookDialog(
      title: title,
      width: 560,
      actions: [
        Expanded(
          child: _message == null
              ? const SizedBox.shrink()
              : Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: OutlookTheme.flaggedColor),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_message!, style: PeopleStyles.error)),
                  ],
                ),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._addressBookChoice(),
          _FormSectionLabel('Full name', first: !_showAddressBook),
          _pair(
            _textField(_firstName, 'First name', autofocus: true),
            _textField(_lastName, 'Last name'),
          ),
          const SizedBox(height: 10),
          _pair(
            _textField(_company, 'Company'),
            _textField(_jobTitle, 'Job title'),
          ),
          const _FormSectionLabel('Internet'),
          for (var i = 0; i < _emails.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _emailField(savedContacts, _emails[i]),
          ],
          const _FormSectionLabel('Phone numbers'),
          ..._grid([
            for (final f in _phones)
              _textField(f.controller, f.fieldLabel,
                  keyboardType: TextInputType.phone),
          ]),
          const _FormSectionLabel('Address'),
          _textField(_street, 'Street', maxLines: 2),
          const SizedBox(height: 10),
          _pair(
            _textField(_city, 'City'),
            _textField(_state, 'State/Province'),
          ),
          const SizedBox(height: 10),
          _pair(
            _textField(_zip, 'ZIP/Postal code'),
            _textField(_country, 'Country/Region'),
          ),
          const _FormSectionLabel('Notes'),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Add notes about this contact',
            ),
          ),
        ],
      ),
    );
  }

  Widget _emailField(Iterable<Contact> savedContacts, _LabeledField field) {
    final showError =
        (field.touched || _saveAttempted) && _isInvalidEmail(field);
    final duplicate = _duplicateOwner(savedContacts, field);
    return Focus(
      skipTraversal: true,
      onFocusChange: (focused) {
        if (!focused && !field.touched && mounted) {
          setState(() => field.touched = true);
        }
      },
      child: _textField(
        field.controller,
        field.fieldLabel,
        keyboardType: TextInputType.emailAddress,
        errorText:
            showError ? 'This doesn\'t look like a valid email address' : null,
        helperText:
            duplicate == null ? null : 'Also used by ${duplicate.displayName}',
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    bool autofocus = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? errorText,
    String? helperText,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      minLines: 1,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 13),
      textInputAction:
          maxLines == 1 ? TextInputAction.done : TextInputAction.newline,
      onSubmitted: maxLines == 1 ? (_) => _save() : null,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        helperText: helperText,
        helperStyle: PeopleStyles.muted,
      ),
    );
  }

  /// Two fields side by side.
  Widget _pair(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }

  /// [fields] laid out three per row.
  List<Widget> _grid(List<Widget> fields) {
    const perRow = 3;
    final rows = <Widget>[];
    for (var start = 0; start < fields.length; start += perRow) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = start; i < start + perRow; i++) ...[
            if (i > start) const SizedBox(width: 10),
            Expanded(child: i < fields.length ? fields[i] : const SizedBox()),
          ],
        ],
      ));
    }
    return rows;
  }
}

/// A small blue label above a group of form fields.
class _FormSectionLabel extends StatelessWidget {
  final String label;
  final bool first;

  const _FormSectionLabel(this.label, {this.first = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 18, bottom: 8),
      child: Text(label, style: PeopleStyles.sectionHeader),
    );
  }
}
