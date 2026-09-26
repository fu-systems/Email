import 'dart:convert';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../models/calendar_event.dart';
import '../models/email_message.dart';

/// A participant's answer to a meeting invitation (an iTIP REPLY).
enum InviteResponse {
  accepted,
  tentative,
  declined;

  /// Human-readable label, e.g. for the reply subject ("Accepted: Lunch").
  String get label {
    switch (this) {
      case InviteResponse.accepted:
        return 'Accepted';
      case InviteResponse.tentative:
        return 'Tentative';
      case InviteResponse.declined:
        return 'Declined';
    }
  }

  /// The iCalendar `PARTSTAT` parameter value for this response.
  String get partStat {
    switch (this) {
      case InviteResponse.accepted:
        return 'ACCEPTED';
      case InviteResponse.tentative:
        return 'TENTATIVE';
      case InviteResponse.declined:
        return 'DECLINED';
    }
  }
}

/// Parses and generates iCalendar (RFC 5545) data.
///
/// All methods are static and pure; parsing never throws; malformed events
/// are skipped.
///
/// Time zone handling when parsing:
/// * UTC times (`...Z`) are converted to local time with [DateTime.toLocal].
/// * Floating times and times with a `TZID` parameter are taken as local
///   wall-clock time. `VTIMEZONE` definitions are ignored, so an invitation
///   created in a different time zone shows at its original wall-clock time.
///   The only exception is a `TZID` naming UTC (for example `UTC`,
///   `Etc/UTC` or `GMT`), which is treated like a `Z` suffix.
///
/// Recurrence rules are mapped to the closest [RecurrenceRule]; see
/// [parseEvents] for details.
class IcalService {
  IcalService._();

  // ─── Parsing ───────────────────────────────────────────────────────

  /// Parses every `VEVENT` in [icsText].
  ///
  /// Each event gets a [CalendarEvent.id] from [idGenerator] (default: a
  /// random UUID v4); the iCalendar `UID` becomes [CalendarEvent.icalUid].
  /// `CREATED` and `LAST-MODIFIED` set the timestamps, falling back to [now]
  /// (default: the current time).
  ///
  /// Property mapping:
  /// * `SUMMARY` → title, `DESCRIPTION`, `LOCATION` (text is unescaped).
  /// * `DTSTART` with `VALUE=DATE` → an all-day event starting at local
  ///   midnight and ending at 23:59 on its last day (the iCalendar `DTEND`
  ///   of an all-day event is exclusive).
  /// * `DTEND`, else `DURATION`, else a default length (one hour for timed
  ///   events, one day for all-day events). A `DTEND` before `DTSTART` is
  ///   replaced by the default length.
  /// * `ORGANIZER` / `ATTENDEE` → addresses with the `mailto:` prefix removed.
  /// * `EXDATE` (every line, comma-separated values) → excluded dates.
  /// * The first `VALARM` with a usable `TRIGGER` → the closest
  ///   [ReminderTime].
  /// * `RRULE` → [RecurrenceRule], `UNTIL` (last local day that can hold an
  ///   occurrence) and `COUNT`. Rules the model cannot express fall back to
  ///   the supported rule whose period in days is closest (for example
  ///   every 3 weeks → every 2 weeks, every 4 weeks → monthly,
  ///   `FREQ=HOURLY` → daily, `FREQ=MONTHLY;BYDAY=2TU` → monthly on the
  ///   start date; several `BYDAY` days per week count as an average
  ///   period). A daily result whose `BYDAY` holds only weekdays becomes
  ///   [RecurrenceRule.weekdays]. `RDATE` is ignored.
  ///
  /// Instances that override one occurrence of a series (`RECURRENCE-ID`)
  /// add their original date to the master's excluded dates when the master
  /// is in the same file. Unless they are cancelled, they are also returned
  /// as standalone, non-recurring events with the series' UID. Cancelled
  /// instances are never returned as events.
  ///
  /// `VTIMEZONE`, `VTODO`, `VJOURNAL` and `VFREEBUSY` blocks are ignored, as
  /// are `CATEGORIES`.
  static List<CalendarEvent> parseEvents(
    String icsText, {
    String Function()? idGenerator,
    DateTime? now,
  }) {
    try {
      final nextId = idGenerator ?? const Uuid().v4;
      final timestamp = now ?? DateTime.now();
      final components = <_Component>[];
      _collectEvents(_parseComponents(icsText), components);

      final events = <CalendarEvent>[];
      final masterIndexByUid = <String, int>{};
      final overrides = <_Component>[];

      for (final component in components) {
        if (component.first('RECURRENCE-ID') != null) {
          overrides.add(component);
          continue;
        }
        final event = _tryBuildEvent(component, nextId, timestamp);
        if (event == null) continue;
        final uid = event.icalUid;
        if (uid != null && event.isRecurring) {
          masterIndexByUid.putIfAbsent(uid, () => events.length);
        }
        events.add(event);
      }

      for (final component in overrides) {
        try {
          final uid = _text(component.first('UID'));
          final masterIndex = uid == null ? null : masterIndexByUid[uid];
          final recurrenceId =
              _parseDateProperty(component.first('RECURRENCE-ID'));
          if (masterIndex != null && recurrenceId != null) {
            final master = events[masterIndex];
            final day = _dateOnly(recurrenceId.value);
            if (!master.excludedDates.any((d) => _sameDay(d, day))) {
              events[masterIndex] = master
                  .copyWith(excludedDates: [...master.excludedDates, day]);
            }
          }
          final status = component.first('STATUS')?.value.trim().toUpperCase();
          if (status == 'CANCELLED') continue;
          final event = _tryBuildEvent(component, nextId, timestamp,
              ignoreRecurrence: true);
          if (event != null) events.add(event);
        } catch (_) {
          // Skip malformed overrides.
        }
      }
      return events;
    } catch (_) {
      return <CalendarEvent>[];
    }
  }

