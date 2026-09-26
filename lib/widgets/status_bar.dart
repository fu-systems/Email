import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/calendar_provider.dart';
import '../providers/contacts_provider.dart';
import '../providers/mail_provider.dart';
import '../providers/navigation_provider.dart';
import '../theme/outlook_theme.dart';

/// Outlook 2013-style status bar: item counts on the left, connection and
/// synchronization state on the right.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();
    final mail = context.watch<MailProvider>();

    final left = <String>[];
    switch (nav.currentSection) {
      case NavigationSection.mail:
        if (mail.selectedFolder != null || mail.isSearching) {
          left.add('ITEMS: ${mail.messages.length}');
          if (!mail.isSearching && mail.unreadCount > 0) {
            left.add('UNREAD: ${mail.unreadCount}');
          }
        }
        break;
      case NavigationSection.calendar:
        final cal = context.watch<CalendarProvider>();
        left.add('ITEMS: ${cal.occurrencesForSelectedDate.length}');
        break;
      case NavigationSection.contacts:
        final contacts = context.watch<ContactsProvider>();
        left.add(contacts.showGroups
            ? 'GROUPS: ${contacts.filteredGroups.length}'
            : 'ITEMS: ${contacts.contacts.length}');
        break;
    }

    final status = _connectionStatus(mail);
    final outboxCount = mail.store.outbox.length;
    final pending = mail.pendingOperationCount;

    return Container(
      height: OutlookTheme.statusBarHeight,
      decoration: OutlookTheme.statusBarDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final item in left) ...[
            Text(item, style: OutlookTheme.statusBarStyle),
            const SizedBox(width: 16),
          ],
          const Spacer(),
          if (outboxCount > 0) ...[
            Text('OUTBOX: $outboxCount', style: OutlookTheme.statusBarStyle),
            const SizedBox(width: 16),
          ],
          if (pending > 0) ...[
            Tooltip(
              message: 'Changes made offline that will be sent to the server '
                  'when you reconnect',
              child: Text('$pending PENDING CHANGE${pending == 1 ? '' : 'S'}',
                  style: OutlookTheme.statusBarStyle),
            ),
            const SizedBox(width: 16),
          ],
          Tooltip(
            message: status.detail ?? '',
            child: InkWell(
              onTap: status.detail == null
                  ? null
                  : () => showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Send/Receive Progress'),
                          content: SelectableText(status.detail!),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(status.icon, size: 13, color: OutlookTheme.textOnPrimary),
                  const SizedBox(width: 6),
                  Text(status.text, style: OutlookTheme.statusBarStyle),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static ({String text, IconData icon, String? detail}) _connectionStatus(
      MailProvider mail) {
    if (mail.accounts.isEmpty) {
      return (text: 'NO ACCOUNTS', icon: Icons.info_outline, detail: null);
    }
    if (mail.workOffline) {
      return (
        text: 'WORKING OFFLINE',
        icon: Icons.cloud_off,
        detail: 'Look In is set to work offline. Turn off "Work Offline" on '
            'the Send / Receive tab to connect.',
      );
    }
    if (mail.isSyncing) {
      return (
        text: (mail.statusText ?? 'Updating...').toUpperCase(),
        icon: Icons.sync,
        detail: null,
      );
    }
    final errors = <String>[];
    var offline = 0;
    for (final a in mail.accounts.where((a) => a.isEnabled)) {
      final state = mail.connectionOf(a.id);
      final error = mail.accountError(a.id);
      if (state == AccountConnection.offline) offline++;
      if (state == AccountConnection.authFailed ||
          state == AccountConnection.error ||
          state == AccountConnection.offline) {
        errors.add('${a.emailAddress}: ${error ?? state.name}');
      }
    }
    final enabled = mail.accounts.where((a) => a.isEnabled).length;
    if (enabled > 0 && offline == enabled) {
      return (
        text: 'DISCONNECTED',
        icon: Icons.cloud_off,
        detail: 'Working from the local cache.\n\n${errors.join('\n')}',
      );
    }
    if (errors.isNotEmpty) {
      return (
        text: 'SEND/RECEIVE ERROR',
        icon: Icons.error_outline,
        detail: errors.join('\n'),
      );
    }
    if (mail.error != null) {
      return (text: 'ERROR', icon: Icons.error_outline, detail: mail.error);
    }
    if (mail.lastSync != null) {
      return (
        text: 'ALL FOLDERS ARE UP TO DATE.   CONNECTED',
        icon: Icons.check_circle_outline,
        detail: null,
      );
    }
    return (text: 'CONNECTING...', icon: Icons.sync, detail: null);
  }
}
