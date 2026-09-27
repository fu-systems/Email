import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/contact.dart';
import '../../models/email_message.dart';
import '../../providers/contacts_provider.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';
import 'contact_actions.dart';
import 'contacts_common.dart';

/// Right-hand pane of the People module: the selected contact's card, the
/// selected group's members, or an empty state.
class ContactDetailPane extends StatelessWidget {
  const ContactDetailPane({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContactsProvider>();
    Widget content;
    if (provider.showGroups) {
      final selected = provider.selectedGroup;
      // Look the group up again so the pane always shows the saved version.
      final group = selected == null
          ? null
          : provider.groups.where((g) => g.id == selected.id).firstOrNull;
      content = group == null
          ? const PeopleEmptyState(
              icon: Icons.groups_outlined,
              title: 'Select a contact group to see its members',
            )
          : _GroupCard(group: group);
    } else {
      final selected = provider.selectedContact;
      final contact =
          selected == null ? null : provider.contactsById[selected.id];
      content = contact == null
          ? const PeopleEmptyState(
              icon: Icons.person_outline,
              title: 'Select a contact to see the details',
            )
          : _ContactCard(contact: contact);
    }
    return ColoredBox(
      color: OutlookTheme.readingPaneBackground,
      child: content,
    );
  }
}

/// Scrollable, width-limited column used by both cards.
class _CardScroll extends StatelessWidget {
  final List<Widget> children;

  const _CardScroll({required this.children});

