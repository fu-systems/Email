import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/outlook_theme.dart';
import '../models/folder.dart';
import '../providers/navigation_provider.dart';
import '../providers/mail_provider.dart';
import '../providers/account_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/contacts_provider.dart';
import '../widgets/ribbon/ribbon_toolbar.dart';
import '../widgets/navigation_bar.dart';
import '../widgets/status_bar.dart';
import 'mail/mail_view.dart';
import 'calendar/calendar_view.dart';
import 'contacts/contacts_view.dart';

/// Main application screen with Outlook 2013 layout:
/// Title bar -> Ribbon -> Content area -> Status bar
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Connect to the active account on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectActiveAccount();
    });
  }

  void _connectActiveAccount() {
    final accountProvider = context.read<AccountProvider>();
    final mailProvider = context.read<MailProvider>();
    final account = accountProvider.activeAccount;
    if (account != null) {
      mailProvider.connectAccount(account);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();

    return Scaffold(
      body: Column(
        children: [
          // Title bar
          _TitleBar(section: nav.currentSection),
          // Ribbon toolbar
          _buildRibbon(context, nav),
          // Main content area with navigation bar
          Expanded(
            child: Row(
              children: [
                // Left sidebar (navigation bar at bottom)
                _buildLeftPanel(nav),
                // Content area
                Expanded(
                  child: _buildContent(nav.currentSection),
                ),
              ],
            ),
          ),
          // Status bar
          const StatusBar(),
        ],
      ),
    );
  }

  Widget _buildRibbon(BuildContext context, NavigationProvider nav) {
    switch (nav.currentSection) {
      case NavigationSection.mail:
        return _buildMailRibbon(context);
      case NavigationSection.calendar:
        return _buildCalendarRibbon(context);
      case NavigationSection.contacts:
        return _buildContactsRibbon(context);
    }
  }

  Widget _buildMailRibbon(BuildContext context) {
    final mail = context.read<MailProvider>();

    return RibbonToolbar(
      onFileTab: () => _showFileMenu(context),
      tabs: [
        RibbonTabDefinition(
          label: 'Home',
          groups: [
            RibbonGroupDefinition(
              label: 'New',
              items: [
                RibbonItem(
                  label: 'New\nEmail',
                  icon: Icons.email,
                  iconColor: OutlookTheme.primaryBlue,
                  isLarge: true,
                  onTap: () => _openCompose(context),
                ),
              ],
            ),
            RibbonGroupDefinition(
              label: 'Delete',
              items: [
                RibbonItem(
                  label: 'Delete',
                  icon: Icons.delete,
                  iconColor: OutlookTheme.flaggedColor,
                  isLarge: true,
                  onTap: () {
                    final msg = mail.selectedMessage;
                    if (msg != null) mail.deleteMessage(msg);
                  },
                ),
              ],
            ),
            RibbonGroupDefinition(
              label: 'Respond',
              items: [
                RibbonItem(
                  label: 'Reply',
                  icon: Icons.reply,
                  iconColor: OutlookTheme.primaryBlue,
                  isLarge: true,
                  onTap: () => _openReply(context, replyAll: false),
                ),
                RibbonItem(
                  label: 'Reply All',
                  icon: Icons.reply_all,
                  isLarge: true,
                  onTap: () => _openReply(context, replyAll: true),
                ),
                RibbonItem(
                  label: 'Forward',
                  icon: Icons.forward,
                  isLarge: true,
                  onTap: () => _openForward(context),
                ),
              ],
            ),
            RibbonGroupDefinition(
              label: 'Move',
              items: [
                RibbonItem(
                  label: 'Move',
                  icon: Icons.drive_file_move_outline,
                  onTap: () => _showMoveDialog(context),
                ),
                RibbonItem(
                  label: 'Rules',
                  icon: Icons.rule,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Rules and filters coming in a future update'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
            RibbonGroupDefinition(
              label: 'Tags',
              items: [
                RibbonItem(
                  label: 'Unread',
                  icon: Icons.markunread,
                  onTap: () {
                    final msg = mail.selectedMessage;
                    if (msg != null) mail.markAsUnread(msg);
                  },
                ),
                RibbonItem(
                  label: 'Flag',
                  icon: Icons.flag,
                  iconColor: OutlookTheme.flaggedColor,
                  onTap: () {
                    final msg = mail.selectedMessage;
                    if (msg != null) mail.toggleFlag(msg);
                  },
                ),
              ],
            ),
          ],
        ),
        RibbonTabDefinition(
          label: 'Send / Receive',
          groups: [
            RibbonGroupDefinition(
              label: 'Send & Receive',
              items: [
                RibbonItem(
                  label: 'Send/Receive\nAll Folders',
                  icon: Icons.sync,
                  iconColor: OutlookTheme.primaryBlue,
                  isLarge: true,
                  onTap: () => mail.refreshMessages(),
                ),
              ],
            ),
          ],
        ),
        RibbonTabDefinition(
          label: 'Folder',
          groups: [
            RibbonGroupDefinition(
              label: 'New',
              items: [
                RibbonItem(
                  label: 'New\nFolder',
                  icon: Icons.create_new_folder,
                  iconColor: OutlookTheme.primaryBlue,
                  isLarge: true,
                  onTap: () => _showNewFolderDialog(context),
                ),
              ],
            ),
          ],
        ),
        RibbonTabDefinition(
          label: 'View',
          groups: [
            RibbonGroupDefinition(
              label: 'Layout',
              items: [
                RibbonItem(
                  label: 'Reading Pane',
                  icon: Icons.view_sidebar,
                  onTap: () {
                    context.read<MailProvider>().toggleReadingPane();
                  },
                ),
                RibbonItem(
                  label: 'Folder Pane',
                  icon: Icons.view_list,
                  onTap: () {
                    context.read<MailProvider>().toggleFolderPane();
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendarRibbon(BuildContext context) {
    return RibbonToolbar(
      onFileTab: () => _showFileMenu(context),
      tabs: [
        RibbonTabDefinition(
          label: 'Home',
          groups: [
            RibbonGroupDefinition(
              label: 'New',
              items: [
                RibbonItem(
                  label: 'New\nAppointment',
                  icon: Icons.event,
                  iconColor: OutlookTheme.primaryBlue,
                  isLarge: true,
                  onTap: () => _openNewEvent(context),
                ),
              ],
            ),
            RibbonGroupDefinition(
              label: 'Go To',
              items: [
                RibbonItem(
                  label: 'Today',
                  icon: Icons.today,
                  iconColor: OutlookTheme.primaryBlue,
                  isLarge: true,
                  onTap: () {
                    context.read<CalendarProvider>().goToToday();
                  },
                ),
              ],
            ),
            RibbonGroupDefinition(
              label: 'Arrange',
              items: [
                RibbonItem(
                  label: 'Day',
                  icon: Icons.view_day,
                  onTap: () {
                    context.read<CalendarProvider>().setViewType(CalendarViewType.day);
                  },
                ),
                RibbonItem(
                  label: 'Week',
                  icon: Icons.view_week,
                  onTap: () {
                    context.read<CalendarProvider>().setViewType(CalendarViewType.week);
                  },
                ),
                RibbonItem(
                  label: 'Month',
                  icon: Icons.calendar_view_month,
                  onTap: () {
                    context.read<CalendarProvider>().setViewType(CalendarViewType.month);
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContactsRibbon(BuildContext context) {
    return RibbonToolbar(
      onFileTab: () => _showFileMenu(context),
      tabs: [
        RibbonTabDefinition(
          label: 'Home',
          groups: [
            RibbonGroupDefinition(
              label: 'New',
              items: [
                RibbonItem(
                  label: 'New\nContact',
                  icon: Icons.person_add,
                  iconColor: OutlookTheme.primaryBlue,
                  isLarge: true,
                  onTap: () => _openNewContact(context),
                ),
              ],
            ),
            RibbonGroupDefinition(
              label: 'Actions',
              items: [
                RibbonItem(
                  label: 'Delete',
                  icon: Icons.delete,
                  iconColor: OutlookTheme.flaggedColor,
                  isLarge: true,
                  onTap: () {
                    final contactsProvider = context.read<ContactsProvider>();
                    final selected = contactsProvider.selectedContact;
                    if (selected != null) {
                      contactsProvider.removeContact(selected.id);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLeftPanel(NavigationProvider nav) {
    return Column(
      children: [
        Expanded(
          child: _buildSideContent(nav.currentSection),
        ),
        const OutlookNavigationBar(),
      ],
    );
  }

  Widget _buildSideContent(NavigationSection section) {
    switch (section) {
      case NavigationSection.mail:
        return const SizedBox.shrink(); // FolderPane is part of MailView
      case NavigationSection.calendar:
        return const SizedBox.shrink(); // Calendar has its own sidebar
      case NavigationSection.contacts:
        return const SizedBox.shrink(); // Contacts has its own sidebar
    }
  }

  Widget _buildContent(NavigationSection section) {
    switch (section) {
      case NavigationSection.mail:
        return const MailView();
      case NavigationSection.calendar:
        return const CalendarView();
      case NavigationSection.contacts:
        return const ContactsView();
    }
  }

  void _showFileMenu(BuildContext context) {
    Navigator.of(context).pushNamed('/account-setup');
  }

  void _openCompose(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _ComposeRoute(),
      ),
    );
  }

  void _openReply(BuildContext context, {required bool replyAll}) {
    final mail = context.read<MailProvider>();
    final msg = mail.selectedMessage;
    if (msg == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ComposeRoute(
          replyTo: msg,
          replyAll: replyAll,
        ),
      ),
    );
  }

  void _openForward(BuildContext context) {
    final mail = context.read<MailProvider>();
    final msg = mail.selectedMessage;
    if (msg == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ComposeRoute(forwardFrom: msg),
      ),
    );
  }

  void _openNewEvent(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const EventEditorDialog(),
    );
  }

  void _openNewContact(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const ContactEditorDialog(),
    );
  }

  void _showMoveDialog(BuildContext context) {
    final mail = context.read<MailProvider>();
    final msg = mail.selectedMessage;
    if (msg == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a message to move')),
      );
      return;
    }

    final folders = mail.folders
        .where((f) => f.id != mail.selectedFolder?.id)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: OutlookTheme.primaryBlue,
                child: Row(
                  children: [
                    const Text('Move to Folder',
                        style: OutlookTheme.titleBarStyle),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 14, color: Colors.white),
                      onPressed: () => Navigator.of(ctx).pop(),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: folders.length,
                  itemBuilder: (_, i) {
                    final folder = folders[i];
                    return _MoveFolderItem(
                      folder: folder,
                      onTap: () {
                        mail.moveMessage(msg, folder);
                        Navigator.of(ctx).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNewFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: OutlookTheme.primaryBlue,
                child: Row(
                  children: [
                    const Text('Create New Folder',
                        style: OutlookTheme.titleBarStyle),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 14, color: Colors.white),
                      onPressed: () => Navigator.of(ctx).pop(),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Folder name',
                        hintText: 'Enter folder name',
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Folder creation will be available in a future update'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Text('Create'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoveFolderItem extends StatefulWidget {
  final MailFolder folder;
  final VoidCallback onTap;

  const _MoveFolderItem({required this.folder, required this.onTap});

  @override
  State<_MoveFolderItem> createState() => _MoveFolderItemState();
}

class _MoveFolderItemState extends State<_MoveFolderItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: _isHovered ? OutlookTheme.hoverColor : Colors.transparent,
          child: Row(
            children: [
              Icon(widget.folder.icon,
                  size: 16, color: OutlookTheme.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.folder.name,
                  style: OutlookTheme.folderLabelStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
    return Container(
      height: 30,
      color: OutlookTheme.primaryBlue,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.mail, size: 14, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            'Look In - ${section.label}',
            style: OutlookTheme.titleBarStyle,
          ),
          const Spacer(),
          // Window controls placeholder
          _WindowButton(icon: Icons.minimize, onTap: () {}),
          _WindowButton(icon: Icons.crop_square, onTap: () {}),
          _WindowButton(icon: Icons.close, onTap: () {}),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _WindowButton({required this.icon, required this.onTap});

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 28,
          height: 20,
          color: _isHovered
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.transparent,
          child: Icon(widget.icon, size: 12, color: Colors.white),
        ),
      ),
    );
  }
}

/// Placeholder route for compose. The actual ComposeScreen is in mail/.
class _ComposeRoute extends StatelessWidget {
  final EmailMessage? replyTo;
  final bool replyAll;
  final EmailMessage? forwardFrom;

  const _ComposeRoute({
    this.replyTo,
    this.replyAll = false,
    this.forwardFrom,
  });

  @override
  Widget build(BuildContext context) {
    // Delegate to the compose screen
    return ComposeScreenRoute(
      replyTo: replyTo,
      replyAll: replyAll,
      forwardFrom: forwardFrom,
    );
  }
}
