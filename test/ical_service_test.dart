import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/calendar_event.dart';
import 'package:look_in/services/ical_service.dart';

/// Joins lines with CRLF, as real .ics files do.
String ics(List<String> lines) => '${lines.join('\r\n')}\r\n';

/// Wraps VEVENT lines in a minimal calendar.
String calendar(List<String> eventLines) => ics([
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Test//EN',
      'BEGIN:VEVENT',
      ...eventLines,
      'END:VEVENT',
      'END:VCALENDAR',
    ]);

CalendarEvent single(List<String> eventLines) {
  final events = IcalService.parseEvents(calendar(eventLines));
  expect(events, hasLength(1));
  return events.single;
}

String Function() counterIds() {
  var n = 0;
  return () => 'id-${++n}';
}

DateTime utc(int y, int m, int d, [int h = 0, int mi = 0, int s = 0]) =>
    DateTime.utc(y, m, d, h, mi, s).toLocal();

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Physical lines of generated output (without the final empty string).
List<String> physicalLines(String text) {
  expect(text.endsWith('\r\n'), isTrue);
  return text.substring(0, text.length - 2).split('\r\n');
}

/// Logical (unfolded) lines of generated output.
List<String> logicalLines(String text) =>
    text.replaceAll('\r\n ', '').split('\r\n')..removeLast();

final googleInvite = ics([
  'BEGIN:VCALENDAR',
  'PRODID:-//Google Inc//Google Calendar 70.9054//EN',
  'VERSION:2.0',
  'CALSCALE:GREGORIAN',
  'METHOD:REQUEST',
  'BEGIN:VEVENT',
  'DTSTART:20260105T140000Z',
  'DTEND:20260105T150000Z',
  'DTSTAMP:20251220T101500Z',
  'ORGANIZER;CN=Bob Smith:mailto:bob@gmail.com',
  'UID:7kukuqrfedlm2f9t0vnk7e5ls4@google.com',
  'ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=',
  ' TRUE;CN=alice@example.com;X-NUM-GUESTS=0:mailto:alice@example.com',
  'ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=ACCEPTED;RSVP=TRUE',
  ' ;CN=Bob Smith;X-NUM-GUESTS=0:mailto:bob@gmail.com',
  'X-MICROSOFT-CDO-OWNERAPPTID:-1062633214',
  'CREATED:20251220T101400Z',
  'DESCRIPTION:Quarterly planning\\, round 2.\\nBring notes.',
  'LAST-MODIFIED:20251220T101500Z',
  'LOCATION:Room 4\\; Building B',
  'SEQUENCE:0',
  'STATUS:CONFIRMED',
  'SUMMARY:Planning',
  'TRANSP:OPAQUE',
  'BEGIN:VALARM',
  'ACTION:DISPLAY',
  'DESCRIPTION:This is an event reminder',
  'TRIGGER:-P0DT0H30M0S',
  'END:VALARM',
  'END:VEVENT',
  'END:VCALENDAR',
]);

final outlookInvite = ics([
  'BEGIN:VCALENDAR',
  'METHOD:REQUEST',
  'PRODID:Microsoft Exchange Server 2010',
  'VERSION:2.0',
  'BEGIN:VTIMEZONE',
  'TZID:W. Europe Standard Time',
  'BEGIN:STANDARD',
  'DTSTART:16010101T030000',
  'TZOFFSETFROM:+0200',
  'TZOFFSETTO:+0100',
  'RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=10',
  'END:STANDARD',
  'BEGIN:DAYLIGHT',
  'DTSTART:16010101T020000',
  'TZOFFSETFROM:+0100',
  'TZOFFSETTO:+0200',
  'RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=3',
  'END:DAYLIGHT',
  'END:VTIMEZONE',
  'BEGIN:VEVENT',
  'ORGANIZER;CN="Jane Doe":mailto:jane@example.com',
  'ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE;CN=John Roe:',
  ' mailto:john@example.com',
  'ATTENDEE;ROLE=OPT-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE;CN="Roe, Rich',
  ' ard":MAILTO:richard@example.com',
  'DESCRIPTION;LANGUAGE=en-US:Hi all\\,\\n\\nLet\'s review the milestones for Q1 a',
  ' nd agree on owners for each workstream.\\nAgenda: scope\\; timeline\\; risks',
  '\t.\\n\\nThanks\\nJane',
  'UID:040000008200E00074C5B7101A82E0080000000010FE7A0B5F8DDC01000000000000000',
  ' 010000000A1B2C3D4E5F60718293A4B5C6D7E8F90',
  'SUMMARY;LANGUAGE=en-US:Project sync',
  'DTSTART;TZID=W. Europe Standard Time:20260112T100000',
  'DTEND;TZID=W. Europe Standard Time:20260112T113000',
  'CLASS:PUBLIC',
  'PRIORITY:5',
  'DTSTAMP:20260105T083000Z',
  'TRANSP:OPAQUE',
  'STATUS:CONFIRMED',
  'SEQUENCE:0',
  'LOCATION;LANGUAGE=en-US:Conference Room 1',
  'X-MICROSOFT-CDO-APPT-SEQUENCE:0',
  'BEGIN:VALARM',
  'DESCRIPTION:REMINDER',
  'TRIGGER;RELATED=START:-PT15M',
  'ACTION:DISPLAY',
  'END:VALARM',
  'END:VEVENT',
  'END:VCALENDAR',
]);

