import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/calendar_event.dart';
import '../../providers/calendar_provider.dart';
import '../../theme/outlook_theme.dart';
import 'calendar_actions.dart';
import 'calendar_layout.dart';
import 'event_chip.dart';

/// The Day, Work Week and Week views: a header per day, a band for all-day
/// and multi-day appointments, and a scrollable 24-hour grid.
///
/// Click an empty half-hour slot to select it, double-click it to create an
/// appointment there, right-click for "New Appointment" / "New All Day
/// Event". Appointments support click (select), double-click (open) and
/// right-click (context menu).
class TimeGridView extends StatefulWidget {
  const TimeGridView({super.key});

  /// Height of one hour in the grid.
  static const double hourHeight = 48;

  /// Width of the hour labels on the left.
  static const double gutterWidth = 56;

  /// Hour at the top of the grid when it is first shown.
  static const int initialHour = 7;

  @override
  State<TimeGridView> createState() => _TimeGridViewState();
}

class _TimeGridViewState extends State<TimeGridView> {
  final _scroll = ScrollController(
    initialScrollOffset: TimeGridView.initialHour * TimeGridView.hourHeight,
  );
  late final Timer _clock;
  DateTime _now = DateTime.now();

  /// Start of the highlighted half-hour slot, if any.
  DateTime? _selectedSlot;

  @override
  void initState() {
    super.initState();
    // Keeps the "now" line current.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _selectSlot(DateTime slot) {
    setState(() => _selectedSlot = slot);
    context.read<CalendarProvider>().selectDate(slot);
  }

  void _clearSlot() {
    if (_selectedSlot != null) setState(() => _selectedSlot = null);
  }

