import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/calendar_event.dart';
import '../../providers/calendar_provider.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';
import 'calendar_actions.dart';
import 'calendar_layout.dart';
import 'event_chip.dart';

/// Left pane of the Calendar module: the date navigator (a compact month
/// calendar) and the appointments of the next seven days.
class CalendarSidebar extends StatelessWidget {
  const CalendarSidebar({super.key});

  /// Width of the pane.
  static const double width = 240;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: OutlookTheme.folderPaneDecoration,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DateNavigator(),
          Divider(height: 1),
          _MyCalendars(),
          Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text('Upcoming', style: OutlookTheme.folderLabelBoldStyle),
          ),
          Expanded(child: _UpcomingList()),
        ],
      ),
    );
  }
}

/// Outlook's Date Navigator: a small month calendar. Today is filled blue,
/// the days of the current view are highlighted, and days with
/// appointments are bold. The arrows browse months without changing the
/// main view; clicking a day selects it.
class DateNavigator extends StatefulWidget {
  const DateNavigator({super.key});

  @override
  State<DateNavigator> createState() => _DateNavigatorState();
}

class _DateNavigatorState extends State<DateNavigator> {
  /// Months browsed away from the selected date's month, and the selected
  /// date that offset applies to (a new selection resets it).
  int _monthOffset = 0;
  DateTime? _offsetAnchor;

