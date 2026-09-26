import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/calendar_event.dart';
import 'package:look_in/providers/calendar_provider.dart';
import 'package:look_in/screens/calendar/calendar_io.dart';
import 'package:look_in/screens/calendar/calendar_layout.dart';
import 'package:look_in/screens/calendar/calendar_view.dart';
import 'package:look_in/screens/calendar/month_view.dart';
import 'package:look_in/screens/calendar/time_grid_view.dart';
import 'package:look_in/services/data_store.dart';
import 'package:look_in/theme/outlook_theme.dart';
import 'package:provider/provider.dart';

/// Wednesday; its Sunday-first week is March 8 - 14, 2026.
final wednesday = DateTime(2026, 3, 11);

CalendarEvent makeEvent(
  String id,
  String title,
  DateTime start,
  Duration length, {
  RecurrenceRule? recurrence,
  int? count,
  bool allDay = false,
  String? uid,
}) {
  return CalendarEvent(
    id: id,
    title: title,
    startTime: start,
    endTime: start.add(length),
    isAllDay: allDay,
    recurrence: recurrence,
    recurrenceCount: count,
    icalUid: uid,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

EventOccurrence occurrence(String id, int startHour, int startMinute,
    int endHour, int endMinute) {
  final event = makeEvent(
    id,
    id,
    DateTime(2026, 3, 11, startHour, startMinute),
    DateTime(2026, 3, 11, endHour, endMinute)
        .difference(DateTime(2026, 3, 11, startHour, startMinute)),
  );
  return EventOccurrence(
      event: event, start: event.startTime, end: event.endTime);
}

/// Pumps the calendar module on a 1400×900 window and returns its provider.
Future<CalendarProvider> pumpCalendar(
  WidgetTester tester,
  DataStore store, {
  CalendarViewType view = CalendarViewType.month,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => CalendarProvider(store: store)
          ..selectDate(wednesday)
          ..setViewType(view),
      ),
    ],
    child: MaterialApp(
      theme: OutlookTheme.themeData,
      home: const Scaffold(body: CalendarView()),
    ),
  ));
  await tester.pumpAndSettle();
  return tester.element(find.byType(CalendarView)).read<CalendarProvider>();
}

Finder inMonth(Finder finder) =>
    find.descendant(of: find.byType(MonthView), matching: finder);

Finder inGrid(Finder finder) =>
    find.descendant(of: find.byType(TimeGridView), matching: finder);

