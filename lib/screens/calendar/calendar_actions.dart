import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/calendar_event.dart';
import '../../models/email_message.dart';
import '../../providers/calendar_provider.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';
import '../mail/compose_launcher.dart';
import 'calendar_layout.dart';
import 'event_editor_dialog.dart';

/// Opens the appointment form: for an existing [occurrence], or a new
/// appointment starting at [initialStart] (default: the next hour on the
/// selected date).
Future<void> openEventEditor(
  BuildContext context, {
  EventOccurrence? occurrence,
  DateTime? initialStart,
  bool initialAllDay = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => EventEditorDialog(
      occurrence: occurrence,
      initialStart: initialStart,
      initialAllDay: initialAllDay,
    ),
  );
}

/// The stored version of [event] (it may have changed since an occurrence
/// was expanded), or null when it has been deleted.
CalendarEvent? currentEvent(CalendarProvider cal, CalendarEvent event) =>
    cal.allEvents.firstWhereOrNull((e) => e.id == event.id);

enum _DeleteChoice { occurrence, series }

/// Deletes [occurrence] after asking the user.
///
/// For a recurring appointment the user chooses between deleting this
/// occurrence and deleting the whole series; otherwise a confirmation is
/// shown. Returns true when something was deleted.
Future<bool> deleteOccurrenceWithPrompt(
  BuildContext context,
  EventOccurrence occurrence,
) async {
  final cal = context.read<CalendarProvider>();
  final event = currentEvent(cal, occurrence.event);
  if (event == null) return false;
  final title = displayTitle(event);

  if (!event.isRecurring) {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Appointment',
      message: 'Are you sure you want to delete "$title"?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return false;
    cal.removeEvent(event.id);
    return true;
  }

  final choice = await showDialog<_DeleteChoice>(
    context: context,
    builder: (ctx) => OutlookDialog(
      title: 'Confirm Delete',
      width: 500,
      actions: [
        ElevatedButton(
          autofocus: true,
          onPressed: () => Navigator.of(ctx).pop(_DeleteChoice.occurrence),
          child: const Text('Delete this occurrence'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop(_DeleteChoice.series),
          child: const Text('Delete the series'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"$title" is a recurring appointment. Do you want to delete '
            'only this occurrence or the series?',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            '${formatLongDate(occurrence.start)} · '
            '${formatOccurrenceTime(occurrence)}',
            style: const TextStyle(
                fontSize: 12, color: OutlookTheme.textSecondary),
          ),
        ],
      ),
    ),
  );
  switch (choice) {
    case _DeleteChoice.occurrence:
      cal.removeOccurrence(EventOccurrence(
        event: event,
        start: occurrence.start,
        end: occurrence.end,
      ));
      return true;
    case _DeleteChoice.series:
      cal.removeEvent(event.id);
      return true;
    case null:
      return false;
  }
}

enum _EventMenu { open, email, delete }

/// Shows the right-click menu of an appointment: Open, Email Attendees,
/// Delete and the categories.
Future<void> showEventContextMenu(
  BuildContext context,
  Offset globalPosition,
  EventOccurrence occurrence,
) async {
  final cal = context.read<CalendarProvider>();
  cal.selectOccurrence(occurrence);
  final event = occurrence.event;
  final choice = await showContextMenu<Object>(context, globalPosition, [
    const MenuAction(_EventMenu.open, 'Open', icon: Icons.open_in_new),
    if (event.attendees.isNotEmpty)
      const MenuAction(_EventMenu.email, 'Email Attendees',
          icon: Icons.mail_outline),
    const MenuAction(_EventMenu.delete, 'Delete',
        icon: Icons.delete_outline, shortcut: 'Del'),
    const MenuAction('categorize', 'Categorize',
        icon: Icons.label_outline, enabled: false, dividerBefore: true),
    for (final category in EventCategory.values)
      MenuAction(
        category,
        category.displayName,
        icon: category == event.category
            ? Icons.check_box
            : Icons.check_box_outline_blank,
      ),
  ]);
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _EventMenu.open:
      await openEventEditor(context, occurrence: occurrence);
    case _EventMenu.email:
      await emailAttendees(context, event, occurrence: occurrence);
    case _EventMenu.delete:
      await deleteOccurrenceWithPrompt(context, occurrence);
    case EventCategory category:
      final fresh = currentEvent(cal, event);
      if (fresh != null && fresh.category != category) {
        cal.updateEvent(
            fresh.copyWith(category: category, updatedAt: DateTime.now()));
      }
  }
}

/// Shows the right-click menu of an empty time slot or day:
/// "New Appointment" (at [slotStart]) and "New All Day Event".
Future<void> showSlotContextMenu(
  BuildContext context,
  Offset globalPosition,
  DateTime slotStart,
) async {
  final allDay = await showContextMenu<bool>(context, globalPosition, const [
    MenuAction(false, 'New Appointment', icon: Icons.event),
    MenuAction(true, 'New All Day Event', icon: Icons.today),
  ]);
  if (allDay == null || !context.mounted) return;
  await openEventEditor(context,
      initialStart: slotStart, initialAllDay: allDay);
}

/// Plain-text summary of an appointment (when, where, recurrence, notes)
/// for a message to its attendees.
String describeEventForEmail(CalendarEvent event, {EventOccurrence? occurrence}) {
  final o = occurrence ??
      EventOccurrence(event: event, start: event.startTime, end: event.endTime);
  final location = event.location?.trim() ?? '';
  final notes = event.description?.trim() ?? '';
  final when = event.isAllDay && isSameDate(o.start, lastDayOf(o))
      ? '${formatLongDate(o.start)} (All day)'
      : isSameDate(o.start, lastDayOf(o))
          ? '${formatLongDate(o.start)} ${formatOccurrenceTime(o)}'
          : formatOccurrenceTime(o);
  return [
    'When: $when',
    if (location.isNotEmpty) 'Where: $location',
    if (event.isRecurring) 'Recurrence: ${event.recurrence!.displayName}',
    if (notes.isNotEmpty) ...['', notes],
  ].join('\n');
}

/// Opens a new message to the attendees of [event] with its title as the
/// subject and a summary of when and where as the body.
Future<void> emailAttendees(
  BuildContext context,
  CalendarEvent event, {
  EventOccurrence? occurrence,
}) {
  return openNewMessage(
    context,
    to: [
      for (final a in event.attendees)
        if (a.trim().isNotEmpty) EmailAddress.parse(a),
    ],
    subject: event.title.trim(),
    body: describeEventForEmail(event, occurrence: occurrence),
  );
}