  @override
  Widget build(BuildContext context) {
    final cal = context.watch<CalendarProvider>();
    final days = cal.visibleDays;
    final firstDay = days.first;

    // Expand the visible range once; everything below works on this list.
    final band = <EventOccurrence>[];
    final timed = <EventOccurrence>[];
    for (final o
        in cal.getOccurrencesInRange(firstDay, addDays(days.last, 1))) {
      (isAllDayBandOccurrence(o) ? band : timed).add(o);
    }
    final segments = segmentsByDay(timed, firstDay, days.length);
    final selectedKey = cal.selectedOccurrence?.key;
    final slot = _selectedSlot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DayHeaderRow(
          days: days,
          today: dateOnly(_now),
          selectedDate: cal.selectedDate,
        ),
        _AllDayBand(
          days: days,
          occurrences: band,
          selectedKey: selectedKey,
          onEventSelected: _clearSlot,
        ),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              child: SizedBox(
                height: 24 * TimeGridView.hourHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _HourGutter(),
                    for (var i = 0; i < days.length; i++)
                      Expanded(
                        child: _DayColumn(
                          day: days[i],
                          segments: segments[i],
                          selectedKey: selectedKey,
                          selectedSlot: slot != null && isSameDate(slot, days[i])
                              ? slot
                              : null,
                          now: isSameDate(_now, days[i]) ? _now : null,
                          onSlotSelected: _selectSlot,
                          onEventSelected: _clearSlot,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const _gridLineColor = Color(0xFFE1E1E1);

/// Column headers ("Mon 9"); today's is highlighted in blue. Click selects
/// the day, double-click opens it in the Day view.
class _DayHeaderRow extends StatelessWidget {
  final List<DateTime> days;
  final DateTime today;
  final DateTime selectedDate;

  const _DayHeaderRow({
    required this.days,
    required this.today,
    required this.selectedDate,
  });

  @override
  Widget build(BuildContext context) {
    final single = days.length == 1;
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OutlookTheme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: TimeGridView.gutterWidth),
          for (final day in days)
            Expanded(
              child: _DayHeader(
                day: day,
                label: single
                    ? '${weekdayName(day.weekday)} ${day.day}'
                    : '${weekdayName(day.weekday).substring(0, 3)} ${day.day}',
                isToday: day == today,
                isSelected: !single && day == selectedDate,
              ),
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime day;
  final String label;
  final bool isToday;
  final bool isSelected;

  const _DayHeader({
    required this.day,
    required this.label,
    required this.isToday,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cal = context.read<CalendarProvider>();
    return ClickDetector(
      onTap: (_) => cal.selectDate(day),
      onDoubleTap: (_) {
        cal.selectDate(day);
        cal.setViewType(CalendarViewType.day);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: isToday
              ? OutlookTheme.calendarSelected
              : isSelected
                  ? OutlookTheme.hoverColor
                  : null,
          border: Border(
            left: const BorderSide(color: _gridLineColor),
            top: BorderSide(
              color: isToday ? OutlookTheme.primaryBlue : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
            color: isToday ? OutlookTheme.primaryBlue : OutlookTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// All-day and multi-day appointments as bars spanning their days.
/// Double-click an empty spot for a new all-day event.
class _AllDayBand extends StatelessWidget {
  final List<DateTime> days;
  final List<EventOccurrence> occurrences;
  final String? selectedKey;
  final VoidCallback onEventSelected;

  const _AllDayBand({
    required this.days,
    required this.occurrences,
    required this.selectedKey,
    required this.onEventSelected,
  });

  static const _rowHeight = 22.0;
  static const _maxVisibleRows = 4.5;

  @override
  Widget build(BuildContext context) {
    final placements = layoutAllDayBand(occurrences, days.first, days.length);
    final rows = placements.fold(0, (n, p) => math.max(n, p.row + 1));
    // Always leave an empty row to double-click in.
    final contentHeight = (rows + 1) * _rowHeight + 4;
    final height =
        math.min(contentHeight, _maxVisibleRows * _rowHeight + 4);

    return Container(
      height: height,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OutlookTheme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: TimeGridView.gutterWidth),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columnWidth = constraints.maxWidth / days.length;
                return SingleChildScrollView(
                  child: SizedBox(
                    height: contentHeight,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final day in days)
                                Expanded(child: _AllDaySlot(day: day)),
                            ],
                          ),
                        ),
                        for (final p in placements)
                          Positioned(
                            key: ValueKey(p.occurrence.key),
                            left: p.firstDay * columnWidth + 2,
                            width: (p.lastDay - p.firstDay + 1) * columnWidth - 4,
                            top: 2 + p.row * _rowHeight,
                            height: _rowHeight - 2,
                            child: EventInteraction(
                              occurrence: p.occurrence,
                              onSelected: onEventSelected,
                              child: EventBar(
                                occurrence: p.occurrence,
                                selected: p.occurrence.key == selectedKey,
                                height: _rowHeight - 2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AllDaySlot extends StatelessWidget {
  final DateTime day;

  const _AllDaySlot({required this.day});

  @override
  Widget build(BuildContext context) {
    return ClickDetector(
      onTap: (_) => context.read<CalendarProvider>().selectDate(day),
      onDoubleTap: (_) =>
          openEventEditor(context, initialStart: day, initialAllDay: true),
      onSecondaryTap: (details) => showSlotContextMenu(context,
          details.globalPosition, DateTime(day.year, day.month, day.day, 8)),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: _gridLineColor)),
        ),
      ),
    );
  }
}

/// Hour labels ("8 AM") on the left of the grid.
class _HourGutter extends StatelessWidget {
  const _HourGutter();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: TimeGridView.gutterWidth,
      child: Column(
        children: [
          for (var hour = 0; hour < 24; hour++)
            Container(
              height: TimeGridView.hourHeight,
              alignment: Alignment.topRight,
              padding: const EdgeInsets.only(right: 6, top: 2),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _gridLineColor)),
              ),
              child: Text(
                formatHourLabel(hour),
                maxLines: 1,
                style: const TextStyle(
                    fontSize: 11, color: OutlookTheme.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// One day of the grid: slot background, appointment blocks laid out side
/// by side where they overlap, and the "now" line on today.
class _DayColumn extends StatelessWidget {
  final DateTime day;
  final List<DaySegment> segments;
  final String? selectedKey;
  final DateTime? selectedSlot;
  final DateTime? now;
  final ValueChanged<DateTime> onSlotSelected;
  final VoidCallback onEventSelected;

  const _DayColumn({
    required this.day,
    required this.segments,
    required this.selectedKey,
    required this.selectedSlot,
    required this.now,
    required this.onSlotSelected,
    required this.onEventSelected,
  });

  static const _hourHeight = TimeGridView.hourHeight;
  static const _slotMinutes = 30;
  static const _slotHeight = _hourHeight * _slotMinutes / 60;

  /// Start of the half-hour slot at [dy] pixels from the top.
  DateTime _slotAt(double dy) {
    final index = (dy / _slotHeight).floor().clamp(0, 24 * 60 ~/ _slotMinutes - 1);
    return DateTime(day.year, day.month, day.day, 0, index * _slotMinutes);
  }

  @override
  Widget build(BuildContext context) {
    final layout = layoutIntervals<DaySegment>(
      segments,
      key: (s) => s.occurrence.key,
      start: (s) => s.start,
      end: (s) => s.end,
      minDuration: const Duration(minutes: _slotMinutes),
    );
    final slot = selectedSlot;
    final current = now;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Leave a strip on the right so empty time stays clickable.
        final usableWidth = math.max(0.0, constraints.maxWidth - 8);
        return Stack(
          children: [
            Positioned.fill(
              child: ClickDetector(
                onTap: (d) => onSlotSelected(_slotAt(d.localPosition.dy)),
                onDoubleTap: (d) => openEventEditor(context,
                    initialStart: _slotAt(d.localPosition.dy)),
                onSecondaryTap: (d) {
                  final start = _slotAt(d.localPosition.dy);
                  onSlotSelected(start);
                  showSlotContextMenu(context, d.globalPosition, start);
                },
                child: CustomPaint(
                  painter: _SlotPainter(
                    hourHeight: _hourHeight,
                    selectedSlot: slot == null
                        ? null
                        : minuteOfDay(slot, day) ~/ _slotMinutes,
                  ),
                ),
              ),
            ),
            for (final s in segments)
              _positionedBlock(s, layout[s.occurrence.key]!, usableWidth),
            if (current != null)
              Positioned(
                left: 0,
                right: 0,
                top: minuteOfDay(current, day) * _hourHeight / 60 - 4.5,
                height: 9,
                child: const IgnorePointer(child: _NowLine()),
              ),
          ],
        );
      },
    );
  }

  Widget _positionedBlock(DaySegment s, OverlapSlot slot, double width) {
    const total = 24 * _hourHeight;
    final top = minuteOfDay(s.start, day) * _hourHeight / 60;
    final bottom = minuteOfDay(s.end, day) * _hourHeight / 60;
    final height =
        math.min(math.max(bottom - top, _slotHeight), total - top) - 1;
    final columnWidth = width / slot.columns;
    return Positioned(
      key: ValueKey(s.occurrence.key),
      left: slot.column * columnWidth + 1,
      width: math.max(0.0, columnWidth - 2),
      top: top,
      height: math.max(0.0, height),
      child: EventInteraction(
        occurrence: s.occurrence,
        onSelected: onEventSelected,
        child: EventBlock(
          segment: s,
          selected: s.occurrence.key == selectedKey,
          height: height,
        ),
      ),
    );
  }
}

/// Paints working hours, hour lines, dotted half-hour lines and the
/// selected slot of a day column.
class _SlotPainter extends CustomPainter {
  final double hourHeight;
  final int? selectedSlot;

  const _SlotPainter({required this.hourHeight, required this.selectedSlot});

  static const _workStartHour = 8;
  static const _workEndHour = 17;
  static const _offHoursColor = Color(0xFFF4F7FB);
  static const _halfHourColor = Color(0xFFECECEC);

  @override
  void paint(Canvas canvas, Size size) {
    final offHours = Paint()..color = _offHoursColor;
    canvas
      ..drawRect(
          Rect.fromLTWH(0, 0, size.width, _workStartHour * hourHeight), offHours)
      ..drawRect(
          Rect.fromLTRB(0, _workEndHour * hourHeight, size.width, size.height),
          offHours);

    final slot = selectedSlot;
    if (slot != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, slot * hourHeight / 2, size.width, hourHeight / 2),
        Paint()..color = OutlookTheme.selectedItemBackground,
      );
    }

    final hourLines = Path();
    final halfHourDots = Path();
    for (var hour = 0; hour < 24; hour++) {
      final y = hour * hourHeight + 0.5;
      hourLines
        ..moveTo(0, y)
        ..lineTo(size.width, y);
      final half = y + hourHeight / 2;
      for (var x = 0.0; x < size.width; x += 4) {
        halfHourDots
          ..moveTo(x, half)
          ..lineTo(math.min(x + 2, size.width), half);
      }
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas
      ..drawPath(halfHourDots, stroke..color = _halfHourColor)
      ..drawPath(hourLines, stroke..color = _gridLineColor)
      ..drawLine(const Offset(0.5, 0), Offset(0.5, size.height),
          stroke..color = OutlookTheme.dividerColor);
  }

  @override
  bool shouldRepaint(_SlotPainter old) =>
      old.hourHeight != hourHeight || old.selectedSlot != selectedSlot;
}

/// The red current-time marker.
class _NowLine extends StatelessWidget {
  const _NowLine();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 3.5,
          height: 2,
          child: ColoredBox(color: OutlookTheme.flaggedColor),
        ),
        Positioned(
          left: 0,
          top: 0,
          width: 9,
          height: 9,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: OutlookTheme.flaggedColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}