  /// The calendar's `METHOD` (for example `REQUEST`, `REPLY`, `CANCEL` or
  /// `PUBLISH`), upper-cased, or null when absent or unparseable.
  static String? parseMethod(String icsText) {
    try {
      String? search(List<_Component> components) {
        for (final c in components) {
          if (c.name == 'VCALENDAR') {
            final value = c.first('METHOD')?.value.trim().toUpperCase();
            if (value != null && value.isNotEmpty) return value;
          }
          final nested = search(c.children);
          if (nested != null) return nested;
        }
        return null;
      }

      return search(_parseComponents(icsText));
    } catch (_) {
      return null;
    }
  }

  // ─── Generation ────────────────────────────────────────────────────

  /// Serializes [events] as a complete `VCALENDAR` object.
  ///
  /// Lines end with CRLF and are folded at 75 octets without splitting
  /// UTF-8 sequences. Timed events are written in UTC; all-day events use
  /// `VALUE=DATE` with an exclusive `DTEND`. An empty [method] omits the
  /// `METHOD` property. [now] sets `DTSTAMP` (default: the current time).
  ///
  /// Recurrences are written so that other clients expand them the way
  /// [CalendarEvent.occurrencesBetween] does: monthly series starting on the
  /// 29th–31st and yearly series starting on 29 February use `BYMONTHDAY`
  /// (with `BYSETPOS`) to clamp to the end of short months, and a weekday
  /// series that starts on a weekend is written starting on its first
  /// weekday occurrence.
  ///
  /// Because no `VTIMEZONE` is written, other clients expand recurring
  /// timed events in UTC, so their local time may shift by an hour across
  /// daylight-saving changes.
  static String generateCalendar(
    List<CalendarEvent> events, {
    String method = 'PUBLISH',
    String prodId = '-//Look In//EN',
    DateTime? now,
  }) {
    final upperMethod = method.trim().toUpperCase();
    final stamp = _formatUtc(now ?? DateTime.now());
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'PRODID:${_singleLine(prodId)}',
      'VERSION:2.0',
      'CALSCALE:GREGORIAN',
      if (upperMethod.isNotEmpty) 'METHOD:${_singleLine(upperMethod)}',
    ];
    for (final event in events) {
      _writeEvent(lines, event, method: upperMethod, stamp: stamp);
    }
    lines.add('END:VCALENDAR');
    return _joinLines(lines);
  }

  /// Builds a `METHOD:REPLY` calendar answering the invitation [event] on
  /// behalf of [attendeeEmail].
  ///
  /// The reply carries the event's UID, times, summary and organizer plus a
  /// single `ATTENDEE` with `PARTSTAT` set from [response].
  static String generateReply({
    required CalendarEvent event,
    required String attendeeEmail,
    required InviteResponse response,
    String? attendeeName,
    String prodId = '-//Look In//EN',
    DateTime? now,
  }) {
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'PRODID:${_singleLine(prodId)}',
      'VERSION:2.0',
      'CALSCALE:GREGORIAN',
      'METHOD:REPLY',
      'BEGIN:VEVENT',
      'UID:${_escapeText(event.uid)}',
      'DTSTAMP:${_formatUtc(now ?? DateTime.now())}',
      ..._timeLines(event),
      'SUMMARY:${_escapeText(event.title)}',
      if (_nonEmpty(event.organizer) != null)
        'ORGANIZER:mailto:${_cleanAddress(event.organizer!)}',
      _attendeeLine(
        attendeeEmail,
        name: attendeeName,
        params: ['PARTSTAT=${response.partStat}'],
      ),
      'END:VEVENT',
      'END:VCALENDAR',
    ];
    return _joinLines(lines);
  }

  // ─── Content lines and components ──────────────────────────────────

  static List<String> _unfold(String text) {
    var t = text;
    if (t.startsWith('\uFEFF')) t = t.substring(1);
    t = t.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    t = t.replaceAll(RegExp(r'\n[ \t]'), '');
    return t.split('\n');
  }

  /// Parses `NAME;PARAM=a,"b";OTHER=c:value`; returns null when malformed.
  static _Property? _parseLine(String line) {
    final n = line.length;
    var i = 0;
    while (i < n && line[i] != ';' && line[i] != ':') {
      i++;
    }
    if (i >= n) return null;
    final name = line.substring(0, i).trim().toUpperCase();
    if (name.isEmpty) return null;
    final params = <String, List<String>>{};
    while (i < n && line[i] == ';') {
      i++;
      final start = i;
      while (i < n && line[i] != '=' && line[i] != ';' && line[i] != ':') {
        i++;
      }
      final paramName = line.substring(start, i).trim().toUpperCase();
      final values = <String>[];
      if (i < n && line[i] == '=') {
        i++;
        while (true) {
          if (i < n && line[i] == '"') {
            final close = line.indexOf('"', i + 1);
            if (close < 0) return null;
            values.add(line.substring(i + 1, close));
            i = close + 1;
            while (
                i < n && line[i] != ',' && line[i] != ';' && line[i] != ':') {
              i++;
            }
          } else {
            final start = i;
            while (
                i < n && line[i] != ',' && line[i] != ';' && line[i] != ':') {
              i++;
            }
            values.add(line.substring(start, i));
          }
          if (i < n && line[i] == ',') {
            i++;
            continue;
          }
          break;
        }
      }
      if (paramName.isNotEmpty) {
        params.putIfAbsent(paramName, () => <String>[]).addAll(values);
      }
    }
    if (i >= n || line[i] != ':') return null;
    return _Property(name, params, line.substring(i + 1));
  }

  static List<_Component> _parseComponents(String text) {
    final roots = <_Component>[];
    final stack = <_Component>[];
    for (final raw in _unfold(text)) {
      if (raw.trim().isEmpty) continue;
      final prop = _parseLine(raw);
      if (prop == null) continue;
      if (prop.name == 'BEGIN') {
        final component = _Component(prop.value.trim().toUpperCase());
        (stack.isEmpty ? roots : stack.last.children).add(component);
        stack.add(component);
      } else if (prop.name == 'END') {
        final name = prop.value.trim().toUpperCase();
        final index = stack.lastIndexWhere((c) => c.name == name);
        if (index >= 0) stack.removeRange(index, stack.length);
      } else if (stack.isNotEmpty) {
        stack.last.properties.add(prop);
      }
    }
    return roots;
  }

  static const _ignoredComponents = {
    'VTIMEZONE',
    'VTODO',
    'VJOURNAL',
    'VFREEBUSY',
    'VALARM',
  };

  static void _collectEvents(
      List<_Component> components, List<_Component> out) {
    for (final c in components) {
      if (_ignoredComponents.contains(c.name)) continue;
      if (c.name == 'VEVENT') out.add(c);
      _collectEvents(c.children, out);
    }
  }

  // ─── Event construction ────────────────────────────────────────────

  static CalendarEvent? _tryBuildEvent(
    _Component c,
    String Function() nextId,
    DateTime now, {
    bool ignoreRecurrence = false,
  }) {
    try {
      return _buildEvent(c, nextId, now, ignoreRecurrence: ignoreRecurrence);
    } catch (_) {
      return null;
    }
  }

  static CalendarEvent? _buildEvent(
    _Component c,
    String Function() nextId,
    DateTime now, {
    required bool ignoreRecurrence,
  }) {
    final start = _parseDateProperty(c.first('DTSTART'));
    if (start == null) return null;
    final isAllDay = start.isDate;

    final DateTime startTime;
    final DateTime endTime;
    if (isAllDay) {
      startTime = _dateOnly(start.value);
      DateTime? endExclusive;
      final dtEnd = c.first('DTEND');
      final durationProp = c.first('DURATION');
      if (dtEnd != null) {
        final end = _parseDateProperty(dtEnd);
        if (end != null) endExclusive = _dateOnly(end.value);
      } else if (durationProp != null) {
        final d = _IcalDuration.parse(durationProp.value);
        if (d != null && !d.negative) {
          var days = d.nominalDays;
          final exact = d.exactPart;
          if (exact > Duration.zero) {
            days += (exact.inSeconds / Duration.secondsPerDay).ceil();
          }
          endExclusive = _addDays(startTime, days);
        }
      }
      if (endExclusive == null || !endExclusive.isAfter(startTime)) {
        endExclusive = _addDays(startTime, 1);
      }
      endTime = DateTime(
          endExclusive.year, endExclusive.month, endExclusive.day - 1, 23, 59);
    } else {
      startTime = start.value;
      DateTime? end;
      final dtEnd = c.first('DTEND');
      final durationProp = c.first('DURATION');
      if (dtEnd != null) {
        final parsed = _parseDateProperty(dtEnd);
        if (parsed != null) {
          end = parsed.isDate ? _dateOnly(parsed.value) : parsed.value;
        }
      } else if (durationProp != null) {
        final d = _IcalDuration.parse(durationProp.value);
        if (d != null && !d.negative) end = d.addTo(startTime);
      }
      if (end == null || end.isBefore(startTime)) {
        end = startTime.add(const Duration(hours: 1));
      }
      endTime = end;
    }

    RecurrenceRule? recurrence;
    DateTime? until;
    int? count;
    final rrule = ignoreRecurrence ? null : c.first('RRULE');
    if (rrule != null) {
      final parsed = _parseRRule(rrule.value, startTime, isAllDay);
      if (parsed != null) {
        recurrence = parsed.rule;
        until = parsed.until;
        count = parsed.count;
      }
    }

    final excluded = <DateTime>[];
    if (recurrence != null) {
      for (final prop in c.all('EXDATE')) {
        final tzid = prop.param('TZID');
        final forceDate = prop.param('VALUE')?.toUpperCase() == 'DATE';
        for (final part in prop.value.split(',')) {
          if (part.trim().isEmpty) continue;
          final parsed =
              _parseDateValue(part, tzid: tzid, forceDate: forceDate);
          if (parsed == null) continue;
          final day = _dateOnly(parsed.value);
          if (!excluded.any((d) => _sameDay(d, day))) excluded.add(day);
        }
      }
    }

    final attendees = <String>[];
    for (final prop in c.all('ATTENDEE')) {
      final address = _stripMailto(prop.value);
      if (address.isEmpty) continue;
      if (!attendees.any((a) => a.toLowerCase() == address.toLowerCase())) {
        attendees.add(address);
      }
    }
    final organizerProp = c.first('ORGANIZER');
    final organizer = organizerProp == null
        ? null
        : _nonEmpty(_stripMailto(organizerProp.value));

    ReminderTime? reminder;
    for (final alarm in c.children.where((ch) => ch.name == 'VALARM')) {
      reminder = _reminderFor(alarm, startTime, endTime);
      if (reminder != null) break;
    }

    final created = _parseDateProperty(c.first('CREATED'));
    final modified = _parseDateProperty(c.first('LAST-MODIFIED'));

    return CalendarEvent(
      id: nextId(),
      title: _text(c.first('SUMMARY')) ?? '',
      description: _text(c.first('DESCRIPTION')),
      location: _text(c.first('LOCATION')),
      startTime: startTime,
      endTime: endTime,
      isAllDay: isAllDay,
      reminder: reminder,
      recurrence: recurrence,
      recurrenceUntil: until,
      recurrenceCount: count,
      excludedDates: excluded,
      attendees: attendees,
      organizer: organizer,
      icalUid: _text(c.first('UID')),
      createdAt: created?.value ?? now,
      updatedAt: modified?.value ?? now,
    );
  }

  static ReminderTime? _reminderFor(
      _Component alarm, DateTime start, DateTime end) {
    final action = alarm.first('ACTION')?.value.trim().toUpperCase();
    if (action == 'NONE') return null;
    final trigger = alarm.first('TRIGGER');
    if (trigger == null) return null;
    final valueType = trigger.param('VALUE')?.toUpperCase();
    if (valueType == 'DATE-TIME' ||
        RegExp(r'^\d{8}T', caseSensitive: false)
            .hasMatch(trigger.value.trim())) {
      final at = _parseDateValue(trigger.value, tzid: trigger.param('TZID'));
      if (at == null) return null;
      return ReminderTime.closestTo(start.difference(at.value));
    }
    final d = _IcalDuration.parse(trigger.value);
    if (d == null) return null;
    final offset = d.signedExact;
    final related = trigger.param('RELATED')?.toUpperCase();
    final alarmTime = related == 'END' ? end.add(offset) : start.add(offset);
    return ReminderTime.closestTo(start.difference(alarmTime));
  }

  // ─── Recurrence ────────────────────────────────────────────────────

  static const _weekdayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  static _ParsedRRule? _parseRRule(
      String value, DateTime start, bool isAllDay) {
    final parts = <String, String>{};
    for (final part in value.split(';')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      parts[part.substring(0, eq).trim().toUpperCase()] =
          part.substring(eq + 1).trim();
    }
    final freq = parts['FREQ']?.toUpperCase();
    if (freq == null) return null;
    var interval = int.tryParse(parts['INTERVAL'] ?? '') ?? 1;
    if (interval < 1) interval = 1;
    final byDay = <String>{};
    for (final raw in (parts['BYDAY'] ?? '').split(',')) {
      final day = raw.trim().toUpperCase();
      if (day.length < 2) continue;
      final code = day.substring(day.length - 2);
      if (_weekdayCodes.contains(code)) byDay.add(code);
    }
    final onlyWeekdays =
        byDay.isNotEmpty && !byDay.contains('SA') && !byDay.contains('SU');
    final allWeekdays = onlyWeekdays && byDay.length == 5;

    RecurrenceRule? rule;
    double period;
    switch (freq) {
      case 'SECONDLY':
        period = interval / Duration.secondsPerDay;
      case 'MINUTELY':
        period = interval / Duration.minutesPerDay;
      case 'HOURLY':
        period = interval / Duration.hoursPerDay;
      case 'DAILY':
        if (interval == 1 && allWeekdays) rule = RecurrenceRule.weekdays;
        if (interval == 1 && byDay.isEmpty) rule = RecurrenceRule.daily;
        period = byDay.isEmpty
            ? interval.toDouble()
            : math.max(interval.toDouble(), 7 / byDay.length);
      case 'WEEKLY':
        if (interval == 1 && allWeekdays) rule = RecurrenceRule.weekdays;
        if (byDay.length <= 1) {
          if (interval == 1) rule = RecurrenceRule.weekly;
          if (interval == 2) rule = RecurrenceRule.biweekly;
        }
        period = 7 * interval / math.max(1, byDay.length);
      case 'MONTHLY':
        if (interval == 1) rule = RecurrenceRule.monthly;
        period = 30.436875 * interval;
      case 'YEARLY':
        rule = RecurrenceRule.yearly;
        period = 365.2425 * interval;
      default:
        return null;
    }
    rule ??= _closestRule(period, onlyWeekdays: onlyWeekdays);

    DateTime? until;
    final untilRaw = parts['UNTIL'];
    if (untilRaw != null && untilRaw.isNotEmpty) {
      until = _parseUntil(untilRaw, start, isAllDay);
    }
    int? count;
    final countValue = int.tryParse(parts['COUNT'] ?? '');
    if (countValue != null && countValue > 0) count = countValue;
    return _ParsedRRule(rule, until, count);
  }

  static RecurrenceRule _closestRule(double periodDays,
      {required bool onlyWeekdays}) {
    const candidates = {
      RecurrenceRule.daily: 1.0,
      RecurrenceRule.weekly: 7.0,
      RecurrenceRule.biweekly: 14.0,
      RecurrenceRule.monthly: 30.436875,
      RecurrenceRule.yearly: 365.2425,
    };
    var best = RecurrenceRule.daily;
    if (periodDays > 0) {
      var bestDistance = double.infinity;
      candidates.forEach((rule, days) {
        final distance = (periodDays - days).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          best = rule;
        }
      });
    }
    if (best == RecurrenceRule.daily && onlyWeekdays) {
      return RecurrenceRule.weekdays;
    }
    return best;
  }

  /// The last local day on which an occurrence may start, given UNTIL.
  static DateTime? _parseUntil(String raw, DateTime start, bool isAllDay) {
    final value = raw.trim();
    if (isAllDay) {
      // All-day series are date based: use the date as written.
      final m = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(value);
      if (m == null) return null;
      final y = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final d = int.parse(m.group(3)!);
      if (!_validDate(y, mo, d)) return null;
      return DateTime(y, mo, d);
    }
    final parsed = _parseDateValue(value);
    if (parsed == null) return null;
    if (parsed.isDate) return _dateOnly(parsed.value);
    final local = parsed.value;
    final untilSeconds = local.hour * 3600 + local.minute * 60 + local.second;
    final startSeconds = start.hour * 3600 + start.minute * 60 + start.second;
    // An occurrence on the UNTIL day would start after UNTIL itself.
    if (untilSeconds < startSeconds) {
      return DateTime(local.year, local.month, local.day - 1);
    }
    return _dateOnly(local);
  }

  // ─── Values ────────────────────────────────────────────────────────

  static _IcalDateTime? _parseDateProperty(_Property? prop) {
    if (prop == null) return null;
    return _parseDateValue(
      prop.value,
      tzid: prop.param('TZID'),
      forceDate: prop.param('VALUE')?.toUpperCase() == 'DATE',
    );
  }

  static final _dateRe = RegExp(r'^(\d{4})(\d{2})(\d{2})$');
  static final _dateTimeRe = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?$',
      caseSensitive: false);

  static _IcalDateTime? _parseDateValue(String raw,
      {String? tzid, bool forceDate = false}) {
    final v = raw.trim().replaceAll(RegExp(r'[-:]'), '');
    final dateMatch = _dateRe.firstMatch(v);
    if (dateMatch != null) {
      final y = int.parse(dateMatch.group(1)!);
      final mo = int.parse(dateMatch.group(2)!);
      final d = int.parse(dateMatch.group(3)!);
      if (!_validDate(y, mo, d)) return null;
      return _IcalDateTime(DateTime(y, mo, d), isDate: true);
    }
    final m = _dateTimeRe.firstMatch(v);
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final h = int.parse(m.group(4)!);
    final mi = int.parse(m.group(5)!);
    var s = m.group(6) == null ? 0 : int.parse(m.group(6)!);
    if (!_validDate(y, mo, d) || h > 23 || mi > 59 || s > 60) return null;
    if (s == 60) s = 59; // leap second
    if (forceDate) return _IcalDateTime(DateTime(y, mo, d), isDate: true);
    final isUtc = m.group(7) != null || _isUtcZone(tzid);
    final value = isUtc
        ? DateTime.utc(y, mo, d, h, mi, s).toLocal()
        : DateTime(y, mo, d, h, mi, s);
    return _IcalDateTime(value, isDate: false);
  }

  static bool _isUtcZone(String? tzid) {
    if (tzid == null) return false;
    final t = tzid.trim().toUpperCase();
    const names = {
      'UTC',
      'UCT',
      'GMT',
      'Z',
      'ZULU',
      'ETC/UTC',
      'ETC/UCT',
      'ETC/GMT',
      'ETC/ZULU',
      'COORDINATED UNIVERSAL TIME',
    };
    return names.contains(t) ||
        t.endsWith('/ETC/UTC') ||
        t.endsWith('/ETC/GMT');
  }

  static bool _validDate(int y, int mo, int d) {
    if (y < 1 || mo < 1 || mo > 12 || d < 1) return false;
    return d <= DateTime(y, mo + 1, 0).day;
  }

  static String? _text(_Property? prop) {
    if (prop == null) return null;
    return _nonEmpty(_unescapeText(prop.value).trim());
  }

  static String _unescapeText(String s) {
    if (!s.contains(r'\')) return s;
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == r'\' && i + 1 < s.length) {
        final next = s[i + 1];
        b.write(next == 'n' || next == 'N' ? '\n' : next);
        i++;
      } else {
        b.write(ch);
      }
    }
    return b.toString();
  }

  static String _stripMailto(String value) {
    var v = value.trim();
    if (v.toLowerCase().startsWith('mailto:')) v = v.substring(7).trim();
    return v;
  }

  static String? _nonEmpty(String? s) =>
      s == null || s.trim().isEmpty ? null : s;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ─── Writing ───────────────────────────────────────────────────────

  static void _writeEvent(
    List<String> lines,
    CalendarEvent e, {
    required String method,
    required String stamp,
  }) {
    lines
      ..add('BEGIN:VEVENT')
      ..add('UID:${_escapeText(e.uid)}')
      ..add('DTSTAMP:$stamp')
      ..add('CREATED:${_formatUtc(e.createdAt)}')
      ..add('LAST-MODIFIED:${_formatUtc(e.updatedAt)}')
      ..addAll(_timeLines(e))
      ..add('SUMMARY:${_escapeText(e.title)}');
    final description = _nonEmpty(e.description);
    if (description != null) {
      lines.add('DESCRIPTION:${_escapeText(description)}');
    }
    final location = _nonEmpty(e.location);
    if (location != null) lines.add('LOCATION:${_escapeText(location)}');
    final organizer = _nonEmpty(e.organizer);
    if (organizer != null) {
      lines.add('ORGANIZER:mailto:${_cleanAddress(organizer)}');
    }
    final isRequest = method == 'REQUEST';
    for (final attendee in e.attendees) {
      if (attendee.trim().isEmpty) continue;
      lines.add(_attendeeLine(
        attendee,
        params: isRequest
            ? ['ROLE=REQ-PARTICIPANT', 'PARTSTAT=NEEDS-ACTION', 'RSVP=TRUE']
            : const [],
      ));
    }
    final rrule = _rrule(e);
    if (rrule != null) {
      lines.add(rrule);
      final exdate = _exdate(e);
      if (exdate != null) lines.add(exdate);
    }
    if (method == 'CANCEL') lines.add('STATUS:CANCELLED');
    final reminder = e.reminder;
    if (reminder != null && reminder != ReminderTime.none) {
      lines
        ..add('BEGIN:VALARM')
        ..add('ACTION:DISPLAY')
        ..add(
            'DESCRIPTION:${_escapeText(e.title.isEmpty ? 'Reminder' : e.title)}')
        ..add('TRIGGER:${_formatTrigger(reminder.duration)}')
        ..add('END:VALARM');
    }
    lines.add('END:VEVENT');
  }

  /// Start of the first occurrence (weekday series never start on weekends).
  static DateTime _seriesStart(CalendarEvent e) {
    final s = e.startTime;
    if (e.recurrence == RecurrenceRule.weekdays &&
        s.weekday > DateTime.friday) {
      final shift = 8 - s.weekday;
      return DateTime(s.year, s.month, s.day + shift, s.hour, s.minute,
          s.second, s.millisecond);
    }
    return s;
  }

  static List<String> _timeLines(CalendarEvent e) {
    final start = _seriesStart(e);
    if (e.isAllDay) {
      final firstDay = _dateOnly(start);
      final shift = _daysBetween(e.startTime, start);
      var lastDay = _dateOnly(e.endTime);
      if (e.endTime.isAfter(e.startTime) &&
          e.endTime.hour == 0 &&
          e.endTime.minute == 0 &&
          e.endTime.second == 0) {
        // An end at midnight means the previous day was the last one.
        lastDay = _addDays(lastDay, -1);
      }
      lastDay = _addDays(lastDay, shift);
      if (lastDay.isBefore(firstDay)) lastDay = firstDay;
      return [
        'DTSTART;VALUE=DATE:${_formatDate(firstDay)}',
        'DTEND;VALUE=DATE:${_formatDate(_addDays(lastDay, 1))}',
      ];
    }
    final length = e.endTime.isBefore(e.startTime) ? Duration.zero : e.duration;
    return [
      'DTSTART:${_formatUtc(start)}',
      'DTEND:${_formatUtc(start.add(length))}',
    ];
  }

  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays;

  static String? _rrule(CalendarEvent e) {
    if (!e.isRecurring) return null;
    final s = e.startTime;
    final parts = <String>[];
    switch (e.recurrence!) {
      case RecurrenceRule.none:
        return null;
      case RecurrenceRule.daily:
        parts.add('FREQ=DAILY');
      case RecurrenceRule.weekdays:
        parts.addAll(['FREQ=WEEKLY', 'BYDAY=MO,TU,WE,TH,FR']);
      case RecurrenceRule.weekly:
        parts.add('FREQ=WEEKLY');
      case RecurrenceRule.biweekly:
        parts.addAll(['FREQ=WEEKLY', 'INTERVAL=2']);
      case RecurrenceRule.monthly:
        parts.add('FREQ=MONTHLY');
        if (s.day == 31) {
          parts.add('BYMONTHDAY=-1');
        } else if (s.day > 28) {
          final days = [for (var d = 28; d <= s.day; d++) d];
          parts.addAll(['BYMONTHDAY=${days.join(',')}', 'BYSETPOS=-1']);
        }
      case RecurrenceRule.yearly:
        parts.add('FREQ=YEARLY');
        if (s.month == 2 && s.day == 29) {
          parts.addAll(['BYMONTH=2', 'BYMONTHDAY=-1']);
        }
    }
    final until = e.recurrenceUntil;
    if (until != null) {
      parts.add(e.isAllDay
          ? 'UNTIL=${_formatDate(until)}'
          : 'UNTIL=${_formatUtc(DateTime(until.year, until.month, until.day, 23, 59, 59))}');
    }
    final count = e.recurrenceCount;
    if (count != null && count > 0) parts.add('COUNT=$count');
    return 'RRULE:${parts.join(';')}';
  }

  static String? _exdate(CalendarEvent e) {
    if (e.excludedDates.isEmpty) return null;
    final s = e.startTime;
    if (e.isAllDay) {
      return 'EXDATE;VALUE=DATE:${e.excludedDates.map(_formatDate).join(',')}';
    }
    final values = e.excludedDates.map((d) => _formatUtc(
        DateTime(d.year, d.month, d.day, s.hour, s.minute, s.second)));
    return 'EXDATE:${values.join(',')}';
  }

  static String _attendeeLine(
    String attendee, {
    String? name,
    List<String> params = const [],
  }) {
    final parsed = EmailAddress.parse(attendee);
    final cn = _nonEmpty(name) ?? _nonEmpty(parsed.displayName);
    final allParams = [
      if (cn != null) 'CN=${_paramValue(cn)}',
      ...params,
    ];
    final prefix = allParams.map((p) => ';$p').join();
    return 'ATTENDEE$prefix:mailto:${_cleanAddress(parsed.address)}';
  }

  static String _cleanAddress(String address) {
    final parsed = EmailAddress.parse(_stripMailto(address));
    return parsed.address.replaceAll(RegExp(r'[\s\x00-\x1f]'), '');
  }

  static String _paramValue(String value) {
    final v =
        value.replaceAll('"', "'").replaceAll(RegExp(r'[\x00-\x1f]'), ' ');
    return RegExp('[:;,]').hasMatch(v) ? '"$v"' : v;
  }

  static String _escapeText(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\r', r'\n')
      .replaceAll('\n', r'\n');

  static String _singleLine(String value) =>
      value.replaceAll(RegExp(r'[\r\n]+'), ' ');

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';

  static String _formatUtc(DateTime dt) {
    final u = dt.toUtc();
    return '${_formatDate(u)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
  }

  static String _formatTrigger(Duration before) {
    if (before == Duration.zero) return 'PT0S';
    return '-${_formatDuration(before)}';
  }

  static String _formatDuration(Duration d) {
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    final b = StringBuffer('P');
    if (days > 0) b.write('${days}D');
    if (hours > 0 || minutes > 0 || seconds > 0) {
      b.write('T');
      if (hours > 0) b.write('${hours}H');
      if (minutes > 0) b.write('${minutes}M');
      if (seconds > 0) b.write('${seconds}S');
    }
    return b.length == 1 ? 'PT0S' : b.toString();
  }

  static String _joinLines(List<String> lines) =>
      '${lines.map(_fold).join('\r\n')}\r\n';

  /// Folds [line] so no physical line exceeds 75 octets of UTF-8, never
  /// splitting a multi-byte character.
  static String _fold(String line) {
    if (utf8.encode(line).length <= 75) return line;
    final out = StringBuffer();
    var used = 0;
    for (final rune in line.runes) {
      final size = rune < 0x80
          ? 1
          : rune < 0x800
              ? 2
              : rune < 0x10000
                  ? 3
                  : 4;
      if (used + size > 75) {
        out.write('\r\n ');
        used = 1;
      }
      out.writeCharCode(rune);
      used += size;
    }
    return out.toString();
  }
}

