import 'package:flutter/material.dart';
import '../theme/outlook_theme.dart';

/// Represents a calendar event. Recurring events are stored once and
/// expanded into [EventOccurrence]s on demand.
class CalendarEvent {
  final String id;
  final String title;
  final String? description;
  final String? location;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay;
  final EventCategory category;
  final ReminderTime? reminder;
  final RecurrenceRule? recurrence;

  /// Last day (inclusive) on which a recurring event may occur.
  final DateTime? recurrenceUntil;

  /// Maximum number of occurrences of a recurring event.
  final int? recurrenceCount;

  /// Dates (time ignored) of occurrences removed from a recurring series.
  final List<DateTime> excludedDates;

  final List<String> attendees;

  /// Organizer email address (for meeting invitations).
  final String? organizer;

  /// iCalendar UID; defaults to [id] for locally created events.
  final String? icalUid;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    this.location,
    required this.startTime,
    required this.endTime,
    this.isAllDay = false,
    this.category = EventCategory.blue,
    this.reminder,
    this.recurrence,
    this.recurrenceUntil,
    this.recurrenceCount,
    this.excludedDates = const [],
    this.attendees = const [],
    this.organizer,
    this.icalUid,
    required this.createdAt,
    required this.updatedAt,
  });

  Duration get duration => endTime.difference(startTime);

  bool get isRecurring =>
      recurrence != null && recurrence != RecurrenceRule.none;

  String get uid => icalUid ?? id;

  bool get isMultiDay =>
      startTime.day != endTime.day ||
      startTime.month != endTime.month ||
      startTime.year != endTime.year;

  /// Whether any occurrence of this event overlaps the given calendar day.
  bool occursOn(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = DateTime(date.year, date.month, date.day + 1);
    return occurrencesBetween(dayStart, dayEnd).isNotEmpty;
  }

  /// All occurrences that overlap the half-open range [rangeStart, rangeEnd).
  List<EventOccurrence> occurrencesBetween(
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final result = <EventOccurrence>[];
    final length = duration.isNegative ? Duration.zero : duration;
    // Occurrence ends are computed on the wall clock (same number of days
    // after the start, same time of day) so that daylight saving changes
    // don't shift them, e.g. an all-day event on a 23-hour day.
    final endDayOffset = _daysBetween(startTime, endTime);

    DateTime endOf(DateTime s) {
      if (length == Duration.zero) return s;
      final e = DateTime(s.year, s.month, s.day + endDayOffset, endTime.hour,
          endTime.minute, endTime.second, endTime.millisecond);
      return e.isBefore(s) ? s : e;
    }

    bool overlaps(DateTime s) {
      // Zero-length events are treated as instants inside the range.
      if (length == Duration.zero) {
        return !s.isBefore(rangeStart) && s.isBefore(rangeEnd);
      }
      return s.isBefore(rangeEnd) && endOf(s).isAfter(rangeStart);
    }

    if (!isRecurring) {
      if (overlaps(startTime)) {
        result.add(EventOccurrence(event: this, start: startTime, end: endTime));
      }
      return result;
    }

    final until = recurrenceUntil == null
        ? null
        : DateTime(recurrenceUntil!.year, recurrenceUntil!.month,
            recurrenceUntil!.day + 1);
    final excluded = excludedDates.map(_dateKey).toSet();
    final maxCount = recurrenceCount;

    // Jump close to the query range instead of iterating from the first
    // occurrence: [skipDays] is a safe lower bound (in days after the series
    // start) for occurrences that can still overlap the range. [produced]
    // counts the skipped occurrences so COUNT limits stay exact.
    final skipDays =
        _daysBetween(startTime, rangeStart) - endDayOffset - length.inDays - 2;
    var index = 0;
    var produced = 0;
    var weekdayCursor = DateTime(startTime.year, startTime.month, startTime.day);
    if (skipDays > 0) {
      switch (recurrence) {
        case RecurrenceRule.daily:
        case RecurrenceRule.weekly:
        case RecurrenceRule.biweekly:
          index = skipDays ~/ _periodDays!;
          break;
        case RecurrenceRule.monthly:
          index = ((rangeStart.year - startTime.year) * 12 +
                  rangeStart.month -
                  startTime.month -
                  1 -
                  endDayOffset ~/ 28)
              .clamp(0, 1 << 30);
          break;
        case RecurrenceRule.yearly:
          index = (rangeStart.year - startTime.year - 1 - endDayOffset ~/ 365)
              .clamp(0, 1 << 30);
          break;
        case RecurrenceRule.weekdays:
          final jumpTo = DateTime(weekdayCursor.year, weekdayCursor.month,
              weekdayCursor.day + skipDays);
          produced = _weekdaysBetween(weekdayCursor, jumpTo);
          weekdayCursor = jumpTo;
          break;
        default:
          break;
      }
      if (recurrence != RecurrenceRule.weekdays) produced = index;
    }

    // Safety bound so malformed data can never loop forever.
    for (var guard = 0; guard < 100000; guard++) {
      final DateTime occurrence;
      if (recurrence == RecurrenceRule.weekdays) {
        while (weekdayCursor.weekday > DateTime.friday) {
          weekdayCursor = DateTime(weekdayCursor.year, weekdayCursor.month,
              weekdayCursor.day + 1);
        }
        occurrence = DateTime(weekdayCursor.year, weekdayCursor.month,
            weekdayCursor.day, startTime.hour, startTime.minute,
            startTime.second);
        weekdayCursor = DateTime(
            weekdayCursor.year, weekdayCursor.month, weekdayCursor.day + 1);
      } else {
        occurrence = _nth(index);
        index++;
      }

      if (until != null && !occurrence.isBefore(until)) break;
      if (!occurrence.isBefore(rangeEnd)) break;
      if (maxCount != null && produced >= maxCount) break;
      produced++;

      if (excluded.contains(_dateKey(occurrence))) continue;
      if (overlaps(occurrence)) {
        result.add(EventOccurrence(
          event: this,
          start: occurrence,
          end: endOf(occurrence),
        ));
      }
    }
    return result;
  }

  int? get _periodDays {
    switch (recurrence) {
      case RecurrenceRule.daily:
        return 1;
      case RecurrenceRule.weekly:
        return 7;
      case RecurrenceRule.biweekly:
        return 14;
      default:
        return null;
    }
  }

  /// The [n]th occurrence start for rules other than weekdays.
  DateTime _nth(int n) {
    final s = startTime;
    switch (recurrence) {
      case RecurrenceRule.daily:
        return DateTime(s.year, s.month, s.day + n, s.hour, s.minute, s.second);
      case RecurrenceRule.weekly:
        return DateTime(
            s.year, s.month, s.day + 7 * n, s.hour, s.minute, s.second);
      case RecurrenceRule.biweekly:
        return DateTime(
            s.year, s.month, s.day + 14 * n, s.hour, s.minute, s.second);
      case RecurrenceRule.monthly:
        final firstOfMonth = DateTime(s.year, s.month + n, 1);
        final day = s.day.clamp(1, _daysInMonth(firstOfMonth));
        return DateTime(firstOfMonth.year, firstOfMonth.month, day, s.hour,
            s.minute, s.second);
      case RecurrenceRule.yearly:
        final firstOfMonth = DateTime(s.year + n, s.month, 1);
        final day = s.day.clamp(1, _daysInMonth(firstOfMonth));
        return DateTime(firstOfMonth.year, firstOfMonth.month, day, s.hour,
            s.minute, s.second);
      default:
        return s;
    }
  }

  /// Number of Monday–Friday days in the half-open range [from, to).
  static int _weekdaysBetween(DateTime from, DateTime to) {
    final days = _daysBetween(from, to);
    if (days <= 0) return 0;
    var count = (days ~/ 7) * 5;
    var weekday = from.weekday;
    for (var i = 0; i < days % 7; i++) {
      if (weekday <= DateTime.friday) count++;
      weekday = weekday == DateTime.sunday ? DateTime.monday : weekday + 1;
    }
    return count;
  }

  static int _daysInMonth(DateTime firstOfMonth) =>
      DateTime(firstOfMonth.year, firstOfMonth.month + 1, 0).day;

  static int _daysBetween(DateTime a, DateTime b) {
    final da = DateTime.utc(a.year, a.month, a.day);
    final db = DateTime.utc(b.year, b.month, b.day);
    return db.difference(da).inDays;
  }

  static int _dateKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  CalendarEvent copyWith({
    String? id,
    String? title,
    String? description,
    String? location,
    DateTime? startTime,
    DateTime? endTime,
    bool? isAllDay,
    EventCategory? category,
    ReminderTime? reminder,
    RecurrenceRule? recurrence,
    DateTime? recurrenceUntil,
    bool clearRecurrenceUntil = false,
    int? recurrenceCount,
    bool clearRecurrenceCount = false,
    List<DateTime>? excludedDates,
    List<String>? attendees,
    String? organizer,
    String? icalUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isAllDay: isAllDay ?? this.isAllDay,
      category: category ?? this.category,
      reminder: reminder ?? this.reminder,
      recurrence: recurrence ?? this.recurrence,
      recurrenceUntil: clearRecurrenceUntil
          ? null
          : (recurrenceUntil ?? this.recurrenceUntil),
      recurrenceCount: clearRecurrenceCount
          ? null
          : (recurrenceCount ?? this.recurrenceCount),
      excludedDates: excludedDates ?? this.excludedDates,
      attendees: attendees ?? this.attendees,
      organizer: organizer ?? this.organizer,
      icalUid: icalUid ?? this.icalUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'location': location,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'isAllDay': isAllDay ? 1 : 0,
        'category': category.name,
        'reminder': reminder?.name,
        'recurrence': recurrence?.name,
        'recurrenceUntil': recurrenceUntil?.toIso8601String(),
        'recurrenceCount': recurrenceCount,
        'excludedDates': excludedDates.map((d) => d.toIso8601String()).toList(),
        'attendees': attendees,
        'organizer': organizer,
        'icalUid': icalUid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CalendarEvent.fromMap(Map<String, dynamic> map) => CalendarEvent(
        id: map['id'] as String,
        title: map['title'] as String? ?? '',
        description: map['description'] as String?,
        location: map['location'] as String?,
        startTime: DateTime.parse(map['startTime'] as String),
        endTime: DateTime.parse(map['endTime'] as String),
        isAllDay: (map['isAllDay'] as int?) == 1,
        category: EventCategory.values
                .asNameMap()[map['category'] as String? ?? 'blue'] ??
            EventCategory.blue,
        reminder: ReminderTime.values.asNameMap()[map['reminder']],
        recurrence: RecurrenceRule.values.asNameMap()[map['recurrence']],
        recurrenceUntil: map['recurrenceUntil'] == null
            ? null
            : DateTime.parse(map['recurrenceUntil'] as String),
        recurrenceCount: map['recurrenceCount'] as int?,
        excludedDates: (map['excludedDates'] as List? ?? const [])
            .map((d) => DateTime.parse(d as String))
            .toList(),
        attendees: _parseAttendees(map['attendees']),
        organizer: map['organizer'] as String?,
        icalUid: map['icalUid'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
      );

  static List<String> _parseAttendees(Object? raw) {
    if (raw is List) return raw.cast<String>();
    if (raw is String) {
      return raw.split(';').where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }
}

/// A single concrete occurrence of a (possibly recurring) event.
class EventOccurrence {
  final CalendarEvent event;
  final DateTime start;
  final DateTime end;

  const EventOccurrence({
    required this.event,
    required this.start,
    required this.end,
  });

  /// Stable key identifying this occurrence within its series.
  String get key => '${event.id}@${start.toIso8601String()}';
}

enum EventCategory {
  blue,
  green,
  red,
  orange,
  purple;

  Color get color {
    switch (this) {
      case EventCategory.blue:
        return OutlookTheme.calendarEventDefault;
      case EventCategory.green:
        return OutlookTheme.calendarEventGreen;
      case EventCategory.red:
        return OutlookTheme.calendarEventRed;
      case EventCategory.orange:
        return OutlookTheme.calendarEventOrange;
      case EventCategory.purple:
        return OutlookTheme.calendarEventPurple;
    }
  }

  String get displayName {
    switch (this) {
      case EventCategory.blue:
        return 'Blue Category';
      case EventCategory.green:
        return 'Green Category';
      case EventCategory.red:
        return 'Red Category';
      case EventCategory.orange:
        return 'Orange Category';
      case EventCategory.purple:
        return 'Purple Category';
    }
  }
}

enum ReminderTime {
  none,
  atTime,
  fiveMinutes,
  fifteenMinutes,
  thirtyMinutes,
  oneHour,
  twoHours,
  oneDay,
  twoDays;

  String get displayName {
    switch (this) {
      case ReminderTime.none:
        return 'None';
      case ReminderTime.atTime:
        return 'At time of event';
      case ReminderTime.fiveMinutes:
        return '5 minutes';
      case ReminderTime.fifteenMinutes:
        return '15 minutes';
      case ReminderTime.thirtyMinutes:
        return '30 minutes';
      case ReminderTime.oneHour:
        return '1 hour';
      case ReminderTime.twoHours:
        return '2 hours';
      case ReminderTime.oneDay:
        return '1 day';
      case ReminderTime.twoDays:
        return '2 days';
    }
  }

  Duration get duration {
    switch (this) {
      case ReminderTime.none:
        return Duration.zero;
      case ReminderTime.atTime:
        return Duration.zero;
      case ReminderTime.fiveMinutes:
        return const Duration(minutes: 5);
      case ReminderTime.fifteenMinutes:
        return const Duration(minutes: 15);
      case ReminderTime.thirtyMinutes:
        return const Duration(minutes: 30);
      case ReminderTime.oneHour:
        return const Duration(hours: 1);
      case ReminderTime.twoHours:
        return const Duration(hours: 2);
      case ReminderTime.oneDay:
        return const Duration(days: 1);
      case ReminderTime.twoDays:
        return const Duration(days: 2);
    }
  }

  /// Closest reminder option for a trigger offset (e.g. from an iCal VALARM).
  static ReminderTime closestTo(Duration before) {
    var best = ReminderTime.atTime;
    var bestDiff = before.inMinutes.abs();
    for (final r in ReminderTime.values) {
      if (r == ReminderTime.none) continue;
      final diff = (r.duration.inMinutes - before.inMinutes).abs();
      if (diff < bestDiff) {
        best = r;
        bestDiff = diff;
      }
    }
    return best;
  }
}

enum RecurrenceRule {
  none,
  daily,
  weekdays,
  weekly,
  biweekly,
  monthly,
  yearly;

  String get displayName {
    switch (this) {
      case RecurrenceRule.none:
        return 'Does not repeat';
      case RecurrenceRule.daily:
        return 'Daily';
      case RecurrenceRule.weekdays:
        return 'Every weekday (Mon-Fri)';
      case RecurrenceRule.weekly:
        return 'Weekly';
      case RecurrenceRule.biweekly:
        return 'Every 2 weeks';
      case RecurrenceRule.monthly:
        return 'Monthly';
      case RecurrenceRule.yearly:
        return 'Yearly';
    }
  }
}
