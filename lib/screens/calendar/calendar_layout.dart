/// Pure date, formatting and layout helpers for the Calendar module.
///
/// Nothing in this file depends on widgets, so the layout rules (overlap
/// columns, all-day band rows, per-day grouping) can be unit tested.
library;

import '../../models/calendar_event.dart';

// ─── Dates ───────────────────────────────────────────────────────────

/// Midnight at the start of [d]'s calendar day.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Midnight of the day [days] calendar days after [d] (DST-safe).
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

/// Whether [a] and [b] fall on the same calendar day.
bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whole calendar days from [a]'s day to [b]'s day (negative if before).
int daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
    .difference(DateTime.utc(a.year, a.month, a.day))
    .inDays;

/// The last calendar day an occurrence covers. An end at exactly midnight
/// belongs to the previous day (the end is exclusive).
DateTime lastDayOf(EventOccurrence o) {
  final end = o.end;
  if (!end.isAfter(o.start)) return dateOnly(o.start);
  final atMidnight = end.hour == 0 &&
      end.minute == 0 &&
      end.second == 0 &&
      end.millisecond == 0 &&
      end.microsecond == 0;
  return atMidnight ? addDays(end, -1) : dateOnly(end);
}

/// Minutes from the start of [day] to [t], clamped to the day (0–1440).
int minuteOfDay(DateTime t, DateTime day) {
  if (t.isBefore(dateOnly(day))) return 0;
  if (!isSameDate(t, day)) return 24 * 60;
  return t.hour * 60 + t.minute;
}

/// Whether an occurrence is shown in the all-day band of the time grid
/// (and as a filled bar in the month view): all-day events and anything
/// lasting 24 hours or more.
bool isAllDayBandOccurrence(EventOccurrence o) =>
    o.event.isAllDay || o.end.difference(o.start) >= const Duration(hours: 24);

// ─── Formatting ──────────────────────────────────────────────────────

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];
const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  'Sunday',
];

/// Full month name, e.g. "March" (1-based [month]).
String monthName(int month) => _monthNames[month - 1];

/// Full weekday name for a [DateTime.weekday] value, e.g. "Monday".
String weekdayName(int weekday) => _weekdayNames[weekday - 1];

/// Event title, or "(No title)" when empty.
String displayTitle(CalendarEvent e) =>
    e.title.trim().isEmpty ? '(No title)' : e.title.trim();

/// 12-hour clock time for minutes after midnight, e.g. "9:00 AM".
String formatMinutes(int minutes) {
  final m = minutes % (24 * 60);
  final hour = m ~/ 60;
  final minute = m % 60;
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  final suffix = hour < 12 ? 'AM' : 'PM';
  return '$h12:${minute.toString().padLeft(2, '0')} $suffix';
}

/// 12-hour clock time, e.g. "9:00 AM".
String formatTime(DateTime t) => formatMinutes(t.hour * 60 + t.minute);

/// Hour label for the time grid gutter, e.g. "8 AM" or "12 PM".
String formatHourLabel(int hour) {
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12 ${hour < 12 ? 'AM' : 'PM'}';
}

/// Long date, e.g. "Wednesday, March 11, 2026".
String formatLongDate(DateTime d) =>
    '${weekdayName(d.weekday)}, ${monthName(d.month)} ${d.day}, ${d.year}';

/// Short date as shown in the appointment form, e.g. "Wed 3/11/2026".
String formatShortDate(DateTime d) =>
    '${weekdayName(d.weekday).substring(0, 3)} ${d.month}/${d.day}/${d.year}';

/// Human duration, e.g. "30 minutes", "1 hour", "1.5 hours", "2 days".
String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  if (minutes < 60) return '$minutes minute${minutes == 1 ? '' : 's'}';
  if (minutes % (24 * 60) == 0) {
    final days = minutes ~/ (24 * 60);
    return '$days day${days == 1 ? '' : 's'}';
  }
  final hours = minutes / 60;
  // "1.50" -> "1.5", "2.00" -> "2", "1.25" stays.
  final text = hours.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$text hour${hours == 1 ? '' : 's'}';
}

