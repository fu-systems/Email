import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/email_message.dart';
import '../models/folder.dart';
import '../providers/calendar_provider.dart';
import '../providers/contacts_provider.dart';
import '../providers/mail_provider.dart';
import '../providers/navigation_provider.dart';
import '../services/ical_service.dart';
import '../services/print_service.dart';
import '../theme/outlook_theme.dart';
import '../widgets/common.dart';
import '../widgets/navigation_bar.dart';
import '../widgets/reading_pane.dart';
import '../widgets/ribbon/ribbon_toolbar.dart';
import '../widgets/status_bar.dart';
import 'backstage/backstage_view.dart';
import 'calendar/calendar_view.dart';
import 'contacts/contacts_view.dart';
import 'mail/compose_launcher.dart';
import 'mail/mail_dialogs.dart';
import 'mail/mail_view.dart';

/// Main application screen with the Outlook 2013 layout:
/// title bar → ribbon → module content → navigation bar → status bar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchFocus = FocusNode(debugLabel: 'mail search');
  final _rootFocus = FocusNode(debugLabel: 'home');

  @override
  void dispose() {
    _searchFocus.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  // ─── Commands ──────────────────────────────────────────────────────

  MailProvider get _mail => context.read<MailProvider>();

  EmailMessage? get _focused => _mail.selectedMessage;

  bool get _inMail =>
      context.read<NavigationProvider>().currentSection ==
      NavigationSection.mail;

  void _newItem() {
    switch (context.read<NavigationProvider>().currentSection) {
      case NavigationSection.mail:
        openNewMessage(context);
        break;
      case NavigationSection.calendar:
        _newAppointment();
        break;
      case NavigationSection.contacts:
        _newContact();
        break;
    }
  }

  void _newAppointment() => showDialog(
      context: context, builder: (_) => const EventEditorDialog());

  void _newContact() => showDialog(
      context: context, builder: (_) => const ContactEditorDialog());

  void _newContactGroup() => showDialog(
      context: context, builder: (_) => const ContactGroupEditorDialog());

  void _reply({bool all = false}) {
    final m = _focused;
    if (m == null || !_inMail || m.id.startsWith('outbox|')) return;
    openReply(context, m, replyAll: all);
  }

  void _forward() {
    final m = _focused;
    if (m == null || !_inMail || m.id.startsWith('outbox|')) return;
    openForward(context, m);
  }

  Future<void> _delete() {
    final section = context.read<NavigationProvider>().currentSection;
    switch (section) {
      case NavigationSection.mail:
        return _mail.deleteMessage();
      case NavigationSection.calendar:
        final occurrence = context.read<CalendarProvider>().selectedOccurrence;
        return occurrence == null
            ? Future.value()
            : deleteOccurrenceWithPrompt(context, occurrence);
      case NavigationSection.contacts:
        final contacts = context.read<ContactsProvider>();
        if (contacts.selectedContact != null) {
          return deleteContactWithPrompt(context, contacts.selectedContact!);
        } else if (contacts.selectedGroup != null) {
          return deleteGroupWithPrompt(context, contacts.selectedGroup!);
        }
        return Future.value();
    }
  }

  Future<void> _moveToJunk() async {
    final m = _focused;
    if (m == null) return;
    final junk = await _mail.ensureSpecialFolder(m.accountId, FolderType.spam);
    if (!mounted) return;
    if (junk == null) {
      showStatusMessage(context, 'This account has no Junk folder.');
      return;
    }
    await _mail.moveMessage(junk);
  }

  void _openFile([BackstagePage page = BackstagePage.info]) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BackstageView(initialPage: page),
    ));
  }

  void _openRules() =>
      showDialog(context: context, builder: (_) => const RulesDialog());

  void _focusSearch() {
    final nav = context.read<NavigationProvider>();
    if (nav.currentSection == NavigationSection.mail) {
      _searchFocus.requestFocus();
      return;
    }
    // The search box only exists once the Mail view has been built.
    nav.switchSection(NavigationSection.mail);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _renameSelectedFolder() async {
    final f = _mail.selectedFolder;
    if (f == null || f.type != FolderType.other) {
      showStatusMessage(context, 'Select a folder you created to rename it.');
      return;
    }
    final name = await showTextInputDialog(context,
        title: 'Rename Folder',
        label: 'Name',
        initialValue: f.name,
        confirmLabel: 'Rename');
    if (name == null) return;
    try {
      await _mail.renameFolder(f, name);
    } catch (e) {
      if (mounted) showStatusMessage(context, '$e', isError: true);
    }
  }

  Future<void> _deleteSelectedFolder() async {
    final f = _mail.selectedFolder;
    if (f == null || f.type != FolderType.other) {
      showStatusMessage(context, 'Select a folder you created to delete it.');
      return;
    }
    if (!await showConfirmDialog(context,
        title: 'Delete Folder',
        message: 'Delete "${f.displayName}" and all of its messages?',
        confirmLabel: 'Delete',
        destructive: true)) {
      return;
    }
    try {
      await _mail.deleteFolder(f);
    } catch (e) {
      if (mounted) showStatusMessage(context, '$e', isError: true);
    }
  }

  Future<void> _emailCalendar() async {
    final calendar = context.read<CalendarProvider>();
    final events = calendar.allEvents;
    if (events.isEmpty) {
      showStatusMessage(context, 'Your calendar is empty.');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('look_in_cal_');
    final file = File(p.join(dir.path, 'Calendar.ics'));
    await file.writeAsString(IcalService.generateCalendar(events));
    final size = await file.length();
    if (!mounted) return;
    await openNewMessage(
      context,
      subject: 'Calendar',
      body: 'My calendar is attached as an iCalendar (.ics) file.',
      attachments: [
        Attachment(
          id: 'calendar',
          fileName: 'Calendar.ics',
          mimeType: 'text/calendar',
          size: size,
          localPath: file.path,
        ),
      ],
    );
  }

  Future<void> _printCalendar() async {
    final cal = context.read<CalendarProvider>();
    final days = cal.viewType == CalendarViewType.month
        ? cal.visibleDays
            .where((d) => d.month == cal.focusedDate.month)
            .toList()
        : cal.visibleDays;
    final ok = await PrintService.printAgenda(
        cal.rangeTitle, days, cal.getOccurrencesForDate);
    if (!ok && mounted) {
      showStatusMessage(context, 'Could not open the print view.',
          isError: true);
    }
  }

  Future<void> _emailContacts() async {
    final contacts = context.read<ContactsProvider>();
    final List<EmailAddress> to;
    if (contacts.selectedGroup != null) {
      to = contacts
          .groupAddresses(contacts.selectedGroup!)
          .map((a) => EmailAddress(address: a))
          .toList();
    } else if (contacts.selectedContact?.primaryEmail != null) {
      final c = contacts.selectedContact!;
      to = [EmailAddress(address: c.primaryEmail!, displayName: c.displayName)];
    } else {
      showStatusMessage(
          context, 'Select a contact or group with an email address.');
      return;
    }
    await openNewMessage(context, to: to);
  }

  void _openSelectedMessage() {
    final m = _focused;
    if (m == null) return;
    if (m.isDraft || m.id.startsWith('outbox|')) {
      openDraft(context, m);
    } else {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const _StandaloneMessage()));
    }
  }

  // ─── Ribbons ───────────────────────────────────────────────────────

  Widget _buildRibbon(NavigationSection section) {
    switch (section) {
      case NavigationSection.mail:
        return _buildMailRibbon();
      case NavigationSection.calendar:
        return _buildCalendarRibbon();
      case NavigationSection.contacts:
        return _buildContactsRibbon();
    }
  }

  Widget _buildMailRibbon() {
    final mail = context.watch<MailProvider>();
    final message = mail.selectedMessage;
    final hasSelection = message != null || mail.selectedIds.isNotEmpty;
    final canRespond = message != null && !message.id.startsWith('outbox|');
    final anyUnread = mail.selectedMessages.any((m) => !m.isRead) ||
        (message != null && !message.isRead);
    final folder = mail.selectedFolder;
    final accountId = folder?.accountId ?? mail.defaultAccount?.id;
    final customFolder = folder?.type == FolderType.other;

    return RibbonToolbar(
      onFileTab: _openFile,
      tabs: [
        RibbonTabDefinition(label: 'Home', groups: [
          RibbonGroupDefinition(label: 'New', items: [
            RibbonItem(
              label: 'New\nEmail',
              icon: Icons.email_outlined,
              isLarge: true,
              tooltip: 'New Email (Ctrl+N)',
              onTap: () => openNewMessage(context),
            ),
            RibbonItem(
              label: 'New\nItems',
              icon: Icons.post_add,
              isLarge: true,
              menu: [
                RibbonMenuItem(
                    label: 'E-mail Message',
                    onTap: () => openNewMessage(context)),
                RibbonMenuItem(label: 'Appointment', onTap: _newAppointment),
                RibbonMenuItem(label: 'Contact', onTap: _newContact),
                RibbonMenuItem(
                    label: 'Contact Group', onTap: _newContactGroup),
              ],
            ),
          ]),
          RibbonGroupDefinition(label: 'Delete', items: [
            RibbonItem(
              label: 'Junk',
              icon: Icons.report_outlined,
              tooltip: 'Move to Junk E-mail',
              onTap: canRespond ? _moveToJunk : null,
            ),
            RibbonItem(
              label: 'Delete',
              icon: Icons.delete_outline,
              iconColor: OutlookTheme.textSecondary,
              isLarge: true,
              tooltip: 'Delete (Delete)',
              onTap: hasSelection ? _delete : null,
            ),
          ]),
          RibbonGroupDefinition(label: 'Respond', items: [
            RibbonItem(
              label: 'Reply',
              icon: Icons.reply,
              isLarge: true,
              tooltip: 'Reply (Ctrl+R)',
              onTap: canRespond ? () => _reply() : null,
            ),
            RibbonItem(
              label: 'Reply\nAll',
              icon: Icons.reply_all,
              isLarge: true,
              tooltip: 'Reply All (Ctrl+Shift+R)',
              onTap: canRespond ? () => _reply(all: true) : null,
            ),
            RibbonItem(
              label: 'Forward',
              icon: Icons.forward,
              isLarge: true,
              tooltip: 'Forward (Ctrl+F)',
              onTap: canRespond ? _forward : null,
            ),
          ]),
          RibbonGroupDefinition(label: 'Move', items: [
            RibbonItem(
              label: 'Move',
              icon: Icons.drive_file_move_outline,
              isLarge: true,
              tooltip: 'Move to Folder (Ctrl+Shift+V)',
              onTap: canRespond ? () => showMoveToFolderDialog(context) : null,
            ),
            RibbonItem(
              label: 'Rules',
              icon: Icons.rule,
              isLarge: true,
              menu: [
                if (canRespond)
                  RibbonMenuItem(
                    label: 'Create Rule...',
                    onTap: () => showCreateRuleDialog(context, message),
                  ),
                RibbonMenuItem(
                    label: 'Manage Rules & Alerts...', onTap: _openRules),
              ],
            ),
          ]),
          RibbonGroupDefinition(label: 'Tags', items: [
            RibbonItem(
              label: anyUnread ? 'Mark Read' : 'Mark Unread',
              icon: anyUnread
                  ? Icons.drafts_outlined
                  : Icons.markunread_outlined,
              tooltip: anyUnread
                  ? 'Mark as Read (Ctrl+Q)'
                  : 'Mark as Unread (Ctrl+U)',
              onTap: hasSelection
                  ? () => anyUnread ? mail.markAsRead() : mail.markAsUnread()
                  : null,
            ),
            RibbonItem(
              label: 'Follow Up',
              icon: Icons.flag_outlined,
              iconColor: OutlookTheme.flaggedColor,
              tooltip: 'Flag / Clear Flag (Insert)',
              onTap: canRespond ? () => mail.toggleFlag() : null,
            ),
          ]),
          RibbonGroupDefinition(label: 'Find', items: [
            RibbonItem(
              label: 'Search',
              icon: Icons.search,
              tooltip: 'Search (Ctrl+E)',
              onTap: _focusSearch,
            ),
            RibbonItem(
              label: 'Filter Unread',
              icon: Icons.filter_list,
              isChecked: mail.unreadOnly,
              onTap: () => mail.setUnreadOnly(!mail.unreadOnly),
            ),
          ]),
          RibbonGroupDefinition(label: 'Send/Receive', items: [
            RibbonItem(
              label: 'Send/Receive\nAll Folders',
              icon: Icons.sync,
              isLarge: true,
              tooltip: 'Send/Receive All Folders (F9)',
              onTap: () => mail.syncAll(),
            ),
          ]),
        ]),
        RibbonTabDefinition(label: 'Send / Receive', groups: [
          RibbonGroupDefinition(label: 'Send & Receive', items: [
            RibbonItem(
              label: 'Send/Receive\nAll Folders',
              icon: Icons.sync,
              isLarge: true,
              tooltip: 'Send/Receive All Folders (F9)',
              onTap: () => mail.syncAll(),
            ),
            RibbonItem(
              label: 'Update Folder',
              icon: Icons.refresh,
              tooltip: 'Update Folder (Shift+F9)',
              onTap: () => mail.refreshMessages(),
            ),
            RibbonItem(
              label: 'Send All',
              icon: Icons.outbox_outlined,
              tooltip: 'Send everything in the Outbox',
              onTap: accountId == null
                  ? null
                  : () async {
                      for (final a in mail.accounts) {
                        await mail.syncAccount(a.id);
                      }
                    },
            ),
          ]),
          RibbonGroupDefinition(label: 'Preferences', items: [
            RibbonItem(
              label: 'Work\nOffline',
              icon: Icons.cloud_off_outlined,
              isLarge: true,
              isChecked: mail.workOffline,
              tooltip: 'Disconnect from all mail servers',
              onTap: () => mail.setWorkOffline(!mail.workOffline),
            ),
          ]),
        ]),
        RibbonTabDefinition(label: 'Folder', groups: [
          RibbonGroupDefinition(label: 'New', items: [
            RibbonItem(
              label: 'New\nFolder',
              icon: Icons.create_new_folder_outlined,
              isLarge: true,
              onTap: accountId == null
                  ? null
                  : () => showNewFolderDialog(context,
                      accountId: accountId,
                      parent: folder?.type == FolderType.outbox ? null : folder),
            ),
          ]),
          RibbonGroupDefinition(label: 'Actions', items: [
            RibbonItem(
              label: 'Rename Folder',
              icon: Icons.drive_file_rename_outline,
              onTap: customFolder ? _renameSelectedFolder : null,
            ),
            RibbonItem(
              label: 'Delete Folder',
              icon: Icons.folder_delete_outlined,
              onTap: customFolder ? _deleteSelectedFolder : null,
            ),
          ]),
          RibbonGroupDefinition(label: 'Clean Up', items: [
            RibbonItem(
              label: 'Mark All\nas Read',
              icon: Icons.mark_email_read_outlined,
              isLarge: true,
              onTap: folder == null ? null : () => mail.markFolderRead(folder),
            ),
            RibbonItem(
              label: 'Empty Folder',
              icon: Icons.delete_sweep_outlined,
              onTap: folder == null || folder.type == FolderType.outbox
                  ? null
                  : () async {
                      if (await showConfirmDialog(context,
                          title: 'Empty Folder',
                          message: 'Permanently delete everything in '
                              '"${folder.displayName}"?',
                          confirmLabel: 'Delete All',
                          destructive: true)) {
                        await mail.emptyFolder(folder);
                      }
                    },
            ),
            RibbonItem(
              label: 'Run Rules Now',
              icon: Icons.play_circle_outline,
              onTap: folder?.type == FolderType.inbox
                  ? () async {
                      final n = await mail.runRulesNow(folder!);
                      if (mounted) {
                        showStatusMessage(
                            context, 'Rules applied to $n message(s)');
                      }
                    }
                  : null,
            ),
          ]),
        ]),
        RibbonTabDefinition(label: 'View', groups: [
          RibbonGroupDefinition(label: 'Arrangement', items: [
            for (final s in MessageSort.values)
              RibbonItem(
                label: s.label,
                icon: _sortIcons[s]!,
                isChecked: mail.sort == s,
                onTap: () => mail.setSort(s),
              ),
            RibbonItem(
              label: 'Reverse Sort',
              icon: Icons.swap_vert,
              onTap: () => mail.setSort(mail.sort),
            ),
          ]),
          RibbonGroupDefinition(label: 'Layout', items: [
            RibbonItem(
              label: 'Folder\nPane',
              icon: Icons.view_sidebar_outlined,
              isLarge: true,
              isChecked: mail.showFolderPane,
              onTap: mail.toggleFolderPane,
            ),
            RibbonItem(
              label: 'Reading\nPane',
              icon: Icons.chrome_reader_mode_outlined,
              isLarge: true,
              menu: [
                for (final pos in ReadingPanePosition.values)
                  RibbonMenuItem(
                    label: pos.name[0].toUpperCase() + pos.name.substring(1),
                    isChecked: mail.readingPanePosition == pos,
                    onTap: () => mail.setReadingPanePosition(pos),
                  ),
              ],
            ),
          ]),
        ]),
      ],
    );
  }

  static const _sortIcons = {
    MessageSort.date: Icons.calendar_today_outlined,
    MessageSort.from: Icons.person_outline,
    MessageSort.subject: Icons.subject,
    MessageSort.size: Icons.straighten,
    MessageSort.importance: Icons.priority_high,
  };

  Widget _buildCalendarRibbon() {
    final cal = context.watch<CalendarProvider>();
    return RibbonToolbar(
      onFileTab: _openFile,
      tabs: [
        RibbonTabDefinition(label: 'Home', groups: [
          RibbonGroupDefinition(label: 'New', items: [
            RibbonItem(
              label: 'New\nAppointment',
              icon: Icons.event,
              isLarge: true,
              tooltip: 'New Appointment (Ctrl+N)',
              onTap: _newAppointment,
            ),
            RibbonItem(
              label: 'New\nItems',
              icon: Icons.post_add,
              isLarge: true,
              menu: [
                RibbonMenuItem(label: 'Appointment', onTap: _newAppointment),
                RibbonMenuItem(
                    label: 'E-mail Message',
                    onTap: () => openNewMessage(context)),
                RibbonMenuItem(label: 'Contact', onTap: _newContact),
              ],
            ),
          ]),
          RibbonGroupDefinition(label: 'Go To', items: [
            RibbonItem(
              label: 'Today',
              icon: Icons.today,
              isLarge: true,
              onTap: cal.goToToday,
            ),
            RibbonItem(
              label: 'Previous',
              icon: Icons.chevron_left,
              onTap: cal.goToPrevious,
            ),
            RibbonItem(
              label: 'Next',
              icon: Icons.chevron_right,
              onTap: cal.goToNext,
            ),
          ]),
          RibbonGroupDefinition(label: 'Arrange', items: [
            RibbonItem(
              label: 'Day',
              icon: Icons.view_day_outlined,
              isLarge: true,
              isChecked: cal.viewType == CalendarViewType.day,
              tooltip: 'Day (Ctrl+Alt+1)',
              onTap: () => cal.setViewType(CalendarViewType.day),
            ),
            RibbonItem(
              label: 'Work\nWeek',
              icon: Icons.view_week_outlined,
              isLarge: true,
              isChecked: cal.viewType == CalendarViewType.workWeek,
              tooltip: 'Work Week (Ctrl+Alt+2)',
              onTap: () => cal.setViewType(CalendarViewType.workWeek),
            ),
            RibbonItem(
              label: 'Week',
              icon: Icons.calendar_view_week,
              isLarge: true,
              isChecked: cal.viewType == CalendarViewType.week,
              tooltip: 'Week (Ctrl+Alt+3)',
              onTap: () => cal.setViewType(CalendarViewType.week),
            ),
            RibbonItem(
              label: 'Month',
              icon: Icons.calendar_view_month,
              isLarge: true,
              isChecked: cal.viewType == CalendarViewType.month,
              tooltip: 'Month (Ctrl+Alt+4)',
              onTap: () => cal.setViewType(CalendarViewType.month),
            ),
          ]),
          RibbonGroupDefinition(label: 'Share', items: [
            RibbonItem(
              label: 'E-mail\nCalendar',
              icon: Icons.forward_to_inbox,
              isLarge: true,
              onTap: _emailCalendar,
            ),
            RibbonItem(
              label: 'Print',
              icon: Icons.print_outlined,
              tooltip: 'Print the current view (opens in your browser)',
              onTap: _printCalendar,
            ),
            RibbonItem(
              label: 'Import',
              icon: Icons.file_download_outlined,
              tooltip: 'Import an iCalendar (.ics) file',
              onTap: () => importCalendarFile(context),
            ),
            RibbonItem(
              label: 'Export',
              icon: Icons.file_upload_outlined,
              tooltip: 'Export as an iCalendar (.ics) file',
              onTap: () => exportCalendarFile(context),
            ),
          ]),
        ]),
      ],
    );
  }

  Widget _buildContactsRibbon() {
    final contacts = context.watch<ContactsProvider>();
    final hasSelection =
        contacts.selectedContact != null || contacts.selectedGroup != null;
    return RibbonToolbar(
      onFileTab: _openFile,
      tabs: [
        RibbonTabDefinition(label: 'Home', groups: [
          RibbonGroupDefinition(label: 'New', items: [
            RibbonItem(
              label: 'New\nContact',
              icon: Icons.person_add_alt,
              isLarge: true,
              tooltip: 'New Contact (Ctrl+N)',
              onTap: _newContact,
            ),
            RibbonItem(
              label: 'New Contact\nGroup',
              icon: Icons.group_add_outlined,
              isLarge: true,
              onTap: _newContactGroup,
            ),
          ]),
          RibbonGroupDefinition(label: 'Delete', items: [
            RibbonItem(
              label: 'Delete',
              icon: Icons.delete_outline,
              iconColor: OutlookTheme.textSecondary,
              isLarge: true,
              onTap: hasSelection ? _delete : null,
            ),
          ]),
          RibbonGroupDefinition(label: 'Communicate', items: [
            RibbonItem(
              label: 'Email',
              icon: Icons.email_outlined,
              isLarge: true,
              onTap: hasSelection ? _emailContacts : null,
            ),
          ]),
          RibbonGroupDefinition(label: 'Current View', items: [
            RibbonItem(
              label: 'Contacts',
              icon: Icons.person_outline,
              isChecked: !contacts.showGroups,
              onTap: () => contacts.setShowGroups(false),
            ),
            RibbonItem(
              label: 'Groups',
              icon: Icons.groups_outlined,
              isChecked: contacts.showGroups,
              onTap: () => contacts.setShowGroups(true),
            ),
          ]),
          RibbonGroupDefinition(label: 'Share', items: [
            RibbonItem(
              label: 'Import',
              icon: Icons.file_download_outlined,
              tooltip: 'Import contacts (CSV or vCard)',
              onTap: () => importContactsFromFile(context),
            ),
            RibbonItem(
              label: 'Export',
              icon: Icons.file_upload_outlined,
              tooltip: 'Export contacts (CSV or vCard)',
              onTap: () => exportContactsToFile(context),
            ),
            RibbonItem(
              label: 'Print',
              icon: Icons.print_outlined,
              tooltip: 'Print the selected contact (opens in your browser)',
              onTap: contacts.selectedContact == null
                  ? null
                  : () => PrintService.printContact(contacts.selectedContact!),
            ),
          ]),
        ]),
      ],
    );
  }

  // ─── Keyboard shortcuts ────────────────────────────────────────────

  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final nav = context.read<NavigationProvider>();
    void mailOnly(VoidCallback action) {
      if (_inMail) action();
    }

    void calendarView(CalendarViewType type) {
      nav.switchSection(NavigationSection.calendar);
      context.read<CalendarProvider>().setViewType(type);
    }

    void goToInbox() {
      nav.switchSection(NavigationSection.mail);
      final account = _mail.currentAccount;
      final inbox = account == null
          ? null
          : _mail.folderByType(account.id, FolderType.inbox);
      if (inbox != null) _mail.selectFolder(inbox);
    }

    void print() {
      switch (nav.currentSection) {
        case NavigationSection.mail:
          final m = _focused;
          if (m != null) printMessage(context, m);
          break;
        case NavigationSection.calendar:
          _printCalendar();
          break;
        case NavigationSection.contacts:
          final c = context.read<ContactsProvider>().selectedContact;
          if (c != null) PrintService.printContact(c);
          break;
      }
    }

    return {
      // Navigation
      const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
          nav.switchSection(NavigationSection.mail),
      const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
          nav.switchSection(NavigationSection.calendar),
      const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
          nav.switchSection(NavigationSection.contacts),
      const SingleActivator(LogicalKeyboardKey.keyI,
          control: true, shift: true): goToInbox,
      // New items
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newItem,
      const SingleActivator(LogicalKeyboardKey.keyM,
          control: true, shift: true): () => openNewMessage(context),
      const SingleActivator(LogicalKeyboardKey.keyA,
          control: true, shift: true): _newAppointment,
      const SingleActivator(LogicalKeyboardKey.keyC,
          control: true, shift: true): _newContact,
      // Send / receive
      const SingleActivator(LogicalKeyboardKey.f9): () => _mail.syncAll(),
      const SingleActivator(LogicalKeyboardKey.f9, shift: true): () =>
          _mail.refreshMessages(),
      // Mail actions
      const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
          _reply(),
      const SingleActivator(LogicalKeyboardKey.keyR,
          control: true, shift: true): () => _reply(all: true),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): _forward,
      const SingleActivator(LogicalKeyboardKey.keyE, control: true):
          _focusSearch,
      const SingleActivator(LogicalKeyboardKey.f3): _focusSearch,
      const SingleActivator(LogicalKeyboardKey.delete): _delete,
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): _delete,
      const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () =>
          mailOnly(() => _mail.markAsRead()),
      const SingleActivator(LogicalKeyboardKey.keyU, control: true): () =>
          mailOnly(() => _mail.markAsUnread()),
      const SingleActivator(LogicalKeyboardKey.insert): () =>
          mailOnly(() => _mail.toggleFlag()),
      const SingleActivator(LogicalKeyboardKey.keyV,
          control: true, shift: true): () =>
          mailOnly(() => showMoveToFolderDialog(context)),
      const SingleActivator(LogicalKeyboardKey.keyA, control: true): () =>
          mailOnly(_mail.selectAll),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
          mailOnly(() => _mail.selectAdjacent(1)),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
          mailOnly(() => _mail.selectAdjacent(-1)),
      const SingleActivator(LogicalKeyboardKey.enter): () =>
          mailOnly(_openSelectedMessage),
      const SingleActivator(LogicalKeyboardKey.keyP, control: true): print,
      // Calendar views
      const SingleActivator(LogicalKeyboardKey.digit1,
          control: true, alt: true): () => calendarView(CalendarViewType.day),
      const SingleActivator(LogicalKeyboardKey.digit2,
          control: true, alt: true): () =>
          calendarView(CalendarViewType.workWeek),
      const SingleActivator(LogicalKeyboardKey.digit3,
          control: true, alt: true): () => calendarView(CalendarViewType.week),
      const SingleActivator(LogicalKeyboardKey.digit4,
          control: true, alt: true): () =>
          calendarView(CalendarViewType.month),
    };
  }

  // ─── Build ─────────────────────────────────────────────────────────

  /// Returns keyboard focus to the main window after clicks outside text
  /// fields, so that shortcuts keep working.
  void _reclaimFocus() {
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final now = FocusManager.instance.primaryFocus;
      // A text field's focus node belongs to a Focus inside EditableText.
      final inTextField =
          now?.context?.findAncestorStateOfType<EditableTextState>() != null;
      if (!inTextField && !_rootFocus.hasFocus && mounted) {
        final route = ModalRoute.of(context);
        if (route?.isCurrent ?? true) _rootFocus.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();

    return CallbackShortcuts(
      bindings: _shortcuts(),
      child: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        child: Scaffold(
          body: Listener(
            onPointerDown: (_) => _reclaimFocus(),
            child: Column(
              children: [
                _TitleBar(section: nav.currentSection),
                _buildRibbon(nav.currentSection),
                Expanded(child: _buildContent(nav.currentSection)),
                const OutlookNavigationBar(),
                const StatusBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(NavigationSection section) {
    switch (section) {
      case NavigationSection.mail:
        return MailView(searchFocus: _searchFocus);
      case NavigationSection.calendar:
        return const CalendarView();
      case NavigationSection.contacts:
        return const ContactsView();
    }
  }
}

/// The selected message in its own window (Enter in the message list).
class _StandaloneMessage extends StatelessWidget {
  const _StandaloneMessage();

  @override
  Widget build(BuildContext context) {
    final message = context.watch<MailProvider>().selectedMessage;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              Container(
                height: 30,
                color: OutlookTheme.primaryBlue,
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${message?.subject ?? ''} - Message',
                          style: OutlookTheme.titleBarStyle,
                          overflow: TextOverflow.ellipsis),
                    ),
                    IconButton(
                      tooltip: 'Close (Esc)',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close,
                          size: 14, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const Expanded(child: ReadingPane()),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  final NavigationSection section;

  const _TitleBar({required this.section});

  @override
  Widget build(BuildContext context) {
    final mail = context.watch<MailProvider>();
    final String title;
    switch (section) {
      case NavigationSection.mail:
        final folder = mail.selectedFolder;
        final account = mail.currentAccount;
        title = [
          if (mail.isSearching)
            'Search Results'
          else if (folder != null)
            folder.displayName,
          if (account != null) account.emailAddress,
          'Look In',
        ].join(' - ');
        break;
      case NavigationSection.calendar:
        title = 'Calendar - Look In';
        break;
      case NavigationSection.contacts:
        title = 'People - Look In';
        break;
    }
    return Container(
      height: 30,
      color: OutlookTheme.primaryBlue,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.mail, size: 14, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: OutlookTheme.titleBarStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (mail.workOffline || mail.isOffline)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text('Working Offline',
                  style: TextStyle(fontSize: 11, color: Colors.white70)),
            ),
        ],
      ),
    );
  }
}