Future<void> doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late DataStore store;

  setUp(() => store = DataStore.inMemory());

  group('CalendarView', () {
    testWidgets('month view shows appointments', (tester) async {
      store.saveEvent(makeEvent('e1', 'Team sync',
          DateTime(2026, 3, 11, 9), const Duration(hours: 1)));
      store.saveEvent(makeEvent('e2', 'Conference', DateTime(2026, 3, 12),
          const Duration(days: 2, hours: -1), allDay: true));
      await pumpCalendar(tester, store);

      expect(find.text('March 2026'), findsWidgets);
      expect(inMonth(find.textContaining('Team sync')), findsOneWidget);
      expect(inMonth(find.textContaining('9:00 AM')), findsOneWidget);
      // A two-day all-day event shows in both of its days.
      expect(inMonth(find.text('Conference')), findsNWidgets(2));
    });

    testWidgets('switching to Week, Work Week and Day shows the event',
        (tester) async {
      store.saveEvent(makeEvent('e1', 'Team sync',
          DateTime(2026, 3, 11, 9), const Duration(hours: 1)));
      final cal = await pumpCalendar(tester, store);

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(cal.viewType, CalendarViewType.week);
      expect(find.text('March 8 - 14, 2026'), findsOneWidget);
      expect(inGrid(find.text('Team sync')), findsOneWidget);
      expect(inGrid(find.text('Wed 11')), findsOneWidget);
      expect(inGrid(find.text('9:00 AM - 10:00 AM')), findsOneWidget);

      await tester.tap(find.text('Work Week'));
      await tester.pumpAndSettle();
      expect(find.text('March 9 - 13, 2026'), findsOneWidget);
      expect(inGrid(find.text('Team sync')), findsOneWidget);

      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(find.text('March 11, 2026'), findsOneWidget);
      expect(inGrid(find.text('Wednesday 11')), findsOneWidget);
      expect(inGrid(find.text('Team sync')), findsOneWidget);

      // Navigating to the next day leaves the appointment behind.
      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.text('March 12, 2026'), findsOneWidget);
      expect(inGrid(find.text('Team sync')), findsNothing);
    });

    testWidgets('all-day events appear in the all-day band', (tester) async {
      store.saveEvent(makeEvent('e1', 'Holiday', DateTime(2026, 3, 9),
          const Duration(hours: 23, minutes: 59), allDay: true));
      await pumpCalendar(tester, store, view: CalendarViewType.week);
      expect(inGrid(find.text('Holiday')), findsOneWidget);
    });

    testWidgets('recurring daily event appears on every day of the week',
        (tester) async {
      store.saveEvent(makeEvent('r1', 'Standup', DateTime(2026, 3, 8, 9, 30),
          const Duration(minutes: 15),
          recurrence: RecurrenceRule.daily));
      final cal = await pumpCalendar(tester, store, view: CalendarViewType.week);
      expect(inGrid(find.text('Standup')), findsNWidgets(7));

      // Removing one occurrence leaves the other six.
      final wednesdayOccurrence = cal.getOccurrencesForDate(wednesday).single;
      cal.removeOccurrence(wednesdayOccurrence);
      await tester.pumpAndSettle();
      expect(inGrid(find.text('Standup')), findsNWidgets(6));
    });

    testWidgets('EventEditorDialog creates an appointment', (tester) async {
      await pumpCalendar(tester, store);
      showDialog<void>(
        context: tester.element(find.byType(CalendarView)),
        builder: (_) =>
            EventEditorDialog(initialStart: DateTime(2026, 3, 11, 14)),
      );
      await tester.pumpAndSettle();
      expect(find.text('New Appointment'), findsOneWidget);

      await tester.enterText(
          find.byKey(EventEditorDialog.subjectFieldKey), 'Dentist');
      await tester.enterText(
          find.byKey(EventEditorDialog.locationFieldKey), 'Main Street');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      final event = store.events.single;
      expect(event.title, 'Dentist');
      expect(event.location, 'Main Street');
      expect(event.startTime, DateTime(2026, 3, 11, 14));
      expect(event.endTime, DateTime(2026, 3, 11, 14, 30));
      expect(event.isRecurring, isFalse);
      expect(find.text('New Appointment'), findsNothing);
      expect(inMonth(find.textContaining('Dentist')), findsOneWidget);
    });

    testWidgets('editor rejects an end before the start and saves all-day',
        (tester) async {
      await pumpCalendar(tester, store);
      showDialog<void>(
        context: tester.element(find.byType(CalendarView)),
        builder: (_) =>
            EventEditorDialog(initialStart: DateTime(2026, 3, 11, 14)),
      );
      await tester.pumpAndSettle();

      // Pick an end time before the start.
      await tester.tap(find.text('2:30 PM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1:00 PM').last);
      await tester.pumpAndSettle();
      expect(
          find.text('The end time you entered occurs before the start time.'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
      expect(store.events, isEmpty);

      // All-day events only compare dates.
      await tester.tap(find.byKey(EventEditorDialog.allDayCheckboxKey));
      await tester.pumpAndSettle();
      expect(find.text('New All Day Event'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      final event = store.events.single;
      expect(event.isAllDay, isTrue);
      expect(event.startTime, DateTime(2026, 3, 11));
      expect(event.endTime, DateTime(2026, 3, 11, 23, 59));
    });

    testWidgets('double-clicking an empty slot opens a new appointment there',
        (tester) async {
      await pumpCalendar(tester, store, view: CalendarViewType.day);
      final label = tester.getTopRight(inGrid(find.text('10 AM')));
      // The label sits 2px below the hour line; aim inside the 10:00 slot.
      final slot = Offset(label.dx + 100, label.dy + 10);
      await tester.tapAt(slot);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(slot);
      await tester.pumpAndSettle();

      expect(find.text('New Appointment'), findsOneWidget);
      expect(find.text('10:00 AM'), findsOneWidget);
      await tester.enterText(
          find.byKey(EventEditorDialog.subjectFieldKey), 'Call');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(store.events.single.startTime, DateTime(2026, 3, 11, 10));
      expect(inGrid(find.text('Call')), findsOneWidget);
    });

    testWidgets('opening an occurrence edits the whole series',
        (tester) async {
      store.saveEvent(makeEvent('r1', 'Standup', DateTime(2026, 3, 8, 9, 30),
          const Duration(minutes: 30),
          recurrence: RecurrenceRule.daily));
      final cal = await pumpCalendar(tester, store, view: CalendarViewType.week);

      // Sunday is index 0, so Wednesday's occurrence is index 3.
      await doubleTap(tester, inGrid(find.text('Standup')).at(3));
      expect(cal.selectedOccurrence?.start, DateTime(2026, 3, 11, 9, 30));
      expect(find.text('Changes apply to the entire series'), findsOneWidget);
      expect(find.text('Wed 3/11/2026'), findsNWidgets(2));

      await tester.enterText(
          find.byKey(EventEditorDialog.subjectFieldKey), 'Daily scrum');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      final event = store.events.single;
      expect(event.title, 'Daily scrum');
      expect(event.startTime, DateTime(2026, 3, 8, 9, 30));
      expect(event.recurrence, RecurrenceRule.daily);
      expect(inGrid(find.text('Daily scrum')), findsNWidgets(7));
    });

    testWidgets('Delete key deletes the selected appointment',
        (tester) async {
      store.saveEvent(makeEvent('e1', 'Team sync',
          DateTime(2026, 3, 11, 9), const Duration(hours: 1)));
      final cal = await pumpCalendar(tester, store, view: CalendarViewType.day);

      await tester.tap(inGrid(find.text('Team sync')));
      await tester.pumpAndSettle();
      expect(cal.selectedOccurrence?.event.id, 'e1');

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.text('Delete Appointment'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(store.events, isEmpty);
      expect(inGrid(find.text('Team sync')), findsNothing);
    });

    testWidgets('right-click menu categorizes an appointment',
        (tester) async {
      store.saveEvent(makeEvent('e1', 'Team sync',
          DateTime(2026, 3, 11, 9), const Duration(hours: 1)));
      await pumpCalendar(tester, store, view: CalendarViewType.day);

      await tester.tap(inGrid(find.text('Team sync')),
          buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Green Category'));
      await tester.pumpAndSettle();

      expect(store.events.single.category, EventCategory.green);
    });

    testWidgets('"+N more" opens the day in the Day view', (tester) async {
      for (var i = 0; i < 6; i++) {
        store.saveEvent(makeEvent('e$i', 'Meeting $i',
            DateTime(2026, 3, 11, 8 + i), const Duration(minutes: 30)));
      }
      final cal = await pumpCalendar(tester, store);
      expect(inMonth(find.text('+3 more')), findsOneWidget);

      await tester.tap(find.text('+3 more'));
      await tester.pumpAndSettle();
      expect(cal.viewType, CalendarViewType.day);
      expect(inGrid(find.text('Meeting 5')), findsOneWidget);
    });
  });

  group('layoutOverlaps', () {
    test('puts overlapping events side by side', () {
      final a = occurrence('a', 9, 0, 10, 0);
      final b = occurrence('b', 9, 30, 10, 30);
      final c = occurrence('c', 10, 30, 11, 0);
      final layout = layoutOverlaps([c, b, a]);

      expect(layout[a.key], (column: 0, columns: 2));
      expect(layout[b.key], (column: 1, columns: 2));
      // Starts when b ends: a new group with the full width.
      expect(layout[c.key], (column: 0, columns: 1));
    });

    test('reuses freed columns within a group', () {
      final a = occurrence('a', 9, 0, 12, 0);
      final b = occurrence('b', 9, 0, 10, 0);
      final c = occurrence('c', 10, 0, 11, 0);
      final d = occurrence('d', 10, 30, 11, 30);
      final layout = layoutOverlaps([a, b, c, d]);

      expect(layout[a.key], (column: 0, columns: 3));
      expect(layout[b.key], (column: 1, columns: 3));
      expect(layout[c.key], (column: 1, columns: 3));
      expect(layout[d.key], (column: 2, columns: 3));
    });

    test('minDuration makes short events take up space', () {
      final a = occurrence('a', 9, 0, 9, 5);
      final b = occurrence('b', 9, 15, 9, 20);
      expect(layoutOverlaps([a, b])[b.key], (column: 0, columns: 1));
      expect(
        layoutOverlaps([a, b], minDuration: const Duration(minutes: 30))[b.key],
        (column: 1, columns: 2),
      );
    });
  });

  group('layout helpers', () {
    test('all-day band stacks overlapping spans into rows', () {
      final sunday = DateTime(2026, 3, 8);
      final long = makeEvent('long', 'Trip', DateTime(2026, 3, 9),
          const Duration(days: 3), allDay: true);
      final short = makeEvent('short', 'Holiday', DateTime(2026, 3, 10),
          const Duration(hours: 23, minutes: 59), allDay: true);
      final later = makeEvent('later', 'Offsite', DateTime(2026, 3, 13),
          const Duration(days: 5), allDay: true);
      final placements = layoutAllDayBand([
        for (final e in [short, later, long])
          EventOccurrence(event: e, start: e.startTime, end: e.endTime),
      ], sunday, 7);
      final byId = {for (final p in placements) p.occurrence.event.id: p};

      expect((byId['long']!.firstDay, byId['long']!.lastDay), (1, 3));
      expect(byId['long']!.row, 0);
      expect(byId['short']!.row, 1);
      // Clipped to the visible week and placed in the first free row.
      expect((byId['later']!.firstDay, byId['later']!.lastDay), (5, 6));
      expect(byId['later']!.row, 0);
    });

    test('segmentsByDay clips overnight appointments to each day', () {
      final e = makeEvent('n', 'Night shift', DateTime(2026, 3, 10, 22),
          const Duration(hours: 4));
      final o = EventOccurrence(event: e, start: e.startTime, end: e.endTime);
      final days = segmentsByDay([o], DateTime(2026, 3, 8), 7);

      expect(days[2].single.start, DateTime(2026, 3, 10, 22));
      expect(days[2].single.end, DateTime(2026, 3, 11));
      expect(days[3].single.start, DateTime(2026, 3, 11));
      expect(days[3].single.end, DateTime(2026, 3, 11, 2));
      expect(days[3].single.continuesFromPreviousDay, isTrue);
    });

    test('formats times like Outlook', () {
      expect(formatMinutes(0), '12:00 AM');
      expect(formatMinutes(9 * 60 + 30), '9:30 AM');
      expect(formatMinutes(12 * 60), '12:00 PM');
      expect(formatHourLabel(13), '1 PM');
      expect(formatDuration(const Duration(minutes: 90)), '1.5 hours');
      expect(formatDuration(const Duration(hours: 1)), '1 hour');
      expect(formatShortDate(wednesday), 'Wed 3/11/2026');
    });
  });

  group('planCalendarImport', () {
    test('updates events with a known UID and adds the rest', () {
      final existing = makeEvent('local-1', 'Old title',
              DateTime(2026, 3, 11, 9), const Duration(hours: 1),
              uid: 'uid-1')
          .copyWith(category: EventCategory.red);
      final parsedKnown = makeEvent('parsed-1', 'New title',
          DateTime(2026, 3, 11, 10), const Duration(hours: 1),
          uid: 'uid-1');
      final parsedNew = makeEvent('parsed-2', 'Brand new',
          DateTime(2026, 3, 12, 10), const Duration(hours: 1),
          uid: 'uid-2');

      final plan = planCalendarImport([existing], [parsedKnown, parsedNew]);

      expect(plan.added.map((e) => e.id), ['parsed-2']);
      final updated = plan.updated.single;
      expect(updated.id, 'local-1');
      expect(updated.title, 'New title');
      expect(updated.category, EventCategory.red);
      expect(updated.uid, 'uid-1');
    });
  });
}
