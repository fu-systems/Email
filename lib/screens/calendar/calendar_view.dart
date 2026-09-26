import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/calendar_provider.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';
import 'calendar_actions.dart';
import 'calendar_sidebar.dart';
import 'month_view.dart';
import 'time_grid_view.dart';

export 'calendar_actions.dart'
    show deleteOccurrenceWithPrompt, emailAttendees, openEventEditor;
export 'calendar_io.dart' show exportCalendarFile, importCalendarFile;
export 'event_editor_dialog.dart' show EventEditorDialog;

/// The Calendar module: the date navigator and upcoming appointments on
/// the left, and the Day / Work Week / Week / Month view on the right.
///
/// Keyboard: Delete deletes the selected appointment (after asking), Enter
/// opens it.
class CalendarView extends StatelessWidget {
  const CalendarView({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CalendarKeyboardScope(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CalendarSidebar(),
          Expanded(child: _CalendarMain()),
        ],
      ),
    );
  }
}

/// Gives the calendar keyboard focus when clicked and handles its keys.
class _CalendarKeyboardScope extends StatefulWidget {
  final Widget child;

  const _CalendarKeyboardScope({required this.child});

  @override
  State<_CalendarKeyboardScope> createState() => _CalendarKeyboardScopeState();
}

class _CalendarKeyboardScopeState extends State<_CalendarKeyboardScope> {
  final _focusNode = FocusNode(debugLabel: 'Calendar');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _deleteSelected() {
    final occurrence = context.read<CalendarProvider>().selectedOccurrence;
    if (occurrence != null) deleteOccurrenceWithPrompt(context, occurrence);
  }

  void _openSelected() {
    final occurrence = context.read<CalendarProvider>().selectedOccurrence;
    if (occurrence != null) openEventEditor(context, occurrence: occurrence);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
        const SingleActivator(LogicalKeyboardKey.enter): _openSelected,
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: Listener(
          onPointerDown: (_) {
            if (!_focusNode.hasFocus) _focusNode.requestFocus();
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// Header row plus the current view.
class _CalendarMain extends StatelessWidget {
  const _CalendarMain();

  @override
  Widget build(BuildContext context) {
    final viewType =
        context.select<CalendarProvider, CalendarViewType>((c) => c.viewType);
    return ColoredBox(
      color: OutlookTheme.readingPaneBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CalendarHeader(),
          Expanded(
            child: viewType == CalendarViewType.month
                ? const MonthView()
                : const TimeGridView(),
          ),
        ],
      ),
    );
  }
}

/// ◀ ▶ Today, the date range title and the Day | Work Week | Week | Month
/// switch.
class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader();

  @override
  Widget build(BuildContext context) {
    final cal = context.watch<CalendarProvider>();
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OutlookTheme.dividerColor)),
      ),
      child: Row(
        children: [
          HoverButton(
            icon: Icons.chevron_left,
            tooltip: 'Previous',
            iconSize: 20,
            color: OutlookTheme.textSecondary,
            padding: const EdgeInsets.all(3),
            onTap: cal.goToPrevious,
          ),
          HoverButton(
            icon: Icons.chevron_right,
            tooltip: 'Next',
            iconSize: 20,
            color: OutlookTheme.textSecondary,
            padding: const EdgeInsets.all(3),
            onTap: cal.goToNext,
          ),
          const SizedBox(width: 4),
          HoverButton(
            icon: Icons.today,
            label: 'Today',
            tooltip: 'Go to today',
            onTap: cal.goToToday,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              cal.rangeTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OutlookTheme.readingPaneSubject,
            ),
          ),
          const SizedBox(width: 12),
          _ViewSwitcher(current: cal.viewType, onChanged: cal.setViewType),
        ],
      ),
    );
  }
}

/// Segmented Day | Work Week | Week | Month control.
class _ViewSwitcher extends StatelessWidget {
  final CalendarViewType current;
  final ValueChanged<CalendarViewType> onChanged;

  const _ViewSwitcher({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        border: Border.all(color: OutlookTheme.dividerColor),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final type in CalendarViewType.values)
            HoverButton(
              label: type.label,
              selected: type == current,
              color: type == current
                  ? OutlookTheme.primaryBlue
                  : OutlookTheme.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              onTap: () => onChanged(type),
            ),
        ],
      ),
    );
  }
}
