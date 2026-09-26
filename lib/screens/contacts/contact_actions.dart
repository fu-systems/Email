import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/contact.dart';
import '../../models/email_message.dart';
import '../../providers/contacts_provider.dart';
import '../../widgets/common.dart';
import '../mail/compose_launcher.dart';
import 'contact_editor_dialog.dart';
import 'group_editor_dialog.dart';

// Actions on contacts and contact groups shared by the People list, the
// detail pane and the ribbon.

/// Opens [ContactEditorDialog] for [contact], or for a new contact when
/// [contact] is null. Returns the saved contact, or null when cancelled.
Future<Contact?> openContactEditor(BuildContext context, {Contact? contact}) {
  return showDialog<Contact>(
    context: context,
    builder: (_) => ContactEditorDialog(contact: contact),
  );
}

/// Opens [ContactGroupEditorDialog] for [group], or for a new group when
/// [group] is null. Returns the saved group, or null when cancelled.
Future<ContactGroup?> openGroupEditor(
  BuildContext context, {
  ContactGroup? group,
}) {
  return showDialog<ContactGroup>(
    context: context,
    builder: (_) => ContactGroupEditorDialog(group: group),
  );
}

/// The recipient for [contact] at [address] (default: its primary email),
/// with the contact's name as display name when it has one.
EmailAddress contactRecipient(Contact contact, [String? address]) {
  final email = address ?? contact.primaryEmail ?? '';
  final name = contact.displayName;
  return EmailAddress(
    address: email,
    displayName: name == email || name == 'Unknown' ? null : name,
  );
}

/// Recipients of [group]: the primary email of each member contact (with its
/// name) followed by the group's one-off addresses, without duplicates.
/// Members that were deleted or have no email address are skipped.
List<EmailAddress> groupRecipients(
  ContactGroup group,
  Map<String, Contact> contactsById,
) {
  final seen = <String>{};
  final result = <EmailAddress>[];
  for (final id in group.memberIds) {
    final contact = contactsById[id];
    final email = contact?.primaryEmail;
    if (contact == null || email == null) continue;
    if (seen.add(email.toLowerCase())) {
      result.add(contactRecipient(contact, email));
    }
  }
  for (final extra in group.extraAddresses) {
    final parsed = EmailAddress.parse(extra);
    if (parsed.address.isNotEmpty && seen.add(parsed.address.toLowerCase())) {
      result.add(parsed);
    }
  }
  return result;
}

/// Starts a new message to [contact] at [address] (default: its primary
/// email). Does nothing when the contact has no email address.
Future<void> emailContact(
  BuildContext context,
  Contact contact, {
  String? address,
}) async {
  final email = address ?? contact.primaryEmail;
  if (email == null || email.trim().isEmpty) return;
  await openNewMessage(context, to: [contactRecipient(contact, email)]);
}

/// Starts a new message to every member of [group].
Future<void> emailGroup(BuildContext context, ContactGroup group) async {
  final recipients =
      groupRecipients(group, context.read<ContactsProvider>().contactsById);
  if (recipients.isEmpty) {
    showStatusMessage(
        context, '"${group.name}" has no members with an email address.');
    return;
  }
  await openNewMessage(context, to: recipients);
}

/// Adds [contact] to [group] and keeps the contact selected.
void addContactToGroup(
  BuildContext context,
  Contact contact,
  ContactGroup group,
) {
  final provider = context.read<ContactsProvider>();
  if (group.memberIds.contains(contact.id)) return;
  final previous = provider.selectedContact;
  provider.saveGroup(group.copyWith(
    memberIds: [...group.memberIds, contact.id],
    updatedAt: DateTime.now(),
  ));
  // saveGroup selects the group; in the contacts list, keep the selection.
  if (!provider.showGroups) {
    provider.selectContact(
        previous == null ? null : provider.contactsById[previous.id]);
  }
  showStatusMessage(
      context, 'Added ${contact.displayName} to "${group.name}".');
}

/// Removes a member from [group]: the contact with [contactId], or the
/// one-off [address].
void removeGroupMember(
  ContactsProvider provider,
  ContactGroup group, {
  String? contactId,
  String? address,
}) {
  provider.saveGroup(ContactGroup(
    id: group.id,
    name: group.name,
    memberIds: group.memberIds.where((id) => id != contactId).toList(),
    extraAddresses: group.extraAddresses.where((a) => a != address).toList(),
    notes: group.notes,
    createdAt: group.createdAt,
    updatedAt: DateTime.now(),
  ));
}

