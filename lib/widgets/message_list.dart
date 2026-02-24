import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme/outlook_theme.dart';
import '../models/email_message.dart';
import '../providers/mail_provider.dart';

/// Outlook 2013-style message list panel.
class MessageList extends StatelessWidget {
  const MessageList({super.key});

  @override
  Widget build(BuildContext context) {
    final mail = context.watch<MailProvider>();
    final messages = mail.messages;
    final selectedId = mail.selectedMessage?.id;

    return Container(
      width: OutlookTheme.messageListWidth,
      decoration: OutlookTheme.messageListDecoration,
      child: Column(
        children: [
          // Folder title and sort
          _MessageListHeader(
            folderName: mail.selectedFolder?.name ?? 'Inbox',
            messageCount: messages.length,
          ),
          const Divider(height: 1),
          // Message list
          Expanded(
            child: messages.isEmpty
                ? _EmptyState(isLoading: mail.isLoading || mail.isSyncing)
                : ListView.builder(
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return MessageListItem(
                        message: msg,
                        isSelected: msg.id == selectedId,
                        onTap: () => mail.selectMessage(msg),
                        onFlagTap: () => mail.toggleFlag(msg),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MessageListHeader extends StatelessWidget {
  final String folderName;
  final int messageCount;

  const _MessageListHeader({
    required this.folderName,
    required this.messageCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: OutlookTheme.folderPaneBackground,
      child: Row(
        children: [
          Text(
            folderName,
            style: const TextStyle(
              fontFamily: OutlookTheme.fontFamily,
              fontFamilyFallback: OutlookTheme.fontFamilyFallback,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: OutlookTheme.textPrimary,
            ),
          ),
          const Spacer(),
          Text(
            '$messageCount items',
            style: OutlookTheme.messageDate,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isLoading;

  const _EmptyState({required this.isLoading});

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
            Text(
              'Loading messages...',
              style: TextStyle(
                color: OutlookTheme.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mail_outline,
            size: 48,
            color: OutlookTheme.dividerColor,
          ),
          SizedBox(height: 12),
          Text(
            'No messages to display',
            style: TextStyle(
              color: OutlookTheme.textMuted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual message item in the message list.
class MessageListItem extends StatefulWidget {
  final EmailMessage message;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onFlagTap;

  const MessageListItem({
    super.key,
    required this.message,
    required this.isSelected,
    required this.onTap,
    this.onFlagTap,
  });

  @override
  State<MessageListItem> createState() => _MessageListItemState();
}

class _MessageListItemState extends State<MessageListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isUnread = !msg.isRead;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? OutlookTheme.selectedItemBackground
                : _isHovered
                    ? OutlookTheme.hoverColor
                    : isUnread
                        ? OutlookTheme.unreadMessageBackground
                        : OutlookTheme.readMessageBackground,
            border: Border(
              left: isUnread
                  ? const BorderSide(
                      color: OutlookTheme.unreadIndicator,
                      width: 3,
                    )
                  : BorderSide.none,
              bottom: const BorderSide(
                color: OutlookTheme.dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Message content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sender + Date row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            msg.from.display,
                            style: isUnread
                                ? OutlookTheme.messageSenderUnread
                                : OutlookTheme.messageSenderRead,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(msg.date),
                          style: OutlookTheme.messageDate,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Subject
                    Text(
                      msg.subject.isEmpty ? '(No Subject)' : msg.subject,
                      style: isUnread
                          ? OutlookTheme.messageSubjectUnread
                          : OutlookTheme.messageSubjectRead,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    // Preview + icons
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            msg.preview,
                            style: OutlookTheme.messagePreview,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (msg.hasAttachments)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.attach_file,
                              size: 14,
                              color: OutlookTheme.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Flag button
              if (_isHovered || msg.isFlagged)
                GestureDetector(
                  onTap: widget.onFlagTap,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, top: 2),
                    child: Icon(
                      msg.isFlagged ? Icons.flag : Icons.flag_outlined,
                      size: 16,
                      color: msg.isFlagged
                          ? OutlookTheme.flaggedColor
                          : OutlookTheme.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(date.year, date.month, date.day);

    if (msgDate == today) {
      return DateFormat.jm().format(date);
    } else if (today.difference(msgDate).inDays < 7) {
      return DateFormat.E().format(date);
    } else if (date.year == now.year) {
      return DateFormat('MMM d').format(date);
    } else {
      return DateFormat('M/d/yy').format(date);
    }
  }
}
