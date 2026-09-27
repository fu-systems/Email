import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/contact.dart';
import '../services/data_store.dart';
import '../services/sync/graph_pim_sync.dart';

/// A suggestion for recipient auto-complete.
class RecipientSuggestion {
  final String label;
  final String address;
  final ContactGroup? group;

  const RecipientSuggestion({
    required this.label,
    required this.address,
    this.group,
  });

  bool get isGroup => group != null;

  /// Text inserted into a recipient field.
  String get insertText =>
      label.isNotEmpty && label != address ? '$label <$address>' : address;
}

/// State management for the Contacts/People module.
class ContactsProvider extends ChangeNotifier {
  final DataStore _store;
  Contact? _selectedContact;
  ContactGroup? _selectedGroup;
  String _searchQuery = '';
  String? _selectedLetter;
  bool _showGroups = false;

  /// Microsoft address books (optional).
  final GraphPimSync? _pim;

  /// Shows only this address book: `local` or a source id; null for all.
  String? _addressBook;

  ContactsProvider({DataStore? store, this._pim})
      : _store = store ?? DataStore.instance {
    _pim?.addListener(_onSynced);
  }

  void _onSynced() {
    final selected = _selectedContact;
    if (selected != null) _selectedContact = _store.getContact(selected.id);
    notifyListeners();
  }

  @override
  void dispose() {
    _pim?.removeListener(_onSynced);
    super.dispose();
  }

  /// The local address book and one per Microsoft account.
  List<({String? id, String label})> get addressBooks => [
        (id: null, label: 'Contacts'),
        for (final s in _pim?.sources ?? const <({String id, String label})>[])
          (id: s.id, label: 'Contacts - ${s.label}'),
      ];

  String addressBookLabel(String? sourceId) => sourceId == null
      ? 'Contacts'
      : 'Contacts - ${_pim?.labelFor(sourceId) ?? 'Microsoft account'}';

  /// The last sync problem of a Microsoft address book.
  String? addressBookError(String sourceId) =>
      _pim?.errorFor(sourceId, calendar: false);

  /// The address book shown (`local`, a source id, or null for all).
  String? get addressBookFilter => _addressBook;

  /// Number of contacts in an address book (null: the local one).
  int countIn(String? sourceId) =>
      _store.contacts.where((c) => c.sourceId == sourceId).length;

  void setAddressBookFilter(String? key) {
    _addressBook = key;
    _selectedContact = null;
    notifyListeners();
  }

  bool _inFilter(Contact c) =>
      _addressBook == null || (c.sourceId ?? 'local') == _addressBook;

  // Getters
  Contact? get selectedContact => _selectedContact;
  ContactGroup? get selectedGroup => _selectedGroup;
  String get searchQuery => _searchQuery;
  String? get selectedLetter => _selectedLetter;
  bool get showGroups => _showGroups;
  List<ContactGroup> get groups => _store.groups;
  List<Contact> get allContacts => _store.contacts;
  Map<String, Contact> get contactsById => _store.contactsById;

  List<Contact> get contacts {
    var list = _searchQuery.isNotEmpty
        ? _store.searchContacts(_searchQuery)
        : _store.contacts;
    if (_addressBook != null) list = list.where(_inFilter).toList();
    if (_selectedLetter != null) {
      list = list.where((c) {
        final first = c.fileAs.isNotEmpty ? c.fileAs[0].toUpperCase() : '#';
        return _selectedLetter == '#'
            ? !RegExp('[A-Z]').hasMatch(first)
            : first == _selectedLetter;
      }).toList();
    }
    return list;
  }

  List<ContactGroup> get filteredGroups {
    if (_searchQuery.isEmpty) return groups;
    final q = _searchQuery.toLowerCase();
    return groups.where((g) => g.name.toLowerCase().contains(q)).toList();
  }

  /// Unique first letters for the alphabet index.
  List<String> get availableLetters {
    final letters = _store.contacts
        .map((c) => c.fileAs.isNotEmpty ? c.fileAs[0].toUpperCase() : '#')
        .map((l) => RegExp('[A-Z]').hasMatch(l) ? l : '#')
        .toSet()
        .toList();
    letters.sort();
    return letters;
  }

  // ─── Selection ─────────────────────────────────────────────────────

  void selectContact(Contact? contact) {
    _selectedContact = contact;
    _selectedGroup = null;
    notifyListeners();
  }

  void selectGroup(ContactGroup? group) {
    _selectedGroup = group;
    _selectedContact = null;
    notifyListeners();
  }

