import 'package:flutter/material.dart';

import '../../models/email_message.dart';
import 'compose_screen.dart';

/// Opens a new message window, optionally pre-filled.
///
/// This is the entry point other modules (People, Calendar, reading pane)
/// use to start a message.
Future<void> openNewMessage(
  BuildContext context, {
  List<EmailAddress> to = const [],
  List<EmailAddress> cc = const [],
  String subject = '',
  String body = '',
  List<Attachment> attachments = const [],
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ComposeScreen(
        mode: ComposeMode.newMessage,
        initialTo: to,
        initialCc: cc,
        initialSubject: subject,
        initialBody: body,
        initialAttachments: attachments,
      ),
    ),
  );
}

/// Opens a reply (or reply-all) to [message].
Future<void> openReply(
  BuildContext context,
  EmailMessage message, {
  bool replyAll = false,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ComposeScreen(
        mode: replyAll ? ComposeMode.replyAll : ComposeMode.reply,
        original: message,
      ),
    ),
  );
}

/// Opens a forward of [message].
Future<void> openForward(BuildContext context, EmailMessage message) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ComposeScreen(
        mode: ComposeMode.forward,
        original: message,
      ),
    ),
  );
}

/// Opens a saved draft (or an Outbox item) for editing.
Future<void> openDraft(BuildContext context, EmailMessage draft) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ComposeScreen(
        mode: ComposeMode.editDraft,
        original: draft,
      ),
    ),
  );
}