class _Property {
  final String name;
  final Map<String, List<String>> params;
  final String value;

  const _Property(this.name, this.params, this.value);

  String? param(String name) {
    final values = params[name];
    return values == null || values.isEmpty ? null : values.first;
  }
}

class _Component {
  final String name;
  final List<_Property> properties = [];
  final List<_Component> children = [];

  _Component(this.name);

  _Property? first(String name) {
    for (final p in properties) {
      if (p.name == name) return p;
    }
    return null;
  }

  Iterable<_Property> all(String name) =>
      properties.where((p) => p.name == name);
}

class _IcalDateTime {
  final DateTime value;
  final bool isDate;

  const _IcalDateTime(this.value, {required this.isDate});
}

class _ParsedRRule {
  final RecurrenceRule rule;
  final DateTime? until;
  final int? count;

  const _ParsedRRule(this.rule, this.until, this.count);
}

/// An RFC 5545 DURATION value such as `-PT15M`, `P1D` or `P1W`.
class _IcalDuration {
  final bool negative;
  final int weeks;
  final int days;
  final int hours;
  final int minutes;
  final int seconds;

  const _IcalDuration({
    required this.negative,
    required this.weeks,
    required this.days,
    required this.hours,
    required this.minutes,
    required this.seconds,
  });

  static final _re = RegExp(
      r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
      caseSensitive: false);

