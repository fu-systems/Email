import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/outlook_theme.dart';
import '../models/email_message.dart';

/// Outlook 2013-style reading pane for viewing email content.
class ReadingPane extends StatelessWidget {
  final EmailMessage? message;
  final VoidCallback? onReply;
  final VoidCallback? onReplyAll;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;

  const ReadingPane({
    super.key,
    this.message,
    this.onReply,
    this.onReplyAll,
    this.onForward,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (message == null) {
      return const _EmptyReadingPane();
    }

    return Container(
      color: OutlookTheme.readingPaneBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Message header
          _MessageHeader(
            message: message!,
            onReply: onReply,
            onReplyAll: onReplyAll,
            onForward: onForward,
          ),
          const Divider(height: 1),
          // Message body
          Expanded(
            child: _MessageBody(message: message!),
          ),
        ],
      ),
    );
  }
}

class _EmptyReadingPane extends StatelessWidget {
  const _EmptyReadingPane();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: OutlookTheme.readingPaneBackground,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mail_outline,
              size: 64,
              color: OutlookTheme.dividerColor,
            ),
            SizedBox(height: 16),
            Text(
              'Select a message to read',
              style: TextStyle(
                fontFamily: OutlookTheme.fontFamily,
                fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                fontSize: 16,
                color: OutlookTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageHeader extends StatelessWidget {
  final EmailMessage message;
  final VoidCallback? onReply;
  final VoidCallback? onReplyAll;
  final VoidCallback? onForward;

  const _MessageHeader({
    required this.message,
    this.onReply,
    this.onReplyAll,
    this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject
          Text(
            message.subject.isEmpty ? '(No Subject)' : message.subject,
            style: OutlookTheme.readingPaneSubject,
          ),
          const SizedBox(height: 12),
          // Quick actions row
          Row(
            children: [
              _QuickAction(
                icon: Icons.reply,
                label: 'Reply',
                onTap: onReply,
              ),
              const SizedBox(width: 4),
              _QuickAction(
                icon: Icons.reply_all,
                label: 'Reply All',
                onTap: onReplyAll,
              ),
              const SizedBox(width: 4),
              _QuickAction(
                icon: Icons.forward,
                label: 'Forward',
                onTap: onForward,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // From
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: OutlookTheme.primaryBlue,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Center(
                  child: Text(
                    _getInitials(message.from.display),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.from.display,
                      style: OutlookTheme.readingPaneSender,
                    ),
                    const SizedBox(height: 2),
                    // To
                    Row(
                      children: [
                        const Text(
                          'To: ',
                          style: OutlookTheme.readingPaneRecipient,
                        ),
                        Expanded(
                          child: Text(
                            message.to.map((a) => a.display).join('; '),
                            style: OutlookTheme.readingPaneRecipient,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (message.cc.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Text(
                            'Cc: ',
                            style: OutlookTheme.readingPaneRecipient,
                          ),
                          Expanded(
                            child: Text(
                              message.cc.map((a) => a.display).join('; '),
                              style: OutlookTheme.readingPaneRecipient,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Date
              Text(
                DateFormat('EEE M/d/yyyy h:mm a').format(message.date),
                style: OutlookTheme.messageDate,
              ),
            ],
          ),
          // Attachments
          if (message.hasAttachments && message.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: message.attachments.map((att) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: OutlookTheme.dividerColor),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.attach_file,
                          size: 14, color: OutlookTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        '${att.fileName} (${att.sizeFormatted})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: OutlookTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _QuickAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _isHovered ? OutlookTheme.hoverColor : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
            border: _isHovered
                ? Border.all(color: OutlookTheme.selectedItemBorder)
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: OutlookTheme.primaryBlue),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 12,
                  color: OutlookTheme.primaryBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  final EmailMessage message;

  const _MessageBody({required this.message});

  @override
  Widget build(BuildContext context) {
    final body = message.textBody ?? message.htmlBody ?? '';

    if (body.isEmpty) {
      return const Center(
        child: Text(
          'No content',
          style: TextStyle(
            color: OutlookTheme.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    // For now, display as plain text. HTML rendering can be added with
    // flutter_html package for richer content display.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        body,
        style: const TextStyle(
          fontFamily: OutlookTheme.fontFamily,
          fontFamilyFallback: OutlookTheme.fontFamilyFallback,
          fontSize: 14,
          color: OutlookTheme.textPrimary,
          height: 1.5,
        ),
      ),
    );
  }
}
