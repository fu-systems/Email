import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/calendar_event.dart';
import 'package:look_in/models/contact.dart';
import 'package:look_in/models/email_account.dart';
import 'package:look_in/providers/calendar_provider.dart';
import 'package:look_in/providers/contacts_provider.dart';
import 'package:look_in/services/backends/graph_client.dart';
import 'package:look_in/services/data_store.dart';
import 'package:look_in/services/ical_service.dart';
import 'package:look_in/services/oauth/token_manager.dart';
import 'package:look_in/services/sync/graph_pim_mappers.dart';
import 'package:look_in/services/sync/graph_pim_sync.dart';

import 'graph_mail_test.dart' show FakeTokens;
import 'support/fake_graph_server.dart';

const _account = EmailAccount(
  id: 'ms',
  displayName: 'Ann Example',
  emailAddress: 'ann@outlook.com',
  protocol: IncomingProtocol.graph,
  incomingHost: 'outlook.office365.com',
  incomingPort: 993,
  smtpHost: 'smtp.office365.com',
  smtpPort: 587,
  username: 'ann@outlook.com',
  password: '',
  authMethod: AuthMethod.oauth2,
  oauthProvider: 'microsoft',
  oauthClientId: '11111111-2222-3333-4444-555555555555',
);

const _source = 'graph:ms';

