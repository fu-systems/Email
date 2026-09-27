import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/email_account.dart';
import '../../models/folder.dart';
import '../../providers/account_provider.dart';
import '../../providers/mail_provider.dart';
import '../../services/data_store.dart';
import '../../services/spell_checker.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/compose/signature_editor.dart';
import '../calendar/calendar_view.dart';
import '../contacts/contacts_view.dart';
import '../mail/mail_dialogs.dart';
import '../settings/account_setup_screen.dart';
import '../mail/compose_screen.dart' show ComposeScreen;
import '../settings/microsoft_sign_in.dart';

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
    // Finish keyring writes and close the database cleanly (flushes the
    // WAL) before quitting.
    final store = context.read<MailProvider>().store;
    await store.flushSecrets().timeout(const Duration(seconds: 5),
        onTimeout: () {});
    store.close();
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

/// The app registration used for "Sign in with Microsoft".
class _MicrosoftRegistrationOption extends StatefulWidget {
  final DataStore store;

  const _MicrosoftRegistrationOption({required this.store});

  @override
  State<_MicrosoftRegistrationOption> createState() =>
      _MicrosoftRegistrationOptionState();
}

class _MicrosoftRegistrationOptionState
    extends State<_MicrosoftRegistrationOption> {
  @override
  Widget build(BuildContext context) {
    final registration = currentMicrosoftRegistration(widget.store);
    final source = switch (registration?.source) {
      null => '',
      'settings' => '',
      'build' => ' (built into this copy of Look In)',
      final path => ' (from $path)',
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            registration == null
                ? 'Not set up. Outlook.com and Microsoft 365 accounts sign in '
                    'through an app registration you create in Microsoft Entra.'
                : 'App registration ${registration.clientId} '
                    '(${registration.audience.label})$source.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: () async {
            await showMicrosoftRegistrationDialog(context, store: widget.store);
            if (mounted) setState(() {});
          },
          child: Text(registration == null ? 'Set Up...' : 'Change...'),
        ),
      ],
    );
  }
}

/// "Store passwords in the system keyring" with the current location and
/// any problem opening the keyring.
class _SecretStoreOption extends StatefulWidget {
  final DataStore store;

  const _SecretStoreOption({required this.store});

  @override
  State<_SecretStoreOption> createState() => _SecretStoreOptionState();
}

class _SecretStoreOptionState extends State<_SecretStoreOption> {
  bool _busy = false;

  Future<void> _toggle(bool useKeyring) async {
    setState(() => _busy = true);
    try {
      await widget.store.useSecretStore(useKeyring ? 'keyring' : 'file');
      if (mounted) {
        showStatusMessage(
            context,
            useKeyring
                ? 'Passwords moved to the system keyring'
                : 'Passwords moved to Look In\'s encrypted file');
      }
    } catch (e) {
      if (mounted) showStatusMessage(context, 'Could not switch: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final error = store.secretStoreError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: store.secretStoreId == 'keyring',
          onChanged: _busy ? null : (v) => _toggle(v ?? false),
          title: const Text(
              'Store passwords and sign-in tokens in the system keyring '
              '(GNOME Keyring, KWallet)',
              style: TextStyle(fontSize: 13)),
          secondary: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : null,
        ),
        Text(
          error ??
              (store.secretStoreId == 'keyring'
                  ? 'Your desktop keyring protects them and unlocks when you '
                      'sign in to your computer.'
                  : 'They are encrypted with a key kept in Look In\'s data '
                      'folder.'),
          style: TextStyle(
              fontSize: 12,
              color: error == null
                  ? OutlookTheme.textSecondary
                  : Colors.red.shade700),
        ),
      ],
    );
  }
}

class _SpellingOptions extends StatefulWidget {
  final DataStore store;
  final Widget Function(String label, String key, {bool defaultValue}) toggle;

  const _SpellingOptions({required this.store, required this.toggle});

  @override
  State<_SpellingOptions> createState() => _SpellingOptionsState();
}

class _SpellingOptionsState extends State<_SpellingOptions> {
  late final Future<SpellingSetup?> _setup = Spelling.setup();

