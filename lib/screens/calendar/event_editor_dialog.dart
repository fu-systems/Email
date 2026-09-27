import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/calendar_event.dart';
import '../../models/email_message.dart';
import '../../providers/calendar_provider.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';
import 'appointment_form_fields.dart';
import 'calendar_actions.dart';
import 'calendar_layout.dart';

/// Splits an attendees field (addresses separated by `;` or `,`, optionally
/// as `Name <address>`) into [addresses], de-duplicated, and the entries
/// that do not look like e-mail addresses ([invalid]). Validation is loose:
/// `something@something` without spaces is accepted.
({List<String> addresses, List<String> invalid}) parseAttendeeList(
    String text) {
  final addresses = <String>[];
  final invalid = <String>[];
  final seen = <String>{};
  for (final a in EmailAddress.parseList(text)) {
    if (!RegExp(r'^[^@\s<>]+@[^@\s<>]+$').hasMatch(a.address)) {
      invalid.add(a.toString());
    } else if (seen.add(a.address.toLowerCase())) {
      addresses.add(a.toString());
    }
  }
  return (addresses: addresses, invalid: invalid);
}

/// The appointment form (Outlook's Appointment window) as a dialog.
///
/// With neither [event] nor [occurrence] it creates a new appointment
/// starting at [initialStart] (default: the next hour on the selected date)
/// and lasting 30 minutes, or an all-day event when [initialAllDay] is set.
///
/// When opened for an [occurrence] of a recurring series the form shows
/// that occurrence's times, but saving applies every change to the entire
/// series: moving the occurrence moves all occurrences by the same amount.
class EventEditorDialog extends StatefulWidget {
  /// The appointment to edit (defaults to [occurrence]'s event).
  final CalendarEvent? event;

  /// The occurrence that was opened, for recurring appointments.
  final EventOccurrence? occurrence;

  /// Start of a new appointment.
  final DateTime? initialStart;

  /// Whether a new appointment starts as an all-day event.
  final bool initialAllDay;

  const EventEditorDialog({
    super.key,
    this.event,
    this.occurrence,
    this.initialStart,
    this.initialAllDay = false,
  });

  /// Keys of the form fields (for tests and automation).
  static const subjectFieldKey = Key('eventEditor.subject');
  static const locationFieldKey = Key('eventEditor.location');
  static const attendeesFieldKey = Key('eventEditor.attendees');
  static const notesFieldKey = Key('eventEditor.notes');
  static const allDayCheckboxKey = Key('eventEditor.allDay');
  static const repeatFieldKey = Key('eventEditor.repeat');
  static const calendarFieldKey = Key('eventEditor.calendar');

