import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/calendar_event.dart';
import '../../providers/calendar_provider.dart';
import '../../theme/outlook_theme.dart';
import 'calendar_actions.dart';
import 'calendar_layout.dart';

/// Detects desktop-style clicks, double-clicks and right-clicks.
///
/// Unlike [GestureDetector.onDoubleTap], the first click is reported right
/// away (so selection feels instant); a second click within the
/// double-click interval is then reported through [onDoubleTap].
class ClickDetector extends StatefulWidget {
  final Widget child;
  final GestureTapUpCallback? onTap;
  final GestureTapUpCallback? onDoubleTap;
  final GestureTapUpCallback? onSecondaryTap;
  final HitTestBehavior behavior;

  const ClickDetector({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.behavior = HitTestBehavior.opaque,
  });

  /// Maximum time between the clicks of a double-click.
  static const doubleClickTime = Duration(milliseconds: 400);

  /// Maximum distance (logical pixels) between the clicks of a double-click.
  static const doubleClickSlop = 16.0;

  @override
  State<ClickDetector> createState() => _ClickDetectorState();
}

class _ClickDetectorState extends State<ClickDetector> {
  DateTime? _lastClick;
  Offset _lastPosition = Offset.zero;

  void _handleTapUp(TapUpDetails details) {
    final now = DateTime.now();
    final last = _lastClick;
    final isDouble = widget.onDoubleTap != null &&
        last != null &&
        now.difference(last) <= ClickDetector.doubleClickTime &&
        (details.globalPosition - _lastPosition).distance <=
            ClickDetector.doubleClickSlop;
    if (isDouble) {
      _lastClick = null;
      widget.onDoubleTap!(details);
    } else {
      _lastClick = now;
      _lastPosition = details.globalPosition;
      widget.onTap?.call(details);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clickable = widget.onTap != null || widget.onDoubleTap != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTapUp: clickable ? _handleTapUp : null,
      onSecondaryTapUp: widget.onSecondaryTap,
      child: widget.child,
    );
  }
}

/// Standard appointment interactions: click selects, double-click opens
/// the appointment, right-click shows its context menu.
class EventInteraction extends StatelessWidget {
  final EventOccurrence occurrence;
  final Widget child;

  /// Called after a click selected the occurrence.
  final VoidCallback? onSelected;

  const EventInteraction({
    super.key,
    required this.occurrence,
    required this.child,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ClickDetector(
      onTap: (_) {
        context.read<CalendarProvider>().selectOccurrence(occurrence);
        onSelected?.call();
      },
      onDoubleTap: (_) => openEventEditor(context, occurrence: occurrence),
      onSecondaryTap: (details) {
        onSelected?.call();
        showEventContextMenu(context, details.globalPosition, occurrence);
      },
      child: Tooltip(
        message: _tooltipFor(occurrence),
        excludeFromSemantics: true,
        child: child,
      ),
    );
  }

  static String _tooltipFor(EventOccurrence o) {
    final location = o.event.location?.trim() ?? '';
    return [
      displayTitle(o.event),
      formatOccurrenceTime(o),
      if (location.isNotEmpty) location,
    ].join('\n');
  }
}

/// Light category tint used as the background of timed appointments.
Color eventFillColor(EventCategory category) =>
    Color.alphaBlend(category.color.withValues(alpha: 0.16), Colors.white);

Color _eventBorderColor(EventCategory category) =>
    Color.alphaBlend(category.color.withValues(alpha: 0.5), Colors.white);

Color _darken(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - 0.2).clamp(0.0, 1.0)).toColor();
}

/// An appointment block in the Day / Week time grid: light category fill,
/// a color bar on the left, and as many of title, time and location as fit
/// in [height].
class EventBlock extends StatelessWidget {
  final DaySegment segment;
  final bool selected;
  final double height;

  const EventBlock({
    super.key,
    required this.segment,
    required this.selected,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final o = segment.occurrence;
    final category = o.event.category;
    final location = o.event.location?.trim() ?? '';
    final lines = ((height - 4) / 15).floor();
    return Container(
      decoration: BoxDecoration(
        color: eventFillColor(category),
        border: Border.all(
          color: selected ? _darken(category.color) : _eventBorderColor(category),
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 5, color: category.color),
          Expanded(
            child: ClipRect(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 1, 2, 0),
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  maxHeight: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle(o.event),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: OutlookTheme.textPrimary,
                        ),
                      ),
                      if (lines >= 2)
                        Text(
                          formatOccurrenceTime(o),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _detailStyle,
                        ),
                      if (lines >= 3 && location.isNotEmpty)
                        Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _detailStyle,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _detailStyle =
      TextStyle(fontSize: 11, color: OutlookTheme.textSecondary);
}

/// A single-line bar filled with the category color, used for all-day and
/// multi-day appointments in the all-day band and the month view.
class EventBar extends StatelessWidget {
  final EventOccurrence occurrence;
  final bool selected;
  final double height;

  const EventBar({
    super.key,
    required this.occurrence,
    required this.selected,
    this.height = 18,
  });

  @override
  Widget build(BuildContext context) {
    final color = occurrence.event.category.color;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        border: selected
            ? Border.all(color: const Color(0xFF1B1B1B), width: 2)
            : null,
      ),
      child: Text(
        displayTitle(occurrence.event),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// A single-line entry for a timed appointment in the month view: a
/// category dot, the start time (on the day it starts) and the title.
class EventLine extends StatelessWidget {
  final EventOccurrence occurrence;

  /// The month cell's day; the start time is shown only on the first day.
  final DateTime day;
  final bool selected;
  final double height;

  const EventLine({
    super.key,
    required this.occurrence,
    required this.day,
    required this.selected,
    this.height = 18,
  });

  @override
  Widget build(BuildContext context) {
    final color = occurrence.event.category.color;
    final showTime = isSameDate(occurrence.start, day);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: selected ? eventFillColor(occurrence.event.category) : null,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: selected ? _darken(color) : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (showTime)
                  TextSpan(
                    text: '${formatTime(occurrence.start)} ',
                    style: const TextStyle(color: OutlookTheme.textSecondary),
                  ),
                TextSpan(text: displayTitle(occurrence.event)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: OutlookTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
