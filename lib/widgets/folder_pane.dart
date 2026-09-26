import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/email_account.dart';
import '../models/email_message.dart';
import '../models/folder.dart';
import '../providers/mail_provider.dart';
import '../screens/mail/mail_dialogs.dart';
import '../theme/outlook_theme.dart';
import 'common.dart';

/// Outlook 2013-style folder pane: Favorites plus one folder tree per
/// account. Folders accept messages dragged from the message list.
class FolderPane extends StatefulWidget {
  const FolderPane({super.key});

  @override
  State<FolderPane> createState() => _FolderPaneState();
}

class _FolderPaneState extends State<FolderPane> {
  final Set<String> _collapsedAccounts = {};
  final Set<String> _collapsedFolders = {};
  bool _favoritesCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final mail = context.watch<MailProvider>();
    final accounts = mail.accounts;
    final defaultAccount = mail.defaultAccount;

    final favorites = <MailFolder>[];
    if (defaultAccount != null) {
      for (final type in [FolderType.inbox, FolderType.sent, FolderType.trash]) {
        final f = mail.folderByType(defaultAccount.id, type);
        if (f != null) favorites.add(f);
      }
    }

    return Container(
      decoration: OutlookTheme.folderPaneDecoration,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          if (favorites.isNotEmpty) ...[
            _SectionHeader(
              title: 'Favorites',
              collapsed: _favoritesCollapsed,
              onToggle: () =>
                  setState(() => _favoritesCollapsed = !_favoritesCollapsed),
            ),
            if (!_favoritesCollapsed)
              for (final f in favorites)
                _FolderItem(
                  folder: f,
                  depth: 0,
                  isSelected: mail.selectedFolder?.id == f.id,
                ),
            const SizedBox(height: 8),
          ],
          for (final account in accounts) ...[
            _AccountHeader(
              account: account,
              collapsed: _collapsedAccounts.contains(account.id),
              onToggle: () => setState(() {
                if (!_collapsedAccounts.remove(account.id)) {
                  _collapsedAccounts.add(account.id);
                }
              }),
            ),
            if (!_collapsedAccounts.contains(account.id))
              ..._buildTree(mail, account),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildTree(MailProvider mail, EmailAccount account) {
    final folders = mail.foldersOf(account.id);
    if (folders.isEmpty) {
      final state = mail.connectionOf(account.id);
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 4, 12, 4),
          child: Text(
            state == AccountConnection.connecting
                ? 'Connecting...'
                : state == AccountConnection.online
                    ? 'Loading folders...'
                    : 'Folders will appear once connected.',
            style: const TextStyle(fontSize: 12, color: OutlookTheme.textMuted),
          ),
        ),
      ];
    }
    final paths = folders.map((f) => f.path).toSet();
    final hasChildren = <String>{
      for (final f in folders)
        if (f.parentPath != null && paths.contains(f.parentPath)) f.parentPath!,
    };
    final widgets = <Widget>[];
    for (final f in folders) {
      // Hidden when any ancestor is collapsed.
      var hidden = false;
      var parent = f.parentPath;
      while (parent != null) {
        if (_collapsedFolders.contains('${account.id}|$parent')) {
          hidden = true;
          break;
        }
        final idx = parent.lastIndexOf(f.delimiter);
        parent = idx > 0 ? parent.substring(0, idx) : null;
      }
      if (hidden) continue;
      final key = '${account.id}|${f.path}';
      widgets.add(_FolderItem(
        folder: f,
        depth: f.type == FolderType.outbox ? 0 : f.depth,
        isSelected: mail.selectedFolder?.id == f.id,
        expandable: hasChildren.contains(f.path),
        expanded: !_collapsedFolders.contains(key),
        onToggleExpand: () => setState(() {
          if (!_collapsedFolders.remove(key)) _collapsedFolders.add(key);
        }),
      ));
    }
    return widgets;
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool collapsed;
  final VoidCallback onToggle;

