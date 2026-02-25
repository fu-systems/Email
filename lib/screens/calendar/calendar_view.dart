import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../theme/outlook_theme.dart';
import '../../models/calendar_event.dart';
import '../../providers/calendar_provider.dart';

/// Calendar module — Outlook 2013-style with month grid and event list.
class CalendarView extends StatelessWidget {
  const CalendarView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        // Left pane: mini calendar
        SizedBox(
          width: OutlookTheme.folderPaneWidth + 60,
          child: _CalendarSidebar(),
        ),
        VerticalDivider(width: 1),
        // Right pane: event list for selected date
        Expanded(child: _EventListPane()),
      ],
    );
  }
}

/// Sidebar with TableCalendar month grid.
class _CalendarSidebar extends StatelessWidget {
  const _CalendarSidebar();

  @override
  Widget build(BuildContext context) {
    final cal = context.watch<CalendarProvider>();

    return Container(
      decoration: OutlookTheme.folderPaneDecoration,
      child: Column(
        children: [
          // Month calendar
          TableCalendar<CalendarEvent>(
            firstDay: DateTime(2020, 1, 1),
            lastDay: DateTime(2035, 12, 31),
            focusedDay: cal.focusedDate,
            selectedDayPredicate: (day) => isSameDay(day, cal.selectedDate),
            onDaySelected: (selected, focused) {
              cal.selectDate(selected);
              cal.setFocusedDate(focused);
            },
            onPageChanged: (focused) {
              cal.setFocusedDate(focused);
            },
            eventLoader: (day) => cal.getEventsForDate(day),
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: OutlookTheme.calendarToday.withOpacity( 0.15),
                shape: BoxShape.circle,
              ),
              todayTextStyle: const TextStyle(
                color: OutlookTheme.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
              selectedDecoration: const BoxDecoration(
                color: OutlookTheme.primaryBlue,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: const TextStyle(color: Colors.white),
              markerDecoration: const BoxDecoration(
                color: OutlookTheme.accentBlue,
                shape: BoxShape.circle,
              ),
              markerSize: 5,
              markersMaxCount: 3,
              outsideDaysVisible: true,
              outsideTextStyle: TextStyle(
                color: OutlookTheme.textMuted.withOpacity( 0.5),
              ),
              defaultTextStyle: const TextStyle(
                fontFamily: OutlookTheme.fontFamily,
                fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                fontSize: 13,
              ),
              weekendTextStyle: const TextStyle(
                fontFamily: OutlookTheme.fontFamily,
                fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                fontSize: 13,
                color: OutlookTheme.textSecondary,
              ),
            ),
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(
                fontFamily: OutlookTheme.fontFamily,
                fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: OutlookTheme.textPrimary,
              ),
              leftChevronIcon: Icon(Icons.chevron_left,
                  size: 18, color: OutlookTheme.textSecondary),
              rightChevronIcon: Icon(Icons.chevron_right,
                  size: 18, color: OutlookTheme.textSecondary),
            ),
            daysOfWeekStyle: const DaysOfWeekStyle(
              weekdayStyle: TextStyle(
                fontFamily: OutlookTheme.fontFamily,
                fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                fontSize: 11,
                color: OutlookTheme.textMuted,
              ),
              weekendStyle: TextStyle(
                fontFamily: OutlookTheme.fontFamily,
                fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                fontSize: 11,
                color: OutlookTheme.textMuted,
              ),
            ),
            calendarFormat: CalendarFormat.month,
            startingDayOfWeek: StartingDayOfWeek.sunday,
          ),
          const Divider(height: 1),
          // View type selector
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: CalendarViewType.values.map((type) {
                final isActive = cal.viewType == type;
                return Expanded(
                  child: _ViewTypeButton(
                    label: type.label,
                    isActive: isActive,
                    onTap: () => cal.setViewType(type),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          // Today button
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => cal.goToToday(),
                icon: const Icon(Icons.today, size: 14),
                label: const Text('Today'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewTypeButton extends StatefulWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ViewTypeButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_ViewTypeButton> createState() => _ViewTypeButtonState();
}

class _ViewTypeButtonState extends State<_ViewTypeButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: widget.isActive
                ? OutlookTheme.primaryBlue
                : _isHovered
                    ? OutlookTheme.hoverColor
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                fontFamily: OutlookTheme.fontFamily,
                fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                fontSize: 12,
                fontWeight:
                    widget.isActive ? FontWeight.w600 : FontWeight.w400,
                color:
                    widget.isActive ? Colors.white : OutlookTheme.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Right pane — event list for the selected date.
class _EventListPane extends StatelessWidget {
  const _EventListPane();

  @override
  Widget build(BuildContext context) {
    final cal = context.watch<CalendarProvider>();
    final events = cal.eventsForSelectedDate;
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(cal.selectedDate);

    return Container(
      color: OutlookTheme.readingPaneBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: OutlookTheme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                Text(
                  dateStr,
                  style: OutlookTheme.readingPaneSubject.copyWith(fontSize: 16),
                ),
                const Spacer(),
                _AddEventButton(
                  onTap: () => _showEventDialog(context),
                ),
              ],
            ),
          ),
          // Event list
          Expanded(
            child: events.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_available,
                            size: 48,
                            color:
                                OutlookTheme.textMuted.withOpacity( 0.4)),
                        const SizedBox(height: 12),
                        Text(
                          'No events scheduled',
                          style: TextStyle(
                            fontFamily: OutlookTheme.fontFamily,
                            fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                            fontSize: 14,
                            color: OutlookTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      return _EventTile(
                        event: events[index],
                        isSelected: cal.selectedEvent?.id == events[index].id,
                        onTap: () => cal.selectEvent(events[index]),
                        onEdit: () =>
                            _showEventDialog(context, event: events[index]),
                        onDelete: () {
                          cal.removeEvent(events[index].id);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showEventDialog(BuildContext context, {CalendarEvent? event}) {
    showDialog(
      context: context,
      builder: (_) => EventEditorDialog(event: event),
    );
  }
}

class _AddEventButton extends StatefulWidget {
  final VoidCallback onTap;

  const _AddEventButton({required this.onTap});

  @override
  State<_AddEventButton> createState() => _AddEventButtonState();
}

class _AddEventButtonState extends State<_AddEventButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _isHovered ? OutlookTheme.hoverColor : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
            border: _isHovered
                ? Border.all(color: OutlookTheme.selectedItemBorder)
                : Border.all(color: Colors.transparent),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 14, color: OutlookTheme.primaryBlue),
              SizedBox(width: 4),
              Text(
                'New Event',
                style: TextStyle(
                  fontFamily: OutlookTheme.fontFamily,
                  fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                  fontSize: 12,
                  color: OutlookTheme.primaryBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single event row in the list.
class _EventTile extends StatefulWidget {
  final CalendarEvent event;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EventTile({
    required this.event,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_EventTile> createState() => _EventTileState();
}

class _EventTileState extends State<_EventTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final timeStr = e.isAllDay
        ? 'All day'
        : '${DateFormat.jm().format(e.startTime)} - ${DateFormat.jm().format(e.endTime)}';

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onEdit,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? OutlookTheme.selectedItemBackground
                : _isHovered
                    ? OutlookTheme.hoverColor
                    : Colors.transparent,
            border: widget.isSelected
                ? Border.all(color: OutlookTheme.selectedItemBorder)
                : null,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            children: [
              // Category color bar
              Container(
                width: 4,
                height: 36,
                decoration: BoxDecoration(
                  color: e.category.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              // Event details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title.isEmpty ? '(No title)' : e.title,
                      style: const TextStyle(
                        fontFamily: OutlookTheme.fontFamily,
                        fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: OutlookTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeStr,
                      style: OutlookTheme.messageDate,
                    ),
                    if (e.location != null && e.location!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          e.location!,
                          style: OutlookTheme.messagePreview,
                        ),
                      ),
                  ],
                ),
              ),
              // Actions
              if (_isHovered || widget.isSelected) ...[
                IconButton(
                  icon: const Icon(Icons.edit, size: 16),
                  onPressed: widget.onEdit,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 28, minHeight: 28),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: OutlookTheme.flaggedColor),
                  onPressed: widget.onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 28, minHeight: 28),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Event create/edit dialog.
class EventEditorDialog extends StatefulWidget {
  final CalendarEvent? event;

  const EventEditorDialog({super.key, this.event});

  @override
  State<EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends State<EventEditorDialog> {
  late TextEditingController _titleController;
  late TextEditingController _locationController;
  late TextEditingController _descriptionController;
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;
  late bool _isAllDay;
  late EventCategory _category;
  ReminderTime? _reminder;

  bool get _isEditing => widget.event != null;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _titleController = TextEditingController(text: e?.title ?? '');
    _locationController = TextEditingController(text: e?.location ?? '');
    _descriptionController =
        TextEditingController(text: e?.description ?? '');

    if (e != null) {
      _startDate = e.startTime;
      _startTime = TimeOfDay.fromDateTime(e.startTime);
      _endDate = e.endTime;
      _endTime = TimeOfDay.fromDateTime(e.endTime);
      _isAllDay = e.isAllDay;
      _category = e.category;
      _reminder = e.reminder;
    } else {
      final cal = context.read<CalendarProvider>();
      final defaultEvent = cal.createDefaultEvent();
      _startDate = defaultEvent.startTime;
      _startTime = TimeOfDay.fromDateTime(defaultEvent.startTime);
      _endDate = defaultEvent.endTime;
      _endTime = TimeOfDay.fromDateTime(defaultEvent.endTime);
      _isAllDay = false;
      _category = EventCategory.blue;
      _reminder = ReminderTime.fifteenMinutes;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _save() {
    final cal = context.read<CalendarProvider>();
    final start = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _isAllDay ? 0 : _startTime.hour,
      _isAllDay ? 0 : _startTime.minute,
    );
    final end = DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day,
      _isAllDay ? 23 : _endTime.hour,
      _isAllDay ? 59 : _endTime.minute,
    );
    final now = DateTime.now();

    if (_isEditing) {
      cal.updateEvent(widget.event!.copyWith(
        title: _titleController.text,
        location: _locationController.text,
        description: _descriptionController.text,
        startTime: start,
        endTime: end,
        isAllDay: _isAllDay,
        category: _category,
        reminder: _reminder,
        updatedAt: now,
      ));
    } else {
      cal.addEvent(cal.createDefaultEvent().copyWith(
            title: _titleController.text,
            location: _locationController.text,
            description: _descriptionController.text,
            startTime: start,
            endTime: end,
            isAllDay: _isAllDay,
            category: _category,
            reminder: _reminder,
            createdAt: now,
            updatedAt: now,
          ));
    }
    Navigator.of(context).pop();
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: OutlookTheme.primaryBlue,
              child: Row(
                children: [
                  Text(
                    _isEditing ? 'Edit Event' : 'New Event',
                    style: OutlookTheme.titleBarStyle,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 14, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                ],
              ),
            ),
            // Form
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'Event title',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      hintText: 'Add location',
                      prefixIcon: Icon(Icons.location_on, size: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // All-day toggle
                  Row(
                    children: [
                      Checkbox(
                        value: _isAllDay,
                        onChanged: (v) =>
                            setState(() => _isAllDay = v ?? false),
                      ),
                      const Text('All day',
                          style: TextStyle(fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Start date/time
                  Row(
                    children: [
                      const SizedBox(
                          width: 50,
                          child: Text('Start:',
                              style: TextStyle(fontSize: 13))),
                      OutlinedButton(
                        onPressed: () => _pickDate(true),
                        child: Text(
                            DateFormat.yMMMd().format(_startDate),
                            style: const TextStyle(fontSize: 12)),
                      ),
                      if (!_isAllDay) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _pickTime(true),
                          child: Text(_startTime.format(context),
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  // End date/time
                  Row(
                    children: [
                      const SizedBox(
                          width: 50,
                          child: Text('End:',
                              style: TextStyle(fontSize: 13))),
                      OutlinedButton(
                        onPressed: () => _pickDate(false),
                        child: Text(
                            DateFormat.yMMMd().format(_endDate),
                            style: const TextStyle(fontSize: 12)),
                      ),
                      if (!_isAllDay) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _pickTime(false),
                          child: Text(_endTime.format(context),
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Category + reminder row
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<EventCategory>(
                          value: _category,
                          decoration:
                              const InputDecoration(labelText: 'Category'),
                          items: EventCategory.values.map((c) {
                            return DropdownMenuItem(
                              value: c,
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: c.color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(c.displayName,
                                      style:
                                          const TextStyle(fontSize: 13)),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _category = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<ReminderTime>(
                          value: _reminder ?? ReminderTime.none,
                          decoration:
                              const InputDecoration(labelText: 'Reminder'),
                          items: ReminderTime.values.map((r) {
                            return DropdownMenuItem(
                              value: r,
                              child: Text(r.displayName,
                                  style:
                                      const TextStyle(fontSize: 13)),
                            );
                          }).toList(),
                          onChanged: (v) {
                            setState(() => _reminder = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      hintText: 'Add notes',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            // Action buttons
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _save,
                    child: Text(_isEditing ? 'Save' : 'Create'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