  static _IcalDuration? parse(String raw) {
    final m = _re.firstMatch(raw.trim());
    if (m == null) return null;
    if (m.group(2) == null &&
        m.group(3) == null &&
        m.group(4) == null &&
        m.group(5) == null &&
        m.group(6) == null) {
      return null;
    }
    int value(int group) =>
        m.group(group) == null ? 0 : int.parse(m.group(group)!);
    return _IcalDuration(
      negative: m.group(1) == '-',
      weeks: value(2),
      days: value(3),
      hours: value(4),
      minutes: value(5),
      seconds: value(6),
    );
  }

  /// Calendar days (weeks and days), which follow local wall-clock time.
  int get nominalDays => weeks * 7 + days;

  /// The hours/minutes/seconds part, which is an exact duration.
  Duration get exactPart =>
      Duration(hours: hours, minutes: minutes, seconds: seconds);

  /// The whole value as an exact, signed duration (a day counts 24 hours).
  Duration get signedExact {
    final d = Duration(days: nominalDays) + exactPart;
    return negative ? -d : d;
  }

  /// [start] moved forward by this (non-negative) duration.
  DateTime addTo(DateTime start) => DateTime(
        start.year,
        start.month,
        start.day + nominalDays,
        start.hour,
        start.minute,
        start.second,
        start.millisecond,
      ).add(exactPart);
}
