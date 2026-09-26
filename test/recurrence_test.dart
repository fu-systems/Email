import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/calendar_event.dart';

CalendarEvent event({
  required DateTime start,
  DateTime? end,
  Duration length = const Duration(hours: 1),
  bool isAllDay = false,
  RecurrenceRule? recurrence,
  DateTime? until,
  int? count,
  List<DateTime> excluded = const [],
}) =>
    CalendarEvent(
      id: 'e1',
      title: 'Test',
      startTime: start,
      endTime: end ?? start.add(length),
      isAllDay: isAllDay,
      recurrence: recurrence,
      recurrenceUntil: until,
      recurrenceCount: count,
      excludedDates: excluded,
      createdAt: DateTime(2020),
      updatedAt: DateTime(2020),
    );

List<DateTime> starts(CalendarEvent e, DateTime from, DateTime to) =>
    e.occurrencesBetween(from, to).map((o) => o.start).toList();

void main() {
  group('non-recurring events', () {
    final e = event(start: DateTime(2026, 1, 5, 9));

    test('occurs only on its own day', () {
      expect(e.occursOn(DateTime(2026, 1, 5)), isTrue);
      expect(e.occursOn(DateTime(2026, 1, 5, 23, 59)), isTrue);
      expect(e.occursOn(DateTime(2026, 1, 4)), isFalse);
      expect(e.occursOn(DateTime(2026, 1, 6)), isFalse);
    });

    test('occurrencesBetween returns the event itself', () {
      final occurrences =
          e.occurrencesBetween(DateTime(2026, 1, 1), DateTime(2026, 2, 1));
      expect(occurrences, hasLength(1));
      expect(occurrences.single.start, e.startTime);
      expect(occurrences.single.end, e.endTime);
      expect(occurrences.single.event, same(e));
      expect(occurrences.single.key, 'e1@${e.startTime.toIso8601String()}');
    });

    test('range bounds are half-open', () {
      // Ends exactly at the range start: no overlap.
      expect(
          e.occurrencesBetween(DateTime(2026, 1, 5, 10), DateTime(2026, 1, 6)),
          isEmpty);
      // Starts exactly at the range end: no overlap.
      expect(
          e.occurrencesBetween(DateTime(2026, 1, 4), DateTime(2026, 1, 5, 9)),
          isEmpty);
      expect(
          e.occurrencesBetween(
              DateTime(2026, 1, 5, 9, 59), DateTime(2026, 1, 5, 9, 59, 30)),
          hasLength(1));
    });

    test('RecurrenceRule.none behaves like no recurrence', () {
      final none = event(
          start: DateTime(2026, 1, 5, 9), recurrence: RecurrenceRule.none);
      expect(none.isRecurring, isFalse);
      expect(starts(none, DateTime(2026), DateTime(2027)),
          [DateTime(2026, 1, 5, 9)]);
    });

    test('multi-day event overlaps every day it spans', () {
      final trip = event(
        start: DateTime(2026, 1, 5, 18),
        end: DateTime(2026, 1, 8, 10),
      );
      expect(trip.isMultiDay, isTrue);
      for (final day in [5, 6, 7, 8]) {
        expect(trip.occursOn(DateTime(2026, 1, day)), isTrue, reason: '$day');
      }
      expect(trip.occursOn(DateTime(2026, 1, 9)), isFalse);
      expect(trip.occursOn(DateTime(2026, 1, 4)), isFalse);
    });

    test('zero-length events are instants inside the range', () {
      final instant =
          event(start: DateTime(2026, 1, 5, 9), length: Duration.zero);
      expect(instant.occursOn(DateTime(2026, 1, 5)), isTrue);
      expect(
          instant.occurrencesBetween(
              DateTime(2026, 1, 5, 9), DateTime(2026, 1, 5, 10)),
          hasLength(1));
      expect(
          instant.occurrencesBetween(
              DateTime(2026, 1, 5, 8), DateTime(2026, 1, 5, 9)),
          isEmpty);
    });

    test('all-day event ending at 23:59 does not spill into the next day', () {
      final holiday = event(
        start: DateTime(2026, 1, 5),
        end: DateTime(2026, 1, 5, 23, 59),
        isAllDay: true,
      );
      expect(holiday.occursOn(DateTime(2026, 1, 5)), isTrue);
      expect(holiday.occursOn(DateTime(2026, 1, 6)), isFalse);
    });
  });

  group('daily', () {
    test('every day from the start', () {
      final e = event(
          start: DateTime(2026, 1, 5, 9), recurrence: RecurrenceRule.daily);
      expect(starts(e, DateTime(2026, 1, 1), DateTime(2026, 1, 10)), [
        DateTime(2026, 1, 5, 9),
        DateTime(2026, 1, 6, 9),
        DateTime(2026, 1, 7, 9),
        DateTime(2026, 1, 8, 9),
        DateTime(2026, 1, 9, 9),
      ]);
      expect(e.occursOn(DateTime(2026, 1, 4)), isFalse);
      expect(e.occursOn(DateTime(2026, 3, 15)), isTrue);
    });

    test('occurrence ends keep the event length', () {
      final e = event(
        start: DateTime(2026, 1, 5, 9),
        length: const Duration(minutes: 30),
        recurrence: RecurrenceRule.daily,
      );
      final o = e
          .occurrencesBetween(DateTime(2026, 1, 7), DateTime(2026, 1, 8))
          .single;
      expect(o.start, DateTime(2026, 1, 7, 9));
      expect(o.end, DateTime(2026, 1, 7, 9, 30));
    });

    test('keeps local wall-clock time across months and years', () {
      final e = event(
          start: DateTime(2026, 12, 30, 23, 15),
          recurrence: RecurrenceRule.daily);
      expect(starts(e, DateTime(2026, 12, 30), DateTime(2027, 1, 3)), [
        DateTime(2026, 12, 30, 23, 15),
        DateTime(2026, 12, 31, 23, 15),
        DateTime(2027, 1, 1, 23, 15),
        DateTime(2027, 1, 2, 23, 15),
      ]);
    });

    test('keeps local wall-clock time across the whole year', () {
      final e = event(
          start: DateTime(2026, 1, 1, 9, 30), recurrence: RecurrenceRule.daily);
      final all = starts(e, DateTime(2026), DateTime(2027));
      expect(all, hasLength(365));
      expect(all.every((s) => s.hour == 9 && s.minute == 30), isTrue);
    });
  });

  group('weekdays', () {
    test('series starting on a weekend begins on Monday', () {
      final saturday = DateTime(2026, 1, 3, 9);
      final e = event(start: saturday, recurrence: RecurrenceRule.weekdays);
      final result = starts(e, DateTime(2026, 1, 1), DateTime(2026, 1, 17));
      expect(result, [
        for (final d in [5, 6, 7, 8, 9, 12, 13, 14, 15, 16])
          DateTime(2026, 1, d, 9),
      ]);
      expect(e.occursOn(DateTime(2026, 1, 3)), isFalse);
      expect(e.occursOn(DateTime(2026, 1, 4)), isFalse);
      expect(e.occursOn(DateTime(2026, 1, 10)), isFalse);
      expect(e.occursOn(DateTime(2026, 1, 11)), isFalse);
      expect(e.occursOn(DateTime(2026, 1, 12)), isTrue);
    });

    test('never on Saturday or Sunday over a long range', () {
      final e = event(
          start: DateTime(2026, 1, 5, 8), recurrence: RecurrenceRule.weekdays);
      final all = starts(e, DateTime(2026), DateTime(2027));
      expect(all.any((s) => s.weekday > DateTime.friday), isFalse);
      // 2026 has 261 weekdays; the series starts after Thu 1 and Fri 2 Jan.
      expect(all, hasLength(259));
    });

    test('with a count starting on a Friday', () {
      final e = event(
        start: DateTime(2026, 1, 9, 9),
        recurrence: RecurrenceRule.weekdays,
        count: 3,
      );
      expect(starts(e, DateTime(2026), DateTime(2027)), [
        DateTime(2026, 1, 9, 9),
        DateTime(2026, 1, 12, 9),
        DateTime(2026, 1, 13, 9),
      ]);
    });

    test('with an until date on a weekend', () {
      final e = event(
        start: DateTime(2026, 1, 5, 9),
        recurrence: RecurrenceRule.weekdays,
        until: DateTime(2026, 1, 11),
      );
      expect(starts(e, DateTime(2026), DateTime(2027)), hasLength(5));
    });
  });

  group('weekly and biweekly', () {
    test('weekly on the start weekday', () {
      final e = event(
          start: DateTime(2026, 1, 5, 10), recurrence: RecurrenceRule.weekly);
      expect(starts(e, DateTime(2026, 1, 1), DateTime(2026, 2, 1)), [
        DateTime(2026, 1, 5, 10),
        DateTime(2026, 1, 12, 10),
        DateTime(2026, 1, 19, 10),
        DateTime(2026, 1, 26, 10),
      ]);
      expect(e.occursOn(DateTime(2026, 1, 13)), isFalse);
    });

    test('biweekly every other week', () {
      final e = event(
          start: DateTime(2026, 1, 5, 10), recurrence: RecurrenceRule.biweekly);
      expect(starts(e, DateTime(2026, 1, 1), DateTime(2026, 2, 15)), [
        DateTime(2026, 1, 5, 10),
        DateTime(2026, 1, 19, 10),
        DateTime(2026, 2, 2, 10),
      ]);
      expect(e.occursOn(DateTime(2026, 1, 12)), isFalse);
      expect(e.occursOn(DateTime(2026, 1, 26)), isFalse);
    });

    test('biweekly queried mid-series stays on the right weeks', () {
      final e = event(
          start: DateTime(2026, 1, 5, 10), recurrence: RecurrenceRule.biweekly);
      // 2026-06-29 is 25 weeks after the start (odd): no occurrence.
      expect(e.occursOn(DateTime(2026, 6, 29)), isFalse);
      // 2026-07-06 is 26 weeks after the start (even).
      expect(e.occursOn(DateTime(2026, 7, 6)), isTrue);
    });
  });

  group('monthly', () {
    test('on the 31st clamps to the last day of shorter months', () {
      final e = event(
          start: DateTime(2026, 1, 31, 12), recurrence: RecurrenceRule.monthly);
      expect(starts(e, DateTime(2026, 1, 1), DateTime(2026, 6, 1)), [
        DateTime(2026, 1, 31, 12),
        DateTime(2026, 2, 28, 12),
        DateTime(2026, 3, 31, 12),
        DateTime(2026, 4, 30, 12),
        DateTime(2026, 5, 31, 12),
      ]);
    });

    test('on the 31st in a leap year uses February 29th', () {
      final e = event(
          start: DateTime(2028, 1, 31, 12), recurrence: RecurrenceRule.monthly);
      expect(starts(e, DateTime(2028, 2, 1), DateTime(2028, 3, 1)),
          [DateTime(2028, 2, 29, 12)]);
    });

    test('on the 30th', () {
      final e = event(
          start: DateTime(2026, 1, 30, 8), recurrence: RecurrenceRule.monthly);
      expect(starts(e, DateTime(2026, 2, 1), DateTime(2026, 4, 1)), [
        DateTime(2026, 2, 28, 8),
        DateTime(2026, 3, 30, 8),
      ]);
    });

    test('across a year boundary', () {
      final e = event(
          start: DateTime(2026, 11, 15, 8), recurrence: RecurrenceRule.monthly);
      expect(starts(e, DateTime(2026, 11, 1), DateTime(2027, 3, 1)), [
        DateTime(2026, 11, 15, 8),
        DateTime(2026, 12, 15, 8),
        DateTime(2027, 1, 15, 8),
        DateTime(2027, 2, 15, 8),
      ]);
    });
  });

  group('yearly', () {
    test('on February 29th falls back to February 28th', () {
      final e = event(
          start: DateTime(2024, 2, 29, 9), recurrence: RecurrenceRule.yearly);
      expect(starts(e, DateTime(2024), DateTime(2029)), [
        DateTime(2024, 2, 29, 9),
        DateTime(2025, 2, 28, 9),
        DateTime(2026, 2, 28, 9),
        DateTime(2027, 2, 28, 9),
        DateTime(2028, 2, 29, 9),
      ]);
    });

    test('ordinary date', () {
      final e = event(
        start: DateTime(2020, 7, 4),
        end: DateTime(2020, 7, 4, 23, 59),
        isAllDay: true,
        recurrence: RecurrenceRule.yearly,
      );
      expect(e.occursOn(DateTime(2031, 7, 4)), isTrue);
      expect(e.occursOn(DateTime(2031, 7, 5)), isFalse);
      expect(e.occursOn(DateTime(2019, 7, 4)), isFalse);
    });
  });

  group('limits', () {
    test('recurrenceUntil is inclusive', () {
      final e = event(
        start: DateTime(2026, 1, 5, 9),
        recurrence: RecurrenceRule.daily,
        until: DateTime(2026, 1, 8),
      );
      expect(starts(e, DateTime(2026), DateTime(2027)), [
        DateTime(2026, 1, 5, 9),
        DateTime(2026, 1, 6, 9),
        DateTime(2026, 1, 7, 9),
        DateTime(2026, 1, 8, 9),
      ]);
      expect(e.occursOn(DateTime(2026, 1, 8)), isTrue);
      expect(e.occursOn(DateTime(2026, 1, 9)), isFalse);
    });

    test('recurrenceUntil ignores its time of day', () {
      final e = event(
        start: DateTime(2026, 1, 5, 21),
        recurrence: RecurrenceRule.weekly,
        until: DateTime(2026, 1, 19, 0, 0, 1),
      );
      expect(starts(e, DateTime(2026), DateTime(2027)).last,
          DateTime(2026, 1, 19, 21));
    });

    test('recurrenceCount limits the number of occurrences', () {
      final e = event(
        start: DateTime(2026, 1, 5, 9),
        recurrence: RecurrenceRule.daily,
        count: 3,
      );
      expect(starts(e, DateTime(2026), DateTime(2027)), [
        DateTime(2026, 1, 5, 9),
        DateTime(2026, 1, 6, 9),
        DateTime(2026, 1, 7, 9),
      ]);
      expect(starts(e, DateTime(2026, 1, 7), DateTime(2027)),
          [DateTime(2026, 1, 7, 9)]);
      expect(starts(e, DateTime(2026, 1, 8), DateTime(2027)), isEmpty);
    });

    test('recurrenceCount for monthly and yearly rules', () {
      final monthly = event(
        start: DateTime(2026, 1, 31, 9),
        recurrence: RecurrenceRule.monthly,
        count: 2,
      );
      expect(starts(monthly, DateTime(2026), DateTime(2027)),
          [DateTime(2026, 1, 31, 9), DateTime(2026, 2, 28, 9)]);
      final yearly = event(
        start: DateTime(2026, 5, 1, 9),
        recurrence: RecurrenceRule.yearly,
        count: 2,
      );
      expect(starts(yearly, DateTime(2026), DateTime(2040)), hasLength(2));
    });

    test('until and count together: whichever ends first', () {
      final e = event(
        start: DateTime(2026, 1, 5, 9),
        recurrence: RecurrenceRule.daily,
        until: DateTime(2026, 1, 6),
        count: 10,
      );
      expect(starts(e, DateTime(2026), DateTime(2027)), hasLength(2));
      final e2 = event(
        start: DateTime(2026, 1, 5, 9),
        recurrence: RecurrenceRule.daily,
        until: DateTime(2026, 1, 30),
        count: 2,
      );
      expect(starts(e2, DateTime(2026), DateTime(2027)), hasLength(2));
    });

    test('excludedDates remove occurrences (time of day ignored)', () {
      final e = event(
        start: DateTime(2026, 1, 5, 10),
        recurrence: RecurrenceRule.weekly,
        excluded: [DateTime(2026, 1, 12, 15, 30), DateTime(2026, 1, 20)],
      );
      expect(starts(e, DateTime(2026, 1, 1), DateTime(2026, 2, 1)), [
        DateTime(2026, 1, 5, 10),
        DateTime(2026, 1, 19, 10),
        DateTime(2026, 1, 26, 10),
      ]);
      expect(e.occursOn(DateTime(2026, 1, 12)), isFalse);
    });

    test('excluded occurrences still count toward recurrenceCount', () {
      final e = event(
        start: DateTime(2026, 1, 5, 9),
        recurrence: RecurrenceRule.daily,
        count: 3,
        excluded: [DateTime(2026, 1, 6)],
      );
      expect(starts(e, DateTime(2026), DateTime(2027)),
          [DateTime(2026, 1, 5, 9), DateTime(2026, 1, 7, 9)]);
    });

    test('excluding the first occurrence', () {
      final e = event(
        start: DateTime(2026, 1, 5, 9),
        recurrence: RecurrenceRule.weekly,
        excluded: [DateTime(2026, 1, 5)],
      );
      expect(e.occursOn(DateTime(2026, 1, 5)), isFalse);
      expect(e.occursOn(DateTime(2026, 1, 12)), isTrue);
    });
  });

  group('multi-day recurring events', () {
    test('weekly weekend event overlapping the range start', () {
      final e = event(
        start: DateTime(2026, 1, 9, 18),
        end: DateTime(2026, 1, 11, 12),
        recurrence: RecurrenceRule.weekly,
      );
      final saturday =
          e.occurrencesBetween(DateTime(2026, 1, 10), DateTime(2026, 1, 11));
      expect(saturday.single.start, DateTime(2026, 1, 9, 18));
      expect(saturday.single.end, DateTime(2026, 1, 11, 12));
      expect(e.occursOn(DateTime(2026, 1, 17)), isTrue);
      expect(e.occursOn(DateTime(2026, 1, 18)), isTrue);
      expect(e.occursOn(DateTime(2026, 1, 14)), isFalse);
    });

    test('daily event longer than a day overlaps several occurrences', () {
      final e = event(
        start: DateTime(2026, 1, 1, 10),
        length: const Duration(hours: 50),
        recurrence: RecurrenceRule.daily,
      );
      expect(starts(e, DateTime(2026, 1, 10), DateTime(2026, 1, 11)), [
        DateTime(2026, 1, 8, 10),
        DateTime(2026, 1, 9, 10),
        DateTime(2026, 1, 10, 10),
      ]);
    });

    test('long range far from the start still finds overlapping occurrences',
        () {
      final e = event(
        start: DateTime(2020, 1, 3, 20),
        length: const Duration(days: 3),
        recurrence: RecurrenceRule.biweekly,
      );
      // 2026-01-02 is 313 weeks after 2020-01-03 (odd), 2025-12-26 is 312.
      final result = starts(e, DateTime(2025, 12, 28), DateTime(2025, 12, 29));
      expect(result, [DateTime(2025, 12, 26, 20)]);
    });
  });

  group('performance', () {
    test('daily series from 2000 queried for a week in 2030', () {
      final e = event(
          start: DateTime(2000, 1, 1, 8), recurrence: RecurrenceRule.daily);
      final watch = Stopwatch()..start();
      final result = starts(e, DateTime(2030, 6, 3), DateTime(2030, 6, 10));
      watch.stop();
      expect(result, [for (var d = 3; d < 10; d++) DateTime(2030, 6, d, 8)]);
      expect(watch.elapsedMilliseconds, lessThan(50));
    });

    test('many far-future queries stay fast for every rule', () {
      final watch = Stopwatch()..start();
      for (final rule in RecurrenceRule.values) {
        final e = event(start: DateTime(2000, 1, 3, 8), recurrence: rule);
        for (var week = 0; week < 20; week++) {
          final from = DateTime(2030, 1, 1 + week * 7);
          e.occurrencesBetween(
              from, DateTime(from.year, from.month, from.day + 7));
        }
      }
      watch.stop();
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });

    test('weekdays series from 2000 queried in 2030', () {
      final e = event(
          start: DateTime(2000, 1, 3, 8), recurrence: RecurrenceRule.weekdays);
      // 2030-06-03 is a Monday.
      final result = starts(e, DateTime(2030, 6, 3), DateTime(2030, 6, 10));
      expect(result, [for (var d = 3; d < 8; d++) DateTime(2030, 6, d, 8)]);
    });
  });

  group('daylight saving time', () {
    /// The first day of [year] that is shorter than 24 hours in the local
    /// time zone (spring forward), or null where there is no DST.
    DateTime? shortDay(int year) {
      for (var d = DateTime(year);
          d.year == year;
          d = DateTime(d.year, d.month, d.day + 1)) {
        final next = DateTime(d.year, d.month, d.day + 1);
        if (next.difference(d) < const Duration(hours: 24)) return d;
      }
      return null;
    }

    test('timed daily events keep their wall-clock time', () {
      final e = event(
          start: DateTime(2026, 1, 1, 9), recurrence: RecurrenceRule.daily);
      final all = starts(e, DateTime(2026), DateTime(2027));
      expect(all.every((s) => s.hour == 9 && s.minute == 0), isTrue);
    });

    test(
      'all-day daily occurrence on a spring-forward day stays on that day',
      () {
        final day = shortDay(2026) ?? DateTime(2026, 3, 8);
        final e = event(
          start: DateTime(day.year, day.month, day.day - 1),
          end: DateTime(day.year, day.month, day.day - 1, 23, 59),
          isAllDay: true,
          recurrence: RecurrenceRule.daily,
          count: 2,
        );
        final nextDay = DateTime(day.year, day.month, day.day + 1);
        final onShortDay = e.occurrencesBetween(day, nextDay).single;
        expect(onShortDay.end.day, day.day);
        expect(e.occursOn(nextDay), isFalse);
      },
    );
  });

  group('windowed queries match a full expansion', () {
    test('random series and windows', () {
      final random = Random(42);
      final rules = RecurrenceRule.values
          .where((r) => r != RecurrenceRule.none)
          .toList();
      for (var i = 0; i < 400; i++) {
        final rule = rules[random.nextInt(rules.length)];
        final start = DateTime(2019 + random.nextInt(3), 1 + random.nextInt(12),
            1 + random.nextInt(31), random.nextInt(24), random.nextInt(4) * 15);
        final allDay = random.nextInt(4) == 0;
        final lengthDays = random.nextInt(5) == 0 ? random.nextInt(4) : 0;
        final begin =
            allDay ? DateTime(start.year, start.month, start.day) : start;
        final end = allDay
            ? DateTime(begin.year, begin.month, begin.day + lengthDays, 23, 59)
            : begin.add(Duration(
                days: lengthDays, minutes: 15 + random.nextInt(8) * 15));
        final count = random.nextBool() ? 1 + random.nextInt(400) : null;
        final until = count == null && random.nextBool()
            ? begin.add(Duration(days: random.nextInt(2000)))
            : null;
        final excluded = [
          for (var k = 0; k < random.nextInt(4); k++)
            begin.add(Duration(days: random.nextInt(900))),
        ];
        final e = CalendarEvent(
          id: 'e$i',
          title: 't',
          startTime: begin,
          endTime: end,
          isAllDay: allDay,
          recurrence: rule,
          recurrenceCount: count,
          recurrenceUntil: until,
          excludedDates: excluded,
          createdAt: begin,
          updatedAt: begin,
        );
        final windowStart = begin.add(Duration(days: random.nextInt(3000)));
        final windowEnd =
            windowStart.add(Duration(days: 1 + random.nextInt(40)));
        final full = e
            .occurrencesBetween(begin.subtract(const Duration(days: 1)),
                windowEnd)
            .where((o) =>
                o.start.isBefore(windowEnd) &&
                (o.end.isAfter(windowStart) ||
                    (o.end == o.start && !o.start.isBefore(windowStart))))
            .map((o) => o.start)
            .toList();
        final windowed = e
            .occurrencesBetween(windowStart, windowEnd)
            .map((o) => o.start)
            .toList();
        expect(windowed, full,
            reason: 'rule=$rule start=$begin end=$end count=$count '
                'until=$until window=$windowStart..$windowEnd');
      }
    });
  });
}