/// The groups that [contact] belongs to.
List<ContactGroup> groupsContaining(
  ContactsProvider provider,
  Contact contact,
) =>
    provider.groups.where((g) => g.memberIds.contains(contact.id)).toList();

/// Asks for confirmation, then deletes [contact] (which also removes it from
/// every contact group).
Future<void> deleteContactWithPrompt(
  BuildContext context,
  Contact contact,
) async {
  final provider = context.read<ContactsProvider>();
  final groupCount = groupsContaining(provider, contact).length;
  final groupNote = switch (groupCount) {
    0 => '',
    1 => ' It will also be removed from 1 contact group.',
    _ => ' It will also be removed from $groupCount contact groups.',
  };
  final confirmed = await showConfirmDialog(
    context,
    title: 'Delete Contact',
    message: 'Delete the contact "${contact.displayName}"?$groupNote',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!confirmed) return;
  provider.removeContact(contact.id);
}

/// Asks for confirmation, then deletes [group]. Its member contacts are
/// kept.
Future<void> deleteGroupWithPrompt(
  BuildContext context,
  ContactGroup group,
) async {
  final provider = context.read<ContactsProvider>();
  final confirmed = await showConfirmDialog(
    context,
    title: 'Delete Contact Group',
    message: 'Delete the contact group "${group.name}"? '
        'The contacts in it will not be deleted.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!confirmed) return;
  provider.removeGroup(group.id);
}

enum _ContactMenu { email, edit, addToGroup, delete }

enum _GroupMenu { email, edit, delete }

/// Shows the right-click menu for [contact] at [position]: Email, Edit,
/// Add to Group ▸ (a second menu listing the groups) and Delete.
Future<void> showContactContextMenu(
  BuildContext context,
  Offset position,
  Contact contact,
) async {
  final provider = context.read<ContactsProvider>();
  final groups = provider.groups;
  final hasEmail = contact.primaryEmail != null;
  final choice = await showContextMenu<_ContactMenu>(context, position, [
    MenuAction(_ContactMenu.email, 'Email',
        icon: Icons.mail_outline, enabled: hasEmail),
    const MenuAction(_ContactMenu.edit, 'Edit', icon: Icons.edit_outlined),
    MenuAction(_ContactMenu.addToGroup, 'Add to Group',
        icon: Icons.group_add_outlined,
        enabled: hasEmail && groups.isNotEmpty,
        shortcut: '▸',
        dividerBefore: true),
    const MenuAction(_ContactMenu.delete, 'Delete',
        icon: Icons.delete_outline, dividerBefore: true),
  ]);
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _ContactMenu.email:
      await emailContact(context, contact);
    case _ContactMenu.edit:
      await openContactEditor(context, contact: contact);
    case _ContactMenu.addToGroup:
      final groupId = await showContextMenu<String>(context, position, [
        for (final g in groups)
          MenuAction(
            g.id,
            g.name,
            icon: g.memberIds.contains(contact.id)
                ? Icons.check
                : Icons.groups_outlined,
            enabled: !g.memberIds.contains(contact.id),
          ),
      ]);
      final group = groups.where((g) => g.id == groupId).firstOrNull;
      if (group != null && context.mounted) {
        addContactToGroup(context, contact, group);
      }
    case _ContactMenu.delete:
      await deleteContactWithPrompt(context, contact);
  }
}

/// Shows the right-click menu for [group] at [position]: Email Group, Edit
/// and Delete.
Future<void> showGroupContextMenu(
  BuildContext context,
  Offset position,
  ContactGroup group,
) async {
  final provider = context.read<ContactsProvider>();
  final canEmail = provider.groupAddresses(group).isNotEmpty;
  final choice = await showContextMenu<_GroupMenu>(context, position, [
    MenuAction(_GroupMenu.email, 'Email Group',
        icon: Icons.mail_outline, enabled: canEmail),
    const MenuAction(_GroupMenu.edit, 'Edit', icon: Icons.edit_outlined),
    const MenuAction(_GroupMenu.delete, 'Delete',
        icon: Icons.delete_outline, dividerBefore: true),
  ]);
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _GroupMenu.email:
      await emailGroup(context, group);
    case _GroupMenu.edit:
      await openGroupEditor(context, group: group);
    case _GroupMenu.delete:
      await deleteGroupWithPrompt(context, group);
  }
}