  const _SectionHeader({
    required this.title,
    required this.collapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        child: Row(
          children: [
            Icon(collapsed ? Icons.arrow_right : Icons.arrow_drop_down,
                size: 18, color: OutlookTheme.textSecondary),
            Text(
              title,
              style: const TextStyle(
                fontFamily: OutlookTheme.fontFamily,
                fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: OutlookTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  final EmailAccount account;
  final bool collapsed;
  final VoidCallback onToggle;

  const _AccountHeader({
    required this.account,
    required this.collapsed,
    required this.onToggle,
  });

  Future<void> _menu(BuildContext context, Offset position) async {
    final mail = context.read<MailProvider>();
    final choice = await showContextMenu<String>(context, position, [
      const MenuAction('sync', 'Update Folder List / Send & Receive',
          icon: Icons.sync),
      const MenuAction('newFolder', 'New Folder...',
          icon: Icons.create_new_folder_outlined),
      const MenuAction('settings', 'Account Settings...',
          icon: Icons.settings_outlined, dividerBefore: true),
    ]);
    if (!context.mounted) return;
    switch (choice) {
      case 'sync':
        await mail.syncAccount(account.id, full: true);
        break;
      case 'newFolder':
        await showNewFolderDialog(context, accountId: account.id);
        break;
      case 'settings':
        await Navigator.of(context)
            .pushNamed('/account-setup', arguments: account.id);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mail = context.watch<MailProvider>();
    final state = mail.connectionOf(account.id);
    final error = mail.accountError(account.id);
    final syncing = mail.isSyncing;

    Widget? status;
    switch (state) {
      case AccountConnection.offline:
        status = Tooltip(
          message: 'Disconnected${error != null ? ': $error' : ''}',
          child: const Icon(Icons.cloud_off, size: 14, color: OutlookTheme.textMuted),
        );
        break;
      case AccountConnection.authFailed:
      case AccountConnection.error:
        status = Tooltip(
          message: error ?? 'Error',
          child: const Icon(Icons.error_outline,
              size: 14, color: OutlookTheme.flaggedColor),
        );
        break;
      case AccountConnection.connecting:
        status = const SizedBox(
            width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5));
        break;
      default:
        status = syncing
            ? const Icon(Icons.sync, size: 14, color: OutlookTheme.textMuted)
            : null;
    }

    return GestureDetector(
      onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          child: Row(
            children: [
              Icon(collapsed ? Icons.arrow_right : Icons.arrow_drop_down,
                  size: 18, color: OutlookTheme.textSecondary),
              Expanded(
                child: Tooltip(
                  message: '${account.displayName} (${account.protocol.label})',
                  child: Text(
                    account.emailAddress,
                    style: const TextStyle(
                      fontFamily: OutlookTheme.fontFamily,
                      fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: OutlookTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (status != null) status,
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderItem extends StatefulWidget {
  final MailFolder folder;
  final int depth;
  final bool isSelected;
  final bool expandable;
  final bool expanded;
  final VoidCallback? onToggleExpand;

  const _FolderItem({
    required this.folder,
    required this.depth,
    required this.isSelected,
    this.expandable = false,
    this.expanded = true,
    this.onToggleExpand,
  });

  @override
  State<_FolderItem> createState() => _FolderItemState();
}

class _FolderItemState extends State<_FolderItem> {
  bool _isHovered = false;

  Future<void> _menu(Offset position) async {
    final mail = context.read<MailProvider>();
    final f = widget.folder;
    final isOutbox = f.type == FolderType.outbox;
    final custom = f.type == FolderType.other;
    final emptiable = f.type == FolderType.trash || f.type == FolderType.spam;
    final choice = await showContextMenu<String>(context, position, [
      if (!isOutbox) ...[
        const MenuAction('newFolder', 'New Folder...',
            icon: Icons.create_new_folder_outlined),
        MenuAction('rename', 'Rename Folder',
            icon: Icons.drive_file_rename_outline, enabled: custom),
        MenuAction('delete', 'Delete Folder',
            icon: Icons.folder_delete_outlined, enabled: custom),
        const MenuAction('markRead', 'Mark All as Read',
            icon: Icons.drafts_outlined, dividerBefore: true),
        if (emptiable)
          MenuAction('empty',
              f.type == FolderType.trash ? 'Empty Folder' : 'Delete All',
              icon: Icons.delete_sweep_outlined),
        if (f.type == FolderType.inbox)
          const MenuAction('rules', 'Run Rules Now', icon: Icons.rule),
        const MenuAction('refresh', 'Update Folder',
            icon: Icons.sync, dividerBefore: true),
      ] else
        const MenuAction('sendAll', 'Send All', icon: Icons.send),
    ]);
    if (!mounted || choice == null) return;
    try {
      switch (choice) {
        case 'newFolder':
          await showNewFolderDialog(context, accountId: f.accountId, parent: f);
          break;
        case 'rename':
          final name = await showTextInputDialog(context,
              title: 'Rename Folder',
              label: 'Name',
              initialValue: f.name,
              confirmLabel: 'Rename');
          if (name != null) await mail.renameFolder(f, name);
          break;
        case 'delete':
          if (await showConfirmDialog(context,
              title: 'Delete Folder',
              message: 'Delete the folder "${f.displayName}" and all of its '
                  'messages? This cannot be undone.',
              confirmLabel: 'Delete',
              destructive: true)) {
            await mail.deleteFolder(f);
          }
          break;
        case 'markRead':
          await mail.markFolderRead(f);
          break;
        case 'empty':
          if (mounted &&
              await showConfirmDialog(context,
                  title: 'Empty Folder',
                  message: 'Everything in "${f.displayName}" will be '
                      'permanently deleted.',
                  confirmLabel: 'Delete All',
                  destructive: true)) {
            await mail.emptyFolder(f);
          }
          break;
        case 'rules':
          final n = await mail.runRulesNow(f);
          if (mounted) showStatusMessage(context, 'Rules applied to $n message(s)');
          break;
        case 'refresh':
          await mail.selectFolder(f);
          break;
        case 'sendAll':
          await mail.syncAccount(f.accountId);
          break;
      }
    } catch (e) {
      if (mounted) showStatusMessage(context, '$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.folder;
    final isSpecialCount = f.type == FolderType.drafts || f.type == FolderType.outbox;
    final count = isSpecialCount ? f.totalCount : f.unreadCount;
    final showCount = count > 0;
    final bold = f.unreadCount > 0 && !isSpecialCount;

    return DragTarget<List<EmailMessage>>(
      onWillAcceptWithDetails: (details) =>
          f.isSelectable &&
          f.type != FolderType.outbox &&
          details.data.isNotEmpty &&
          details.data.every(
              (m) => m.accountId == f.accountId && m.folderId != f.id),
      onAcceptWithDetails: (details) async {
        final mail = context.read<MailProvider>();
        await mail.moveMessagesTo(details.data, f);
        if (mounted) {
          showStatusMessage(this.context,
              'Moved ${details.data.length} item(s) to ${f.displayName}');
        }
      },
      builder: (_, candidates, rejected) {
        final isDropTarget = candidates.isNotEmpty;
        return MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: () => context.read<MailProvider>().selectFolder(f),
            onSecondaryTapDown: (d) => _menu(d.globalPosition),
            child: Container(
              height: 26,
              padding: EdgeInsets.only(left: 10.0 + 14 * widget.depth, right: 10),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? OutlookTheme.selectedItemBackground
                    : isDropTarget
                        ? OutlookTheme.selectedItemBorder.withValues(alpha: 0.35)
                        : _isHovered
                            ? OutlookTheme.hoverColor
                            : Colors.transparent,
                border: isDropTarget
                    ? Border.all(color: OutlookTheme.selectedItemBorder)
                    : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    child: widget.expandable
                        ? GestureDetector(
                            onTap: widget.onToggleExpand,
                            child: Icon(
                              widget.expanded
                                  ? Icons.arrow_drop_down
                                  : Icons.arrow_right,
                              size: 16,
                              color: OutlookTheme.textSecondary,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      f.displayName,
                      style: (bold
                              ? OutlookTheme.folderLabelBoldStyle
                              : OutlookTheme.folderLabelStyle)
                          .copyWith(
                        color: f.isSelectable
                            ? OutlookTheme.textPrimary
                            : OutlookTheme.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showCount)
                    Text(
                      isSpecialCount ? '[$count]' : '$count',
                      style: TextStyle(
                        fontFamily: OutlookTheme.fontFamily,
                        fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                        fontSize: 12,
                        fontWeight: isSpecialCount ? FontWeight.w400 : FontWeight.w600,
                        color: isSpecialCount
                            ? OutlookTheme.textSecondary
                            : OutlookTheme.primaryBlue,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
