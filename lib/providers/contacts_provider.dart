import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/contact.dart';
import '../services/database_service.dart';

/// State management for the Contacts/People module.
class ContactsProvider extends ChangeNotifier {
  final DataCache _cache = DataCache.instance;
  Contact? _selectedContact;
  String _searchQuery = '';
  String? _selectedLetter;

  // Getters
  Contact? get selectedContact => _selectedContact;
  String get searchQuery => _searchQuery;
  String? get selectedLetter => _selectedLetter;

  List<Contact> get contacts {
    var list = _cache.contacts;

    if (_searchQuery.isNotEmpty) {
      list = _cache.searchContacts(_searchQuery);
    }

    if (_selectedLetter != null) {
      list = list.where((c) {
        return c.fileAs.toUpperCase().startsWith(_selectedLetter!);
      }).toList();
    }

    return list;
  }

  /// Get unique first letters for the alphabet index.
  List<String> get availableLetters {
    final letters = _cache.contacts
        .map((c) => c.fileAs.isNotEmpty ? c.fileAs[0].toUpperCase() : '#')
        .toSet()
        .toList();
    letters.sort();
    return letters;
  }

  // ─── Selection ─────────────────────────────────────────────────────

  void selectContact(Contact? contact) {
    _selectedContact = contact;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _selectedContact = null;
    notifyListeners();
  }

  void setLetterFilter(String? letter) {
    _selectedLetter = letter;
    _selectedContact = null;
    notifyListeners();
  }

  // ─── CRUD ──────────────────────────────────────────────────────────

  void addContact(Contact contact) {
    _cache.saveContact(contact);
    _selectedContact = contact;
    notifyListeners();
  }

  void updateContact(Contact contact) {
    _cache.saveContact(contact);
    if (_selectedContact?.id == contact.id) {
      _selectedContact = contact;
    }
    notifyListeners();
  }

  void removeContact(String id) {
    _cache.removeContact(id);
    if (_selectedContact?.id == id) {
      _selectedContact = null;
    }
    notifyListeners();
  }

  Contact createEmpty() {
    final now = DateTime.now();
    return Contact(
      id: const Uuid().v4(),
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Import contact from an email address (auto-create from message sender).
  Contact createFromEmail(String address, {String? name}) {
    final now = DateTime.now();
    String? firstName;
    String? lastName;
    if (name != null && name.isNotEmpty) {
      final parts = name.split(' ');
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
}
