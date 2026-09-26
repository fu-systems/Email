import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/calendar_event.dart';
import '../services/data_store.dart';
import '../services/notification_service.dart';

/// State management for the Calendar module.
class CalendarProvider extends ChangeNotifier {
  final DataStore _store;
  final NotificationService? _notifications;
  DateTime _selectedDate = _today();
  DateTime _focusedDate = _today();
  CalendarEvent? _selectedEvent;
  EventOccurrence? _selectedOccurrence;
  CalendarViewType _viewType = CalendarViewType.month;
  Timer? _reminderTimer;
  final Set<String> _remindedKeys = {};

  CalendarProvider({DataStore? store, NotificationService? notifications})
      : _store = store ?? DataStore.instance,
        _notifications = notifications {
    _viewType = CalendarViewType.values
            .asNameMap()[_store.getString('calendarView') ?? 'month'] ??
        CalendarViewType.month;
    if (_notifications != null) {
      _reminderTimer = Timer.periodic(
          const Duration(seconds: 30), (_) => checkReminders(DateTime.now()));
    }
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // Getters
  DateTime get selectedDate => _selectedDate;
  DateTime get focusedDate => _focusedDate;
  CalendarEvent? get selectedEvent => _selectedEvent;
  EventOccurrence? get selectedOccurrence => _selectedOccurrence;
  CalendarViewType get viewType => _viewType;

  List<EventOccurrence> get occurrencesForSelectedDate =>
      _store.getOccurrencesForDate(_selectedDate);

  /// Events (not occurrences) that occur on the selected date.
  List<CalendarEvent> get eventsForSelectedDate =>
      occurrencesForSelectedDate.map((o) => o.event).toList();

  List<CalendarEvent> get allEvents => _store.events;

  List<CalendarEvent> getEventsForDate(DateTime date) =>
      _store.getOccurrencesForDate(date).map((o) => o.event).toList();

  List<EventOccurrence> getOccurrencesForDate(DateTime date) =>
      _store.getOccurrencesForDate(date);

  List<EventOccurrence> getOccurrencesInRange(DateTime start, DateTime end) =>
      _store.getOccurrencesInRange(start, end);

  /// First day (Sunday) of the week containing [date].
  static DateTime weekStart(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return DateTime(d.year, d.month, d.day - (d.weekday % 7));
  }

  /// The days shown by the current view around [focusedDate].
  List<DateTime> get visibleDays {
    switch (_viewType) {
      case CalendarViewType.day:
        return [_selectedDate];
      case CalendarViewType.workWeek:
        final start = weekStart(_selectedDate);
        return [for (var i = 1; i <= 5; i++) DateTime(start.year, start.month, start.day + i)];
      case CalendarViewType.week:
        final start = weekStart(_selectedDate);
        return [for (var i = 0; i < 7; i++) DateTime(start.year, start.month, start.day + i)];
      case CalendarViewType.month:
        final first = DateTime(_focusedDate.year, _focusedDate.month, 1);
        final start = weekStart(first);
        return [for (var i = 0; i < 42; i++) DateTime(start.year, start.month, start.day + i)];
    }
  }

  // ─── Navigation ────────────────────────────────────────────────────

  void selectDate(DateTime date) {
    _selectedDate = DateTime(date.year, date.month, date.day);
    _focusedDate = _selectedDate;
    _selectedEvent = null;
    _selectedOccurrence = null;
    notifyListeners();
  }

  void setFocusedDate(DateTime date) {
    _focusedDate = date;
    notifyListeners();
  }

  void selectEvent(CalendarEvent? event) {
    _selectedEvent = event;
    _selectedOccurrence = null;
    notifyListeners();
  }

  void selectOccurrence(EventOccurrence? occurrence) {
    _selectedOccurrence = occurrence;
    _selectedEvent = occurrence?.event;
    notifyListeners();
  }

  void setViewType(CalendarViewType type) {
    _viewType = type;
    _store.setString('calendarView', type.name);
    notifyListeners();
  }

  void goToToday() {
    _selectedDate = _today();
    _focusedDate = _today();
    notifyListeners();
  }

  void goToPrevious() => _step(-1);

  void goToNext() => _step(1);

  void _step(int direction) {
    final d = _selectedDate;
    switch (_viewType) {
      case CalendarViewType.day:
        _selectedDate = DateTime(d.year, d.month, d.day + direction);
        break;
      case CalendarViewType.workWeek:
      case CalendarViewType.week:
        _selectedDate = DateTime(d.year, d.month, d.day + 7 * direction);
        break;
      case CalendarViewType.month:
        final target = DateTime(_focusedDate.year, _focusedDate.month + direction, 1);
        final lastDay = DateTime(target.year, target.month + 1, 0).day;
        _selectedDate = DateTime(target.year, target.month, d.day.clamp(1, lastDay));
        break;
    }
    _focusedDate = _selectedDate;
    notifyListeners();
  }

  /// Title for the current view, e.g. "March 2026" or "March 2 - 8, 2026".
  String get rangeTitle {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    switch (_viewType) {
      case CalendarViewType.day:
        return '${months[_selectedDate.month - 1]} ${_selectedDate.day}, ${_selectedDate.year}';
      case CalendarViewType.month:
        return '${months[_focusedDate.month - 1]} ${_focusedDate.year}';
      case CalendarViewType.week:
      case CalendarViewType.workWeek:
        final days = visibleDays;
        final a = days.first;
        final b = days.last;
        if (a.month == b.month) {
          return '${months[a.month - 1]} ${a.day} - ${b.day}, ${b.year}';
        }
        return '${months[a.month - 1]} ${a.day} - ${months[b.month - 1]} ${b.day}, ${b.year}';
    }
  }

  // ─── Event CRUD ────────────────────────────────────────────────────

  void addEvent(CalendarEvent event) {
    _store.saveEvent(event);
    notifyListeners();
  }

  void addEvents(List<CalendarEvent> events) {
    _store.saveEvents(events);
    notifyListeners();
  }

  void updateEvent(CalendarEvent event) {
    _store.saveEvent(event);
    if (_selectedEvent?.id == event.id) {
      _selectedEvent = event;
      _selectedOccurrence = null;
    }
    notifyListeners();
  }

  void removeEvent(String id) {
    _store.removeEvent(id);
    if (_selectedEvent?.id == id) {
      _selectedEvent = null;
      _selectedOccurrence = null;
    }
    notifyListeners();
  }

  /// Removes a single occurrence from a recurring series.
  void removeOccurrence(EventOccurrence occurrence) {
    final event = occurrence.event;
    if (!event.isRecurring) return removeEvent(event.id);
    final day = DateTime(
        occurrence.start.year, occurrence.start.month, occurrence.start.day);
    updateEvent(event.copyWith(
      excludedDates: [...event.excludedDates, day],
      updatedAt: DateTime.now(),
    ));
  }

  CalendarEvent? eventByUid(String uid) => _store.getEventByUid(uid);

  CalendarEvent createDefaultEvent({DateTime? start}) {
    final now = DateTime.now();
    final begin = start ??
        DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          (now.hour + 1).clamp(0, 23),
        );
    return CalendarEvent(
      id: const Uuid().v4(),
      title: '',
      startTime: begin,
      endTime: begin.add(const Duration(minutes: 30)),
      reminder: ReminderTime.fifteenMinutes,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ─── Reminders ─────────────────────────────────────────────────────

  /// Occurrences whose reminder time has passed but that haven't started
  /// more than an hour ago, and were not reminded about yet.
  List<EventOccurrence> dueReminders(DateTime now) {
    final due = <EventOccurrence>[];
    final upcoming = _store.getOccurrencesInRange(
        now.subtract(const Duration(hours: 1)), now.add(const Duration(days: 3)));
    for (final o in upcoming) {
      final reminder = o.event.reminder;
      if (reminder == null || reminder == ReminderTime.none) continue;
      final at = o.start.subtract(reminder.duration);
      if (now.isBefore(at)) continue;
      if (now.isAfter(o.start.add(const Duration(hours: 1)))) continue;
      if (_remindedKeys.contains(o.key)) continue;
      due.add(o);
    }
    return due;
  }

  /// Shows desktop notifications for due reminders.
  void checkReminders(DateTime now) {
    for (final o in dueReminders(now)) {
      _remindedKeys.add(o.key);
      final minutes = o.start.difference(now).inMinutes;
      final when = minutes <= 0
          ? 'Now'
          : minutes < 60
              ? 'In $minutes minutes'
              : 'At ${o.start.hour.toString().padLeft(2, '0')}:${o.start.minute.toString().padLeft(2, '0')}';
      _notifications?.show(
        title: o.event.title.isEmpty ? '(No title)' : o.event.title,
        body: [when, if (o.event.location?.isNotEmpty ?? false) o.event.location!]
            .join(' · '),
        tag: 'reminder-${o.key}',
        icon: 'appointment-soon',
      );
    }
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    super.dispose();
  }
}

enum CalendarViewType {
  day,
  workWeek,
  week,
  month;

  String get label {
    switch (this) {
      case CalendarViewType.day:
        return 'Day';
      case CalendarViewType.workWeek:
        return 'Work Week';
      case CalendarViewType.week:
        return 'Week';
      case CalendarViewType.month:
        return 'Month';
    }
  }
}