  static const _weekdayInitials = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  void _browse(DateTime selected, int delta) {
    setState(() {
      if (_offsetAnchor != selected) _monthOffset = 0;
      _offsetAnchor = selected;
      _monthOffset += delta;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cal = context.watch<CalendarProvider>();
    final selected = cal.selectedDate;
    final offset = _offsetAnchor == selected ? _monthOffset : 0;
    final month = DateTime(selected.year, selected.month + offset, 1);
    final firstDay = CalendarProvider.weekStart(month);
    final today = dateOnly(DateTime.now());

    final byDay = occurrencesByDay(
      cal.getOccurrencesInRange(firstDay, addDays(firstDay, 42)),
      firstDay,
      42,
    );

    final highlighted = cal.viewType == CalendarViewType.month
        ? {selected}
        : cal.visibleDays.toSet();

    Widget cell(int index) {
      final day = addDays(firstDay, index);
      return _NavigatorDay(
        day: day,
        inMonth: day.month == month.month,
        isToday: day == today,
        highlighted: highlighted.contains(day),
        hasEvents: byDay[index].isNotEmpty,
        onTap: cal.selectDate,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              HoverButton(
                icon: Icons.chevron_left,
                tooltip: 'Previous month',
                color: OutlookTheme.textSecondary,
                padding: const EdgeInsets.all(3),
                onTap: () => _browse(selected, -1),
              ),
              Expanded(
                child: Text(
                  '${monthName(month.month)} ${month.year}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OutlookTheme.folderLabelBoldStyle,
                ),
              ),
              HoverButton(
                icon: Icons.chevron_right,
                tooltip: 'Next month',
                color: OutlookTheme.textSecondary,
                padding: const EdgeInsets.all(3),
                onTap: () => _browse(selected, 1),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final initial in _weekdayInitials)
                Expanded(
                  child: Text(
                    initial,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11, color: OutlookTheme.textMuted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          for (var week = 0; week < 6; week++)
            Row(
              children: [
                for (var d = 0; d < 7; d++) Expanded(child: cell(week * 7 + d)),
              ],
            ),
        ],
      ),
    );
  }
}

class _NavigatorDay extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool highlighted;
  final bool hasEvents;
  final ValueChanged<DateTime> onTap;

  const _NavigatorDay({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.highlighted,
    required this.hasEvents,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isToday
        ? Colors.white
        : inMonth
            ? OutlookTheme.textPrimary
            : OutlookTheme.textMuted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onTap(day),
        child: Container(
          height: 24,
          margin: const EdgeInsets.all(0.5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isToday
                ? OutlookTheme.calendarToday
                : highlighted
                    ? OutlookTheme.calendarSelected
                    : null,
            border: highlighted && isToday
                ? Border.all(color: OutlookTheme.darkBlue, width: 2)
                : null,
          ),
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: hasEvents ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Appointments from now until the end of the seventh day, grouped by day.
class _UpcomingList extends StatelessWidget {
  const _UpcomingList();

  @override
  Widget build(BuildContext context) {
    final cal = context.watch<CalendarProvider>();
    final now = DateTime.now();
    final today = dateOnly(now);
    final occurrences = cal.getOccurrencesInRange(now, addDays(today, 7));
    if (occurrences.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Text(
          'No upcoming appointments',
          style: TextStyle(fontSize: 12, color: OutlookTheme.textMuted),
        ),
      );
    }

    // Group by the day each occurrence is (still) happening on.
    final byDay = occurrencesByDay(occurrences, today, 7);
    final seen = <String>{};
    final children = <Widget>[];
    for (var i = 0; i < 7; i++) {
      final items = [
        for (final o in byDay[i])
          if (seen.add(o.key)) o,
      ];
      if (items.isEmpty) continue;
      final day = addDays(today, i);
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
        child: Text(
          i == 0
              ? 'Today'
              : i == 1
                  ? 'Tomorrow'
                  : '${weekdayName(day.weekday)}, '
                      '${monthName(day.month).substring(0, 3)} ${day.day}',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: OutlookTheme.textSecondary,
          ),
        ),
      ));
      for (final o in items) {
        children.add(_UpcomingItem(
          occurrence: o,
          selected: cal.selectedOccurrence?.key == o.key,
        ));
      }
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: children,
    );
  }
}

class _UpcomingItem extends StatelessWidget {
  final EventOccurrence occurrence;
  final bool selected;

  const _UpcomingItem({required this.occurrence, required this.selected});

  @override
  Widget build(BuildContext context) {
    final event = occurrence.event;
    final location = event.location?.trim() ?? '';
    return ClickDetector(
      onTap: (_) {
        final cal = context.read<CalendarProvider>();
        cal.selectDate(occurrence.start);
        cal.selectOccurrence(occurrence);
      },
      onDoubleTap: (_) => openEventEditor(context, occurrence: occurrence),
      onSecondaryTap: (details) =>
          showEventContextMenu(context, details.globalPosition, occurrence),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: selected
            ? OutlookTheme.selectedItemDecoration()
            : const BoxDecoration(),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: event.category.color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.isAllDay
                          ? 'All day'
                          : isSameDate(occurrence.start, occurrence.end)
                              ? '${formatTime(occurrence.start)} - '
                                  '${formatTime(occurrence.end)}'
                              : formatOccurrenceTime(occurrence),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OutlookTheme.messageDate,
                    ),
                    Text(
                      displayTitle(event),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, color: OutlookTheme.textPrimary),
                    ),
                    if (location.isNotEmpty)
                      Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OutlookTheme.messagePreview,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "My Calendars": the local calendar and those of Microsoft accounts,
/// each shown or hidden with its checkbox.
class _MyCalendars extends StatelessWidget {
  const _MyCalendars();

  @override
  Widget build(BuildContext context) {
    final cal = context.watch<CalendarProvider>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 2),
            child: Text('My Calendars', style: OutlookTheme.folderLabelBoldStyle),
          ),
          for (final c in cal.calendars) ...[
            InkWell(
              onTap: () =>
                  cal.setCalendarVisible(c.id, !cal.isCalendarVisible(c.id)),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    height: 26,
                    child: Checkbox(
                      value: cal.isCalendarVisible(c.id),
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) => cal.setCalendarVisible(c.id, v ?? true),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      c.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
            if (c.id != null && cal.calendarError(c.id!) != null)
              Padding(
                padding: const EdgeInsets.only(left: 32, bottom: 4),
                child: Tooltip(
                  message: cal.calendarError(c.id!)!,
                  child: const Text(
                    'Not synced (hover for details)',
                    style: TextStyle(
                      fontSize: 11,
                      color: OutlookTheme.flaggedColor,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
