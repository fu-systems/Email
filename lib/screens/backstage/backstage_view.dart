import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/email_account.dart';
import '../../models/folder.dart';
import '../../providers/account_provider.dart';
import '../../providers/mail_provider.dart';
import '../../services/data_store.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';
import '../calendar/calendar_view.dart';
import '../contacts/contacts_view.dart';
import '../mail/mail_dialogs.dart';
import '../settings/account_setup_screen.dart';

enum BackstagePage { info, openExport, options, about }

/// Outlook 2013's File tab ("backstage"): account information and
/// settings, import/export, options and exit.
class BackstageView extends StatefulWidget {
  final BackstagePage initialPage;

  const BackstageView({super.key, this.initialPage = BackstagePage.info});

  @override
  State<BackstageView> createState() => _BackstageViewState();
}

class _BackstageViewState extends State<BackstageView> {
  late BackstagePage _page = widget.initialPage;

  Future<void> _exit() async {
    // Close the database cleanly (flushes the WAL) before quitting.
    context.read<MailProvider>().store.close();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 190,
            color: OutlookTheme.primaryBlue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 16),
                    child: Tooltip(
                      message: 'Back (Esc)',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.arrow_back,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ),
                _NavItem(
                  label: 'Info',
                  selected: _page == BackstagePage.info,
                  onTap: () => setState(() => _page = BackstagePage.info),
                ),
                _NavItem(
                  label: 'Open & Export',
                  selected: _page == BackstagePage.openExport,
                  onTap: () => setState(() => _page = BackstagePage.openExport),
                ),
                _NavItem(
                  label: 'Options',
                  selected: _page == BackstagePage.options,
                  onTap: () => setState(() => _page = BackstagePage.options),
                ),
                _NavItem(
                  label: 'About',
                  selected: _page == BackstagePage.about,
                  onTap: () => setState(() => _page = BackstagePage.about),
                ),
                _NavItem(label: 'Exit', selected: false, onTap: _exit),
              ],
            ),
          ),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    Navigator.of(context).pop(),
              },
              child: Focus(
                autofocus: true,
                child: Container(
                  color: Colors.white,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(40, 32, 40, 32),
                    child: switch (_page) {
                      BackstagePage.info => const _InfoPage(),
                      BackstagePage.openExport => const _OpenExportPage(),
                      BackstagePage.options => const _OptionsPage(),
                      BackstagePage.about => const _AboutPage(),
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.centerLeft,
          color: widget.selected
              ? OutlookTheme.darkBlue
              : _hovered
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
          child: Text(
            widget.label,
            style: const TextStyle(
              fontFamily: OutlookTheme.fontFamily,
              fontFamilyFallback: OutlookTheme.fontFamilyFallback,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  final String text;

  const _PageTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: OutlookTheme.fontFamily,
          fontFamilyFallback: OutlookTheme.fontFamilyFallback,
          fontSize: 30,
          fontWeight: FontWeight.w300,
          color: OutlookTheme.primaryBlue,
        ),
      ),
    );
  }
}