/// "All day", "9:00 AM - 10:00 AM", or a range with dates when the
/// occurrence spans several days.
String formatOccurrenceTime(EventOccurrence o) {
  final last = lastDayOf(o);
  if (o.event.isAllDay) {
    if (isSameDate(o.start, last)) return 'All day';
    return '${formatShortDate(o.start)} - ${formatShortDate(last)}';
  }
  if (isSameDate(o.start, o.end) || !o.end.isAfter(o.start)) {
    return '${formatTime(o.start)} - ${formatTime(o.end)}';
  }
  return '${formatShortDate(o.start)} ${formatTime(o.start)} - '
      '${formatShortDate(o.end)} ${formatTime(o.end)}';
}

// ─── Grouping ────────────────────────────────────────────────────────

/// Sort order within a day: band occurrences first, then by start time,
/// longer occurrences first.
int compareForDay(EventOccurrence a, EventOccurrence b) {
  final bandA = isAllDayBandOccurrence(a);
  final bandB = isAllDayBandOccurrence(b);
  if (bandA != bandB) return bandA ? -1 : 1;
  final byStart = a.start.compareTo(b.start);
  if (byStart != 0) return byStart;
  return b.end.compareTo(a.end);
}

/// Buckets [occurrences] into [dayCount] consecutive days starting at
/// [firstDay]. Occurrences spanning several days appear in every day they
/// cover. Each bucket is sorted with [compareForDay].
List<List<EventOccurrence>> occurrencesByDay(
  Iterable<EventOccurrence> occurrences,
  DateTime firstDay,
  int dayCount,
) {
  final buckets = List.generate(dayCount, (_) => <EventOccurrence>[]);
  for (final o in occurrences) {
    final first = daysBetween(firstDay, o.start);
    final last = daysBetween(firstDay, lastDayOf(o));
    for (var i = first < 0 ? 0 : first; i <= last && i < dayCount; i++) {
      buckets[i].add(o);
    }
  }
  for (final bucket in buckets) {
    bucket.sort(compareForDay);
  }
  return buckets;
}

/// The part of an occurrence that falls within one day of the time grid.
class DaySegment {
  /// The full (unclipped) occurrence.
  final EventOccurrence occurrence;

  /// Segment start, clipped to the day.
  final DateTime start;

  /// Segment end, clipped to the end of the day.
  final DateTime end;

  const DaySegment(this.occurrence, this.start, this.end);

  /// Whether the occurrence started on an earlier day.
  bool get continuesFromPreviousDay => occurrence.start.isBefore(start);

  /// Whether the occurrence ends on a later day.
  bool get continuesToNextDay => occurrence.end.isAfter(end);
}

/// Splits timed occurrences into per-day [DaySegment]s for [dayCount]
/// consecutive days starting at [firstDay].
List<List<DaySegment>> segmentsByDay(
  Iterable<EventOccurrence> occurrences,
  DateTime firstDay,
  int dayCount,
) {
  final days = List.generate(dayCount, (_) => <DaySegment>[]);
  for (final o in occurrences) {
    final first = daysBetween(firstDay, o.start);
    final last = daysBetween(firstDay, lastDayOf(o));
    for (var i = first < 0 ? 0 : first; i <= last && i < dayCount; i++) {
      final dayStart = addDays(firstDay, i);
      final dayEnd = addDays(firstDay, i + 1);
      final start = o.start.isBefore(dayStart) ? dayStart : o.start;
      final end = o.end.isAfter(dayEnd) ? dayEnd : o.end;
      days[i].add(DaySegment(o, start, end.isBefore(start) ? start : end));
    }
  }
  return days;
}

// ─── Overlap layout ──────────────────────────────────────────────────

/// Horizontal placement of an event in a day column: it occupies column
/// [column] (0-based) of [columns] equal-width columns.
typedef OverlapSlot = ({int column, int columns});