  @override
  Widget build(BuildContext context) {
    // Desktop scroll behavior adds the scrollbar.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Avatar, title lines and an action row.
class _CardHeader extends StatelessWidget {
  final Widget avatar;
  final String title;
  final List<String> subtitles;
  final List<Widget> actions;

  const _CardHeader({
    required this.avatar,
    required this.title,
    required this.subtitles,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatar,
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(title, style: OutlookTheme.readingPaneSubject),
              for (final line in subtitles)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(line, style: PeopleStyles.secondary),
                ),
              const SizedBox(height: 10),
              // Offset the buttons' padding so their icons line up with
              // the title.
              Transform.translate(
                offset: const Offset(-8, 0),
                child: Wrap(spacing: 4, runSpacing: 4, children: actions),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A "label   value" line in a card section.
class _DetailRow extends StatelessWidget {
  final String label;
  final Widget value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                overflow: TextOverflow.ellipsis, style: PeopleStyles.muted),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final Contact contact;

  const _ContactCard({required this.contact});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContactsProvider>();
    final memberOf = groupsContaining(provider, contact);
    final jobTitle = cleanText(contact.jobTitle);
    final company = cleanText(contact.company);
    final address = contact.address;
    final notes = cleanText(contact.notes);
    final hasDetails = contact.emails.isNotEmpty ||
        contact.phones.isNotEmpty ||
        (address != null && !address.isEmpty) ||
        notes != null;

    return _CardScroll(
      children: [
        _CardHeader(
          avatar: ContactAvatar(contact: contact, size: 72),
          title: contact.displayName,
          subtitles: [
            ?jobTitle,
            if (company != null && company != contact.displayName) company,
          ],
          actions: [
            HoverButton(
              icon: Icons.mail_outline,
              label: 'Email',
              tooltip: contact.primaryEmail == null
                  ? 'This contact has no email address'
                  : 'Send an email to ${contact.primaryEmail}',
              onTap: contact.primaryEmail == null
                  ? null
                  : () => emailContact(context, contact),
            ),
            HoverButton(
              icon: Icons.edit_outlined,
              label: 'Edit',
              onTap: () => openContactEditor(context, contact: contact),
            ),
            HoverButton(
              icon: Icons.delete_outline,
              label: 'Delete',
              onTap: () => deleteContactWithPrompt(context, contact),
            ),
          ],
        ),
        if (contact.emails.isNotEmpty) ...[
          const PeopleSectionHeader('Email'),
          for (final email in contact.emails)
            _DetailRow(
              label: email.label,
              value: Align(
                alignment: Alignment.centerLeft,
                child: PeopleLink(
                  email.address,
                  tooltip: 'Send an email to ${email.address}',
                  onTap: () =>
                      emailContact(context, contact, address: email.address),
                ),
              ),
            ),
        ],
        if (contact.phones.isNotEmpty) ...[
          const PeopleSectionHeader('Phone'),
          for (final phone in contact.phones)
            _DetailRow(
              label: phone.label,
              value: SelectableText(phone.number, style: PeopleStyles.body),
            ),
        ],
        if (address != null && !address.isEmpty) ...[
          const PeopleSectionHeader('Address'),
          SelectableText(address.formatted, style: PeopleStyles.body),
        ],
        if (notes != null) ...[
          const PeopleSectionHeader('Notes'),
          SelectableText(notes, style: PeopleStyles.body),
        ],
        if (memberOf.isNotEmpty) ...[
          const PeopleSectionHeader('Member of'),
          for (final group in memberOf)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const GroupAvatar(size: 22),
                  const SizedBox(width: 8),
                  Flexible(
                    child: PeopleLink(
                      group.name,
                      tooltip: 'Show this contact group',
                      onTap: () {
                        provider.setShowGroups(true);
                        provider.selectGroup(group);
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (!hasDetails && memberOf.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 28),
            child: Text(
              'No contact details yet. Click Edit to add an email address '
              'or phone number.',
              style: PeopleStyles.muted,
            ),
          ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  final ContactGroup group;

  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContactsProvider>();
    final byId = provider.contactsById;
    final members = [
      for (final id in group.memberIds)
        ?byId[id],
    ];
    final notes = cleanText(group.notes);
    final canEmail = provider.groupAddresses(group).isNotEmpty;
    final count = members.length + group.extraAddresses.length;

    return _CardScroll(
      children: [
        _CardHeader(
          avatar: const GroupAvatar(size: 72),
          title: group.name,
          subtitles: [memberCountLabel(count)],
          actions: [
            HoverButton(
              icon: Icons.mail_outline,
              label: 'Email Group',
              tooltip: canEmail
                  ? 'Send an email to everyone in this group'
                  : 'No member has an email address',
              onTap: canEmail ? () => emailGroup(context, group) : null,
            ),
            HoverButton(
              icon: Icons.edit_outlined,
              label: 'Edit',
              onTap: () => openGroupEditor(context, group: group),
            ),
            HoverButton(
              icon: Icons.delete_outline,
              label: 'Delete',
              onTap: () => deleteGroupWithPrompt(context, group),
            ),
          ],
        ),
        if (notes != null) ...[
          const PeopleSectionHeader('Notes'),
          SelectableText(notes, style: PeopleStyles.body),
        ],
        const PeopleSectionHeader('Members'),
        if (count == 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'This group has no members yet. Click Edit to add some.',
              style: PeopleStyles.muted,
            ),
          ),
        for (final contact in members)
          _MemberRow(
            avatar: ContactAvatar(contact: contact, size: 32),
            name: contact.displayName,
            email: contact.primaryEmail ?? 'No email address',
            onRemove: () =>
                removeGroupMember(provider, group, contactId: contact.id),
          ),
        for (final extra in group.extraAddresses)
          _extraMemberRow(provider, extra),
      ],
    );
  }

  Widget _extraMemberRow(ContactsProvider provider, String extra) {
    final parsed = EmailAddress.parse(extra);
    return _MemberRow(
      avatar: InitialsAvatar(
        initials: InitialsAvatar.initialsFor(parsed.display),
        seed: parsed.address,
        size: 32,
      ),
      name: parsed.display,
      email: parsed.displayName == null ? null : parsed.address,
      onRemove: () => removeGroupMember(provider, group, address: extra),
    );
  }
}

/// A group member: avatar, name, email and a remove button.
class _MemberRow extends StatefulWidget {
  final Widget avatar;
  final String name;
  final String? email;
  final VoidCallback onRemove;

  const _MemberRow({
    required this.avatar,
    required this.name,
    required this.email,
    required this.onRemove,
  });

  @override
  State<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends State<_MemberRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        color: _hovered ? OutlookTheme.hoverColor : Colors.transparent,
        child: Row(
          children: [
            widget.avatar,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.name,
                      overflow: TextOverflow.ellipsis,
                      style: PeopleStyles.itemName),
                  if (widget.email != null)
                    Text(widget.email!,
                        overflow: TextOverflow.ellipsis,
                        style: PeopleStyles.muted),
                ],
              ),
            ),
            HoverButton(
              icon: Icons.close,
              iconSize: 14,
              tooltip: 'Remove ${widget.name} from this group',
              color: OutlookTheme.textSecondary,
              padding: const EdgeInsets.all(5),
              onTap: widget.onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
