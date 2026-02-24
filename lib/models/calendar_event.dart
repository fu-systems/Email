import 'package:flutter/material.dart';
import '../theme/outlook_theme.dart';

/// Represents a calendar event.
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
  final List<String> attendees;
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
    this.attendees = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  Duration get duration => endTime.difference(startTime);

  bool get isMultiDay =>
      startTime.day != endTime.day ||
      startTime.month != endTime.month ||
      startTime.year != endTime.year;

  bool occursOn(DateTime date) {
    final start = DateTime(startTime.year, startTime.month, startTime.day);
    final end = DateTime(endTime.year, endTime.month, endTime.day);
    final target = DateTime(date.year, date.month, date.day);
    return !target.isBefore(start) && !target.isAfter(end);
  }

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
    List<String>? attendees,
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
      attendees: attendees ?? this.attendees,
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
        'attendees': attendees.join(';'),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CalendarEvent.fromMap(Map<String, dynamic> map) => CalendarEvent(
        id: map['id'] as String,
        title: map['title'] as String,
        description: map['description'] as String?,
        location: map['location'] as String?,
        startTime: DateTime.parse(map['startTime'] as String),
        endTime: DateTime.parse(map['endTime'] as String),
        isAllDay: (map['isAllDay'] as int?) == 1,
        category: EventCategory.values.byName(
          map['category'] as String? ?? 'blue',
        ),
        reminder: map['reminder'] != null
            ? ReminderTime.values.byName(map['reminder'] as String)
            : null,
        recurrence: map['recurrence'] != null
            ? RecurrenceRule.values.byName(map['recurrence'] as String)
            : null,
        attendees: (map['attendees'] as String?)
                ?.split(';')
                .where((s) => s.isNotEmpty)
                .toList() ??
            [],
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
      );
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
