import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/email_message.dart';
import '../../providers/mail_provider.dart';
import '../../widgets/folder_pane.dart';
import '../../widgets/message_list.dart';
import '../../widgets/reading_pane.dart';
import 'compose_screen.dart';

export 'compose_screen.dart' show ComposeScreenRoute;

/// The main mail view with three-pane layout:
/// Folder pane | Message list | Reading pane
class MailView extends StatelessWidget {
  const MailView({super.key});

  @override
  Widget build(BuildContext context) {
    final mail = context.watch<MailProvider>();

    return Row(
      children: [
        // Folder pane
        if (mail.showFolderPane) const FolderPane(),
        // Message list
        if (mail.showReadingPane)
          const MessageList()
        else
          const Expanded(child: MessageList()),
        // Reading pane
        if (mail.showReadingPane)
          Expanded(
            child: ReadingPane(
              message: mail.selectedMessage,
              onReply: () => _openCompose(
                context,
                replyTo: mail.selectedMessage,
              ),
              onReplyAll: () => _openCompose(
                context,
                replyTo: mail.selectedMessage,
                replyAll: true,
              ),
              onForward: () => _openCompose(
                context,
                forwardFrom: mail.selectedMessage,
              ),
              onDelete: () {
                final msg = mail.selectedMessage;
                if (msg != null) mail.deleteMessage(msg);
              },
            ),
          ),
      ],
    );
  }

  void _openCompose(
    BuildContext context, {
    EmailMessage? replyTo,
    bool replyAll = false,
    EmailMessage? forwardFrom,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreenRoute(
          replyTo: replyTo,
          replyAll: replyAll,
          forwardFrom: forwardFrom,
        ),
      ),
    );
  }
}