/// Assigns side-by-side columns to overlapping occurrences, keyed by
/// [EventOccurrence.key].
///
/// Occurrences are processed by start time (longer first on ties). Each is
/// put in the first column whose previous event has ended; a group of
/// transitively overlapping occurrences shares one column count. Events
/// shorter than [minDuration] are treated as lasting [minDuration], which
/// matches how they are drawn.
Map<String, OverlapSlot> layoutOverlaps(
  List<EventOccurrence> occurrences, {
  Duration minDuration = Duration.zero,
}) =>
    layoutIntervals<EventOccurrence>(
      occurrences,
      key: (o) => o.key,
      start: (o) => o.start,
      end: (o) => o.end,
      minDuration: minDuration,
    );

/// Generic form of [layoutOverlaps] for any interval type.
Map<String, OverlapSlot> layoutIntervals<T>(
  Iterable<T> items, {
  required String Function(T) key,
  required DateTime Function(T) start,
  required DateTime Function(T) end,
  Duration minDuration = Duration.zero,
}) {
  DateTime visualEnd(T item) {
    final s = start(item);
    final e = end(item);
    final min = s.add(minDuration);
    return e.isBefore(min) ? min : e;
  }

  final sorted = items.toList()
    ..sort((a, b) {
      final byStart = start(a).compareTo(start(b));
      if (byStart != 0) return byStart;
      return visualEnd(b).compareTo(visualEnd(a));
    });

  final result = <String, OverlapSlot>{};
  final cluster = <(T, int)>[];
  final columnEnds = <DateTime>[];
  DateTime? clusterEnd;

  void flush() {
    for (final (item, column) in cluster) {
      result[key(item)] = (column: column, columns: columnEnds.length);
    }
    cluster.clear();
    columnEnds.clear();
    clusterEnd = null;
  }

  for (final item in sorted) {
    final s = start(item);
    final e = visualEnd(item);
    if (clusterEnd != null && !s.isBefore(clusterEnd!)) flush();
    var column = columnEnds.indexWhere((end) => !end.isAfter(s));
    if (column == -1) {
      column = columnEnds.length;
      columnEnds.add(e);
    } else {
      columnEnds[column] = e;
    }
    cluster.add((item, column));
    if (clusterEnd == null || e.isAfter(clusterEnd!)) clusterEnd = e;
  }
  flush();
  return result;
}

// ─── All-day band layout ─────────────────────────────────────────────

/// Position of an occurrence in the all-day band: it spans day columns
/// [firstDay]..[lastDay] (inclusive, indexes into the visible days) on
/// row [row].
class BandPlacement {
  final EventOccurrence occurrence;
  final int firstDay;
  final int lastDay;
  final int row;

  const BandPlacement(this.occurrence, this.firstDay, this.lastDay, this.row);
}

/// Stacks band occurrences into rows so that no two overlap on a day.
/// Days outside [firstDay]..[firstDay]+[dayCount] are clipped away.
List<BandPlacement> layoutAllDayBand(
  Iterable<EventOccurrence> occurrences,
  DateTime firstDay,
  int dayCount,
) {
  final spans = <(EventOccurrence, int, int)>[];
  for (final o in occurrences) {
    final first = daysBetween(firstDay, o.start);
    final last = daysBetween(firstDay, lastDayOf(o));
    if (last < 0 || first >= dayCount) continue;
    spans.add((o, first < 0 ? 0 : first, last >= dayCount ? dayCount - 1 : last));
  }
  spans.sort((a, b) {
    final byFirst = a.$2.compareTo(b.$2);
    if (byFirst != 0) return byFirst;
    final bySpan = (b.$3 - b.$2).compareTo(a.$3 - a.$2);
    if (bySpan != 0) return bySpan;
    return a.$1.start.compareTo(b.$1.start);
  });

  final rows = <List<bool>>[];
  final placements = <BandPlacement>[];
  for (final (o, first, last) in spans) {
    var row = rows.indexWhere((used) {
      for (var d = first; d <= last; d++) {
        if (used[d]) return false;
      }
      return true;
    });
    if (row == -1) {
      row = rows.length;
      rows.add(List.filled(dayCount, false));
    }
    for (var d = first; d <= last; d++) {
      rows[row][d] = true;
    }
    placements.add(BandPlacement(o, first, last, row));
  }
  return placements;
}