/// A large square backstage button with a title and description.
class _Tile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  const _Tile({
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
  });

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                width: 96,
                height: 88,
                decoration: BoxDecoration(
                  color: _hovered && enabled ? OutlookTheme.hoverColor : null,
                  border: Border.all(
                    color: _hovered && enabled
                        ? OutlookTheme.selectedItemBorder
                        : OutlookTheme.dividerColor,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.icon,
                        size: 30,
                        color: enabled
                            ? OutlookTheme.primaryBlue
                            : OutlookTheme.textMuted),
                    const SizedBox(height: 6),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(widget.description,
                      style: const TextStyle(
                          fontSize: 12.5, color: OutlookTheme.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Info ────────────────────────────────────────────────────────────

class _InfoPage extends StatefulWidget {
  const _InfoPage();

  @override
  State<_InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<_InfoPage> {
  String? _accountId;

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountProvider>();
    final mail = context.watch<MailProvider>();
    final list = accounts.accounts;
    final EmailAccount? account =
        list.where((a) => a.id == _accountId).firstOrNull ??
            accounts.defaultAccount;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageTitle('Account Information'),
          if (account != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: OutlookTheme.dividerColor),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: account.id,
                  isExpanded: true,
                  items: [
                    for (final a in list)
                      DropdownMenuItem(
                        value: a.id,
                        child: Row(
                          children: [
                            const Icon(Icons.mail_outline,
                                size: 18, color: OutlookTheme.primaryBlue),
                            const SizedBox(width: 10),
                            Text(a.emailAddress,
                                style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 8),
                            Text(
                              '${a.protocol.label}${a.isDefault ? ' · default' : ''}'
                              '${a.isEnabled ? '' : ' · disabled'}',
                              style: const TextStyle(
                                  fontSize: 12, color: OutlookTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() => _accountId = id),
                ),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AccountSetupScreen())),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Account'),
          ),
          const SizedBox(height: 24),
          if (account != null) ...[
            _Tile(
              icon: Icons.manage_accounts_outlined,
              title: 'Account Settings',
              description:
                  'Change settings for this account: servers, password, '
                  'signature and how often to check for new mail.',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AccountSetupScreen(accountId: account.id))),
            ),
            _Tile(
              icon: Icons.star_outline,
              title: 'Set as Default',
              description: account.isDefault
                  ? 'This is the default account for new messages.'
                  : 'Use this account for new messages by default.',
              onTap: account.isDefault
                  ? null
                  : () => accounts.setDefaultAccount(account.id),
            ),
            _Tile(
              icon: Icons.cleaning_services_outlined,
              title: 'Mailbox Cleanup',
              description: 'Permanently delete everything in Deleted Items.',
              onTap: () async {
                final trash = mail.folderByType(account.id, FolderType.trash);
                if (trash == null) {
                  showStatusMessage(context, 'This account has no Deleted Items folder.');
                  return;
                }
                if (await showConfirmDialog(context,
                    title: 'Empty Deleted Items',
                    message: 'Everything in "${trash.displayName}" will be '
                        'permanently deleted.',
                    confirmLabel: 'Empty',
                    destructive: true)) {
                  await mail.emptyFolder(trash);
                  if (context.mounted) {
                    showStatusMessage(context, 'Deleted Items emptied');
                  }
                }
              },
            ),
            _Tile(
              icon: Icons.rule,
              title: 'Rules and Alerts',
              description: 'Organize incoming messages automatically: move, '
                  'flag, mark as read or delete messages that match.',
              onTap: () => showDialog(
                  context: context, builder: (_) => const RulesDialog()),
            ),
            _Tile(
              icon: Icons.person_remove_outlined,
              title: 'Remove Account',
              description: 'Remove this account and its locally stored mail '
                  'from Look In. Mail on the server is not affected.',
              onTap: () async {
                if (await showConfirmDialog(context,
                    title: 'Remove Account',
                    message: 'Remove ${account.emailAddress} from Look In? '
                        'Locally cached messages for this account are '
                        'deleted.',
                    confirmLabel: 'Remove',
                    destructive: true)) {
                  setState(() => _accountId = null);
                  await accounts.removeAccount(account.id);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Open & Export ───────────────────────────────────────────────────

class _OpenExportPage extends StatelessWidget {
  const _OpenExportPage();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageTitle('Open & Export'),
          _Tile(
            icon: Icons.contact_page_outlined,
            title: 'Import Contacts',
            description: 'Import contacts from a CSV file (Outlook, Gmail) or '
                'a vCard (.vcf) file.',
            onTap: () => importContactsFromFile(context),
          ),
          _Tile(
            icon: Icons.ios_share,
            title: 'Export Contacts',
            description: 'Save all contacts as an Outlook CSV or vCard file.',
            onTap: () => exportContactsToFile(context),
          ),
          _Tile(
            icon: Icons.event_note_outlined,
            title: 'Import Calendar',
            description: 'Import appointments from an iCalendar (.ics) file.',
            onTap: () => importCalendarFile(context),
          ),
          _Tile(
            icon: Icons.event_available_outlined,
            title: 'Export Calendar',
            description: 'Save your calendar as an iCalendar (.ics) file that '
                'other calendar applications can open.',
            onTap: () => exportCalendarFile(context),
          ),
        ],
      ),
    );
  }
}

// ─── Options ─────────────────────────────────────────────────────────

class _OptionsPage extends StatelessWidget {
  const _OptionsPage();

  @override
  Widget build(BuildContext context) {
    final mail = context.watch<MailProvider>();
    Widget toggle(String label, String key, {bool defaultValue = false}) =>
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: mail.preference(key, defaultValue: defaultValue),
          onChanged: (v) => mail.setPreference(key, v ?? defaultValue),
          title: Text(label, style: const TextStyle(fontSize: 13)),
        );
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(text,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: OutlookTheme.primaryBlue)),
        );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageTitle('Options'),
          heading('General'),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: mail.notifications.enabled,
            onChanged: (v) => mail.setNotificationsEnabled(v ?? true),
            title: const Text(
                'Show a desktop alert when new messages arrive and for '
                'appointment reminders',
                style: TextStyle(fontSize: 13)),
          ),
          heading('Mail'),
          toggle('Mark items as read when viewed in the Reading Pane',
              'markReadOnSelect', defaultValue: true),
          toggle('After moving or deleting an open item, open the next item',
              'selectNextAfterDelete', defaultValue: true),
          toggle('Always download pictures in HTML messages (less private)',
              'alwaysDownloadPictures'),
          Row(
            children: [
              const Text('Reading Pane:', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 12),
              DropdownButton<ReadingPanePosition>(
                value: mail.readingPanePosition,
                isDense: true,
                items: const [
                  DropdownMenuItem(
                      value: ReadingPanePosition.right, child: Text('Right')),
                  DropdownMenuItem(
                      value: ReadingPanePosition.bottom, child: Text('Bottom')),
                  DropdownMenuItem(
                      value: ReadingPanePosition.off, child: Text('Off')),
                ],
                onChanged: (v) {
                  if (v != null) mail.setReadingPanePosition(v);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Safe senders: pictures from these senders are always '
                  'downloaded.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              OutlinedButton(
                onPressed: () {
                  mail.store.setString('safeSenders', null);
                  showStatusMessage(context, 'Safe senders list cleared');
                },
                child: const Text('Clear list'),
              ),
            ],
          ),
          heading('Send and receive'),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: mail.workOffline,
            onChanged: (v) => mail.setWorkOffline(v ?? false),
            title: const Text('Work Offline (don\'t connect to mail servers)',
                style: TextStyle(fontSize: 13)),
          ),
          const Text(
            'How often each account checks for new mail is set in its '
            'Account Settings.',
            style: TextStyle(fontSize: 12, color: OutlookTheme.textSecondary),
          ),
          heading('Signatures'),
          for (final a in mail.accounts)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.draw_outlined, size: 18),
              title: Text(a.emailAddress, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                a.signature?.split('\n').first ?? '(no signature)',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: TextButton(
                onPressed: () => _editSignature(context, a),
                child: const Text('Edit'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editSignature(BuildContext context, EmailAccount account) async {
    final controller = TextEditingController(text: account.signature ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => OutlookDialog(
        title: 'Signature - ${account.emailAddress}',
        width: 520,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 8,
          minLines: 5,
          decoration: const InputDecoration(
            hintText: 'Kind regards,\nYour Name',
          ),
        ),
      ),
    );
    controller.dispose();
    if (result == null || !context.mounted) return;
    final trimmed = result.trimRight();
    await context.read<AccountProvider>().updateAccount(trimmed.isEmpty
        ? account.copyWith(clearSignature: true)
        : account.copyWith(signature: trimmed));
  }
}

// ─── About ───────────────────────────────────────────────────────────

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    final dataDir = DataStore.dataDirectory ??
        '${Platform.environment['HOME'] ?? '~'}/.local/share/systems.fu.look_in';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageTitle('About Look In'),
          const Text('Look In 0.2.0',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'A Linux email client inspired by Microsoft Outlook '
            '2013. Email over IMAP, POP3 and SMTP, calendar and contacts, with '
            'everything stored locally so you can keep working offline.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          SelectableText(
            'Data folder: $dataDir',
            style: const TextStyle(fontSize: 12.5, color: OutlookTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          const Text(
              'Copyright (c) 2026 Functionally Unique LLC. Free for '
              'non-commercial use under the FU License; commercial use needs '
              'a separate license.',
              style: TextStyle(fontSize: 12.5, color: OutlookTheme.textSecondary)),
        ],
      ),
    );
  }
}
