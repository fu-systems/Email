import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/calendar_event.dart';
import '../../providers/calendar_provider.dart';
import '../../services/file_dialogs.dart';
import '../../services/ical_service.dart';
import '../../widgets/common.dart';

/// How imported events map onto the calendar: [added] are new, [updated]
/// replace existing events with the same iCalendar UID (keeping their id,
/// creation time and category).
typedef CalendarImportPlan = ({
  List<CalendarEvent> added,
  List<CalendarEvent> updated,
});

/// Matches [parsed] events against [existing] ones by [CalendarEvent.uid].
///
/// When several events share a UID (a recurring series and its modified
/// occurrences), each existing event is updated at most once, preferring
/// the one with the same kind (series or single) and start time.
CalendarImportPlan planCalendarImport(
  List<CalendarEvent> existing,
  List<CalendarEvent> parsed,
) {
  final byUid = <String, List<CalendarEvent>>{};
  for (final e in existing) {
    byUid.putIfAbsent(e.uid, () => []).add(e);
  }
  final claimed = <String>{};
  final added = <CalendarEvent>[];
  final updated = <CalendarEvent>[];
  for (final event in parsed) {
    final candidates = [
      for (final e in byUid[event.uid] ?? const <CalendarEvent>[])
        if (!claimed.contains(e.id)) e,
    ];
    if (candidates.isEmpty) {
      added.add(event);
      continue;
    }
    final match = candidates.firstWhereOrNull((e) =>
            e.isRecurring == event.isRecurring &&
            e.startTime == event.startTime) ??
        candidates.firstWhereOrNull((e) => e.isRecurring == event.isRecurring) ??
        candidates.first;
    claimed.add(match.id);
    updated.add(event.copyWith(
      id: match.id,
      icalUid: match.uid,
      category: match.category,
      createdAt: match.createdAt,
    ));
  }
  return (added: added, updated: updated);
}

/// Lets the user pick iCalendar (.ics) files and imports their events.
///
/// Events whose UID is already in the calendar are updated instead of
/// duplicated. Reports "Imported N events" (or the problem) in the status
/// area.
Future<void> importCalendarFile(BuildContext context) async {
  final cal = context.read<CalendarProvider>();
  final paths = await FileDialogs.pickFiles(
    context,
    title: 'Import iCalendar File',
    extensions: const ['ics'],
    multiple: true,
  );
  if (paths.isEmpty) return;

  final parsed = <CalendarEvent>[];
  final failed = <String>[];
  for (final path in paths) {
    try {
      final bytes = await File(path).readAsBytes();
      final events =
          IcalService.parseEvents(utf8.decode(bytes, allowMalformed: true));
      if (events.isEmpty) failed.add(p.basename(path));
      parsed.addAll(events);
    } catch (_) {
      failed.add(p.basename(path));
    }
  }

  if (parsed.isNotEmpty) {
    final plan = planCalendarImport(cal.allEvents, parsed);
    cal.addEvents([...plan.added, ...plan.updated]);
  }
  if (!context.mounted) return;

  final count = parsed.length;
  final imported = 'Imported $count event${count == 1 ? '' : 's'}';
  if (failed.isEmpty) {
    showStatusMessage(context, imported);
  } else if (count == 0) {
    showStatusMessage(
      context,
      'No events could be imported from ${failed.join(', ')}',
      isError: true,
    );
  } else {
    showStatusMessage(
      context,
      '$imported. No events could be read from ${failed.join(', ')}',
      isError: true,
    );
  }
}

/// Saves every appointment as an iCalendar file (`calendar.ics`).
Future<void> exportCalendarFile(BuildContext context) async {
  final events = context.read<CalendarProvider>().allEvents;
  if (events.isEmpty) {
    showStatusMessage(context, 'There are no appointments to export');
    return;
  }
  try {
    final ics = IcalService.generateCalendar(events);
    final path = await FileDialogs.saveFile(
      context,
      fileName: 'calendar.ics',
      bytes: Uint8List.fromList(utf8.encode(ics)),
      title: 'Export Calendar',
      mimeType: 'text/calendar',
      extensions: const ['ics'],
    );
    if (path == null || !context.mounted) return;
    showStatusMessage(context,
        'Exported ${events.length} event${events.length == 1 ? '' : 's'} to $path');
  } catch (e) {
    if (!context.mounted) return;
    showStatusMessage(context, 'Could not export the calendar: $e',
        isError: true);
  }
}
