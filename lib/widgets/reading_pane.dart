import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/calendar_event.dart';
import '../models/email_message.dart';
import '../models/folder.dart';
import '../providers/calendar_provider.dart';
import '../providers/mail_provider.dart';
import '../screens/contacts/contacts_view.dart';
import '../screens/mail/compose_launcher.dart';
import '../services/file_dialogs.dart';
import '../services/html_sanitizer.dart';
import '../services/ical_service.dart';
import '../services/mime_converter.dart';
import '../services/print_service.dart';
import '../theme/outlook_theme.dart';
import 'common.dart';

/// Outlook 2013-style reading pane showing the selected message.
class ReadingPane extends StatelessWidget {
  const ReadingPane({super.key});

  @override
  Widget build(BuildContext context) {
    final mail = context.watch<MailProvider>();
    final message = mail.selectedMessage;
    final selectedCount = mail.selectedIds.length;

    if (message == null) {
      return _EmptyReadingPane(
        text: selectedCount > 1
            ? '$selectedCount items selected'
            : 'Select an item to read',
      );
    }

    return Container(
      color: OutlookTheme.readingPaneBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MessageHeader(message: message),
          _InfoBars(message: message, isLoading: mail.isLoadingBody),
          if (message.calendarInvite != null)
            _InviteBar(key: ValueKey('invite-${message.id}'), message: message),
          if (message.visibleAttachments.isNotEmpty)
            _AttachmentBar(message: message),
          const Divider(height: 1),
          Expanded(
            child: _MessageBody(
              key: ValueKey('body-${message.id}'),
              message: message,
              isLoading: mail.isLoadingBody,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyReadingPane extends StatelessWidget {
  final String text;

  const _EmptyReadingPane({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: OutlookTheme.readingPaneBackground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mail_outline,
                size: 64, color: OutlookTheme.dividerColor),
            const SizedBox(height: 16),
            Text(
              text,
              style: const TextStyle(
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

// ─── Header ──────────────────────────────────────────────────────────

class _MessageHeader extends StatelessWidget {
  final EmailMessage message;

  const _MessageHeader({required this.message});

  @override
  Widget build(BuildContext context) {
    final mail = context.read<MailProvider>();
    final isOutbox = message.id.startsWith('outbox|');
    final folder = mail.store.getFolder(message.folderId);
    final isDraft = message.isDraft || folder?.type == FolderType.drafts;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isOutbox || isDraft)
                HoverButton(
                  icon: Icons.edit_outlined,
                  label: isOutbox ? 'Edit' : 'Edit Draft',
                  onTap: () => openDraft(context, message),
                )
              else ...[
                HoverButton(
                  icon: Icons.reply,
                  label: 'Reply',
                  onTap: () => openReply(context, message),
                ),
                HoverButton(
                  icon: Icons.reply_all,
                  label: 'Reply All',
                  onTap: () => openReply(context, message, replyAll: true),
                ),
                HoverButton(
                  icon: Icons.forward,
                  label: 'Forward',
                  onTap: () => openForward(context, message),
                ),
              ],
              const Spacer(),
              HoverButton(
                icon: Icons.print_outlined,
                tooltip: 'Print (opens a print view in your browser)',
                color: OutlookTheme.textSecondary,
                onTap: () => printMessage(context, message),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onSecondaryTapDown: (d) =>
                    _senderMenu(context, d.globalPosition, message.from),
                child: InitialsAvatar(
                  initials: InitialsAvatar.initialsFor(message.from.display),
                  seed: message.from.address,
                  size: 44,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEE M/d/yyyy h:mm a').format(message.date),
                      style: OutlookTheme.messageDate,
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onSecondaryTapDown: (d) =>
                          _senderMenu(context, d.globalPosition, message.from),
                      child: Text(
                        message.from.displayName != null
                            ? '${message.from.displayName} <${message.from.address}>'
                            : message.from.address,
                        style: OutlookTheme.readingPaneSender,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      message.subject,
                      style: OutlookTheme.readingPaneSubject.copyWith(fontSize: 17),
                    ),
                    const SizedBox(height: 4),
                    _AddressLine(label: 'To', addresses: message.to),
                    if (message.cc.isNotEmpty)
                      _AddressLine(label: 'Cc', addresses: message.cc),
                    if (message.bcc.isNotEmpty)
                      _AddressLine(label: 'Bcc', addresses: message.bcc),
                  ],
                ),
              ),
              if (message.importance == MessageImportance.high)
                const Tooltip(
                  message: 'High importance',
                  child: Icon(Icons.priority_high,
                      color: OutlookTheme.flaggedColor, size: 18),
                ),
              if (message.isFlagged)
                const Tooltip(
                  message: 'Flagged',
                  child: Icon(Icons.flag,
                      color: OutlookTheme.flaggedColor, size: 18),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddressLine extends StatelessWidget {
  final String label;
  final List<EmailAddress> addresses;

  const _AddressLine({required this.label, required this.addresses});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(label, style: OutlookTheme.readingPaneRecipient),
          ),
          Expanded(
            child: Wrap(
              children: [
                for (var i = 0; i < addresses.length; i++)
                  GestureDetector(
                    onSecondaryTapDown: (d) =>
                        _senderMenu(context, d.globalPosition, addresses[i]),
                    child: Tooltip(
                      message: addresses[i].address,
                      child: Text(
                        '${addresses[i].display}${i < addresses.length - 1 ? '; ' : ''}',
                        style: OutlookTheme.readingPaneRecipient,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _senderMenu(
    BuildContext context, Offset position, EmailAddress address) async {
  final choice = await showContextMenu<String>(context, position, [
    const MenuAction('email', 'Send Email', icon: Icons.mail_outline),
    const MenuAction('contact', 'Add to Outlook Contacts',
        icon: Icons.person_add_alt),
    const MenuAction('copy', 'Copy', icon: Icons.copy, dividerBefore: true),
  ]);
  if (!context.mounted) return;
  switch (choice) {
    case 'email':
      await openNewMessage(context, to: [address]);
      break;
    case 'contact':
      await showDialog(
        context: context,
        builder: (_) => ContactEditorDialog(
          initialEmail: address.address,
          initialName: address.displayName,
        ),
      );
      break;
    case 'copy':
      await Clipboard.setData(ClipboardData(text: address.toString()));
      break;
  }
}

/// Prints [message] (downloading its body first when needed).
Future<void> printMessage(BuildContext context, EmailMessage message) async {
  final mail = context.read<MailProvider>();
  final full = await mail.loadFullMessage(message);
  final owner = mail.accountById(message.accountId)?.displayName ?? '';
  final ok = await PrintService.printMessage(full, owner: owner);
  if (!ok && context.mounted) {
    showStatusMessage(context,
        'Could not open the print view. Is a web browser installed?',
        isError: true);
  }
}

// ─── Info bars ───────────────────────────────────────────────────────

class _InfoBars extends StatelessWidget {
  final EmailMessage message;
  final bool isLoading;

  const _InfoBars({required this.message, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final mail = context.read<MailProvider>();
    final bars = <Widget>[];
    final outbox = mail.outboxItem(message);
    if (outbox != null) {
      bars.add(_InfoBarRow(
        icon: Icons.outbox,
        text: outbox.lastError == null
            ? 'This message is in the Outbox and will be sent on the next '
                'Send/Receive.'
            : 'This message could not be sent: ${outbox.lastError}',
        actions: [
          TextButton(
            onPressed: () => mail.syncAccount(message.accountId),
            child: const Text('Send Now'),
          ),
        ],
      ));
    }
    if (message.isAnswered) {
      bars.add(const _InfoBarRow(
          icon: Icons.reply, text: 'You replied to this message.'));
    }
    if (message.importance == MessageImportance.high) {
      bars.add(const _InfoBarRow(
          icon: Icons.priority_high,
          text: 'This message was sent with High importance.'));
    }
    if (!message.hasBody && isLoading) {
      bars.add(const _InfoBarRow(
          icon: Icons.downloading, text: 'Downloading message...'));
    } else if (!message.hasBody && outbox == null) {
      bars.add(_InfoBarRow(
        icon: Icons.cloud_off,
        text: mail.isOffline
            ? 'This message has not been downloaded yet. Connect to the '
                'network to read it.'
            : 'This message has not been downloaded yet.',
        actions: [
          TextButton(
            onPressed: () => mail.loadFullMessage(message),
            child: const Text('Download'),
          ),
        ],
      ));
    }
    return Column(children: bars);
  }
}

class _InfoBarRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final List<Widget> actions;

  const _InfoBarRow({
    required this.icon,
    required this.text,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      constraints: const BoxConstraints(minHeight: 28),
      color: const Color(0xFFF2F2F2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: OutlookTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, color: OutlookTheme.textSecondary)),
          ),
          ...actions,
        ],
      ),
    );
  }
}

// ─── Meeting invitations ─────────────────────────────────────────────

class _InviteBar extends StatefulWidget {
  final EmailMessage message;

  const _InviteBar({super.key, required this.message});

  @override
  State<_InviteBar> createState() => _InviteBarState();
}

class _InviteBarState extends State<_InviteBar> {
  CalendarEvent? _event;
  String? _method;
  bool _loaded = false;
  bool _busy = false;
  String? _response;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mail = context.read<MailProvider>();
    final invite = widget.message.calendarInvite;
    final source = await mail.messageSource(widget.message);
    if (!mounted || invite == null || source == null) return;
    final ics = MimeConverter.extractTextPart(source, invite.id);
    if (ics == null) return;
    final events = IcalService.parseEvents(ics);
    setState(() {
      _event = events.firstOrNull;
      _method = IcalService.parseMethod(ics)?.toUpperCase();
      _loaded = true;
    });
  }

  Future<void> _respond(InviteResponse? response) async {
    final event = _event;
    if (event == null) return;
    final calendar = context.read<CalendarProvider>();
    final mail = context.read<MailProvider>();
    setState(() => _busy = true);

    final existing = calendar.eventByUid(event.uid);
    if (response == InviteResponse.declined) {
      if (existing != null) calendar.removeEvent(existing.id);
    } else {
      calendar.addEvent(existing == null
          ? event
          : event.copyWith(id: existing.id, updatedAt: DateTime.now()));
    }

    if (response != null && event.organizer != null) {
      final account = mail.accountById(widget.message.accountId);
      if (account != null) {
        final ics = IcalService.generateReply(
          event: event,
          attendeeEmail: account.emailAddress,
          attendeeName: account.displayName,
          response: response,
        );
        await mail.sendCalendarReply(
          accountId: account.id,
          organizer: EmailAddress(address: event.organizer!),
          subject: '${response.label}: ${event.title}',
          text: '${account.displayName} has ${response.label.toLowerCase()} '
              'this meeting: ${event.title}',
          ics: ics,
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _response = response?.label ?? 'Added to calendar';
    });
    showStatusMessage(
      context,
      response == null
          ? 'Added "${event.title}" to your calendar'
          : '${response.label}: ${event.title}',
    );
  }

  void _removeCancelled() {
    final event = _event;
    if (event == null) return;
    final calendar = context.read<CalendarProvider>();
    final existing = calendar.eventByUid(event.uid);
    if (existing != null) calendar.removeEvent(existing.id);
    setState(() => _response = 'Removed from calendar');
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    if (!_loaded || event == null) return const SizedBox.shrink();
    final isCancel = _method == 'CANCEL';
    final when = event.isAllDay
        ? DateFormat('EEEE, MMMM d, yyyy').format(event.startTime)
        : '${DateFormat('EEEE, MMMM d, yyyy h:mm a').format(event.startTime)}'
            ' - ${DateFormat.jm().format(event.endTime)}';
    final existing = context.watch<CalendarProvider>().eventByUid(event.uid);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: OutlookTheme.hoverColor,
        border: Border.all(color: OutlookTheme.selectedItemBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isCancel ? Icons.event_busy : Icons.event,
                  size: 18, color: OutlookTheme.primaryBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isCancel ? 'Meeting canceled: ${event.title}' : event.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('When: $when', style: const TextStyle(fontSize: 12)),
          if (event.location?.isNotEmpty ?? false)
            Text('Where: ${event.location}', style: const TextStyle(fontSize: 12)),
          if (event.isRecurring)
            Text('Recurrence: ${event.recurrence!.displayName}',
                style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          if (_response != null)
            Text(_response!,
                style: const TextStyle(
                    fontSize: 12, color: OutlookTheme.calendarEventGreen))
          else if (_busy)
            const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
          else if (isCancel)
            OutlinedButton.icon(
              onPressed: existing == null ? null : _removeCancelled,
              icon: const Icon(Icons.delete_outline, size: 14),
              label: Text(existing == null
                  ? 'Not in your calendar'
                  : 'Remove from Calendar'),
            )
          else
            Wrap(
              spacing: 6,
              children: [
                if (event.organizer != null) ...[
                  OutlinedButton.icon(
                    onPressed: () => _respond(InviteResponse.accepted),
                    icon: const Icon(Icons.check,
                        size: 14, color: OutlookTheme.calendarEventGreen),
                    label: const Text('Accept'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _respond(InviteResponse.tentative),
                    icon: const Icon(Icons.help_outline, size: 14),
                    label: const Text('Tentative'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _respond(InviteResponse.declined),
                    icon: const Icon(Icons.close,
                        size: 14, color: OutlookTheme.flaggedColor),
                    label: const Text('Decline'),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: () => _respond(null),
                  icon: const Icon(Icons.event_available, size: 14),
                  label: Text(existing == null
                      ? 'Add to Calendar'
                      : 'Update in Calendar'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─── Attachments ─────────────────────────────────────────────────────

class _AttachmentBar extends StatelessWidget {
  final EmailMessage message;

  const _AttachmentBar({required this.message});

  static IconData iconFor(String mimeType, String fileName) {
    final type = mimeType.toLowerCase();
    final ext = p.extension(fileName).toLowerCase();
    if (type.startsWith('image/')) return Icons.image_outlined;
    if (type.contains('pdf') || ext == '.pdf') return Icons.picture_as_pdf_outlined;
    if (type.startsWith('text/calendar')) return Icons.event;
    if (type.startsWith('audio/')) return Icons.audiotrack;
    if (type.startsWith('video/')) return Icons.movie_outlined;
    if (type.contains('zip') || ['.zip', '.gz', '.tar', '.7z'].contains(ext)) {
      return Icons.folder_zip_outlined;
    }
    if (['.doc', '.docx', '.odt', '.rtf'].contains(ext)) {
      return Icons.description_outlined;
    }
    if (['.xls', '.xlsx', '.ods', '.csv'].contains(ext)) {
      return Icons.table_chart_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final attachments = message.visibleAttachments;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final att in attachments)
            _AttachmentChip(message: message, attachment: att),
          if (attachments.length > 1)
            HoverButton(
              icon: Icons.download,
              label: 'Save All Attachments',
              onTap: () => saveAllAttachments(context, message),
            ),
        ],
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  final EmailMessage message;
  final Attachment attachment;

  const _AttachmentChip({required this.message, required this.attachment});

  Future<Uint8List?> _data(BuildContext context) async {
    final data =
        await context.read<MailProvider>().attachmentData(message, attachment);
    if (data == null && context.mounted) {
      showStatusMessage(context,
          'The attachment could not be downloaded. Check your connection.',
          isError: true);
    }
    return data;
  }

  Future<void> _open(BuildContext context) async {
    final data = await _data(context);
    if (data == null || !context.mounted) return;
    final ok = await FileDialogs.openBytes(attachment.fileName, data);
    if (!ok && context.mounted) {
      showStatusMessage(context, 'No application is set up to open this file.',
          isError: true);
    }
  }

  Future<void> _save(BuildContext context) async {
    final data = await _data(context);
    if (data == null || !context.mounted) return;
    final path = await FileDialogs.saveFile(
      context,
      fileName: attachment.fileName,
      bytes: data,
      mimeType: attachment.mimeType,
      title: 'Save Attachment',
    );
    if (path != null && context.mounted) {
      showStatusMessage(context, 'Saved to $path');
    }
  }

  Future<void> _menu(BuildContext context, Offset position) async {
    final choice = await showContextMenu<String>(context, position, [
      const MenuAction('open', 'Open', icon: Icons.open_in_new),
      const MenuAction('save', 'Save As...', icon: Icons.save_alt),
      if (message.visibleAttachments.length > 1)
        const MenuAction('saveAll', 'Save All Attachments...',
            icon: Icons.download),
    ]);
    if (!context.mounted) return;
    switch (choice) {
      case 'open':
        await _open(context);
        break;
      case 'save':
        await _save(context);
        break;
      case 'saveAll':
        await saveAllAttachments(context, message);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${attachment.fileName}\nDouble-click to open, right-click for more',
      child: GestureDetector(
        onDoubleTap: () => _open(context),
        onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
        child: InkWell(
          onTap: () {
            final box = context.findRenderObject() as RenderBox?;
            final pos = box == null
                ? Offset.zero
                : box.localToGlobal(Offset(0, box.size.height));
            _menu(context, pos);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: OutlookTheme.dividerColor),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _AttachmentBar.iconFor(attachment.mimeType, attachment.fileName),
                  size: 18,
                  color: OutlookTheme.primaryBlue,
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(attachment.fileName,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(attachment.sizeFormatted,
                        style: const TextStyle(
                            fontSize: 10.5, color: OutlookTheme.textMuted)),
                  ],
                ),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_drop_down,
                    size: 16, color: OutlookTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Saves every attachment of [message] into a folder the user picks.
Future<void> saveAllAttachments(BuildContext context, EmailMessage message) async {
  final mail = context.read<MailProvider>();
  final dir = await FileDialogs.pickDirectory(context,
      title: 'Save All Attachments');
  if (dir == null) return;
  var saved = 0;
  for (final att in message.visibleAttachments) {
    final data = await mail.attachmentData(message, att);
    if (data == null) continue;
    var target = File(p.join(dir, FileDialogs.sanitizeFileName(att.fileName)));
    var n = 1;
    while (await target.exists()) {
      final base = p.basenameWithoutExtension(att.fileName);
      final ext = p.extension(att.fileName);
      target = File(p.join(dir, FileDialogs.sanitizeFileName('$base ($n)$ext')));
      n++;
    }
    await target.writeAsBytes(data, flush: true);
    saved++;
  }
  if (context.mounted) {
    showStatusMessage(context, 'Saved $saved attachment(s) to $dir');
  }
}

// ─── Body ────────────────────────────────────────────────────────────

class _MessageBody extends StatefulWidget {
  final EmailMessage message;
  final bool isLoading;

  const _MessageBody({super.key, required this.message, required this.isLoading});

  @override
  State<_MessageBody> createState() => _MessageBodyState();
}

class _MessageBodyState extends State<_MessageBody> {
  bool _allowImages = false;
  SanitizedHtml? _cached;
  String? _cacheKey;

  bool _senderIsSafe(MailProvider mail) {
    if (mail.store.getBool('alwaysDownloadPictures')) return true;
    final raw = mail.store.getString('safeSenders');
    if (raw == null) return false;
    final list = (jsonDecode(raw) as List).cast<String>();
    return list.contains(widget.message.from.address.toLowerCase());
  }

  void _addSafeSender(MailProvider mail) {
    final raw = mail.store.getString('safeSenders');
    final list = raw == null ? <String>[] : (jsonDecode(raw) as List).cast<String>();
    final address = widget.message.from.address.toLowerCase();
    if (!list.contains(address)) list.add(address);
    mail.store.setString('safeSenders', jsonEncode(list));
    setState(() => _allowImages = true);
  }

  SanitizedHtml _sanitized(MailProvider mail, bool allowImages) {
    final m = widget.message;
    final html = m.htmlBody;
    final key = '${m.id}|$allowImages|${html?.length}|${m.textBody?.length}';
    if (_cacheKey == key && _cached != null) return _cached!;
    SanitizedHtml result;
    if (html != null && html.trim().isNotEmpty) {
      final hasCid = html.contains('cid:');
      result = sanitizeEmailHtml(
        html,
        allowRemoteImages: allowImages,
        resolveCid: hasCid
            ? MimeConverter.cidResolver(
                mail.store.getMessageSource(m.id), m.attachments)
            : null,
      );
    } else {
      result = SanitizedHtml(
        html: '<div style="white-space: pre-wrap">'
            '${plainTextToHtml(m.textBody ?? '')}</div>',
        blockedImageCount: 0,
      );
    }
    _cacheKey = key;
    _cached = result;
    return result;
  }

  Future<void> _onLink(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (uri.scheme == 'mailto') {
      final to = EmailAddress.parseList(Uri.decodeComponent(uri.path));
      await openNewMessage(
        context,
        to: to,
        subject: uri.queryParameters['subject'] ?? '',
        body: uri.queryParameters['body'] ?? '',
      );
      return;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showStatusMessage(context, 'Could not open $url', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mail = context.watch<MailProvider>();
    final m = widget.message;
    if (!m.hasBody) {
      return Center(
        child: widget.isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('No content downloaded',
                style: TextStyle(
                    color: OutlookTheme.textMuted,
                    fontStyle: FontStyle.italic)),
      );
    }

    final allowImages = _allowImages || _senderIsSafe(mail);
    final sanitized = _sanitized(mail, allowImages);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sanitized.hasBlockedImages && !allowImages)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            color: const Color(0xFFF2F2F2),
            child: Row(
              children: [
                const Icon(Icons.image_not_supported_outlined,
                    size: 14, color: OutlookTheme.textSecondary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'To help protect your privacy, Look In prevented '
                    'automatic download of some pictures in this message.',
                    style: TextStyle(
                        fontSize: 12, color: OutlookTheme.textSecondary),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _allowImages = true),
                  child: const Text('Download pictures'),
                ),
                TextButton(
                  onPressed: () => _addSafeSender(mail),
                  child: const Text('Always from this sender'),
                ),
              ],
            ),
          ),
        Expanded(
          child: SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Html(
                data: sanitized.html,
                extensions: const [TableHtmlExtension()],
                onLinkTap: (url, _, __) => _onLink(url),
                style: {
                  'body': Style(
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                    fontFamily: OutlookTheme.fontFamily,
                    fontSize: FontSize(14),
                    color: OutlookTheme.textPrimary,
                    lineHeight: const LineHeight(1.45),
                  ),
                  'a': Style(color: OutlookTheme.textLink),
                  'blockquote': Style(
                    margin: Margins.only(left: 4),
                    padding: HtmlPaddings.only(left: 10),
                    border: const Border(
                        left: BorderSide(color: OutlookTheme.dividerColor, width: 2)),
                    color: OutlookTheme.textSecondary,
                  ),
                  'img': Style(width: Width.auto()),
                  // flutter_html ignores the cellpadding attribute.
                  'td': Style(
                      padding: HtmlPaddings.symmetric(horizontal: 6, vertical: 3)),
                  'th': Style(
                      padding: HtmlPaddings.symmetric(horizontal: 6, vertical: 3),
                      textAlign: TextAlign.left),
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
