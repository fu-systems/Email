import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/email_message.dart';
import '../models/folder.dart';
import '../providers/mail_provider.dart';
import '../screens/mail/compose_launcher.dart';
import '../screens/mail/mail_dialogs.dart';
import '../theme/outlook_theme.dart';
import 'common.dart';
import 'reading_pane.dart';

/// Outlook 2013-style message list: search box, All/Unread filter, sort
/// menu, date groups, multi-selection and drag and drop.
class MessageList extends StatelessWidget {
  final FocusNode? searchFocus;

  const MessageList({super.key, this.searchFocus});

  @override
  Widget build(BuildContext context) {
    final mail = context.watch<MailProvider>();
    final messages = mail.messages;
    final folder = mail.selectedFolder;
    final showGroups = mail.sort == MessageSort.date && !mail.isSearching;

    // Flatten into rows with date-group headers.
    final rows = <Object>[];
    String? lastGroup;
    for (final m in messages) {
      if (showGroups) {
        final group = dateGroupLabel(m.date, DateTime.now());
        if (group != lastGroup) {
          rows.add(group);
          lastGroup = group;
        }
      }
      rows.add(m);
    }
    final canLoadOlder = mail.canLoadOlder(folder);

    return Container(
      color: OutlookTheme.messageListBackground,
      child: Column(
        children: [
          _SearchBox(focusNode: searchFocus),
          _ListHeader(count: messages.length),
          const Divider(height: 1),
          Expanded(
            child: messages.isEmpty
                ? _EmptyState(
                    isLoading: mail.isLoading,
                    isSearching: mail.isSearching,
                    canLoadOlder: canLoadOlder,
                  )
                : ListView.builder(
                    itemCount: rows.length + (canLoadOlder ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == rows.length) {
                        return _LoadOlderButton(isLoading: mail.isLoadingOlder);
                      }
                      final row = rows[index];
                      if (row is String) return _GroupHeader(label: row);
                      final msg = row as EmailMessage;
                      return MessageListItem(
                        key: ValueKey(msg.id),
                        message: msg,
                        isSelected: mail.selectedIds.contains(msg.id),
                        isFocused: mail.selectedMessage?.id == msg.id,
                        folderName: mail.isSearching
                            ? mail.store.getFolder(msg.folderId)?.displayName
                            : null,
                        isDraftFolder: folder?.type == FolderType.drafts,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Outlook's date group for a message received at [date].
  static String dateGroupLabel(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff < 0) return 'Today';
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    final startOfWeek = today.subtract(Duration(days: today.weekday % 7));
    if (!day.isBefore(startOfWeek)) return DateFormat.EEEE().format(date);
    if (!day.isBefore(startOfWeek.subtract(const Duration(days: 7)))) {
      return 'Last Week';
    }
    if (!day.isBefore(startOfWeek.subtract(const Duration(days: 14)))) {
      return 'Two Weeks Ago';
    }
    if (!day.isBefore(startOfWeek.subtract(const Duration(days: 21)))) {
      return 'Three Weeks Ago';
    }
    final startOfMonth = DateTime(today.year, today.month, 1);
    if (!day.isBefore(startOfMonth)) return 'Earlier this Month';
    final startOfLastMonth = DateTime(today.year, today.month - 1, 1);
    if (!day.isBefore(startOfLastMonth)) return 'Last Month';
    return 'Older';
  }
}

class _SearchBox extends StatefulWidget {
  final FocusNode? focusNode;

  const _SearchBox({this.focusNode});

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mail = context.watch<MailProvider>();
    if (!mail.isSearching && _controller.text.isNotEmpty) {
      _controller.clear();
    }
    final scopeLabel = mail.searchScope == SearchScope.currentFolder
        ? 'Current Folder'
        : 'All Mailboxes';
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 30,
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () {
                    _controller.clear();
                    mail.clearSearch();
                  },
                },
                child: TextField(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  onChanged: mail.setSearchQuery,
                  onSubmitted: (_) {
                    if (mail.isSearching) mail.searchOnServer();
                  },
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'Search $scopeLabel (Ctrl+E)',
                    hintStyle: const TextStyle(
                        fontSize: 12.5, color: OutlookTheme.textMuted),
                    suffixIcon: mail.isSearching
                        ? IconButton(
                            tooltip: 'Close search',
                            icon: const Icon(Icons.close, size: 14),
                            onPressed: () {
                              _controller.clear();
                              mail.clearSearch();
                            },
                          )
                        : const Icon(Icons.search, size: 16),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<SearchScope>(
            tooltip: 'Search scope',
            initialValue: mail.searchScope,
            onSelected: mail.setSearchScope,
            itemBuilder: (_) => [
              for (final s in SearchScope.values)
                PopupMenuItem(
                  value: s,
                  height: 30,
                  child: Text(s.label, style: const TextStyle(fontSize: 12.5)),
                ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.arrow_drop_down,
                  size: 18, color: OutlookTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  final int count;

  const _ListHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    final mail = context.watch<MailProvider>();
    Widget tab(String label, bool active, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? OutlookTheme.primaryBlue : OutlookTheme.textSecondary,
              ),
            ),
          ),
        );

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          if (mail.isSearching) ...[
            Text(
              mail.isSearchingServer
                  ? 'Searching the server...'
                  : '$count results',
              style: const TextStyle(
                  fontSize: 12.5, color: OutlookTheme.textSecondary),
            ),
            const Spacer(),
            if (!mail.isSearchingServer)
              TextButton(
                onPressed: mail.searchOnServer,
                child: const Text('Search the server',
                    style: TextStyle(fontSize: 12)),
              ),
          ] else ...[
            tab('All', !mail.unreadOnly, () => mail.setUnreadOnly(false)),
            tab('Unread', mail.unreadOnly, () => mail.setUnreadOnly(true)),
            const Spacer(),
            PopupMenuButton<MessageSort>(
              tooltip: 'Arrange by',
              onSelected: mail.setSort,
              itemBuilder: (_) => [
                for (final s in MessageSort.values)
                  CheckedPopupMenuItem(
                    value: s,
                    checked: mail.sort == s,
                    height: 30,
                    child: Text(s.label, style: const TextStyle(fontSize: 12.5)),
                  ),
              ],
              child: Row(
                children: [
                  Text('By ${mail.sort.label}',
                      style: const TextStyle(
                          fontSize: 12, color: OutlookTheme.textSecondary)),
                  const Icon(Icons.arrow_drop_down,
                      size: 16, color: OutlookTheme.textSecondary),
                ],
              ),
            ),
            IconButton(
              tooltip: mail.sortAscending ? 'Oldest on top' : 'Newest on top',
              onPressed: () => mail.setSort(mail.sort),
              icon: Icon(
                mail.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: OutlookTheme.textSecondary,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;

  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: OutlookTheme.textSecondary,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isLoading;
  final bool isSearching;
  final bool canLoadOlder;

  const _EmptyState({
    required this.isLoading,
    required this.isSearching,
    required this.canLoadOlder,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 12),
            Text('Loading messages...',
                style: TextStyle(color: OutlookTheme.textMuted, fontSize: 13)),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isSearching
                ? 'We didn\'t find anything.'
                : 'We didn\'t find anything to show here.',
            style: const TextStyle(color: OutlookTheme.textMuted, fontSize: 13),
          ),
          if (isSearching)
            TextButton(
              onPressed: () => context.read<MailProvider>().searchOnServer(),
              child: const Text('Search the server'),
            ),
          if (canLoadOlder)
            const _LoadOlderButton(isLoading: false),
        ],
      ),
    );
  }
}

class _LoadOlderButton extends StatelessWidget {
  final bool isLoading;

  const _LoadOlderButton({required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: () =>
                    context.read<MailProvider>().loadOlderMessages(),
                child: const Text('More messages on the server',
                    style: TextStyle(fontSize: 12)),
              ),
      ),
    );
  }
}

/// Individual message row.
class MessageListItem extends StatefulWidget {
  final EmailMessage message;
  final bool isSelected;
  final bool isFocused;
  final String? folderName;
  final bool isDraftFolder;

  const MessageListItem({
    super.key,
    required this.message,
    required this.isSelected,
    this.isFocused = false,
    this.folderName,
    this.isDraftFolder = false,
  });

  @override
  State<MessageListItem> createState() => _MessageListItemState();
}

class _MessageListItemState extends State<MessageListItem> {
  bool _isHovered = false;

  void _onTap() {
    final mail = context.read<MailProvider>();
    final keys = HardwareKeyboard.instance;
    mail.selectMessage(
      widget.message,
      toggle: keys.isControlPressed,
      range: keys.isShiftPressed,
    );
  }

  void _onDoubleTap() {
    final m = widget.message;
    if (m.id.startsWith('outbox|') || m.isDraft || widget.isDraftFolder) {
      openDraft(context, m);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MessageWindow(message: m),
    ));
  }

  Future<void> _onSecondaryTap(Offset position) async {
    final mail = context.read<MailProvider>();
    if (!widget.isSelected) await mail.selectMessage(widget.message);
    if (!mounted) return;
    await showMessageContextMenu(context, position, widget.message);
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isUnread = !msg.isRead;
    final isOutbox = msg.id.startsWith('outbox|');
    final isDraft = msg.isDraft || widget.isDraftFolder;
    final selected = widget.isSelected;

    final content = Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: BoxDecoration(
        color: selected
            ? OutlookTheme.selectedItemBackground
            : _isHovered
                ? OutlookTheme.hoverColor
                : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: isUnread ? OutlookTheme.unreadIndicator : Colors.transparent,
            width: 3,
          ),
          bottom: const BorderSide(color: Color(0xFFEAEAEA)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isOutbox || isDraft
                            ? msg.to.map((a) => a.display).join('; ')
                            : msg.from.display,
                        style: isUnread
                            ? OutlookTheme.messageSenderUnread
                            : OutlookTheme.messageSenderRead,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (msg.hasAttachments)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.attach_file,
                            size: 13, color: OutlookTheme.textMuted),
                      ),
                  ],
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    if (msg.isAnswered)
                      const Padding(
                        padding: EdgeInsets.only(right: 3),
                        child: Icon(Icons.reply,
                            size: 13, color: OutlookTheme.textMuted),
                      ),
                    if (msg.importance == MessageImportance.high)
                      const Padding(
                        padding: EdgeInsets.only(right: 2),
                        child: Icon(Icons.priority_high,
                            size: 13, color: OutlookTheme.flaggedColor),
                      ),
                    if (msg.importance == MessageImportance.low)
                      const Padding(
                        padding: EdgeInsets.only(right: 2),
                        child: Icon(Icons.arrow_downward,
                            size: 13, color: OutlookTheme.textMuted),
                      ),
                    if (isDraft && !isOutbox)
                      const Text('[Draft] ',
                          style: TextStyle(
                              fontSize: 12.5, color: OutlookTheme.draftColor)),
                    Expanded(
                      child: Text(
                        msg.subject,
                        style: isUnread
                            ? OutlookTheme.messageSubjectUnread.copyWith(
                                color: OutlookTheme.primaryBlue)
                            : OutlookTheme.messageSubjectRead,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatListDate(msg.date, DateTime.now()),
                      style: isUnread
                          ? OutlookTheme.messageDate.copyWith(
                              color: OutlookTheme.primaryBlue,
                              fontWeight: FontWeight.w600)
                          : OutlookTheme.messageDate,
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  widget.folderName != null
                      ? '${widget.folderName} · ${msg.preview}'
                      : msg.preview,
                  style: OutlookTheme.messagePreview.copyWith(
                    color: isOutbox && msg.preview.startsWith('Not sent')
                        ? OutlookTheme.flaggedColor
                        : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 22,
            child: (_isHovered || msg.isFlagged) && !isOutbox
                ? GestureDetector(
                    onTap: () =>
                        context.read<MailProvider>().toggleFlag(msg),
                    child: Tooltip(
                      message: msg.isFlagged ? 'Clear flag' : 'Flag',
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, top: 20),
                        child: Icon(
                          msg.isFlagged ? Icons.flag : Icons.outlined_flag,
                          size: 15,
                          color: msg.isFlagged
                              ? OutlookTheme.flaggedColor
                              : OutlookTheme.textMuted,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );

    final interactive = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        onDoubleTap: _onDoubleTap,
        onSecondaryTapDown: (d) => _onSecondaryTap(d.globalPosition),
        child: content,
      ),
    );

    if (isOutbox) return interactive;

    return Draggable<List<EmailMessage>>(
      data: selected
          ? context.read<MailProvider>().selectedMessages
          : [msg],
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: Colors.white,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mail, size: 16, color: OutlookTheme.primaryBlue),
              const SizedBox(width: 6),
              Text(
                selected && context.read<MailProvider>().selectedIds.length > 1
                    ? '${context.read<MailProvider>().selectedIds.length} items'
                    : msg.subject,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      child: interactive,
    );
  }
}

/// Outlook's compact date: time for today, weekday this week, else date.
String formatListDate(DateTime date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final msgDate = DateTime(date.year, date.month, date.day);
  final diff = today.difference(msgDate).inDays;
  if (diff <= 0) return DateFormat.jm().format(date);
  if (diff < 7) return DateFormat('E h:mm a').format(date);
  if (date.year == now.year) return DateFormat('E M/d').format(date);
  return DateFormat('M/d/yyyy').format(date);
}

/// The right-click menu for messages (list and message window).
Future<void> showMessageContextMenu(
  BuildContext context,
  Offset position,
  EmailMessage message,
) async {
  final mail = context.read<MailProvider>();
  final isOutbox = message.id.startsWith('outbox|');
  final targets = mail.selectedMessages.isNotEmpty
      ? mail.selectedMessages
      : [message];
  final multiple = targets.length > 1;
  final anyUnread = targets.any((m) => !m.isRead);
  final anyFlagged = targets.any((m) => m.isFlagged);

  final choice = await showContextMenu<String>(context, position, [
    if (isOutbox) ...[
      const MenuAction('edit', 'Edit', icon: Icons.edit_outlined),
      const MenuAction('sendNow', 'Send Now', icon: Icons.send),
    ] else ...[
      MenuAction('reply', 'Reply', icon: Icons.reply, enabled: !multiple, shortcut: 'Ctrl+R'),
      MenuAction('replyAll', 'Reply All',
          icon: Icons.reply_all, enabled: !multiple, shortcut: 'Ctrl+Shift+R'),
      MenuAction('forward', 'Forward',
          icon: Icons.forward, enabled: !multiple, shortcut: 'Ctrl+F'),
      MenuAction(
        anyUnread ? 'read' : 'unread',
        anyUnread ? 'Mark as Read' : 'Mark as Unread',
        icon: anyUnread ? Icons.drafts_outlined : Icons.markunread_outlined,
        dividerBefore: true,
        shortcut: anyUnread ? 'Ctrl+Q' : 'Ctrl+U',
      ),
      MenuAction(anyFlagged ? 'unflag' : 'flag',
          anyFlagged ? 'Clear Flag' : 'Flag',
          icon: anyFlagged ? Icons.outlined_flag : Icons.flag,
          shortcut: 'Insert'),
      const MenuAction('move', 'Move to Folder...',
          icon: Icons.drive_file_move_outline, shortcut: 'Ctrl+Shift+V'),
      MenuAction('rule', 'Create Rule...',
          icon: Icons.rule, enabled: !multiple),
      MenuAction('print', 'Print', icon: Icons.print_outlined, enabled: !multiple),
    ],
    const MenuAction('delete', 'Delete',
        icon: Icons.delete_outline, dividerBefore: true, shortcut: 'Del'),
  ]);
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'edit':
      await openDraft(context, message);
      break;
    case 'sendNow':
      await mail.syncAccount(message.accountId);
      break;
    case 'reply':
      await openReply(context, message);
      break;
    case 'replyAll':
      await openReply(context, message, replyAll: true);
      break;
    case 'forward':
      await openForward(context, message);
      break;
    case 'read':
      await mail.markAsRead();
      break;
    case 'unread':
      await mail.markAsUnread();
      break;
    case 'flag':
      await mail.setFlagged(true);
      break;
    case 'unflag':
      await mail.setFlagged(false);
      break;
    case 'move':
      await showMoveToFolderDialog(context);
      break;
    case 'rule':
      await showCreateRuleDialog(context, message);
      break;
    case 'print':
      await printMessage(context, message);
      break;
    case 'delete':
      await mail.deleteMessage();
      break;
  }
}

/// A message opened in its own window (double-click in the list).
class MessageWindow extends StatelessWidget {
  final EmailMessage message;