void main() {
  group('InviteResponse', () {
    test('labels and PARTSTAT values', () {
      expect(InviteResponse.accepted.label, 'Accepted');
      expect(InviteResponse.tentative.label, 'Tentative');
      expect(InviteResponse.declined.label, 'Declined');
      expect(InviteResponse.accepted.partStat, 'ACCEPTED');
      expect(InviteResponse.tentative.partStat, 'TENTATIVE');
      expect(InviteResponse.declined.partStat, 'DECLINED');
    });
  });

  group('parseEvents: real-world samples', () {
    test('Google Calendar invitation', () {
      final events = IcalService.parseEvents(googleInvite,
          idGenerator: counterIds(), now: DateTime(2026));
      expect(events, hasLength(1));
      final e = events.single;
      expect(e.id, 'id-1');
      expect(e.title, 'Planning');
      expect(e.description, 'Quarterly planning, round 2.\nBring notes.');
      expect(e.location, 'Room 4; Building B');
      expect(e.startTime, utc(2026, 1, 5, 14));
      expect(e.endTime, utc(2026, 1, 5, 15));
      expect(e.startTime.isUtc, isFalse);
      expect(e.isAllDay, isFalse);
      expect(e.icalUid, '7kukuqrfedlm2f9t0vnk7e5ls4@google.com');
      expect(e.uid, '7kukuqrfedlm2f9t0vnk7e5ls4@google.com');
      expect(e.organizer, 'bob@gmail.com');
      expect(e.attendees, ['alice@example.com', 'bob@gmail.com']);
      expect(e.reminder, ReminderTime.thirtyMinutes);
      expect(e.recurrence, isNull);
      expect(e.createdAt, utc(2025, 12, 20, 10, 14));
      expect(e.updatedAt, utc(2025, 12, 20, 10, 15));
      expect(IcalService.parseMethod(googleInvite), 'REQUEST');
    });

    test('Outlook invitation with VTIMEZONE, TZID and folded lines', () {
      final events = IcalService.parseEvents(outlookInvite);
      // The STANDARD/DAYLIGHT blocks (with DTSTART and RRULE) are ignored.
      expect(events, hasLength(1));
      final e = events.single;
      expect(e.title, 'Project sync');
      expect(e.location, 'Conference Room 1');
      expect(
        e.description,
        "Hi all,\n\nLet's review the milestones for Q1 and agree on owners "
        'for each workstream.\nAgenda: scope; timeline; risks.\n\n'
        'Thanks\nJane',
      );
      // TZID times are taken as local wall-clock time.
      expect(e.startTime, DateTime(2026, 1, 12, 10));
      expect(e.endTime, DateTime(2026, 1, 12, 11, 30));
      expect(e.organizer, 'jane@example.com');
      expect(e.attendees, ['john@example.com', 'richard@example.com']);
      expect(e.reminder, ReminderTime.fifteenMinutes);
      expect(
        e.icalUid,
        '040000008200E00074C5B7101A82E0080000000010FE7A0B5F8DDC01000000000000000'
        '010000000A1B2C3D4E5F60718293A4B5C6D7E8F90',
      );
      expect(e.recurrence, isNull);
      expect(IcalService.parseMethod(outlookInvite), 'REQUEST');
    });

    test('LF-only line endings and tab folding', () {
      const text = 'BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:lf-1\n'
          'DTSTART:20260301T080000\nSUMMARY:Long\n\ttitle\nEND:VEVENT\n'
          'END:VCALENDAR';
      final e = IcalService.parseEvents(text).single;
      expect(e.title, 'Longtitle');
      expect(e.startTime, DateTime(2026, 3, 1, 8));
    });

    test('byte order mark and lower-case property names', () {
      const text = '\uFEFFbegin:vcalendar\r\nbegin:vevent\r\n'
          'dtstart:20260301T080000Z\r\nsummary:lower\r\nend:vevent\r\n'
          'end:vcalendar\r\n';
      final e = IcalService.parseEvents(text).single;
      expect(e.title, 'lower');
      expect(e.startTime, utc(2026, 3, 1, 8));
    });

    test('multiple events keep their order and get distinct ids', () {
      final text = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:a',
        'DTSTART:20260101T090000Z',
        'SUMMARY:First',
        'END:VEVENT',
        'BEGIN:VTODO',
        'UID:todo',
        'DTSTART:20260101T090000Z',
        'SUMMARY:A task',
        'END:VTODO',
        'BEGIN:VEVENT',
        'UID:b',
        'DTSTART:20260102T090000Z',
        'SUMMARY:Second',
        'END:VEVENT',
        'END:VCALENDAR',
      ]);
      final events = IcalService.parseEvents(text);
      expect(events.map((e) => e.title), ['First', 'Second']);
      expect(events[0].id, isNot(events[1].id));
      expect(events[0].id, isNotEmpty);
    });
  });

  group('parseEvents: times', () {
    test('floating time is local wall-clock time', () {
      final e = single(['DTSTART:20260105T090000', 'DTEND:20260105T100000']);
      expect(e.startTime, DateTime(2026, 1, 5, 9));
      expect(e.endTime, DateTime(2026, 1, 5, 10));
    });

    test('UTC time converts to local', () {
      final e = single(['DTSTART:20260705T233000Z', 'DTEND:20260706T003000Z']);
      expect(e.startTime, utc(2026, 7, 5, 23, 30));
      expect(e.endTime, utc(2026, 7, 6, 0, 30));
      expect(e.startTime.isUtc, isFalse);
    });

    test('TZID naming UTC is treated as UTC', () {
      final e = single(['DTSTART;TZID=UTC:20260105T090000']);
      expect(e.startTime, utc(2026, 1, 5, 9));
      final e2 = single(['DTSTART;TZID=Etc/UTC:20260105T090000']);
      expect(e2.startTime, utc(2026, 1, 5, 9));
    });

    test('TZID for another zone is local wall-clock time', () {
      final e = single([
        'DTSTART;TZID=America/New_York:20260105T090000',
        'DTEND;TZID="America/New_York":20260105T093000',
      ]);
      expect(e.startTime, DateTime(2026, 1, 5, 9));
      expect(e.endTime, DateTime(2026, 1, 5, 9, 30));
    });

    test('time without seconds is accepted', () {
      final e = single(['DTSTART:20260105T0915']);
      expect(e.startTime, DateTime(2026, 1, 5, 9, 15));
    });

    test('no DTEND or DURATION defaults to one hour', () {
      final e = single(['DTSTART:20260105T090000']);
      expect(e.endTime, DateTime(2026, 1, 5, 10));
    });

    test('DTEND before DTSTART falls back to one hour', () {
      final e = single(['DTSTART:20260105T090000', 'DTEND:20260105T080000']);
      expect(e.endTime, DateTime(2026, 1, 5, 10));
    });

    test('DURATION values', () {
      CalendarEvent withDuration(String d) =>
          single(['DTSTART:20260105T090000', 'DURATION:$d']);
      expect(withDuration('PT1H30M').endTime, DateTime(2026, 1, 5, 10, 30));
      expect(withDuration('P1D').endTime, DateTime(2026, 1, 6, 9));
      expect(withDuration('P1W').endTime, DateTime(2026, 1, 12, 9));
      expect(withDuration('P1DT2H').endTime, DateTime(2026, 1, 6, 11));
      expect(withDuration('PT45S').endTime, DateTime(2026, 1, 5, 9, 0, 45));
      expect(withDuration('+PT15M').endTime, DateTime(2026, 1, 5, 9, 15));
      // Negative and malformed durations fall back to the default hour.
      expect(withDuration('-PT15M').endTime, DateTime(2026, 1, 5, 10));
      expect(withDuration('PT').endTime, DateTime(2026, 1, 5, 10));
      expect(withDuration('garbage').endTime, DateTime(2026, 1, 5, 10));
    });

    test('DTEND wins over DURATION', () {
      final e = single([
        'DTSTART:20260105T090000',
        'DTEND:20260105T093000',
        'DURATION:PT2H',
      ]);
      expect(e.endTime, DateTime(2026, 1, 5, 9, 30));
    });
  });

  group('parseEvents: all-day events', () {
    test('single day with exclusive DTEND', () {
      final e = single([
        'DTSTART;VALUE=DATE:20260105',
        'DTEND;VALUE=DATE:20260106',
        'SUMMARY:Holiday',
      ]);
      expect(e.isAllDay, isTrue);
      expect(e.startTime, DateTime(2026, 1, 5));
      expect(e.endTime, DateTime(2026, 1, 5, 23, 59));
      expect(e.occursOn(DateTime(2026, 1, 5)), isTrue);
      expect(e.occursOn(DateTime(2026, 1, 6)), isFalse);
    });

    test('multi-day event', () {
      final e = single([
        'DTSTART;VALUE=DATE:20260105',
        'DTEND;VALUE=DATE:20260108',
      ]);
      expect(e.startTime, DateTime(2026, 1, 5));
      expect(e.endTime, DateTime(2026, 1, 7, 23, 59));
    });

    test('crossing a year boundary', () {
      final e = single([
        'DTSTART;VALUE=DATE:20261231',
        'DTEND;VALUE=DATE:20270101',
      ]);
      expect(e.endTime, DateTime(2026, 12, 31, 23, 59));
    });

    test('no DTEND means a single day', () {
      final e = single(['DTSTART;VALUE=DATE:20260105']);
      expect(e.endTime, DateTime(2026, 1, 5, 23, 59));
    });

    test('date value without VALUE=DATE parameter', () {
      final e = single(['DTSTART:20260105', 'DTEND:20260107']);
      expect(e.isAllDay, isTrue);
      expect(e.endTime, DateTime(2026, 1, 6, 23, 59));
    });

    test('DURATION on an all-day event', () {
      final e = single(['DTSTART;VALUE=DATE:20260105', 'DURATION:P2D']);
      expect(e.endTime, DateTime(2026, 1, 6, 23, 59));
      final w = single(['DTSTART;VALUE=DATE:20260105', 'DURATION:P1W']);
      expect(w.endTime, DateTime(2026, 1, 11, 23, 59));
    });

    test('DTEND equal to DTSTART means a single day', () {
      final e = single([
        'DTSTART;VALUE=DATE:20260105',
        'DTEND;VALUE=DATE:20260105',
      ]);
      expect(e.endTime, DateTime(2026, 1, 5, 23, 59));
    });
  });

  group('parseEvents: text and people', () {
    test('text unescaping', () {
      final e = single([
        'DTSTART:20260105T090000',
        r'SUMMARY:a\, b\; c\\ d',
        r'DESCRIPTION:line1\nline2\Nline3\\n not a newline',
        r'LOCATION:Room\:5 \x',
      ]);
      expect(e.title, r'a, b; c\ d');
      expect(e.description, 'line1\nline2\nline3\\n not a newline');
      // Unknown escapes keep the escaped character.
      expect(e.location, 'Room:5 x');
    });

    test('non-ASCII text', () {
      final e = single(['DTSTART:20260105T090000', 'SUMMARY:Grüße 日本 🎉']);
      expect(e.title, 'Grüße 日本 🎉');
    });

    test('missing SUMMARY gives an empty title; blank fields are null', () {
      final e =
          single(['DTSTART:20260105T090000', 'DESCRIPTION:', 'LOCATION: ']);
      expect(e.title, '');
      expect(e.description, isNull);
      expect(e.location, isNull);
      expect(e.icalUid, isNull);
    });

    test('ORGANIZER and ATTENDEE mailto prefixes are case-insensitive', () {
      final e = single([
        'DTSTART:20260105T090000',
        'ORGANIZER;CN="Doe, Jane";SENT-BY="mailto:assistant@example.com":MailTo:jane@example.com',
        'ATTENDEE:MAILTO:a@example.com',
        'ATTENDEE;CN=B:mailto:b@example.com',
        'ATTENDEE;CN=Duplicate:mailto:A@example.com',
        'ATTENDEE:c@example.com',
      ]);
      expect(e.organizer, 'jane@example.com');
      expect(e.attendees, ['a@example.com', 'b@example.com', 'c@example.com']);
    });

    test('parameter values containing colons', () {
      final e = single([
        'DTSTART:20260105T090000',
        'ATTENDEE;CN="Team: Ops";DELEGATED-FROM="mailto:x@example.com":mailto:ops@example.com',
      ]);
      expect(e.attendees, ['ops@example.com']);
    });
  });

  group('parseEvents: recurrence', () {
    RecurrenceRule? rule(String rrule, {String start = '20260105T090000'}) =>
        single(['DTSTART:$start', 'RRULE:$rrule']).recurrence;

    test('maps supported rules', () {
      expect(rule('FREQ=DAILY'), RecurrenceRule.daily);
      expect(rule('FREQ=DAILY;INTERVAL=1'), RecurrenceRule.daily);
      expect(rule('FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR'), RecurrenceRule.weekdays);
      expect(rule('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'), RecurrenceRule.weekdays);
      expect(rule('FREQ=WEEKLY;WKST=SU;BYDAY=FR,TH,WE,TU,MO'),
          RecurrenceRule.weekdays);
      expect(rule('FREQ=WEEKLY'), RecurrenceRule.weekly);
      expect(rule('FREQ=WEEKLY;BYDAY=MO'), RecurrenceRule.weekly);
      expect(rule('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO'), RecurrenceRule.biweekly);
      expect(rule('FREQ=MONTHLY'), RecurrenceRule.monthly);
      expect(rule('FREQ=MONTHLY;BYMONTHDAY=5'), RecurrenceRule.monthly);
      expect(rule('FREQ=MONTHLY;BYDAY=1MO'), RecurrenceRule.monthly);
      expect(rule('FREQ=YEARLY'), RecurrenceRule.yearly);
      expect(rule('FREQ=YEARLY;BYMONTH=1;BYMONTHDAY=5'), RecurrenceRule.yearly);
      expect(rule('freq=weekly;interval=2'), RecurrenceRule.biweekly);
    });

    test('unsupported rules fall back to the closest supported rule', () {
      expect(rule('FREQ=WEEKLY;INTERVAL=3'), RecurrenceRule.biweekly);
      expect(rule('FREQ=WEEKLY;INTERVAL=4'), RecurrenceRule.monthly);
      expect(rule('FREQ=DAILY;INTERVAL=2'), RecurrenceRule.daily);
      expect(rule('FREQ=DAILY;INTERVAL=7'), RecurrenceRule.weekly);
      expect(rule('FREQ=DAILY;INTERVAL=14'), RecurrenceRule.biweekly);
      expect(rule('FREQ=HOURLY'), RecurrenceRule.daily);
      expect(rule('FREQ=MINUTELY;INTERVAL=30'), RecurrenceRule.daily);
      expect(rule('FREQ=MONTHLY;INTERVAL=2'), RecurrenceRule.monthly);
      expect(rule('FREQ=MONTHLY;INTERVAL=12'), RecurrenceRule.yearly);
      expect(rule('FREQ=YEARLY;INTERVAL=2'), RecurrenceRule.yearly);
      // Several weekdays per week: shown every weekday.
      expect(rule('FREQ=WEEKLY;BYDAY=MO,WE,FR'), RecurrenceRule.weekdays);
      // Includes weekend days: shown daily.
      expect(rule('FREQ=WEEKLY;BYDAY=SA,SU,WE'), RecurrenceRule.daily);
      expect(rule('FREQ=WEEKLY;INTERVAL=0'), RecurrenceRule.weekly);
    });

    test('unknown or missing FREQ means no recurrence', () {
      expect(rule('FREQ=SOMETIMES'), isNull);
      expect(rule('INTERVAL=2'), isNull);
      expect(rule(''), isNull);
      expect(rule('garbage'), isNull);
    });

    test('UNTIL as a date', () {
      final e = single(
          ['DTSTART:20260105T090000', 'RRULE:FREQ=DAILY;UNTIL=20260110']);
      expect(e.recurrenceUntil, DateTime(2026, 1, 10));
      expect(e.recurrenceCount, isNull);
    });

    test('UNTIL as a UTC date-time keeps the last occurrence day', () {
      final e = single([
        'DTSTART:20260105T090000Z',
        'RRULE:FREQ=DAILY;UNTIL=20260110T090000Z',
      ]);
      expect(e.recurrenceUntil, DateTime(2026, 1, 10));
      final e2 = single([
        'DTSTART:20260105T090000Z',
        'RRULE:FREQ=DAILY;UNTIL=20260110T235959Z',
      ]);
      expect(e2.recurrenceUntil, DateTime(2026, 1, 10));
      final starts = e2
          .occurrencesBetween(DateTime(2026, 1, 1), DateTime(2026, 2, 1))
          .map((o) => o.start)
          .toList();
      expect(starts.last, utc(2026, 1, 10, 9));
      expect(starts, hasLength(6));
    });

    test('UNTIL earlier in the day than the start excludes that day', () {
      final e = single([
        'DTSTART:20260105T090000',
        'RRULE:FREQ=DAILY;UNTIL=20260110T080000',
      ]);
      expect(e.recurrenceUntil, DateTime(2026, 1, 9));
    });

    test('UNTIL for all-day events uses the written date', () {
      final e = single([
        'DTSTART;VALUE=DATE:20260105',
        'RRULE:FREQ=WEEKLY;UNTIL=20260126T000000Z',
      ]);
      expect(e.recurrenceUntil, DateTime(2026, 1, 26));
      final d = single([
        'DTSTART;VALUE=DATE:20260105',
        'RRULE:FREQ=WEEKLY;UNTIL=20260126',
      ]);
      expect(d.recurrenceUntil, DateTime(2026, 1, 26));
    });

    test('COUNT', () {
      final e =
          single(['DTSTART:20260105T090000', 'RRULE:FREQ=WEEKLY;COUNT=5']);
      expect(e.recurrenceCount, 5);
      expect(e.recurrenceUntil, isNull);
      expect(
          single(['DTSTART:20260105T090000', 'RRULE:FREQ=WEEKLY;COUNT=x'])
              .recurrenceCount,
          isNull);
      expect(
          single(['DTSTART:20260105T090000', 'RRULE:FREQ=WEEKLY;COUNT=0'])
              .recurrenceCount,
          isNull);
    });

    test('EXDATE on several lines and comma-separated', () {
      final e = single([
        'DTSTART;TZID=Europe/Berlin:20260105T090000',
        'RRULE:FREQ=DAILY;COUNT=10',
        'EXDATE;TZID=Europe/Berlin:20260106T090000,20260108T090000',
        'EXDATE;TZID=Europe/Berlin:20260110T090000',
        'EXDATE;VALUE=DATE:20260111',
        'EXDATE:20260106T090000',
      ]);
      expect(e.excludedDates, [
        DateTime(2026, 1, 6),
        DateTime(2026, 1, 8),
        DateTime(2026, 1, 10),
        DateTime(2026, 1, 11),
      ]);
      final days = e
          .occurrencesBetween(DateTime(2026, 1, 1), DateTime(2026, 2, 1))
          .map((o) => o.start.day)
          .toList();
      expect(days, [5, 7, 9, 12, 13, 14]);
    });

    test('UTC EXDATE matches the local occurrence day', () {
      final e = single([
        'DTSTART:20260105T120000Z',
        'RRULE:FREQ=DAILY;COUNT=3',
        'EXDATE:20260106T120000Z',
      ]);
      expect(e.excludedDates, hasLength(1));
      expect(sameDay(e.excludedDates.single, utc(2026, 1, 6, 12)), isTrue);
      expect(
        e
            .occurrencesBetween(DateTime(2026), DateTime(2027))
            .map((o) => o.start),
        [utc(2026, 1, 5, 12), utc(2026, 1, 7, 12)],
      );
    });

    test('EXDATE without RRULE is ignored', () {
      final e = single(['DTSTART:20260105T090000', 'EXDATE:20260105T090000']);
      expect(e.excludedDates, isEmpty);
    });

    test('an overriding instance excludes the original occurrence', () {
      final text = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:series-1',
        'DTSTART:20260105T090000',
        'DTEND:20260105T100000',
        'RRULE:FREQ=WEEKLY;COUNT=4',
        'SUMMARY:Standup',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:series-1',
        'RECURRENCE-ID:20260112T090000',
        'DTSTART:20260113T140000',
        'DTEND:20260113T150000',
        'SUMMARY:Standup (moved)',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:series-1',
        'RECURRENCE-ID:20260119T090000',
        'DTSTART:20260119T090000',
        'STATUS:CANCELLED',
        'END:VEVENT',
        'END:VCALENDAR',
      ]);
      final events = IcalService.parseEvents(text);
      expect(events, hasLength(2));
      final master = events[0];
      expect(master.recurrence, RecurrenceRule.weekly);
      expect(
          master.excludedDates, [DateTime(2026, 1, 12), DateTime(2026, 1, 19)]);
      final moved = events[1];
      expect(moved.title, 'Standup (moved)');
      expect(moved.recurrence, isNull);
      expect(moved.icalUid, 'series-1');
      expect(moved.startTime, DateTime(2026, 1, 13, 14));
    });
  });

  group('parseEvents: alarms', () {
    ReminderTime? reminder(List<String> alarmLines,
            {List<String> extra = const []}) =>
        single([
          'DTSTART:20260105T090000',
          'DTEND:20260105T100000',
          ...extra,
          'BEGIN:VALARM',
          ...alarmLines,
          'END:VALARM',
        ]).reminder;

    test('relative triggers', () {
      expect(reminder(['ACTION:DISPLAY', 'TRIGGER:-PT15M']),
          ReminderTime.fifteenMinutes);
      expect(reminder(['TRIGGER:-PT5M']), ReminderTime.fiveMinutes);
      expect(reminder(['TRIGGER:-PT1H']), ReminderTime.oneHour);
      expect(reminder(['TRIGGER:-PT2H']), ReminderTime.twoHours);
      expect(reminder(['TRIGGER:-P1D']), ReminderTime.oneDay);
      expect(reminder(['TRIGGER:-P2D']), ReminderTime.twoDays);
      expect(reminder(['TRIGGER:PT0S']), ReminderTime.atTime);
      expect(reminder(['TRIGGER:-PT18H']), ReminderTime.oneDay);
      expect(reminder(['TRIGGER:PT10M']), ReminderTime.atTime);
    });

    test('trigger relative to the end', () {
      // 30 minutes before the end of a one-hour event = 30 minutes after
      // start... which is closest to "at time of event".
      expect(reminder(['TRIGGER;RELATED=END:-PT30M']), ReminderTime.atTime);
      expect(reminder(['TRIGGER;RELATED=END:-PT2H']), ReminderTime.oneHour);
    });

    test('absolute trigger', () {
      expect(reminder(['TRIGGER;VALUE=DATE-TIME:20260105T083000']),
          ReminderTime.thirtyMinutes);
    });

    test('ACTION:NONE alarms and missing triggers are skipped', () {
      expect(
          reminder(['ACTION:NONE', 'TRIGGER;VALUE=DATE-TIME:19760401T005545Z']),
          isNull);
      expect(reminder(['ACTION:DISPLAY']), isNull);
      expect(reminder(['TRIGGER:soon']), isNull);
    });

    test('first usable alarm wins', () {
      final e = single([
        'DTSTART:20260105T090000',
        'BEGIN:VALARM',
        'TRIGGER:bad',
        'END:VALARM',
        'BEGIN:VALARM',
        'TRIGGER:-PT1H',
        'END:VALARM',
        'BEGIN:VALARM',
        'TRIGGER:-PT5M',
        'END:VALARM',
      ]);
      expect(e.reminder, ReminderTime.oneHour);
    });

    test('no alarm gives a null reminder', () {
      expect(single(['DTSTART:20260105T090000']).reminder, isNull);
    });
  });

  group('parseEvents: malformed input never throws', () {
    test('empty and garbage input', () {
      expect(IcalService.parseEvents(''), isEmpty);
      expect(IcalService.parseEvents('hello world'), isEmpty);
      expect(IcalService.parseEvents(':::;;;\r\n\r\n==='), isEmpty);
      expect(IcalService.parseEvents('BEGIN:VEVENT'), isEmpty);
      expect(IcalService.parseEvents('\u0000\u0001\uFFFF'), isEmpty);
    });

    test('bad events are skipped, good ones kept', () {
      final text = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'SUMMARY:No start',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'DTSTART:20261345T250000',
        'SUMMARY:Invalid date',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'DTSTART:20260230',
        'SUMMARY:February 30th',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'DTSTART:tomorrow',
        'SUMMARY:Words',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'DTSTART:20260105T090000',
        'DTEND:not-a-date',
        'RRULE:FREQ=',
        'EXDATE:nope,20260106',
        'SUMMARY;LANGUAGE="unterminated:Broken line is skipped',
        'SUMMARY:Good',
        'this line has no colon',
        ';;;:',
        'BEGIN:VALARM',
        'TRIGGER:-PTXM',
        'END:VALARM',
        'END:VEVENT',
        'END:VCALENDAR',
      ]);
      final events = IcalService.parseEvents(text);
      expect(events, hasLength(1));
      expect(events.single.title, 'Good');
      expect(events.single.endTime, DateTime(2026, 1, 5, 10));
      expect(events.single.recurrence, isNull);
      expect(events.single.reminder, isNull);
    });

    test('missing END lines are tolerated', () {
      const text = 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n'
          'DTSTART:20260105T090000\r\nSUMMARY:Truncated';
      expect(IcalService.parseEvents(text).single.title, 'Truncated');
    });

    test('mismatched END lines are tolerated', () {
      final text = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'DTSTART:20260105T090000',
        'SUMMARY:One',
        'END:VTODO',
        'END:VEVENT',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'DTSTART:20260106T090000',
        'SUMMARY:Two',
        'END:VCALENDAR',
      ]);
      expect(IcalService.parseEvents(text).map((e) => e.title), ['One', 'Two']);
    });

    test('an event outside VCALENDAR is still parsed', () {
      final text = ics([
        'BEGIN:VEVENT',
        'DTSTART:20260105T090000',
        'SUMMARY:Bare',
        'END:VEVENT',
      ]);
      expect(IcalService.parseEvents(text).single.title, 'Bare');
    });

    test('an idGenerator that throws skips the events', () {
      final events = IcalService.parseEvents(googleInvite,
          idGenerator: () => throw StateError('no ids'));
      expect(events, isEmpty);
    });
  });

  group('parseMethod', () {
    test('returns the upper-cased METHOD', () {
      expect(IcalService.parseMethod(googleInvite), 'REQUEST');
      expect(
          IcalService.parseMethod(
              ics(['BEGIN:VCALENDAR', 'METHOD:cancel', 'END:VCALENDAR'])),
          'CANCEL');
      expect(
          IcalService.parseMethod(ics([
            'BEGIN:VCALENDAR',
            'METHOD:REPLY',
            'BEGIN:VEVENT',
            'END:VEVENT',
            'END:VCALENDAR'
          ])),
          'REPLY');
    });

    test('null when absent or malformed', () {
      expect(IcalService.parseMethod(calendar(['DTSTART:20260105'])), isNull);
      expect(IcalService.parseMethod(''), isNull);
      expect(IcalService.parseMethod('METHOD:REQUEST'), isNull);
      expect(
          IcalService.parseMethod(
              ics(['BEGIN:VCALENDAR', 'METHOD:', 'END:VCALENDAR'])),
          isNull);
    });
  });

  group('generateCalendar', () {
    final created = DateTime.utc(2025, 12, 1, 8);
    CalendarEvent event({
      String id = 'evt-1',
      String title = 'Meeting',
      String? description,
      String? location,
      DateTime? start,
      DateTime? end,
      bool isAllDay = false,
      ReminderTime? reminder,
      RecurrenceRule? recurrence,
      DateTime? until,
      int? count,
      List<DateTime> excluded = const [],
      List<String> attendees = const [],
      String? organizer,
      String? icalUid,
    }) =>
        CalendarEvent(
          id: id,
          title: title,
          description: description,
          location: location,
          startTime: start ?? DateTime(2026, 1, 5, 9),
          endTime: end ?? DateTime(2026, 1, 5, 10),
          isAllDay: isAllDay,
          reminder: reminder,
          recurrence: recurrence,
          recurrenceUntil: until,
          recurrenceCount: count,
          excludedDates: excluded,
          attendees: attendees,
          organizer: organizer,
          icalUid: icalUid,
          createdAt: created,
          updatedAt: created,
        );

    String generate(List<CalendarEvent> events, {String method = 'PUBLISH'}) =>
        IcalService.generateCalendar(events,
            method: method, now: DateTime.utc(2026, 1, 1, 12));

    test('calendar structure with CRLF line endings', () {
      final text = generate([event()]);
      final lines = physicalLines(text);
      expect(lines.first, 'BEGIN:VCALENDAR');
      expect(lines.last, 'END:VCALENDAR');
      expect(
          lines,
          containsAll([
            'VERSION:2.0',
            'PRODID:-//Look In//EN',
            'METHOD:PUBLISH',
            'BEGIN:VEVENT',
            'END:VEVENT',
            'UID:evt-1',
            'DTSTAMP:20260101T120000Z',
            'SUMMARY:Meeting',
          ]));
      for (final line in lines) {
        expect(line.contains('\n') || line.contains('\r'), isFalse);
      }
      expect(text.replaceAll('\r\n', '').contains('\n'), isFalse);
    });

    test('custom method and PRODID; empty method omits METHOD', () {
      final text = IcalService.generateCalendar([event()],
          method: 'request', prodId: '-//Acme//Cal 1.0//EN');
      expect(physicalLines(text),
          containsAll(['METHOD:REQUEST', 'PRODID:-//Acme//Cal 1.0//EN']));
      final none = IcalService.generateCalendar([event()], method: '');
      expect(none.contains('METHOD'), isFalse);
      expect(IcalService.parseMethod(none), isNull);
    });

    test('icalUid is used as UID when present', () {
      final lines = logicalLines(generate([event(icalUid: 'abc@example.com')]));
      expect(lines, contains('UID:abc@example.com'));
    });

    test('timed events are written in UTC', () {
      final start = DateTime(2026, 7, 5, 9, 15);
      final lines = logicalLines(generate([
        event(start: start, end: start.add(const Duration(minutes: 45))),
      ]));
      String fmt(DateTime d) {
        final u = d.toUtc();
        String two(int n) => n.toString().padLeft(2, '0');
        return '${u.year}${two(u.month)}${two(u.day)}T'
            '${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
      }

      expect(lines, contains('DTSTART:${fmt(start)}'));
      expect(lines,
          contains('DTEND:${fmt(start.add(const Duration(minutes: 45)))}'));
    });

    test('all-day events use VALUE=DATE with an exclusive end', () {
      final lines = logicalLines(generate([
        event(
          isAllDay: true,
          start: DateTime(2026, 1, 5),
          end: DateTime(2026, 1, 7, 23, 59),
        ),
      ]));
      expect(lines, contains('DTSTART;VALUE=DATE:20260105'));
      expect(lines, contains('DTEND;VALUE=DATE:20260108'));
    });

    test('all-day event ending at midnight of the next day', () {
      final lines = logicalLines(generate([
        event(
          isAllDay: true,
          start: DateTime(2026, 1, 5),
          end: DateTime(2026, 1, 6),
        ),
      ]));
      expect(lines, contains('DTEND;VALUE=DATE:20260106'));
    });

    test('text escaping', () {
      final lines = logicalLines(generate([
        event(
          title: r'a, b; c\ d',
          description: 'line1\nline2\r\nline3',
          location: 'Room 1; Floor 2, East',
        ),
      ]));
      expect(lines, contains(r'SUMMARY:a\, b\; c\\ d'));
      expect(lines, contains(r'DESCRIPTION:line1\nline2\nline3'));
      expect(lines, contains(r'LOCATION:Room 1\; Floor 2\, East'));
    });

    test('lines are folded at 75 octets without splitting characters', () {
      final description =
          List.filled(20, 'Grüße aus Köln — 日本語のテキスト 🎉 ').join();
      final text = generate([
        event(title: 'x' * 200, description: description),
      ]);
      final lines = physicalLines(text);
      for (final line in lines) {
        expect(utf8.encode(line).length, lessThanOrEqualTo(75), reason: line);
        // A split multi-byte character or surrogate pair would not survive
        // a UTF-8 round trip.
        expect(utf8.decode(utf8.encode(line)), line);
      }
      expect(lines.where((l) => l.startsWith(' ')), isNotEmpty);
      final parsed = IcalService.parseEvents(text).single;
      expect(parsed.description, description.trim());
      expect(parsed.title, 'x' * 200);
    });

    test('a line of exactly 75 octets is not folded', () {
      final title = 'y' * (75 - 'SUMMARY:'.length);
      final lines = physicalLines(generate([event(title: title)]));
      expect(lines, contains('SUMMARY:$title'));
    });

    test('organizer and attendees', () {
      final lines = logicalLines(generate([
        event(
          organizer: 'boss@example.com',
          attendees: ['a@example.com', 'Bob Smith <bob@example.com>'],
        ),
      ], method: 'REQUEST'));
      expect(lines, contains('ORGANIZER:mailto:boss@example.com'));
      expect(
          lines,
          contains('ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;'
              'RSVP=TRUE:mailto:a@example.com'));
      expect(
          lines,
          contains('ATTENDEE;CN=Bob Smith;ROLE=REQ-PARTICIPANT;'
              'PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:bob@example.com'));
      final publish = logicalLines(generate([
        event(attendees: ['a@example.com']),
      ]));
      expect(publish, contains('ATTENDEE:mailto:a@example.com'));
    });

    test('CANCEL marks events cancelled', () {
      final lines = logicalLines(generate([event()], method: 'CANCEL'));
      expect(lines, contains('STATUS:CANCELLED'));
      expect(lines, contains('METHOD:CANCEL'));
    });

    test('RRULE for each recurrence', () {
      String rrule(RecurrenceRule r, {DateTime? start, bool allDay = false}) {
        final s = start ?? DateTime(2026, 1, 5, 9);
        final lines = logicalLines(generate([
          event(
            recurrence: r,
            start: s,
            end: allDay
                ? DateTime(s.year, s.month, s.day, 23, 59)
                : s.add(const Duration(hours: 1)),
            isAllDay: allDay,
          ),
        ]));
        return lines.firstWhere((l) => l.startsWith('RRULE:'));
      }

      expect(rrule(RecurrenceRule.daily), 'RRULE:FREQ=DAILY');
      expect(rrule(RecurrenceRule.weekdays),
          'RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR');
      expect(rrule(RecurrenceRule.weekly), 'RRULE:FREQ=WEEKLY');
      expect(rrule(RecurrenceRule.biweekly), 'RRULE:FREQ=WEEKLY;INTERVAL=2');
      expect(rrule(RecurrenceRule.monthly), 'RRULE:FREQ=MONTHLY');
      expect(rrule(RecurrenceRule.yearly), 'RRULE:FREQ=YEARLY');
      expect(rrule(RecurrenceRule.monthly, start: DateTime(2026, 1, 31, 9)),
          'RRULE:FREQ=MONTHLY;BYMONTHDAY=-1');
      expect(rrule(RecurrenceRule.monthly, start: DateTime(2026, 1, 30, 9)),
          'RRULE:FREQ=MONTHLY;BYMONTHDAY=28,29,30;BYSETPOS=-1');
      expect(rrule(RecurrenceRule.yearly, start: DateTime(2028, 2, 29, 9)),
          'RRULE:FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=-1');
      final none =
          logicalLines(generate([event(recurrence: RecurrenceRule.none)]));
      expect(none.where((l) => l.startsWith('RRULE')), isEmpty);
    });

    test('UNTIL, COUNT and EXDATE', () {
      final timed = logicalLines(generate([
        event(
          recurrence: RecurrenceRule.daily,
          until: DateTime(2026, 1, 20),
          excluded: [DateTime(2026, 1, 7), DateTime(2026, 1, 9)],
        ),
      ]));
      final untilUtc = DateTime(2026, 1, 20, 23, 59, 59).toUtc();
      expect(timed.firstWhere((l) => l.startsWith('RRULE')),
          contains('UNTIL=${untilUtc.year}'));
      final exdate = timed.firstWhere((l) => l.startsWith('EXDATE'));
      expect(exdate, startsWith('EXDATE:'));
      expect(exdate.split(':')[1].split(','), hasLength(2));
      expect(exdate, endsWith('Z'));

      final allDay = logicalLines(generate([
        event(
          isAllDay: true,
          start: DateTime(2026, 1, 5),
          end: DateTime(2026, 1, 5, 23, 59),
          recurrence: RecurrenceRule.weekly,
          count: 6,
          excluded: [DateTime(2026, 1, 12)],
        ),
      ]));
      expect(allDay, contains('RRULE:FREQ=WEEKLY;COUNT=6'));
      expect(allDay, contains('EXDATE;VALUE=DATE:20260112'));

      final untilAllDay = logicalLines(generate([
        event(
          isAllDay: true,
          start: DateTime(2026, 1, 5),
          end: DateTime(2026, 1, 5, 23, 59),
          recurrence: RecurrenceRule.weekly,
          until: DateTime(2026, 3, 2),
        ),
      ]));
      expect(untilAllDay, contains('RRULE:FREQ=WEEKLY;UNTIL=20260302'));
    });

    test('VALARM only when a reminder is set', () {
      final lines = logicalLines(generate([
        event(reminder: ReminderTime.fifteenMinutes),
      ]));
      expect(
          lines,
          containsAllInOrder([
            'BEGIN:VALARM',
            'ACTION:DISPLAY',
            'TRIGGER:-PT15M',
            'END:VALARM'
          ]));
      String trigger(ReminderTime r) =>
          logicalLines(generate([event(reminder: r)]))
              .firstWhere((l) => l.startsWith('TRIGGER'));
      expect(trigger(ReminderTime.atTime), 'TRIGGER:PT0S');
      expect(trigger(ReminderTime.oneHour), 'TRIGGER:-PT1H');
      expect(trigger(ReminderTime.twoDays), 'TRIGGER:-P2D');
      expect(generate([event(reminder: ReminderTime.none)]).contains('VALARM'),
          isFalse);
      expect(generate([event()]).contains('VALARM'), isFalse);
    });

    test('weekday series starting on a weekend starts on Monday', () {
      final saturday = DateTime(2026, 1, 3, 9);
      final original = event(
        recurrence: RecurrenceRule.weekdays,
        start: saturday,
        end: saturday.add(const Duration(hours: 1)),
      );
      final parsed = IcalService.parseEvents(generate([original])).single;
      expect(parsed.startTime, DateTime(2026, 1, 5, 9));
      expect(parsed.endTime, DateTime(2026, 1, 5, 10));
      List<DateTime> starts(CalendarEvent e) => e
          .occurrencesBetween(DateTime(2026), DateTime(2026, 3))
          .map((o) => o.start)
          .toList();
      expect(starts(parsed), starts(original));
    });

    test('empty list gives an empty calendar', () {
      final text = generate([]);
      expect(physicalLines(text).contains('BEGIN:VEVENT'), isFalse);
      expect(IcalService.parseEvents(text), isEmpty);
    });
  });

  group('round trip', () {
    final created = DateTime.utc(2025, 12, 1, 8);
    CalendarEvent make(
      String id, {
      String title = 'Event',
      String? description,
      String? location,
      required DateTime start,
      required DateTime end,
      bool isAllDay = false,
      ReminderTime? reminder,
      RecurrenceRule? recurrence,
      DateTime? until,
      int? count,
      List<DateTime> excluded = const [],
      List<String> attendees = const [],
      String? organizer,
    }) =>
        CalendarEvent(
          id: id,
          title: title,
          description: description,
          location: location,
          startTime: start,
          endTime: end,
          isAllDay: isAllDay,
          reminder: reminder,
          recurrence: recurrence,
          recurrenceUntil: until,
          recurrenceCount: count,
          excludedDates: excluded,
          attendees: attendees,
          organizer: organizer,
          createdAt: created,
          updatedAt: created,
        );

    final events = [
      make('timed',
          title: 'Lunch, with "friends"; maybe',
          description: 'Line 1\nLine 2 with \\ backslash\n\nÜnïcödé 🍕',
          location: 'Café Zürich',
          start: DateTime(2026, 3, 27, 12, 30, 15),
          end: DateTime(2026, 3, 27, 13, 45),
          reminder: ReminderTime.fifteenMinutes,
          attendees: ['a@example.com', 'b@example.com'],
          organizer: 'me@example.com'),
      make('allday',
          title: 'Conference',
          start: DateTime(2026, 3, 28),
          end: DateTime(2026, 3, 30, 23, 59),
          isAllDay: true,
          reminder: ReminderTime.oneDay),
      make('weekly',
          title: 'Team sync',
          start: DateTime(2026, 3, 2, 10),
          end: DateTime(2026, 3, 2, 10, 30),
          recurrence: RecurrenceRule.weekly,
          until: DateTime(2026, 6, 29),
          excluded: [DateTime(2026, 3, 30), DateTime(2026, 4, 6)],
          reminder: ReminderTime.fiveMinutes),
      make('daily',
          start: DateTime(2026, 10, 20, 7),
          end: DateTime(2026, 10, 20, 7, 15),
          recurrence: RecurrenceRule.daily,
          count: 20,
          reminder: ReminderTime.atTime),
      make('monthly',
          start: DateTime(2026, 1, 31, 18),
          end: DateTime(2026, 1, 31, 19),
          recurrence: RecurrenceRule.monthly,
          until: DateTime(2026, 12, 31),
          reminder: ReminderTime.twoHours),
      make('yearly',
          start: DateTime(2028, 2, 29),
          end: DateTime(2028, 2, 29, 23, 59),
          isAllDay: true,
          recurrence: RecurrenceRule.yearly,
          count: 5,
          reminder: ReminderTime.twoDays),
      make('weekdays',
          start: DateTime(2026, 3, 9, 8, 45),
          end: DateTime(2026, 3, 9, 9),
          recurrence: RecurrenceRule.weekdays,
          until: DateTime(2026, 4, 3),
          excluded: [DateTime(2026, 3, 13)],
          reminder: ReminderTime.thirtyMinutes),
      make('biweekly-allday',
          start: DateTime(2026, 10, 23),
          end: DateTime(2026, 10, 23, 23, 59),
          isAllDay: true,
          recurrence: RecurrenceRule.biweekly,
          count: 8,
          excluded: [DateTime(2026, 11, 6)],
          reminder: ReminderTime.none),
      make('empty-title',
          title: '',
          start: DateTime(2026, 11, 1, 1, 30),
          end: DateTime(2026, 11, 1, 3, 30)),
    ];

    test('generateCalendar → parseEvents preserves every field', () {
      final text = IcalService.generateCalendar(events);
      final parsed = IcalService.parseEvents(text);
      expect(parsed, hasLength(events.length));
      for (var i = 0; i < events.length; i++) {
        final a = events[i];
        final b = parsed[i];
        final reason = 'event ${a.id}';
        expect(b.icalUid, a.uid, reason: reason);
        expect(b.title, a.title, reason: reason);
        expect(b.description, a.description, reason: reason);
        expect(b.location, a.location, reason: reason);
        expect(b.isAllDay, a.isAllDay, reason: reason);
        expect(b.startTime.difference(a.startTime).inSeconds.abs(),
            lessThanOrEqualTo(1),
            reason: reason);
        expect(b.endTime.difference(a.endTime).inSeconds.abs(),
            lessThanOrEqualTo(1),
            reason: reason);
        expect(b.startTime.isUtc, isFalse, reason: reason);
        expect([
          b.startTime.hour,
          b.startTime.minute
        ], [
          a.startTime.hour,
          a.startTime.minute
        ], reason: reason);
        expect(b.recurrence, a.recurrence, reason: reason);
        expect(b.recurrenceCount, a.recurrenceCount, reason: reason);
        if (a.recurrenceUntil == null) {
          expect(b.recurrenceUntil, isNull, reason: reason);
        } else {
          expect(sameDay(b.recurrenceUntil!, a.recurrenceUntil!), isTrue,
              reason: reason);
        }
        expect(b.excludedDates.length, a.excludedDates.length, reason: reason);
        for (var j = 0; j < a.excludedDates.length; j++) {
          expect(sameDay(b.excludedDates[j], a.excludedDates[j]), isTrue,
              reason: reason);
        }
        final expectedReminder =
            a.reminder == ReminderTime.none ? null : a.reminder;
        expect(b.reminder, expectedReminder, reason: reason);
        expect(b.attendees, a.attendees, reason: reason);
        expect(b.organizer, a.organizer, reason: reason);
      }
    });

    test('occurrences are identical after a round trip', () {
      final parsed =
          IcalService.parseEvents(IcalService.generateCalendar(events));
      for (var i = 0; i < events.length; i++) {
        List<(DateTime, DateTime)> occurrences(CalendarEvent e) => e
            .occurrencesBetween(DateTime(2025, 12, 1), DateTime(2033))
            .map((o) => (o.start, o.end))
            .toList();
        final expected = occurrences(events[i]);
        final actual = occurrences(parsed[i]);
        expect(actual.length, expected.length, reason: events[i].id);
        for (var j = 0; j < expected.length; j++) {
          expect(actual[j].$1.difference(expected[j].$1).inSeconds.abs(),
              lessThanOrEqualTo(1),
              reason: '${events[i].id} #$j');
          expect(actual[j].$2.difference(expected[j].$2).inSeconds.abs(),
              lessThanOrEqualTo(1),
              reason: '${events[i].id} #$j');
        }
      }
    });

    test('parsing, generating and parsing again is stable', () {
      final first = IcalService.parseEvents(outlookInvite);
      final again = IcalService.parseEvents(
          IcalService.generateCalendar(first, method: 'REQUEST'));
      expect(again.single.title, first.single.title);
      expect(again.single.description, first.single.description);
      expect(again.single.startTime, first.single.startTime);
      expect(again.single.endTime, first.single.endTime);
      expect(again.single.icalUid, first.single.icalUid);
      expect(again.single.attendees, first.single.attendees);
      expect(again.single.organizer, first.single.organizer);
      expect(again.single.reminder, first.single.reminder);
    });
  });

  group('generateReply', () {
    final invite = IcalService.parseEvents(outlookInvite).single;

    test('builds a METHOD:REPLY with the attendee status', () {
      final text = IcalService.generateReply(
        event: invite,
        attendeeEmail: 'john@example.com',
        attendeeName: 'John Roe',
        response: InviteResponse.accepted,
        now: DateTime.utc(2026, 1, 6, 10),
      );
      expect(IcalService.parseMethod(text), 'REPLY');
      final lines = logicalLines(text);
      expect(lines, contains('METHOD:REPLY'));
      expect(lines, contains('UID:${invite.icalUid}'));
      expect(lines, contains('ORGANIZER:mailto:jane@example.com'));
      expect(
          lines,
          contains(
              'ATTENDEE;CN=John Roe;PARTSTAT=ACCEPTED:mailto:john@example.com'));
      expect(lines, contains('DTSTAMP:20260106T100000Z'));
      expect(lines.where((l) => l.startsWith('ATTENDEE')), hasLength(1));
      expect(text.contains('VALARM'), isFalse);
      for (final line in physicalLines(text)) {
        expect(utf8.encode(line).length, lessThanOrEqualTo(75));
      }

      final parsed = IcalService.parseEvents(text).single;
      expect(parsed.icalUid, invite.icalUid);
      expect(parsed.attendees, ['john@example.com']);
      expect(parsed.organizer, 'jane@example.com');
      expect(parsed.startTime, invite.startTime);
      expect(parsed.endTime, invite.endTime);
      expect(parsed.title, invite.title);
    });

    test('tentative and declined; name with special characters', () {
      final tentative = IcalService.generateReply(
        event: invite,
        attendeeEmail: 'richard@example.com',
        attendeeName: 'Roe, Richard',
        response: InviteResponse.tentative,
      );
      expect(
          logicalLines(tentative),
          contains(
              'ATTENDEE;CN="Roe, Richard";PARTSTAT=TENTATIVE:mailto:richard@example.com'));
      final declined = IcalService.generateReply(
        event: invite,
        attendeeEmail: 'mailto:x@example.com',
        response: InviteResponse.declined,
      );
      expect(logicalLines(declined),
          contains('ATTENDEE;PARTSTAT=DECLINED:mailto:x@example.com'));
    });

    test('uses the event id when there is no iCalendar UID', () {
      final local = CalendarEvent(
        id: 'local-42',
        title: 'Local',
        startTime: DateTime(2026, 2, 1, 9),
        endTime: DateTime(2026, 2, 1, 10),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final text = IcalService.generateReply(
        event: local,
        attendeeEmail: 'me@example.com',
        response: InviteResponse.accepted,
      );
      expect(logicalLines(text), contains('UID:local-42'));
      expect(text.contains('ORGANIZER'), isFalse);
    });
  });
}