void main() {
  group('mappers', () {
    test('events from Graph: UTC times, categories, reminders', () {
      final e = GraphPimMappers.eventFromGraph({
        'id': 'E1',
        'subject': 'Standup',
        'start': {'dateTime': '2026-10-05T16:00:00.0000000', 'timeZone': 'UTC'},
        'end': {'dateTime': '2026-10-05T16:30:00.0000000', 'timeZone': 'UTC'},
        'isAllDay': false,
        'isReminderOn': true,
        'reminderMinutesBeforeStart': 15,
        'categories': ['Green category'],
        'location': {'displayName': 'Room 1'},
        'body': {'contentType': 'html', 'content': '<p>Agenda</p>'},
        'attendees': [
          {
            'emailAddress': {'address': 'bob@example.com'},
          },
        ],
        'organizer': {
          'emailAddress': {'address': 'carol@example.com'},
        },
        'iCalUId': 'uid-1',
        'seriesMasterId': 'M1',
        '@odata.etag': 'W/"3"',
      }, _source);
      expect(e.id, 'graph:ms:E1');
      expect(e.startTime, DateTime.utc(2026, 10, 5, 16).toLocal());
      expect(e.duration, const Duration(minutes: 30));
      expect(e.category, EventCategory.green);
      expect(e.reminder, ReminderTime.fifteenMinutes);
      expect(e.description, 'Agenda');
      expect(e.location, 'Room 1');
      expect(e.attendees, ['bob@example.com']);
      expect(e.organizer, 'carol@example.com');
      expect(e.icalUid, 'uid-1');
      expect(e.seriesMasterId, 'M1');
      expect(e.etag, 'W/"3"');
      expect(e.sourceId, _source);
      expect(e.remoteId, 'E1');
    });

    test('all-day and cancelled events', () {
      final holiday = GraphPimMappers.eventFromGraph({
        'id': 'H',
        'subject': 'Holidays',
        'isAllDay': true,
        'start': {'dateTime': '2026-12-24T00:00:00.0000000', 'timeZone': 'UTC'},
        'end': {'dateTime': '2026-12-26T00:00:00.0000000', 'timeZone': 'UTC'},
        'isCancelled': true,
      }, _source);
      expect(holiday.startTime, DateTime(2026, 12, 24));
      expect(holiday.endTime, DateTime(2026, 12, 25, 23, 59));
      expect(holiday.title, 'Canceled: Holidays');
      expect(holiday.reminder, ReminderTime.none);
    });

    test('events to Graph: local wall time, recurrence, all-day end', () {
      final now = DateTime(2026);
      final monday = CalendarEvent(
        id: 'x',
        title: 'Team sync',
        startTime: DateTime(2026, 10, 5, 9),
        endTime: DateTime(2026, 10, 5, 9, 30),
        recurrence: RecurrenceRule.weekly,
        recurrenceCount: 3,
        reminder: ReminderTime.fifteenMinutes,
        category: EventCategory.red,
        attendees: const ['bob@example.com'],
        createdAt: now,
        updatedAt: now,
      );
      final json = GraphPimMappers.eventToGraph(
        monday,
        timeZone: 'Europe/Berlin',
      );
      expect(json['start'], {
        'dateTime': '2026-10-05T09:00:00',
        'timeZone': 'Europe/Berlin',
      });
      expect(json['categories'], ['Red category']);
      expect(json['reminderMinutesBeforeStart'], 15);
      expect(json['attendees'], [
        {
          'emailAddress': {'address': 'bob@example.com'},
          'type': 'required',
        },
      ]);
      expect(json['recurrence'], {
        'pattern': {
          'type': 'weekly',
          'interval': 1,
          'daysOfWeek': ['monday'],
          'firstDayOfWeek': 'sunday',
        },
        'range': {
          'startDate': '2026-10-05',
          'recurrenceTimeZone': 'Europe/Berlin',
          'type': 'numbered',
          'numberOfOccurrences': 3,
        },
      });

      // Without a zone, times go in UTC.
      final utc = GraphPimMappers.eventToGraph(monday);
      final start = DateTime(2026, 10, 5, 9).toUtc();
      expect((utc['start'] as Map)['timeZone'], 'UTC');
      expect(
        (utc['start'] as Map)['dateTime'],
        start.toIso8601String().split('.').first.replaceAll('Z', ''),
      );

      final monthly = GraphPimMappers.recurrenceToGraph(
        monday.copyWith(
          recurrence: RecurrenceRule.monthly,
          recurrenceUntil: DateTime(2027, 3, 1),
          clearRecurrenceCount: true,
        ),
        monday.startTime,
        'UTC',
      )!;
      expect(monthly['pattern'], {
        'type': 'absoluteMonthly',
        'interval': 1,
        'dayOfMonth': 5,
      });
      expect((monthly['range'] as Map)['endDate'], '2027-03-01');
      final weekdays = GraphPimMappers.recurrenceToGraph(
        monday.copyWith(
          recurrence: RecurrenceRule.weekdays,
          clearRecurrenceCount: true,
        ),
        monday.startTime,
        'UTC',
      )!;
      expect((weekdays['pattern'] as Map)['daysOfWeek'], hasLength(5));
      expect((weekdays['range'] as Map)['type'], 'noEnd');

      final allDay = GraphPimMappers.eventToGraph(
        CalendarEvent(
          id: 'a',
          title: 'Holidays',
          startTime: DateTime(2026, 12, 24),
          endTime: DateTime(2026, 12, 25, 23, 59),
          isAllDay: true,
          createdAt: now,
          updatedAt: now,
        ),
        timeZone: 'Europe/Berlin',
      );
      expect((allDay['start'] as Map)['dateTime'], '2026-12-24T00:00:00');
      expect((allDay['end'] as Map)['dateTime'], '2026-12-26T00:00:00');
      expect(allDay['isReminderOn'], isFalse);
    });

    test('contacts both ways', () {
      final c = GraphPimMappers.contactFromGraph({
        'id': 'C1',
        'givenName': 'Bob',
        'surname': 'Example',
        'companyName': 'Contoso',
        'jobTitle': 'Engineer',
        'emailAddresses': [
          {'address': 'bob@example.com', 'name': 'Bob'},
          {'address': 'bob@home.example'},
        ],
        'mobilePhone': '+1 555 0101',
        'businessPhones': ['+1 555 0102'],
        'homePhones': [],
        'businessAddress': {
          'street': '1 Main St',
          'city': 'Springfield',
          'postalCode': '12345',
        },
        'personalNotes': 'Met at the conference',
        '@odata.etag': 'W/"1"',
      }, _source);
      expect(c.id, 'graph:ms:C1');
      expect(c.displayName, 'Bob Example');
      expect(c.emails.map((e) => e.address), [
        'bob@example.com',
        'bob@home.example',
      ]);
      expect(c.phones.map((p) => '${p.label}: ${p.number}'), [
        'Mobile: +1 555 0101',
        'Work: +1 555 0102',
      ]);
      expect(c.address?.city, 'Springfield');
      expect(c.notes, 'Met at the conference');

      final back = GraphPimMappers.contactToGraph(c);
      expect(back['givenName'], 'Bob');
      expect(back['mobilePhone'], '+1 555 0101');
      expect(back['businessPhones'], ['+1 555 0102']);
      expect((back['businessAddress'] as Map)['postalCode'], '12345');
      expect(back['emailAddresses'], hasLength(2));
    });

    test('the local time zone', () {
      final dir = Directory.systemTemp.createTempSync('tz');
      final link = Link('${dir.path}/localtime')
        ..createSync('/usr/share/zoneinfo/America/Denver');
      expect(
        GraphPimMappers.localTimeZoneName(
          environment: const {},
          localtimePath: link.path,
          timezonePath: '${dir.path}/none',
        ),
        'America/Denver',
      );
      expect(
        GraphPimMappers.localTimeZoneName(
          environment: const {'TZ': 'Asia/Tokyo'},
        ),
        'Asia/Tokyo',
      );
      File('${dir.path}/timezone').writeAsStringSync('Europe/Paris\n');
      expect(
        GraphPimMappers.localTimeZoneName(
          environment: const {},
          localtimePath: '${dir.path}/missing',
          timezonePath: '${dir.path}/timezone',
        ),
        'Europe/Paris',
      );
    });
  });

  group('sync', () {
    late FakeGraphServer graph;
    late DataStore store;
    late GraphPimSync pim;
    final original = GraphClient.baseUrl;
    final changes = <String>[];

    setUp(() async {
      graph = await FakeGraphServer.start();
      GraphClient.baseUrl = graph.baseUrl;
      store = DataStore.inMemory();
      DataStore.instance = store;
      TokenManager.instance = FakeTokens(store);
      pim = GraphPimSync(store: store);
      pim.setAccounts([_account]);
      changes.clear();
      pim.onLocalChange = changes.add;
    });

    tearDown(() async {
      pim.dispose();
      GraphClient.baseUrl = original;
      TokenManager.instance = null;
      store.close();
      await graph.close();
    });

    List<CalendarEvent> events() =>
        store.events.where((e) => e.sourceId == _source).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    List<Contact> contacts() =>
        store.contacts.where((c) => c.sourceId == _source).toList();

    final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
    DateTime at(int hour) =>
        DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day, hour);

    test('pulls the calendar and contacts', () async {
      graph.addEvent(subject: 'Review', start: at(14), end: at(15));
      graph.addEvent(
        subject: 'Offsite',
        start: DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day),
        end: DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day + 2),
        isAllDay: true,
      );
      graph.addContact({
        'givenName': 'Bob',
        'surname': 'Example',
        'emailAddresses': [
          {'address': 'bob@example.com'},
        ],
      });
      await pim.sync(_account);

      expect(events().map((e) => e.title), ['Offsite', 'Review']);
      final offsite = events().first;
      expect(offsite.isAllDay, isTrue);
      expect(
        offsite.endTime,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day + 1, 23, 59),
      );
      expect(contacts().single.primaryEmail, 'bob@example.com');
      expect(pim.errorFor(_source, calendar: true), isNull);
      expect(pim.sources.single.label, 'ann@outlook.com');
    });

    test('changes on the server arrive by delta', () async {
      final review = graph.addEvent(
        subject: 'Review',
        start: at(14),
        end: at(15),
      );
      final lunch = graph.addEvent(
        subject: 'Lunch',
        start: at(12),
        end: at(13),
      );
      final bob = graph.addContact({'givenName': 'Bob'});
      final carol = graph.addContact({'givenName': 'Carol'});
      await pim.sync(_account);

      graph.changeEvent(review, {'subject': 'Review (moved)'});
      graph.removeEvent(lunch);
      graph.addEvent(subject: 'Dinner', start: at(19), end: at(21));
      graph.changeContact(bob, {'surname': 'Example'});
      graph.removeContact(carol);
      await pim.sync(_account);

      expect(events().map((e) => e.title), ['Review (moved)', 'Dinner']);
      expect(contacts().map((c) => c.displayName), ['Bob Example']);
      expect(
        graph.requests.where((r) => r.contains('calendarView/delta')),
        hasLength(2),
      );
    });

    test('local creates, updates and deletes are sent', () async {
      final cal = CalendarProvider(store: store, pim: pim);
      addTearDown(cal.dispose);
      final now = DateTime.now();
      final start = at(9).toLocal();
      cal.addEvent(
        CalendarEvent(
          id: 'local-1',
          title: 'Dentist',
          startTime: start,
          endTime: start.add(const Duration(hours: 1)),
          sourceId: _source,
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(store.getEvent('local-1')!.pendingSync, 'create');
      expect(changes, ['ms']);

      await pim.sync(_account);
      final serverEvent = graph.occurrences.single;
      expect(serverEvent['subject'], 'Dentist');
      final created = events().single;
      expect(created.id, 'graph:ms:${serverEvent['id']}');
      expect(created.pendingSync, isNull);
      expect(store.getEvent('local-1'), isNull);

      cal.updateEvent(
        created.copyWith(
          title: 'Dentist (rescheduled)',
          updatedAt: DateTime.now(),
        ),
      );
      await pim.sync(_account);
      expect(
        graph.events[serverEvent['id']]!['subject'],
        'Dentist (rescheduled)',
      );

      cal.removeEvent(created.id);
      await pim.sync(_account);
      expect(graph.events, isEmpty);
      expect(events(), isEmpty);

      final people = ContactsProvider(store: store, pim: pim);
      addTearDown(people.dispose);
      people.setAddressBookFilter(_source);
      final draft = people.createEmpty();
      expect(draft.sourceId, _source);
      people.addContact(
        draft.withDetails(
          firstName: 'Dana',
          lastName: 'Example',
          company: null,
          jobTitle: null,
          emails: const [ContactEmail(label: 'Email', address: 'dana@x.com')],
          phones: const [],
          address: null,
          notes: null,
          updatedAt: DateTime.now(),
        ),
      );
      await pim.sync(_account);
      final dana = graph.contacts.values.single;
      expect(dana['surname'], 'Example');
      people.removeContact(contacts().single.id);
      await pim.sync(_account);
      expect(graph.contacts, isEmpty);
    });

    test('a new series goes up without its deleted occurrence', () async {
      final cal = CalendarProvider(store: store, pim: pim);
      addTearDown(cal.dispose);
      final first = at(10).toLocal();
      final now = DateTime.now();
      cal.addEvent(
        CalendarEvent(
          id: 'series',
          title: 'Class',
          startTime: first,
          endTime: first.add(const Duration(hours: 1)),
          recurrence: RecurrenceRule.weekly,
          recurrenceCount: 3,
          excludedDates: [DateTime(first.year, first.month, first.day + 7)],
          sourceId: _source,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await pim.sync(_account);

      final series = events();
      expect(series.map((e) => e.startTime), [
        first,
        first.add(const Duration(days: 14)),
      ]);
      expect(series.every((e) => e.seriesMasterId != null), isTrue);
      expect(cal.isServerSeriesOccurrence(series.first), isTrue);

      cal.removeSeries(series.first);
      expect(events(), isEmpty);
      await pim.sync(_account);
      expect(graph.events, isEmpty);
    });

    test('when both sides changed, the newer change wins', () async {
      final cal = CalendarProvider(store: store, pim: pim);
      addTearDown(cal.dispose);
      final id = graph.addEvent(subject: 'Plan', start: at(8), end: at(9));
      await pim.sync(_account);

      // Changed in Outlook after the change here: Outlook's stays.
      cal.updateEvent(
        events().single.copyWith(
          title: 'Plan (here)',
          updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      );
      graph.changeEvent(id, {'subject': 'Plan (Outlook)'});
      await pim.sync(_account);
      expect(events().single.title, 'Plan (Outlook)');
      expect(graph.events[id]!['subject'], 'Plan (Outlook)');

      // Changed here after Outlook: this one is sent anyway.
      graph.changeEvent(id, {
        'subject': 'Plan (Outlook again)',
      }, at: DateTime.now().subtract(const Duration(hours: 1)));
      cal.updateEvent(
        events().single.copyWith(
          title: 'Plan (here again)',
          updatedAt: DateTime.now(),
        ),
      );
      await pim.sync(_account);
      expect(graph.events[id]!['subject'], 'Plan (here again)');
      expect(events().single.title, 'Plan (here again)');
    });

    test(
      'only what changed is sent, so what Look In doesn\'t show stays',
      () async {
        final cal = CalendarProvider(store: store, pim: pim);
        addTearDown(cal.dispose);
        const html = '<p>Join <a href="https://teams.example/j/1">here</a></p>';
        final id = graph.addEvent(
          subject: 'Sync-up',
          start: at(11),
          end: at(12),
          extra: {
            'body': {'contentType': 'html', 'content': html},
            'isReminderOn': true,
            'reminderMinutesBeforeStart': 15,
            'attendees': [
              {
                'emailAddress': {
                  'address': 'bob@example.com',
                  'name': 'Bob Example',
                },
                'type': 'optional',
                'status': {'response': 'accepted'},
              },
            ],
          },
        );
        final bobId = graph.addContact({
          'givenName': 'Bob',
          'emailAddresses': [
            {'address': 'bob@example.com'},
          ],
          'birthday': '1990-05-01T00:00:00Z',
        });
        await pim.sync(_account);

        cal.updateEvent(
          events().single.copyWith(
            reminder: ReminderTime.thirtyMinutes,
            updatedAt: DateTime.now(),
          ),
        );
        await pim.sync(_account);
        expect(graph.patches[id], [
          {'reminderMinutesBeforeStart': 30},
        ]);
        expect(graph.events[id]!['body'], {
          'contentType': 'html',
          'content': html,
        });

        cal.updateEvent(
          events().single.copyWith(
            attendees: ['bob@example.com', 'carol@example.com'],
            updatedAt: DateTime.now(),
          ),
        );
        await pim.sync(_account);
        expect(graph.patches[id]!.last, {
          'attendees': [
            {
              'emailAddress': {
                'address': 'bob@example.com',
                'name': 'Bob Example',
              },
              'type': 'optional',
            },
            {
              'emailAddress': {'address': 'carol@example.com'},
              'type': 'required',
            },
          ],
        });

        // Moving it sends both times.
        final moved = events().single;
        cal.updateEvent(
          moved.copyWith(
            endTime: moved.endTime.add(const Duration(minutes: 30)),
            updatedAt: DateTime.now(),
          ),
        );
        await pim.sync(_account);
        expect(graph.patches[id]!.last.keys, {'start', 'end', 'isAllDay'});

        final people = ContactsProvider(store: store, pim: pim);
        addTearDown(people.dispose);
        final bob = contacts().single;
        people.updateContact(
          bob.copyWith(jobTitle: 'Finance lead', updatedAt: DateTime.now()),
        );
        await pim.sync(_account);
        expect(graph.patches[bobId], [
          {'jobTitle': 'Finance lead'},
        ]);
        expect(graph.contacts[bobId]!['birthday'], '1990-05-01T00:00:00Z');
      },
    );

    test('meeting invitations are answered through Graph', () async {
      final id = graph.addEvent(
        subject: 'Planning',
        start: at(16),
        end: at(17),
        iCalUId: 'uid-123',
      );
      expect(
        await pim.respondToInvitation(
          _account,
          'uid-123',
          InviteResponse.accepted,
        ),
        isTrue,
      );
      expect(graph.invitationAnswers[id], 'accept');
      expect(events().single.title, 'Planning', reason: 'synced afterwards');

      expect(
        await pim.respondToInvitation(
          _account,
          'unknown',
          InviteResponse.declined,
        ),
        isFalse,
      );
      await pim.respondToInvitation(
        _account,
        'uid-123',
        InviteResponse.declined,
      );
      expect(events(), isEmpty);
    });

    test('a refused calendar does not stop the contacts', () async {
      graph.denyCalendar = true;
      graph.addContact({'givenName': 'Bob'});
      await pim.sync(_account);
      expect(contacts(), hasLength(1));
      expect(
        pim.errorFor(_source, calendar: true),
        contains('Calendars.ReadWrite'),
      );
      expect(pim.errorFor(_source, calendar: false), isNull);
    });

    test('a removed account takes its calendar and contacts along', () async {
      graph.addEvent(subject: 'Review', start: at(14), end: at(15));
      graph.addContact({'givenName': 'Bob'});
      await pim.sync(_account);
      expect(events(), isNotEmpty);
      pim.setAccounts(const []);
      expect(events(), isEmpty);
      expect(contacts(), isEmpty);
      expect(pim.sources, isEmpty);
    });

    test('calendars can be hidden', () async {
      final cal = CalendarProvider(store: store, pim: pim);
      addTearDown(cal.dispose);
      graph.addEvent(subject: 'Review', start: at(14), end: at(15));
      await pim.sync(_account);
      final day = at(14).toLocal();
      final now = DateTime.now();
      cal.addEvent(
        CalendarEvent(
          id: 'mine',
          title: 'Gym',
          startTime: DateTime(day.year, day.month, day.day, 7),
          endTime: DateTime(day.year, day.month, day.day, 8),
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(cal.calendars.map((c) => c.label), [
        'Calendar',
        'Calendar - ann@outlook.com',
      ]);
      expect(cal.getOccurrencesForDate(day), hasLength(2));
      cal.setCalendarVisible(_source, false);
      expect(cal.getOccurrencesForDate(day).single.event.title, 'Gym');
      expect(
        CalendarProvider(store: store, pim: pim).isCalendarVisible(_source),
        isFalse,
        reason: 'remembered',
      );
    });
  });
}
