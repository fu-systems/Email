import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/calendar_event.dart';
import '../services/database_service.dart';

/// State management for the Calendar module.
class CalendarProvider extends ChangeNotifier {
  final DataCache _cache = DataCache.instance;
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDate = DateTime.now();
  CalendarEvent? _selectedEvent;
  CalendarViewType _viewType = CalendarViewType.month;

  // Getters
  DateTime get selectedDate => _selectedDate;
  DateTime get focusedDate => _focusedDate;
  CalendarEvent? get selectedEvent => _selectedEvent;
  CalendarViewType get viewType => _viewType;

  List<CalendarEvent> get eventsForSelectedDate =>
      _cache.getEventsForDate(_selectedDate);

  List<CalendarEvent> get allEvents => _cache.events;

  List<CalendarEvent> getEventsForDate(DateTime date) =>
      _cache.getEventsForDate(date);

  List<CalendarEvent> getEventsInRange(DateTime start, DateTime end) =>
      _cache.getEventsInRange(start, end);

  // ─── Navigation ────────────────────────────────────────────────────

  void selectDate(DateTime date) {
    _selectedDate = date;
    _selectedEvent = null;
    notifyListeners();
  }

  void setFocusedDate(DateTime date) {
    _focusedDate = date;
    notifyListeners();
  }

  void selectEvent(CalendarEvent? event) {
    _selectedEvent = event;
    notifyListeners();
  }

  void setViewType(CalendarViewType type) {
    _viewType = type;
    notifyListeners();
  }

  void goToToday() {
    _selectedDate = DateTime.now();
    _focusedDate = DateTime.now();
    notifyListeners();
  }

  void goToPrevious() {
    switch (_viewType) {
      case CalendarViewType.day:
        _focusedDate = _focusedDate.subtract(const Duration(days: 1));
        _selectedDate = _focusedDate;
        break;
      case CalendarViewType.week:
        _focusedDate = _focusedDate.subtract(const Duration(days: 7));
        _selectedDate = _focusedDate;
        break;
      case CalendarViewType.month:
        _focusedDate = DateTime(
          _focusedDate.year,
          _focusedDate.month - 1,
          _focusedDate.day,
        );
        break;
    }
    notifyListeners();
  }

  void goToNext() {
    switch (_viewType) {
      case CalendarViewType.day:
        _focusedDate = _focusedDate.add(const Duration(days: 1));
        _selectedDate = _focusedDate;
        break;
      case CalendarViewType.week:
        _focusedDate = _focusedDate.add(const Duration(days: 7));
        _selectedDate = _focusedDate;
        break;
      case CalendarViewType.month:
        _focusedDate = DateTime(
          _focusedDate.year,
          _focusedDate.month + 1,
          _focusedDate.day,
        );
        break;
    }
    notifyListeners();
  }

  // ─── Event CRUD ────────────────────────────────────────────────────

  void addEvent(CalendarEvent event) {
    _cache.saveEvent(event);
    notifyListeners();
  }

  void updateEvent(CalendarEvent event) {
    _cache.saveEvent(event);
    if (_selectedEvent?.id == event.id) {
      _selectedEvent = event;
    }
    notifyListeners();
  }

  void removeEvent(String id) {
    _cache.removeEvent(id);
    if (_selectedEvent?.id == id) {
      _selectedEvent = null;
    }
    notifyListeners();
  }

  CalendarEvent createDefaultEvent() {
    final now = DateTime.now();
    final start = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      now.hour + 1,
    );
    return CalendarEvent(
      id: const Uuid().v4(),
      title: '',
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
      createdAt: now,
      updatedAt: now,
    );
  }
}

enum CalendarViewType {
  day,
  week,
  month;

  String get label {
    switch (this) {
      case CalendarViewType.day:
        return 'Day';
      case CalendarViewType.week:
        return 'Week';
      case CalendarViewType.month:
        return 'Month';
    }
  }
}