  const MessageWindow({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            openReply(context, message),
        const SingleActivator(LogicalKeyboardKey.keyR,
            control: true, shift: true): () =>
            openReply(context, message, replyAll: true),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            openForward(context, message),
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
                    const Icon(Icons.mail_outline, size: 14, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${message.subject} - Message',
                          style: OutlookTheme.titleBarStyle,
                          overflow: TextOverflow.ellipsis),
                    ),
                    IconButton(
                      tooltip: 'Close (Esc)',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 14, color: Colors.white),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 24),
                    ),
                  ],
                ),
              ),
              Container(
                height: 40,
                decoration: OutlookTheme.ribbonDecoration,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    HoverButton(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      color: OutlookTheme.textPrimary,
                      onTap: () async {
                        final mail = context.read<MailProvider>();
                        Navigator.of(context).pop();
                        await mail.deleteMessage(message);
                      },
                    ),
                    HoverButton(
                      icon: Icons.drive_file_move_outline,
                      label: 'Move',
                      color: OutlookTheme.textPrimary,
                      onTap: () => showMoveToFolderDialog(context),
                    ),
                    HoverButton(
                      icon: Icons.markunread_outlined,
                      label: 'Mark Unread',
                      color: OutlookTheme.textPrimary,
                      onTap: () =>
                          context.read<MailProvider>().markAsUnread(message),
                    ),
                    HoverButton(
                      icon: Icons.flag_outlined,
                      label: 'Follow Up',
                      color: OutlookTheme.textPrimary,
                      onTap: () =>
                          context.read<MailProvider>().toggleFlag(message),
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
