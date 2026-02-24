import 'package:flutter/material.dart';

/// Manages top-level navigation between Mail, Calendar, and Contacts.
class NavigationProvider extends ChangeNotifier {
  NavigationSection _currentSection = NavigationSection.mail;
  String _currentRibbonTab = 'Home';

  NavigationSection get currentSection => _currentSection;
  String get currentRibbonTab => _currentRibbonTab;

  void switchSection(NavigationSection section) {
    if (_currentSection == section) return;
    _currentSection = section;
    // Reset ribbon tab when switching sections
    _currentRibbonTab = 'Home';
    notifyListeners();
  }

  void switchRibbonTab(String tab) {
    if (_currentRibbonTab == tab) return;
    _currentRibbonTab = tab;
    notifyListeners();
  }
}

enum NavigationSection {
  mail,
  calendar,
  contacts;

  String get label {
    switch (this) {
      case NavigationSection.mail:
        return 'Mail';
      case NavigationSection.calendar:
        return 'Calendar';
      case NavigationSection.contacts:
        return 'People';
    }
  }

  IconData get icon {
    switch (this) {
      case NavigationSection.mail:
        return Icons.mail;
      case NavigationSection.calendar:
        return Icons.calendar_today;
      case NavigationSection.contacts:
        return Icons.people;
    }
  }
}
