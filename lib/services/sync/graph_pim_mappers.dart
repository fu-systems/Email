import 'dart:io';

import '../../models/calendar_event.dart';
import '../../models/contact.dart';
import '../html_sanitizer.dart';

/// Converts between Microsoft Graph's events and contacts and Look In's.
///
/// Events are read with `Prefer: outlook.timezone="UTC"`, so their times
/// are UTC; they are written in the computer's time zone, so recurring
/// series keep their local time across daylight-saving changes.
class GraphPimMappers {
  GraphPimMappers._();

  /// Local id of a synced item.
  static String localId(String sourceId, String remoteId) =>
      '$sourceId:$remoteId';

  // ─── Time ──────────────────────────────────────────────────────────

  /// The computer's IANA time zone (e.g. `Europe/Berlin`), or null.
  static String? localTimeZoneName({
    Map<String, String>? environment,
    String localtimePath = '/etc/localtime',
    String timezonePath = '/etc/timezone',
  }) {
    final env = environment ?? Platform.environment;
    final tz = env['TZ'];
    if (tz != null &&
        tz.isNotEmpty &&
        !tz.startsWith(':') &&
        tz.contains('/')) {
      return tz;
    }
    try {
      final link = Link(localtimePath);
      if (link.existsSync()) {
        final target = link.targetSync();
        final i = target.indexOf('zoneinfo/');
        if (i >= 0) return target.substring(i + 'zoneinfo/'.length);
      }
    } catch (_) {}
    try {
      final name = File(timezonePath).readAsStringSync().trim();
      if (name.contains('/')) return name;
    } catch (_) {}
    return null;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Graph's dateTime format: no offset, no more than seconds.
  static String _wall(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}'
      'T${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  /// A Graph dateTimeTimeZone read in UTC, as local time.
  static DateTime? _utc(Object? raw) {
    final value = (raw as Map?)?['dateTime'] as String?;
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.endsWith('Z') ? value : '${value}Z');
    return parsed?.toLocal();
  }

