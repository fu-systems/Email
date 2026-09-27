import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/calendar_event.dart';
import '../services/data_store.dart';
import '../services/notification_service.dart';
import '../services/sync/graph_pim_sync.dart';

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

  /// Microsoft calendars (optional).
  final GraphPimSync? _pim;

  /// Calendars not shown: `local` or a source id.
  final Set<String> _hidden = {};

  CalendarProvider({DataStore? store, this._notifications, this._pim})
      : _store = store ?? DataStore.instance {
    _viewType = CalendarViewType.values
            .asNameMap()[_store.getString('calendarView') ?? 'month'] ??
        CalendarViewType.month;
    try {
      _hidden.addAll(
          (jsonDecode(_store.getString('hiddenCalendars') ?? '[]') as List)
              .cast<String>());
    } catch (_) {}
    _pim?.addListener(_onSynced);
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

  void _onSynced() {
    // The selected event may have been changed or removed by the sync.
    final selected = _selectedEvent;
    if (selected != null && _store.getEvent(selected.id) == null) {
      _selectedEvent = null;
      _selectedOccurrence = null;
    }
    notifyListeners();
  }

  // ─── Calendars ─────────────────────────────────────────────────────

  /// The local calendar and one per Microsoft account.
  List<({String? id, String label})> get calendars => [
        (id: null, label: 'Calendar'),
        for (final s in _pim?.sources ?? const <({String id, String label})>[])
          (id: s.id, label: 'Calendar - ${s.label}'),
      ];

  /// Short name of the calendar [sourceId] for forms and lists.
  String calendarLabel(String? sourceId) => sourceId == null
      ? 'Calendar'
      : 'Calendar - ${_pim?.labelFor(sourceId) ?? 'Microsoft account'}';

  /// The last sync problem of a Microsoft calendar.
  String? calendarError(String sourceId) =>
      _pim?.errorFor(sourceId, calendar: true);

  bool isCalendarVisible(String? sourceId) =>
      !_hidden.contains(sourceId ?? 'local');

  void setCalendarVisible(String? sourceId, bool visible) {
    final key = sourceId ?? 'local';
    visible ? _hidden.remove(key) : _hidden.add(key);
    _store.setString('hiddenCalendars', jsonEncode(_hidden.toList()));
    notifyListeners();
  }

  /// Where new appointments go (File > Options can't change it yet: the
  /// calendar chosen last in the appointment form).
  String? get defaultCalendarId {
    final id = _store.getString('defaultCalendar');
    if (id == null) return null;
    return calendars.any((c) => c.id == id) ? id : null;
  }

  set defaultCalendarId(String? id) =>
      _store.setString('defaultCalendar', id);

  bool _visible(EventOccurrence o) => isCalendarVisible(o.event.sourceId);

  List<EventOccurrence> get occurrencesForSelectedDate =>
      getOccurrencesForDate(_selectedDate);

  /// Events (not occurrences) that occur on the selected date.
  List<CalendarEvent> get eventsForSelectedDate =>
      occurrencesForSelectedDate.map((o) => o.event).toList();

  List<CalendarEvent> get allEvents => _store.events
      .where((e) => isCalendarVisible(e.sourceId))
      .toList();

  List<CalendarEvent> getEventsForDate(DateTime date) =>
      getOccurrencesForDate(date).map((o) => o.event).toList();

  List<EventOccurrence> getOccurrencesForDate(DateTime date) =>
      _store.getOccurrencesForDate(date).where(_visible).toList();

  List<EventOccurrence> getOccurrencesInRange(DateTime start, DateTime end) =>
      _store.getOccurrencesInRange(start, end).where(_visible).toList();

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
    _store.saveEvent(_pim?.prepareEvent(event) ?? event);
    _pim?.changed(event.sourceId);
    notifyListeners();
  }

  void addEvents(List<CalendarEvent> events) {
    _store.saveEvents(events);
    notifyListeners();
  }

  void updateEvent(CalendarEvent event) {
    event = _pim?.prepareEvent(event) ?? event;
    _store.saveEvent(event);
    _pim?.changed(event.sourceId);
    if (_selectedEvent?.id == event.id) {
      _selectedEvent = event;
      _selectedOccurrence = null;
    }
    notifyListeners();
  }

  void removeEvent(String id) {
    final event = _store.getEvent(id);
    if (event != null) _pim?.eventDeleted(event);
    _store.removeEvent(id);
    _pim?.changed(event?.sourceId);
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

  /// Whether [event] is an occurrence of a series kept on a server, which
  /// can be deleted as a whole.
  bool isServerSeriesOccurrence(CalendarEvent event) =>
      event.seriesMasterId != null;

  /// Deletes the whole series [event] belongs to (Microsoft calendars).
  void removeSeries(CalendarEvent event) {
    final master = event.seriesMasterId;
    if (master == null) return removeEvent(event.id);
    _pim?.seriesDeleted(event.sourceId, master);
    for (final e in _store.events
        .where((e) => e.sourceId == event.sourceId && e.seriesMasterId == master)
        .toList()) {
      _store.removeEvent(e.id);
    }
    _pim?.changed(event.sourceId);
    if (_selectedEvent?.seriesMasterId == master) {
      _selectedEvent = null;
      _selectedOccurrence = null;
    }
    notifyListeners();
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
      sourceId: defaultCalendarId,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ─── Reminders ─────────────────────────────────────────────────────

  /// Occurrences whose reminder time has passed but that haven't started
  /// more than an hour ago, and were not reminded about yet.
  List<EventOccurrence> dueReminders(DateTime now) {
    final due = <EventOccurrence>[];
    final upcoming = getOccurrencesInRange(
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
    _pim?.removeListener(_onSynced);
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