  void setShowGroups(bool value) {
    _showGroups = value;
    _selectedContact = null;
    _selectedGroup = null;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setLetterFilter(String? letter) {
    _selectedLetter = letter;
    notifyListeners();
  }

  // ─── CRUD ──────────────────────────────────────────────────────────

  void addContact(Contact contact) {
    contact = _pim?.prepareContact(contact) ?? contact;
    _store.saveContact(contact);
    _pim?.changed(contact.sourceId);
    _selectedContact = contact;
    _selectedGroup = null;
    notifyListeners();
  }

  /// Adds many contacts (import). Returns the number added.
  int importContacts(List<Contact> contacts, {bool skipDuplicates = true}) {
    final toAdd = <Contact>[];
    for (final c in contacts) {
      final email = c.primaryEmail;
      if (skipDuplicates && email != null && findByEmail(email) != null) {
        continue;
      }
      toAdd.add(c);
    }
    _store.saveContacts(toAdd);
    notifyListeners();
    return toAdd.length;
  }

  void updateContact(Contact contact) {
    contact = _pim?.prepareContact(contact) ?? contact;
    _store.saveContact(contact);
    _pim?.changed(contact.sourceId);
    if (_selectedContact?.id == contact.id) {
      _selectedContact = contact;
    }
    notifyListeners();
  }

  void removeContact(String id) {
    final contact = _store.getContact(id);
    if (contact != null) _pim?.contactDeleted(contact);
    _store.removeContact(id);
    _pim?.changed(contact?.sourceId);
    if (_selectedContact?.id == id) {
      _selectedContact = null;
    }
    if (_selectedGroup != null) _selectedGroup = _store.getGroup(_selectedGroup!.id);
    notifyListeners();
  }

  /// A new contact, in the address book shown (the local one when all
  /// are shown).
  Contact createEmpty() {
    final now = DateTime.now();
    final book = _addressBook;
    return Contact(
      id: const Uuid().v4(),
      sourceId: book == null || book == 'local' ? null : book,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Import contact from an email address (auto-create from message sender).
  Contact createFromEmail(String address, {String? name}) {
    final now = DateTime.now();
    String? firstName;
    String? lastName;
    if (name != null && name.trim().isNotEmpty) {
      final parts = name.trim().split(RegExp(r'\s+'));
      firstName = parts.first;
      if (parts.length > 1) lastName = parts.sublist(1).join(' ');
    }
    return Contact(
      id: const Uuid().v4(),
      firstName: firstName,
      lastName: lastName,
      emails: [ContactEmail(label: 'Email', address: address)],
      createdAt: now,
      updatedAt: now,
    );
  }

  Contact? findByEmail(String address) {
    for (final c in _store.contacts) {
      if (c.hasEmail(address)) return c;
    }
    return null;
  }

  // ─── Groups ────────────────────────────────────────────────────────

  ContactGroup createGroup(String name) {
    final now = DateTime.now();
    return ContactGroup(
      id: const Uuid().v4(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
  }

  void saveGroup(ContactGroup group) {
    _store.saveGroup(group);
    _selectedGroup = group;
    _selectedContact = null;
    notifyListeners();
  }

  void removeGroup(String id) {
    _store.removeGroup(id);
    if (_selectedGroup?.id == id) _selectedGroup = null;
    notifyListeners();
  }

  List<String> groupAddresses(ContactGroup group) =>
      group.resolveAddresses(_store.contactsById);

  ContactGroup? groupByName(String name) {
    final lower = name.trim().toLowerCase();
    for (final g in _store.groups) {
      if (g.name.toLowerCase() == lower) return g;
    }
    return null;
  }

  // ─── Auto-complete ─────────────────────────────────────────────────

  /// Contacts and groups matching [query] for recipient fields.
  List<RecipientSuggestion> suggestions(String query, {int limit = 8}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final result = <RecipientSuggestion>[];
    for (final g in _store.groups) {
      if (g.name.toLowerCase().contains(q)) {
        result.add(RecipientSuggestion(label: g.name, address: '', group: g));
      }
    }
    for (final c in _store.contacts) {
      final nameMatch = c.displayName.toLowerCase().contains(q);
      for (final e in c.emails) {
        if (nameMatch || e.address.toLowerCase().contains(q)) {
          result.add(RecipientSuggestion(
            label: c.displayName == e.address ? '' : c.displayName,
            address: e.address,
          ));
        }
      }
      if (result.length >= limit) break;
    }
    return result.take(limit).toList();
  }
}
