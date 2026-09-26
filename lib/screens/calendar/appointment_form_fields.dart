/// Building blocks of the appointment form (EventEditorDialog): labeled
/// rows, Outlook-style dropdowns, a date field and the series end control.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/calendar_event.dart';
import '../../theme/outlook_theme.dart';
import 'calendar_layout.dart';

/// Width of the label column of a [FormRow].
const double formLabelWidth = 84;

const _fieldTextStyle = TextStyle(fontSize: 13);

/// A form row: fixed-width label on the left, the field on the right.
class FormRow extends StatelessWidget {
  final String label;
  final Widget child;

  /// Aligns the label with the top of a tall field (e.g. Notes).
  final bool alignTop;

  const FormRow({
    super.key,
    required this.label,
    required this.child,
    this.alignTop = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          alignTop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: formLabelWidth,
          child: Padding(
            padding: EdgeInsets.only(top: alignTop ? 8 : 0),
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 13, color: OutlookTheme.textSecondary),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// A single-line, ellipsized dropdown entry.
Widget dropdownItemText(String text) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, color: OutlookTheme.textPrimary),
    );

/// A controlled dropdown styled like the form's text fields.
class FormDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;
  final DropdownButtonBuilder? selectedItemBuilder;

  const FormDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.selectedItemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          selectedItemBuilder: selectedItemBuilder,
          isDense: true,
          isExpanded: true,
          menuMaxHeight: 320,
          iconSize: 18,
          // DropdownButton.style replaces (rather than merges with) the
          // default text style, so start from the theme to keep its font.
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                color: OutlookTheme.textPrimary,
              ),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// Time-of-day dropdown with 30-minute slots ("9:00 AM"); a [minutes]
/// value between slots is added to the list. When [durationFrom] is set,
/// later entries also show the duration from that time
/// ("10:00 AM (1 hour)"), as Outlook does for the end time.
class TimeSlotDropdown extends StatelessWidget {
  final int minutes;
  final ValueChanged<int> onChanged;
  final int? durationFrom;

  const TimeSlotDropdown({
    super.key,
    required this.minutes,
    required this.onChanged,
    this.durationFrom,
  });

  @override
  Widget build(BuildContext context) {
    final values = {for (var m = 0; m < 24 * 60; m += 30) m, minutes}.toList()
      ..sort();
    String label(int m) {
      final from = durationFrom;
      if (from == null || m < from) return formatMinutes(m);
      final length = formatDuration(Duration(minutes: m - from));
      return '${formatMinutes(m)} ($length)';
    }

    return FormDropdown<int>(
      value: minutes,
      items: [
        for (final m in values)
          DropdownMenuItem(value: m, child: dropdownItemText(label(m))),
      ],
      selectedItemBuilder: (_) => [
        for (final m in values)
          Align(
            alignment: Alignment.centerLeft,
            child: dropdownItemText(formatMinutes(m)),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// A button showing a date ("Wed 3/11/2026") that opens a date picker.
class DateField extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  const DateField({super.key, required this.date, required this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dateOnly(date),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () => _pick(context),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 33),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              formatShortDate(date),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _fieldTextStyle,
            ),
          ),
          const Icon(Icons.calendar_today,
              size: 14, color: OutlookTheme.textSecondary),
        ],
      ),
    );
  }
}

/// A checkbox with a clickable label.
class LabeledCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Key of the [Checkbox] itself.
  final Key? checkboxKey;

  const LabeledCheckbox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.checkboxKey,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Checkbox(
            key: checkboxKey,
            value: value,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => onChanged(v ?? false),
          ),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _fieldTextStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Category name with its color swatch.
class CategoryLabel extends StatelessWidget {
  final EventCategory category;

  const CategoryLabel(this.category, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: category.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: dropdownItemText(category.displayName)),
      ],
    );
  }
}

/// How a recurring series ends.
enum SeriesEnd { never, onDate, afterCount }

/// "End: ( ) Never  ( ) On [date]  ( ) After [N] occurrences".
class SeriesEndField extends StatelessWidget {
  final SeriesEnd mode;
  final DateTime until;

  /// Text of the occurrence count field.
  final TextEditingController countController;
  final ValueChanged<SeriesEnd> onModeChanged;
  final ValueChanged<DateTime> onUntilChanged;

  const SeriesEndField({
    super.key,
    required this.mode,
    required this.until,
    required this.countController,
    required this.onModeChanged,
    required this.onUntilChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget option(SeriesEnd value, List<Widget> children) => Row(
          children: [
            Radio<SeriesEnd>(
              value: value,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            ...children,
          ],
        );

    Widget label(SeriesEnd value, String text) => GestureDetector(
          onTap: () => onModeChanged(value),
          child: Text(text, style: _fieldTextStyle),
        );

    return RadioGroup<SeriesEnd>(
      groupValue: mode,
      onChanged: (v) {
        if (v != null) onModeChanged(v);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          option(SeriesEnd.never, [label(SeriesEnd.never, 'Never')]),
          const SizedBox(height: 4),
          option(SeriesEnd.onDate, [
            label(SeriesEnd.onDate, 'On'),
            const SizedBox(width: 8),
            SizedBox(
              width: 170,
              child: DateField(
                date: until,
                onChanged: (d) {
                  onUntilChanged(d);
                  onModeChanged(SeriesEnd.onDate);
                },
              ),
            ),
          ]),
          const SizedBox(height: 4),
          option(SeriesEnd.afterCount, [
            label(SeriesEnd.afterCount, 'After'),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: TextField(
                controller: countController,
                style: _fieldTextStyle,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                onTap: () => onModeChanged(SeriesEnd.afterCount),
              ),
            ),
            const SizedBox(width: 8),
            label(SeriesEnd.afterCount, 'occurrences'),
          ]),
        ],
      ),
    );
  }
}

/// A light yellow information bar.
class InfoBar extends StatelessWidget {
  final String text;

  const InfoBar(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4CE),
        border: Border.all(color: const Color(0xFFF2DE9B)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline,
              size: 14, color: OutlookTheme.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, color: OutlookTheme.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// A validation message under a [FormRow]'s field.
class FieldError extends StatelessWidget {
  final String text;

  const FieldError(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: formLabelWidth, top: 4),
      child: Text(text,
          style: const TextStyle(
              fontSize: 12, color: OutlookTheme.flaggedColor)),
    );
  }
}