  /// The date part of a Graph dateTimeTimeZone (for all-day events).
  static DateTime? _date(Object? raw) {
    final value = (raw as Map?)?['dateTime'] as String?;
    if (value == null || value.length < 10) return null;
    final d = DateTime.tryParse(value.substring(0, 10));
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  // ─── Events ────────────────────────────────────────────────────────

  static const _categoryNames = {
    EventCategory.green: 'Green category',
    EventCategory.red: 'Red category',
    EventCategory.orange: 'Orange category',
    EventCategory.purple: 'Purple category',
  };

  static EventCategory _category(Object? raw) {
    for (final name in (raw as List? ?? const []).cast<String>()) {
      final lower = name.toLowerCase();
      for (final c in EventCategory.values) {
        if (lower.contains(c.name)) return c;
      }
    }
    return EventCategory.blue;
  }

  /// An event (single, occurrence or exception) from Graph.
  static CalendarEvent eventFromGraph(
    Map<String, dynamic> json,
    String sourceId,
  ) {
    final remoteId = json['id'] as String;
    final isAllDay = json['isAllDay'] == true;
    DateTime start;
    DateTime end;
    if (isAllDay) {
      start = _date(json['start']) ?? _dateOnly(DateTime.now());
      final endExclusive = _date(json['end']);
      // Look In's all-day events end on their last day at 23:59.
      final last = endExclusive != null && endExclusive.isAfter(start)
          ? endExclusive.subtract(const Duration(days: 1))
          : start;
      end = DateTime(last.year, last.month, last.day, 23, 59);
    } else {
      start = _utc(json['start']) ?? DateTime.now();
      end = _utc(json['end']) ?? start.add(const Duration(minutes: 30));
      if (end.isBefore(start)) end = start;
    }
    final body = json['body'] as Map?;
    final content = body?['content'] as String? ?? '';
    final description =
        (body?['contentType'] == 'html' ? htmlToPlainText(content) : content)
            .trim();
    final location = ((json['location'] as Map?)?['displayName'] as String?)
        ?.trim();
    final reminderOn = json['isReminderOn'] == true;
    final minutes = json['reminderMinutesBeforeStart'] as int? ?? 15;
    final organizer =
        ((json['organizer'] as Map?)?['emailAddress'] as Map?)?['address']
            as String?;
    final subject = (json['subject'] as String?) ?? '';
    final created = DateTime.tryParse(json['createdDateTime'] as String? ?? '');
    final modified = DateTime.tryParse(
      json['lastModifiedDateTime'] as String? ?? '',
    );
    return CalendarEvent(
      id: localId(sourceId, remoteId),
      title: json['isCancelled'] == true ? 'Canceled: $subject' : subject,
      description: description.isEmpty ? null : description,
      location: location == null || location.isEmpty ? null : location,
      startTime: start,
      endTime: end,
      isAllDay: isAllDay,
      category: _category(json['categories']),
      reminder: reminderOn
          ? (minutes == 0
                ? ReminderTime.atTime
                : ReminderTime.closestTo(Duration(minutes: minutes)))
          : ReminderTime.none,
      attendees: [
        for (final a in (json['attendees'] as List? ?? const []))
          if (((a as Map)['emailAddress'] as Map?)?['address']
              case final String address)
            address,
      ],
      organizer: organizer,
      icalUid: json['iCalUId'] as String?,
      sourceId: sourceId,
      remoteId: remoteId,
      seriesMasterId: json['seriesMasterId'] as String?,
      etag: json['@odata.etag'] as String?,
      createdAt: created?.toLocal() ?? DateTime.now(),
      updatedAt: modified?.toLocal() ?? DateTime.now(),
    );
  }

  static const _weekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  static String _date10(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

  /// Graph's recurrence for a series starting at [start] (local time).
  static Map<String, dynamic>? recurrenceToGraph(
    CalendarEvent e,
    DateTime start,
    String timeZone,
  ) {
    final rule = e.recurrence;
    if (rule == null || rule == RecurrenceRule.none) return null;
    final weekday = _weekdays[start.weekday - 1];
    final pattern = switch (rule) {
      RecurrenceRule.daily => {'type': 'daily', 'interval': 1},
      RecurrenceRule.weekdays => {
        'type': 'weekly',
        'interval': 1,
        'daysOfWeek': _weekdays.sublist(0, 5),
        'firstDayOfWeek': 'sunday',
      },
      RecurrenceRule.weekly => {
        'type': 'weekly',
        'interval': 1,
        'daysOfWeek': [weekday],
        'firstDayOfWeek': 'sunday',
      },
      RecurrenceRule.biweekly => {
        'type': 'weekly',
        'interval': 2,
        'daysOfWeek': [weekday],
        'firstDayOfWeek': 'sunday',
      },
      RecurrenceRule.monthly => {
        'type': 'absoluteMonthly',
        'interval': 1,
        'dayOfMonth': start.day,
      },
      RecurrenceRule.yearly => {
        'type': 'absoluteYearly',
        'interval': 1,
        'dayOfMonth': start.day,
        'month': start.month,
      },
      RecurrenceRule.none => null,
    };
    final until = e.recurrenceUntil;
    final count = e.recurrenceCount;
    return {
      'pattern': pattern,
      'range': {
        'startDate': _date10(start),
        'recurrenceTimeZone': timeZone,
        if (until != null) ...{
          'type': 'endDate',
          'endDate': _date10(until),
        } else if (count != null) ...{
          'type': 'numbered',
          'numberOfOccurrences': count,
        } else
          'type': 'noEnd',
      },
    };
  }

  /// Graph's JSON for creating or updating [e]. [timeZone] is an IANA
  /// name; without one, times are sent in UTC.
  static Map<String, dynamic> eventToGraph(
    CalendarEvent e, {
    String? timeZone,
    bool withRecurrence = true,
  }) {
    final zone = timeZone ?? 'UTC';
    Map<String, String> at(DateTime t) => {
      'dateTime': _wall(timeZone == null ? t.toUtc() : t),
      'timeZone': zone,
    };
    Map<String, dynamic> start;
    Map<String, dynamic> end;
    if (e.isAllDay) {
      final first = _dateOnly(e.startTime);
      var last = _dateOnly(e.endTime);
      if (e.endTime.isAfter(e.startTime) &&
          e.endTime.hour == 0 &&
          e.endTime.minute == 0) {
        last = last.subtract(const Duration(days: 1));
      }
      if (last.isBefore(first)) last = first;
      // All-day events run from midnight to midnight in their zone.
      start = {'dateTime': _wall(first), 'timeZone': zone};
      end = {
        'dateTime': _wall(last.add(const Duration(days: 1))),
        'timeZone': zone,
      };
    } else {
      start = at(e.startTime);
      end = at(e.endTime);
    }
    final reminder = e.reminder;
    final recurrence = withRecurrence
        ? recurrenceToGraph(e, e.startTime, zone)
        : null;
    return {
      'subject': e.title,
      'body': {'contentType': 'text', 'content': e.description ?? ''},
      'location': {'displayName': e.location ?? ''},
      'start': start,
      'end': end,
      'isAllDay': e.isAllDay,
      'isReminderOn': reminder != null && reminder != ReminderTime.none,
      if (reminder != null && reminder != ReminderTime.none)
        'reminderMinutesBeforeStart': reminder.duration.inMinutes,
      'categories': [?_categoryNames[e.category]],
      'attendees': [
        for (final a in e.attendees)
          {
            'emailAddress': {'address': a},
            'type': 'required',
          },
      ],
      'recurrence': ?recurrence,
    };
  }

  // ─── Contacts ──────────────────────────────────────────────────────

  static ContactAddress? _address(Object? raw) {
    if (raw is! Map) return null;
    final address = ContactAddress(
      street: raw['street'] as String?,
      city: raw['city'] as String?,
      state: raw['state'] as String?,
      zipCode: raw['postalCode'] as String?,
      country: raw['countryOrRegion'] as String?,
    );
    return address.isEmpty ? null : address;
  }

  static String? _text(Object? raw) {
    final s = (raw as String?)?.trim();
    return s == null || s.isEmpty ? null : s;
  }

  /// A contact from Graph.
  static Contact contactFromGraph(Map<String, dynamic> json, String sourceId) {
    final remoteId = json['id'] as String;
    final emails = <ContactEmail>[];
    for (final e in (json['emailAddresses'] as List? ?? const [])) {
      final address = ((e as Map)['address'] as String?)?.trim();
      if (address == null || address.isEmpty) continue;
      emails.add(
        ContactEmail(
          label: emails.isEmpty ? 'Email' : 'Email ${emails.length + 1}',
          address: address,
        ),
      );
    }
    final phones = [
      if (_text(json['mobilePhone']) case final String n)
        ContactPhone(label: 'Mobile', number: n),
      for (final n
          in (json['businessPhones'] as List? ?? const []).cast<String>())
        if (n.trim().isNotEmpty) ContactPhone(label: 'Work', number: n.trim()),
      for (final n in (json['homePhones'] as List? ?? const []).cast<String>())
        if (n.trim().isNotEmpty) ContactPhone(label: 'Home', number: n.trim()),
    ];
    final created = DateTime.tryParse(json['createdDateTime'] as String? ?? '');
    final modified = DateTime.tryParse(
      json['lastModifiedDateTime'] as String? ?? '',
    );
    var first = _text(json['givenName']);
    var last = _text(json['surname']);
    final company = _text(json['companyName']);
    if (first == null && last == null && company == null) {
      // Only a display name: use it as the first name.
      first = _text(json['displayName']);
    }
    return Contact(
      id: localId(sourceId, remoteId),
      firstName: first,
      lastName: last,
      company: company,
      jobTitle: _text(json['jobTitle']),
      emails: emails,
      phones: phones,
      address:
          _address(json['businessAddress']) ??
          _address(json['homeAddress']) ??
          _address(json['otherAddress']),
      notes: _text(json['personalNotes']),
      sourceId: sourceId,
      remoteId: remoteId,
      etag: json['@odata.etag'] as String?,
      createdAt: created?.toLocal() ?? DateTime.now(),
      updatedAt: modified?.toLocal() ?? DateTime.now(),
    );
  }

  /// Graph's JSON for creating or updating [c]. Graph keeps at most three
  /// email addresses.
  static Map<String, dynamic> contactToGraph(Contact c) {
    List<String> numbers(bool Function(String label) match) => [
      for (final p in c.phones)
        if (match(p.label.toLowerCase())) p.number,
    ];
    final mobile = numbers((l) => l.contains('mobile') || l.contains('cell'));
    final home = numbers((l) => l.contains('home'));
    final work = [
      for (final p in c.phones)
        if (!mobile.contains(p.number) && !home.contains(p.number)) p.number,
    ];
    final address = c.address;
    return {
      'givenName': c.firstName ?? '',
      'surname': c.lastName ?? '',
      'displayName': c.displayName,
      'companyName': c.company ?? '',
      'jobTitle': c.jobTitle ?? '',
      'emailAddresses': [
        for (final e in c.emails.take(3))
          {'address': e.address, 'name': c.displayName},
      ],
      'mobilePhone': mobile.firstOrNull ?? '',
      'businessPhones': work,
      'homePhones': home,
      'businessAddress': {
        'street': address?.street ?? '',
        'city': address?.city ?? '',
        'state': address?.state ?? '',
        'postalCode': address?.zipCode ?? '',
        'countryOrRegion': address?.country ?? '',
      },
      'personalNotes': c.notes ?? '',
    };
  }
}
