import 'package:flutter/material.dart';

import '../../models/contact.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';

/// Text styles shared by the People module.
class PeopleStyles {
  PeopleStyles._();

  /// A contact or group name in a list row.
  static const TextStyle itemName = TextStyle(
    fontFamily: OutlookTheme.fontFamily,
    fontFamilyFallback: OutlookTheme.fontFamilyFallback,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: OutlookTheme.textPrimary,
  );

  /// Secondary detail text (job title, company, member count).
  static const TextStyle secondary = TextStyle(
    fontFamily: OutlookTheme.fontFamily,
    fontFamilyFallback: OutlookTheme.fontFamilyFallback,
    fontSize: 12,
    color: OutlookTheme.textSecondary,
  );

  /// Muted detail text (email addresses in lists, field labels).
  static const TextStyle muted = TextStyle(
    fontFamily: OutlookTheme.fontFamily,
    fontFamilyFallback: OutlookTheme.fontFamilyFallback,
    fontSize: 12,
    color: OutlookTheme.textMuted,
  );

  /// Body text in the detail pane.
  static const TextStyle body = TextStyle(
    fontFamily: OutlookTheme.fontFamily,
    fontFamilyFallback: OutlookTheme.fontFamilyFallback,
    fontSize: 13,
    color: OutlookTheme.textPrimary,
    height: 1.4,
  );

  /// Small blue section header ("Email", "Phone", ...).
  static const TextStyle sectionHeader = TextStyle(
    fontFamily: OutlookTheme.fontFamily,
    fontFamilyFallback: OutlookTheme.fontFamilyFallback,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: OutlookTheme.primaryBlue,
    letterSpacing: 0.3,
  );

  /// Inline validation and error messages.
  static const TextStyle error = TextStyle(
    fontFamily: OutlookTheme.fontFamily,
    fontFamilyFallback: OutlookTheme.fontFamilyFallback,
    fontSize: 12,
    color: OutlookTheme.flaggedColor,
  );
}

/// The avatar for [contact]: its initials, colored by its primary email
/// (so it matches the sender avatar in mail) or, failing that, its name.
class ContactAvatar extends StatelessWidget {
  /// The contact to draw.
  final Contact contact;

  /// Diameter in logical pixels.
  final double size;

  const ContactAvatar({super.key, required this.contact, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return InitialsAvatar(
      initials: contact.initials,
      seed: contact.primaryEmail ?? contact.displayName,
      size: size,
    );
  }
}

/// A round badge with a group icon, used for contact groups.
class GroupAvatar extends StatelessWidget {
  /// Diameter in logical pixels.
  final double size;

  const GroupAvatar({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: OutlookTheme.primaryBlue.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(Icons.groups,
          size: size * 0.55, color: OutlookTheme.primaryBlue),
    );
  }
}

/// A small blue section header with a hairline rule underneath.
class PeopleSectionHeader extends StatelessWidget {
  /// Header text.
  final String label;

  const PeopleSectionHeader(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20, bottom: 8),
      padding: const EdgeInsets.only(bottom: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OutlookTheme.dividerColor)),
      ),
      child: Text(label, style: PeopleStyles.sectionHeader),
    );
  }
}

/// A muted icon and message shown when there is nothing to display.
class PeopleEmptyState extends StatelessWidget {
  /// The large muted icon.
  final IconData icon;

  /// The main message.
  final String title;

  /// Optional hint underneath [title].
  final String? message;

  /// Optional action (e.g. a "Clear search" button).
  final Widget? action;

  const PeopleEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 48, color: OutlookTheme.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: OutlookTheme.fontFamily,
                fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                fontSize: 14,
                color: OutlookTheme.textMuted,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(message!,
                  textAlign: TextAlign.center, style: PeopleStyles.muted),
            ],
            if (action != null) ...[
              const SizedBox(height: 12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Link-styled text that underlines on hover and runs [onTap] when clicked.
class PeopleLink extends StatefulWidget {
  /// The link text.
  final String text;

  /// Called when the link is clicked.
  final VoidCallback onTap;

  /// Optional tooltip.
  final String? tooltip;

  const PeopleLink(
    this.text, {
    super.key,
    required this.onTap,
    this.tooltip,
  });

  @override
  State<PeopleLink> createState() => _PeopleLinkState();
}

class _PeopleLinkState extends State<PeopleLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Widget link = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.text,
          overflow: TextOverflow.ellipsis,
          style: PeopleStyles.body.copyWith(
            color: OutlookTheme.textLink,
            decoration:
                _hovered ? TextDecoration.underline : TextDecoration.none,
            decorationColor: OutlookTheme.textLink,
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      link = Tooltip(message: widget.tooltip!, child: link);
    }
    return link;
  }
}

/// Returns [value] trimmed, or null when it is empty.
String? cleanText(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// "Job title, Company" (or whichever of the two is set) for [contact],
/// or null when neither is set.
String? contactSubtitle(Contact contact) {
  final parts = [cleanText(contact.jobTitle), cleanText(contact.company)]
      .whereType<String>()
      .toList();
  if (parts.isEmpty) return null;
  // Avoid "Acme, Acme" for company-only contacts whose name is the company.
  if (parts.length == 1 && parts.first == contact.displayName) return null;
  return parts.join(', ');
}

/// "1 member" / "N members".
String memberCountLabel(int count) =>
    count == 1 ? '1 member' : '$count members';