  @override
  State<EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends State<EventEditorDialog> {
  late final TextEditingController _subject;
  late final TextEditingController _location;
  late final TextEditingController _attendees;
  late final TextEditingController _notes;
  late final TextEditingController _count;

  /// Start and end as shown. For all-day events only the dates count; the
  /// times are kept so that unticking "All day event" restores them.
  late DateTime _start;
  late DateTime _end;
  late bool _allDay;
  late ReminderTime _reminder;
  late EventCategory _category;
  late RecurrenceRule _recurrence;
  late SeriesEnd _seriesEnd;
  late DateTime _until;
  String? _attendeeError;
  bool _hadAttendees = false;

  /// Calendar of a new appointment: `local` or a Microsoft calendar.
  late String _calendar;

  CalendarEvent? get _original => widget.event ?? widget.occurrence?.event;
  bool get _isEditing => _original != null;
  bool get _isSeries => _original?.isRecurring ?? false;
  bool get _isRecurring => _recurrence != RecurrenceRule.none;

  /// An occurrence of a recurring meeting from a Microsoft calendar.
  bool get _isServerOccurrence => _original?.seriesMasterId != null;

  @override
  void initState() {
    super.initState();
    final e = _original;
    _subject = TextEditingController(text: e?.title ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _attendees = TextEditingController(text: e?.attendees.join('; ') ?? '')
      ..addListener(_onAttendeesChanged);
    _hadAttendees = _attendees.text.trim().isNotEmpty;
    _notes = TextEditingController(text: e?.description ?? '');
    _count = TextEditingController(text: '${e?.recurrenceCount ?? 10}')
      ..addListener(() => setState(() {}));

    if (e != null) {
      final shown = widget.occurrence ??
          EventOccurrence(event: e, start: e.startTime, end: e.endTime);
      _allDay = e.isAllDay;
      if (_allDay) {
        final first = shown.start;
        final last = lastDayOf(shown);
        _start = DateTime(first.year, first.month, first.day, 8);
        _end = DateTime(last.year, last.month, last.day, 8, 30);
      } else {
        _start = shown.start;
        _end = shown.end.isBefore(shown.start) ? shown.start : shown.end;
      }
      _reminder = e.reminder ?? ReminderTime.none;
      _category = e.category;
      _recurrence = e.recurrence ?? RecurrenceRule.none;
      _seriesEnd = e.recurrenceCount != null
          ? SeriesEnd.afterCount
          : e.recurrenceUntil != null
              ? SeriesEnd.onDate
              : SeriesEnd.never;
    } else {
      final defaults = context.read<CalendarProvider>().createDefaultEvent();
      final given = widget.initialStart ?? defaults.startTime;
      // Appointments are edited with minute precision.
      var start = DateTime(
          given.year, given.month, given.day, given.hour, given.minute);
      _allDay = widget.initialAllDay;
      if (_allDay && start.hour == 0 && start.minute == 0) {
        start = DateTime(start.year, start.month, start.day, 8);
      }
      _start = start;
      _end = start.add(const Duration(minutes: 30));
      _reminder = defaults.reminder ?? ReminderTime.fifteenMinutes;
      _category = defaults.category;
      _recurrence = RecurrenceRule.none;
      _seriesEnd = SeriesEnd.never;
    }
    _until = e?.recurrenceUntil ??
        DateTime(_start.year, _start.month + 3, _start.day);
    _calendar = (e?.sourceId ??
            (e == null
                ? context.read<CalendarProvider>().defaultCalendarId
                : null)) ??
        'local';
  }

  @override
  void dispose() {
    _subject.dispose();
    _location.dispose();
    _attendees.dispose();
    _notes.dispose();
    _count.dispose();
    super.dispose();
  }

  /// Rebuilds when the "Save & Email Attendees" button should appear or
  /// disappear, and clears a stale address error.
  void _onAttendeesChanged() {
    final has = _attendees.text.trim().isNotEmpty;
    if (has != _hadAttendees || _attendeeError != null) {
      setState(() {
        _hadAttendees = has;
        _attendeeError = null;
      });
    }
  }

  // ─── Validation ────────────────────────────────────────────────────

  String? get _rangeError {
    if (_allDay) {
      return dateOnly(_end).isBefore(dateOnly(_start))
          ? 'The end date you entered occurs before the start date.'
          : null;
    }
    return _end.isAfter(_start)
        ? null
        : 'The end time you entered occurs before the start time.';
  }

  int? get _occurrenceCount {
    final n = int.tryParse(_count.text.trim());
    return n == null || n < 1 || n > 999 ? null : n;
  }

  String? get _seriesError {
    if (!_isRecurring) return null;
    switch (_seriesEnd) {
      case SeriesEnd.never:
        return null;
      case SeriesEnd.onDate:
        return dateOnly(_until).isBefore(dateOnly(_start))
            ? 'The series must end on or after its start date.'
            : null;
      case SeriesEnd.afterCount:
        return _occurrenceCount == null
            ? 'Enter a number of occurrences between 1 and 999.'
            : null;
    }
  }

  // ─── Editing times (the end follows the start, like Outlook) ───────

  static int _minutesOf(DateTime t) => t.hour * 60 + t.minute;

  void _setStartDate(DateTime date) {
    setState(() {
      final endDays = daysBetween(_start, _end);
      _start = DateTime(date.year, date.month, date.day, _start.hour,
          _start.minute);
      _end = DateTime(_start.year, _start.month, _start.day + endDays,
          _end.hour, _end.minute);
    });
  }

  void _setStartMinutes(int minutes) {
    setState(() {
      final length = _end.difference(_start);
      _start = DateTime(_start.year, _start.month, _start.day, 0, minutes);
      _end = _start.add(length.isNegative ? Duration.zero : length);
    });
  }

  void _setEndDate(DateTime date) {
    setState(() {
      _end = DateTime(date.year, date.month, date.day, _end.hour, _end.minute);
    });
  }

  void _setEndMinutes(int minutes) {
    setState(() {
      _end = DateTime(_end.year, _end.month, _end.day, 0, minutes);
    });
  }

  void _setAllDay(bool allDay) {
    setState(() {
      _allDay = allDay;
      if (!allDay && !_end.isAfter(_start)) {
        _end = _start.add(const Duration(minutes: 30));
      }
    });
  }

  // ─── Saving and deleting ───────────────────────────────────────────

  void _save({bool thenEmail = false}) {
    // Range and series errors are already shown next to their fields.
    if (_rangeError != null || _seriesError != null) return;
    final parsed = parseAttendeeList(_attendees.text);
    if (parsed.invalid.isNotEmpty) {
      setState(() => _attendeeError =
          'Check these attendee addresses: ${parsed.invalid.join('; ')}');
      return;
    }

    final cal = context.read<CalendarProvider>();
    final original =
        _original == null ? null : currentEvent(cal, _original!) ?? _original;
    final shownStart = _allDay ? dateOnly(_start) : _start;
    final shownEnd =
        _allDay ? DateTime(_end.year, _end.month, _end.day, 23, 59) : _end;

    var start = shownStart;
    var end = shownEnd;
    var excluded = original?.excludedDates ?? const <DateTime>[];
    final occurrence = widget.occurrence;
    if (original != null &&
        original.isRecurring &&
        _isRecurring &&
        occurrence != null) {
      // The form showed one occurrence: shift the series by the same amount.
      final dayShift = daysBetween(occurrence.start, shownStart);
      final endDays = daysBetween(shownStart, shownEnd);
      final s = original.startTime;
      start = DateTime(s.year, s.month, s.day + dayShift, shownStart.hour,
          shownStart.minute);
      end = DateTime(start.year, start.month, start.day + endDays,
          shownEnd.hour, shownEnd.minute);
      if (dayShift != 0) {
        excluded = [for (final d in excluded) addDays(d, dayShift)];
      }
    }
    if (!_isRecurring) excluded = const [];

    final endsOnDate = _isRecurring && _seriesEnd == SeriesEnd.onDate;
    final endsAfterCount = _isRecurring && _seriesEnd == SeriesEnd.afterCount;
    final event = (original ?? cal.createDefaultEvent(start: start)).copyWith(
      title: _subject.text.trim(),
      location: _location.text.trim(),
      description: _notes.text.trim(),
      startTime: start,
      endTime: end,
      isAllDay: _allDay,
      category: _category,
      reminder: _reminder,
      recurrence: _recurrence,
      recurrenceUntil: endsOnDate ? dateOnly(_until) : null,
      clearRecurrenceUntil: !endsOnDate,
      recurrenceCount: endsAfterCount ? _occurrenceCount : null,
      clearRecurrenceCount: !endsAfterCount,
      excludedDates: excluded,
      attendees: parsed.addresses,
      updatedAt: DateTime.now(),
    );
    if (original == null) {
      final calendar = _calendar == 'local' ? null : _calendar;
      cal.defaultCalendarId = calendar;
      cal.addEvent(event.sourceId == calendar
          ? event
          : CalendarEvent.fromMap({...event.toMap(), 'sourceId': calendar}));
    } else {
      cal.updateEvent(event);
    }

    final navigator = Navigator.of(context);
    navigator.pop();
    if (thenEmail && event.attendees.isNotEmpty) {
      // The dialog is gone; open the message from the navigator's context.
      emailAttendees(
        navigator.context,
        event,
        occurrence:
            EventOccurrence(event: event, start: shownStart, end: shownEnd),
      );
    }
  }

  Future<void> _delete() async {
    final original = _original!;
    final navigator = Navigator.of(context);
    final bool deleted;
    if (original.isRecurring && widget.occurrence == null) {
      final cal = context.read<CalendarProvider>();
      deleted = await showConfirmDialog(
        context,
        title: 'Delete Appointment Series',
        message: 'Delete every occurrence of "${displayTitle(original)}"?',
        confirmLabel: 'Delete the series',
        destructive: true,
      );
      if (deleted) cal.removeEvent(original.id);
    } else {
      deleted = await deleteOccurrenceWithPrompt(
        context,
        widget.occurrence ??
            EventOccurrence(
                event: original,
                start: original.startTime,
                end: original.endTime),
      );
    }
    if (deleted && mounted) navigator.pop();
  }

  // ─── UI ────────────────────────────────────────────────────────────

  String get _title {
    if (!_isEditing) return _allDay ? 'New All Day Event' : 'New Appointment';
    final subject = _original!.title.trim();
    final kind = _isSeries
        ? 'Appointment Series'
        : _allDay
            ? 'Event'
            : 'Appointment';
    return '${subject.isEmpty ? 'Untitled' : subject} - $kind';
  }

  static const _fieldStyle = TextStyle(fontSize: 13);

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: OutlookDialog(
        title: _title,
        width: 560,
        actions: _buildActions(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isSeries) ...[
              const InfoBar('Changes apply to the entire series'),
              const SizedBox(height: 12),
            ],
            ..._buildWhatAndWhere(),
            const SizedBox(height: 14),
            ..._buildWhen(),
            const SizedBox(height: 14),
            ..._buildRecurrence(),
            const SizedBox(height: 14),
            ..._buildOptions(),
            const SizedBox(height: 14),
            ..._buildAttendeesAndNotes(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActions() => [
        if (_isEditing) ...[
          OutlinedButton(
            onPressed: _delete,
            style: OutlinedButton.styleFrom(
                foregroundColor: OutlookTheme.flaggedColor),
            child: const Text('Delete'),
          ),
          const Spacer(),
        ],
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_attendees.text.trim().isNotEmpty)
          OutlinedButton(
            onPressed: () => _save(thenEmail: true),
            child: const Text('Save & Email Attendees'),
          ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ];

  List<Widget> _buildWhatAndWhere() => [
        FormRow(
          label: 'Subject',
          child: TextField(
            key: EventEditorDialog.subjectFieldKey,
            controller: _subject,
            autofocus: true,
            style: _fieldStyle,
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(height: 8),
        FormRow(
          label: 'Location',
          child: TextField(
            key: EventEditorDialog.locationFieldKey,
            controller: _location,
            style: _fieldStyle,
            onSubmitted: (_) => _save(),
          ),
        ),
        ..._buildCalendar(),
      ];

  /// Which calendar: chosen for new appointments, shown for others.
  List<Widget> _buildCalendar() {
    final cal = context.read<CalendarProvider>();
    final calendars = cal.calendars;
    if (calendars.length < 2 && _calendar == 'local') return const [];
    return [
      const SizedBox(height: 8),
      FormRow(
        label: 'Calendar',
        child: _isEditing
            ? Text(cal.calendarLabel(_original!.sourceId), style: _fieldStyle)
            : FormDropdown<String>(
                key: EventEditorDialog.calendarFieldKey,
                value: _calendar,
                items: [
                  for (final c in calendars)
                    DropdownMenuItem(
                      value: c.id ?? 'local',
                      child: dropdownItemText(c.label),
                    ),
                ],
                onChanged: (id) => setState(() => _calendar = id),
              ),
      ),
    ];
  }

  List<Widget> _buildWhen() {
    final rangeError = _rangeError;
    return [
      FormRow(
        label: 'Start time',
        child: _dateTimeRow(
          date: _start,
          onDate: _setStartDate,
          time: TimeSlotDropdown(
            minutes: _minutesOf(_start),
            onChanged: _setStartMinutes,
          ),
          trailing: LabeledCheckbox(
            checkboxKey: EventEditorDialog.allDayCheckboxKey,
            label: 'All day event',
            value: _allDay,
            onChanged: _setAllDay,
          ),
        ),
      ),
      const SizedBox(height: 8),
      FormRow(
        label: 'End time',
        child: _dateTimeRow(
          date: _end,
          onDate: _setEndDate,
          time: TimeSlotDropdown(
            minutes: _minutesOf(_end),
            onChanged: _setEndMinutes,
            durationFrom: isSameDate(_start, _end) ? _minutesOf(_start) : null,
          ),
          trailing: const SizedBox.shrink(),
        ),
      ),
      if (rangeError != null) FieldError(rangeError),
    ];
  }

  /// Date field, time dropdown (hidden for all-day events) and a trailing
  /// widget, in columns that line up between the start and end rows.
  Widget _dateTimeRow({
    required DateTime date,
    required ValueChanged<DateTime> onDate,
    required Widget time,
    required Widget trailing,
  }) {
    return Row(
      children: [
        Expanded(flex: 5, child: DateField(date: date, onChanged: onDate)),
        const SizedBox(width: 8),
        Expanded(flex: 4, child: _allDay ? const SizedBox.shrink() : time),
        const SizedBox(width: 8),
        Expanded(flex: 4, child: trailing),
      ],
    );
  }

  List<Widget> _buildRecurrence() {
    if (_isServerOccurrence) {
      return const [
        FormRow(
          label: 'Repeat',
          child: Text(
            'One occurrence of a recurring meeting; changes apply to it only',
            style: TextStyle(fontSize: 12, color: OutlookTheme.textSecondary),
          ),
        ),
      ];
    }
    final seriesError = _seriesError;
    return [
      FormRow(
        label: 'Repeat',
        child: FormDropdown<RecurrenceRule>(
          key: EventEditorDialog.repeatFieldKey,
          value: _recurrence,
          items: [
            for (final r in RecurrenceRule.values)
              DropdownMenuItem(value: r, child: dropdownItemText(r.displayName)),
          ],
          onChanged: (r) => setState(() => _recurrence = r),
        ),
      ),
      if (_isRecurring) ...[
        const SizedBox(height: 4),
        FormRow(
          label: 'End',
          alignTop: true,
          child: SeriesEndField(
            mode: _seriesEnd,
            until: _until,
            countController: _count,
            onModeChanged: (mode) => setState(() => _seriesEnd = mode),
            onUntilChanged: (date) => setState(() => _until = date),
          ),
        ),
        if (seriesError != null) FieldError(seriesError),
      ],
    ];
  }

  List<Widget> _buildOptions() => [
        FormRow(
          label: 'Reminder',
          child: FormDropdown<ReminderTime>(
            value: _reminder,
            items: [
              for (final r in ReminderTime.values)
                DropdownMenuItem(
                    value: r, child: dropdownItemText(r.displayName)),
            ],
            onChanged: (r) => setState(() => _reminder = r),
          ),
        ),
        const SizedBox(height: 8),
        FormRow(
          label: 'Category',
          child: FormDropdown<EventCategory>(
            value: _category,
            items: [
              for (final c in EventCategory.values)
                DropdownMenuItem(value: c, child: CategoryLabel(c)),
            ],
            onChanged: (c) => setState(() => _category = c),
          ),
        ),
      ];

  List<Widget> _buildAttendeesAndNotes() => [
        FormRow(
          label: 'Attendees',
          child: TextField(
            key: EventEditorDialog.attendeesFieldKey,
            controller: _attendees,
            style: _fieldStyle,
            decoration: const InputDecoration(
              hintText: 'Separate e-mail addresses with semicolons',
              hintStyle: TextStyle(fontSize: 12, color: OutlookTheme.textMuted),
            ),
          ),
        ),
        if (_attendeeError != null) FieldError(_attendeeError!),
        const SizedBox(height: 8),
        FormRow(
          label: 'Notes',
          alignTop: true,
          child: TextField(
            key: EventEditorDialog.notesFieldKey,
            controller: _notes,
            style: _fieldStyle,
            minLines: 4,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
          ),
        ),
      ];
}