  Future<void> _editDictionary() async {
    final checker = await Spelling.checker(widget.store);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _CustomDictionaryDialog(store: widget.store, checker: checker),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SpellingSetup?>(
      future: _setup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 24);
        }
        final setup = snapshot.data;
        if (setup == null) {
          return const Text(
            'Spell checking needs hunspell and a dictionary. Install them '
            'with your package manager (for example the hunspell and '
            'hunspell-en-us packages), then restart Look In.',
            style: TextStyle(fontSize: 12, color: OutlookTheme.textSecondary),
          );
        }
        final language = setup.defaultLanguage(
          preferred: widget.store.getString(Spelling.languageKey),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            widget.toggle(
              'Check spelling as you type',
              Spelling.asYouTypeKey,
              defaultValue: true,
            ),
            widget.toggle(
              'Always check spelling before sending',
              Spelling.beforeSendKey,
            ),
            Row(
              children: [
                const Text(
                  'Dictionary language:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: language,
                  isDense: true,
                  items: [
                    for (final l in setup.languages)
                      DropdownMenuItem(
                        value: l,
                        child: Text(languageDisplayName(l)),
                      ),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    await Spelling.setLanguage(widget.store, v);
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(width: 16),
                OutlinedButton(
                  onPressed: _editDictionary,
                  child: const Text('Custom Dictionary...'),
                ),
              ],
            ),
            const Text(
              'Changes apply to message windows you open next.',
              style: TextStyle(fontSize: 12, color: OutlookTheme.textSecondary),
            ),
          ],
        );
      },
    );
  }
}

/// The words added with "Add to Dictionary".
class _CustomDictionaryDialog extends StatefulWidget {
  final DataStore store;
  final SpellChecker? checker;

  const _CustomDictionaryDialog({required this.store, this.checker});

  @override
  State<_CustomDictionaryDialog> createState() =>
      _CustomDictionaryDialogState();
}

class _CustomDictionaryDialogState extends State<_CustomDictionaryDialog> {
  late List<String> _words = _load();

  List<String> _load() =>
      (widget.checker?.dictionary.toList() ??
            Spelling.savedDictionary(widget.store).toList())
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  void _remove(String word) {
    final checker = widget.checker;
    if (checker != null) {
      checker.removeFromDictionary(word);
    } else {
      final words = Spelling.savedDictionary(widget.store).toSet()
        ..remove(word);
      widget.store.setString(
        Spelling.dictionaryKey,
        jsonEncode(words.toList()),
      );
    }
    setState(() => _words = _load());
  }

  Future<void> _add() async {
    final word = await showTextInputDialog(
      context,
      title: 'Add Word',
      label: 'Word',
    );
    final clean = word?.trim() ?? '';
    if (clean.isEmpty || clean.contains(RegExp(r'\s'))) return;
    final checker = widget.checker;
    if (checker != null) {
      checker.addToDictionary(clean);
    } else {
      final words = Spelling.savedDictionary(widget.store).toSet()..add(clean);
      widget.store.setString(
        Spelling.dictionaryKey,
        jsonEncode(words.toList()),
      );
    }
    setState(() => _words = _load());
  }

  @override
  Widget build(BuildContext context) {
    return OutlookDialog(
      title: 'Custom Dictionary',
      width: 380,
      actions: [
        OutlinedButton(onPressed: _add, child: const Text('Add...')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
      child: SizedBox(
        height: 260,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: OutlookTheme.dividerColor),
          ),
          child: _words.isEmpty
              ? const Center(
                  child: Text(
                    'No words added yet.',
                    style: TextStyle(color: OutlookTheme.textMuted),
                  ),
                )
              : ListView(
                  children: [
                    for (final w in _words)
                      ListTile(
                        dense: true,
                        title: Text(w),
                        trailing: IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => _remove(w),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

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
          toggle('Compose messages in HTML (formatted text)',
              ComposeScreen.htmlPreference, defaultValue: true),
          Row(
            children: [
              const Text(
                'Hold sent messages for',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: const [0, 5, 10, 30].contains(mail.sendDelaySeconds)
                    ? mail.sendDelaySeconds
                    : 0,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('No delay')),
                  DropdownMenuItem(value: 5, child: Text('5 seconds')),
                  DropdownMenuItem(value: 10, child: Text('10 seconds')),
                  DropdownMenuItem(value: 30, child: Text('30 seconds')),
                ],
                onChanged: (v) => mail.sendDelaySeconds = v ?? 0,
              ),
              const SizedBox(width: 12),
              const Flexible(
                child: Text(
                  'so you can Undo sending them',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
          heading('Spelling'),
          _SpellingOptions(store: mail.store, toggle: toggle),
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
          heading('Security'),
          _SecretStoreOption(store: mail.store),
          heading('Microsoft accounts'),
          _MicrosoftRegistrationOption(store: mail.store),
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
    final controller = signatureController(account);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => OutlookDialog(
        title: 'Signature - ${account.emailAddress}',
        width: 560,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
        child: SignatureEditor(controller: controller, height: 180),
      ),
    );
    final values = signatureValues(controller);
    controller.dispose();
    if (saved != true || !context.mounted) return;
    await context.read<AccountProvider>().updateAccount(values.html == null
        ? account.copyWith(clearSignature: true)
        : account.copyWith(signature: values.text ?? '', signatureHtml: values.html));
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
