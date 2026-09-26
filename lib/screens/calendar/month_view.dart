import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/calendar_event.dart';
import '../../providers/calendar_provider.dart';
import '../../theme/outlook_theme.dart';
import 'calendar_actions.dart';
import 'calendar_layout.dart';
import 'event_chip.dart';

const _gridLineColor = Color(0xFFE1E1E1);

/// The Month view: six weeks of days, Sunday first.
///
/// Each day shows up to three appointments (all-day ones as filled bars,
/// timed ones as "9:00 AM Title" with a category dot) and a "+N more" link
/// that opens the day in the Day view. Click a day to select it,
/// double-click to create an appointment at 9 AM, right-click for
/// "New Appointment" / "New All Day Event".
class MonthView extends StatelessWidget {
  const MonthView({super.key});

  @override
  Widget build(BuildContext context) {
    final cal = context.watch<CalendarProvider>();
    final days = cal.visibleDays;
    final firstDay = days.first;
    // Expand the visible range once and bucket it per day.
    final byDay = occurrencesByDay(
      cal.getOccurrencesInRange(firstDay, addDays(firstDay, days.length)),
      firstDay,
      days.length,
    );
    final today = dateOnly(DateTime.now());
    final month = cal.focusedDate.month;
    final selectedKey = cal.selectedOccurrence?.key;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _WeekdayHeader(),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var week = 0; week < days.length ~/ 7; week++)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = week * 7; i < week * 7 + 7; i++)
                        Expanded(
                          child: _MonthCell(
                            day: days[i],
                            occurrences: byDay[i],
                            inMonth: days[i].month == month,
                            isToday: days[i] == today,
                            isSelected: days[i] == cal.selectedDate,
                            selectedKey: selectedKey,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Sunday … Saturday" (abbreviated when the columns are narrow).
class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  static const _order = [
    DateTime.sunday, DateTime.monday, DateTime.tuesday, DateTime.wednesday,
    DateTime.thursday, DateTime.friday, DateTime.saturday,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OutlookTheme.dividerColor)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final short = constraints.maxWidth / 7 < 90;
        return Row(
          children: [
            for (final weekday in _order)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    short
                        ? weekdayName(weekday).substring(0, 3)
                        : weekdayName(weekday),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: OutlookTheme.textSecondary),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _MonthCell extends StatelessWidget {
  final DateTime day;
  final List<EventOccurrence> occurrences;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final String? selectedKey;

  const _MonthCell({
    required this.day,
    required this.occurrences,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.selectedKey,
  });

  static const _headerHeight = 22.0;
  static const _lineHeight = 18.0;
  static const _lineGap = 2.0;
  static const _maxChips = 3;

  DateTime get _nineAm => DateTime(day.year, day.month, day.day, 9);

  /// Selects the day, staying on the current month when the day belongs
  /// to the previous or next one.
  void _select(CalendarProvider cal) {
    final focused = cal.focusedDate;
    cal.selectDate(day);
    if (!inMonth) cal.setFocusedDate(focused);
  }

  @override
  Widget build(BuildContext context) {
    final cal = context.read<CalendarProvider>();
    return ClickDetector(
      onTap: (_) => _select(cal),
      onDoubleTap: (_) => openEventEditor(context, initialStart: _nineAm),
      onSecondaryTap: (details) {
        _select(cal);
        showSlotContextMenu(context, details.globalPosition, _nineAm);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? OutlookTheme.calendarSelected
              : inMonth
                  ? Colors.white
                  : const Color(0xFFF7F7F7),
          border: const Border(
            right: BorderSide(color: _gridLineColor),
            bottom: BorderSide(color: _gridLineColor),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => _buildContent(
            cal,
            constraints.maxHeight,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(CalendarProvider cal, double height) {
    // Number of chip lines that fit below the day number.
    final fit = math.max(
      0,
      ((height - _headerHeight - 1) / (_lineHeight + _lineGap)).floor(),
    );
    final total = occurrences.length;
    final capacity = math.min(fit, _maxChips);
    final overflow = total > capacity;
    final shown = overflow ? math.max(0, math.min(fit, _maxChips + 1) - 1) : total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _headerHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: 5, top: 3),
            child: Align(
              alignment: Alignment.topLeft,
              child: _DayNumber(day: day, inMonth: inMonth, isToday: isToday),
            ),
          ),
        ),
        for (final o in occurrences.take(shown))
          Padding(
            key: ValueKey(o.key),
            padding: const EdgeInsets.fromLTRB(3, 0, 3, _lineGap),
            child: SizedBox(
              height: _lineHeight,
              child: EventInteraction(
                occurrence: o,
                child: isAllDayBandOccurrence(o)
                    ? EventBar(
                        occurrence: o,
                        selected: o.key == selectedKey,
                        height: _lineHeight,
                      )
                    : EventLine(
                        occurrence: o,
                        day: day,
                        selected: o.key == selectedKey,
                        height: _lineHeight,
                      ),
              ),
            ),
          ),
        if (overflow && fit > 0)
          _MoreLink(
            count: total - shown,
            height: _lineHeight,
            onTap: () {
              cal.selectDate(day);
              cal.setViewType(CalendarViewType.day);
            },
          ),
      ],
    );
  }
}

/// Day number ("11", or "Mar 1" on the first of a month); today's is a
/// blue badge.
class _DayNumber extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final bool isToday;

  const _DayNumber({
    required this.day,
    required this.inMonth,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final text = day.day == 1
        ? '${monthName(day.month).substring(0, 3)} ${day.day}'
        : '${day.day}';
    if (isToday) {
      return Container(
        constraints: const BoxConstraints(minWidth: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: OutlookTheme.calendarToday,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      );
    }
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: inMonth ? OutlookTheme.textPrimary : OutlookTheme.textMuted,
      ),
    );
  }
}

/// "+N more" link at the bottom of a crowded day.
class _MoreLink extends StatelessWidget {
  final int count;
  final double height;
  final VoidCallback onTap;

  const _MoreLink({
    required this.count,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.centerLeft,
          child: Text(
            '+$count more',
            maxLines: 1,
            style: const TextStyle(fontSize: 11.5, color: OutlookTheme.textLink),
          ),
        ),
      ),
    );
  }
}
