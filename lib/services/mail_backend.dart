import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as enough;
// SmtpCommand isn't exported; it is the documented way to extend SmtpClient.
// ignore: implementation_imports
import 'package:enough_mail/src/private/smtp/smtp_command.dart' as smtp;

import '../models/email_account.dart';
import '../models/email_message.dart';
import '../models/folder.dart';
import 'mime_converter.dart';
import 'oauth/token_manager.dart';

/// Thrown when the server cannot be reached (offline, DNS, timeouts), as
/// opposed to the server rejecting a request.
class MailConnectionException implements Exception {
  final String message;
  final Object? cause;
  const MailConnectionException(this.message, [this.cause]);

  @override
  String toString() => message;
}

/// Thrown when the server rejects the login.
class MailAuthenticationException implements Exception {
  final String message;
  const MailAuthenticationException(this.message);

  @override
  String toString() => message;
}

/// Serializes asynchronous operations (one IMAP connection can only run one
/// command sequence at a time, e.g. SELECT followed by FETCH).
class AsyncLock {
  Future<void> _last = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final previous = _last;
    _last = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }
}

/// A full message download: the parsed message and its raw MIME source.
class DownloadedMessage {
  final EmailMessage message;
  final Uint8List source;
  const DownloadedMessage(this.message, this.source);
}

/// Result of synchronizing the newest messages of an IMAP folder.
class FolderSnapshot {
  /// The folder with refreshed counts and UIDVALIDITY.
  final MailFolder folder;

  /// Newest messages (headers; bodies for those listed in [downloads]).
  final List<EmailMessage> messages;

  /// Full downloads for messages that were not cached before.
  final List<DownloadedMessage> downloads;

  /// All UIDs on the server that are >= the smallest UID in [messages];
  /// cached messages in that range that are missing here were deleted.
  final Set<int> existingUids;

  /// True when UIDVALIDITY changed and all cached UIDs are stale.
  final bool uidValidityChanged;

  const FolderSnapshot({
    required this.folder,
    required this.messages,
    required this.downloads,
    required this.existingUids,
    required this.uidValidityChanged,
  });
}

String _describe(Object error) {
  if (error is enough.ImapException) {
    return error.message ?? error.toString();
  }
  if (error is enough.SmtpException) return error.message ?? error.toString();
  if (error is enough.PopException) return error.message;
  if (error is SocketException) {
    return 'Cannot reach server: ${error.osError?.message ?? error.message}';
  }
  if (error is HandshakeException) {
    return 'Secure connection failed: ${error.message}. '
        'If the server uses a self-signed certificate, enable '
        '"Accept untrusted certificates" in the account settings.';
  }
  if (error is TimeoutException) return 'The server did not respond in time';
  return error.toString();
}

bool _isConnectionError(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is HandshakeException ||
    error is TlsException ||
    error is MailConnectionException ||
    (error is enough.ImapException &&
        (error.message?.toLowerCase().contains('closed') ?? false));

bool Function(X509Certificate)? _certificateHandler(EmailAccount account) =>
    account.acceptInvalidCertificates ? (_) => true : null;

// ─── IMAP ────────────────────────────────────────────────────────────

/// IMAP implementation of the mail operations.
///
/// Folder paths are stored in their server (modified UTF-7) encoding;
/// enough_mail APIs that re-encode paths are given the decoded form.
class ImapBackend {
  final EmailAccount account;
  final AsyncLock _lock = AsyncLock();
  enough.ImapClient? _client;

  /// Largest message downloaded completely during sync (others on demand).
  static const int autoDownloadLimit = 256 * 1024;

  static const _headerFetch = '(UID FLAGS ENVELOPE RFC822.SIZE BODYSTRUCTURE '
      'BODY.PEEK[HEADER.FIELDS (REFERENCES IMPORTANCE X-PRIORITY)])';

  ImapBackend(this.account);

  bool get isConnected => _client?.isLoggedIn ?? false;

  Future<void> connect() => _lock.run(_connect);

  Future<void> _connect() async {
    await _closeQuietly();
    final client = enough.ImapClient(
      onBadCertificate: _certificateHandler(account),
      defaultResponseTimeout: const Duration(seconds: 90),
    );
    try {
      await client.connectToServer(
        account.incomingHost,
        account.incomingPort,
        isSecure: account.incomingSecurity == ConnectionSecurity.ssl,
      );
      if (account.incomingSecurity == ConnectionSecurity.starttls) {
        await client.startTls();
      }
    } catch (e) {
      throw MailConnectionException(_describe(e), e);
    }
    try {
      if (account.usesOAuth) {
        final token = await TokenManager.instance.accessToken(account);
        await client.authenticateWithOAuth2(account.username, token);
      } else {
        await client.login(account.username, account.password);
      }
    } on enough.ImapException catch (e) {
      await _disconnectQuietly(client);
      final message = e.message ?? 'check your user name and password';
      throw MailAuthenticationException(account.usesOAuth
          ? 'Sign-in failed: ${explainMicrosoftError(message)}'
          : 'Login failed: $message');
    } on MailAuthenticationException {
      await _disconnectQuietly(client);
      rethrow;
    } on MailConnectionException {
      await _disconnectQuietly(client);
      rethrow;
    } catch (e) {
      throw MailConnectionException(_describe(e), e);
    }
    _client = client;
  }

  Future<void> disconnect() => _lock.run(_closeQuietly);

  static Future<void> _disconnectQuietly(enough.ImapClient client) async {
    try {
      await client.disconnect();
    } catch (_) {}
  }

  Future<void> _closeQuietly() async {
    final client = _client;
    _client = null;
    if (client == null) return;
    try {
      await client.logout().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      await client.disconnect();
    } catch (_) {}
  }

  /// Runs [op] with a logged-in client, reconnecting once when the
  /// connection turns out to be dead.
  Future<T> _run<T>(Future<T> Function(enough.ImapClient client) op) {
    return _lock.run(() async {
      if (_client == null || !(_client!.isConnected && _client!.isLoggedIn)) {
        await _connect();
      }
      try {
        return await op(_client!);
      } catch (e) {
        if (!_isConnectionError(e)) {
          if (e is enough.ImapException) throw Exception(_describe(e));
          rethrow;
        }
        await _connect();
        try {
          return await op(_client!);
        } catch (e2) {
          if (_isConnectionError(e2)) {
            throw MailConnectionException(_describe(e2), e2);
          }
          rethrow;
        }
      }
    });
  }

  static String decodePath(String encodedPath) => enough.Mailbox(
        encodedName: encodedPath,
        encodedPath: encodedPath,
        flags: [],
        pathSeparator: '/',
      ).path;

  enough.Mailbox _mailbox(MailFolder folder) => enough.Mailbox(
        encodedName: folder.path.split(folder.delimiter).last,
        encodedPath: folder.path,
        flags: [],
        pathSeparator: folder.delimiter,
      );

  Future<enough.Mailbox> _select(enough.ImapClient c, MailFolder folder) =>
      c.selectMailbox(_mailbox(folder));

  String _messageId(MailFolder folder, int uid) =>
      '${account.id}|${folder.path}|$uid';

  EmailMessage _convert(enough.MimeMessage msg, MailFolder folder) {
    final uid = msg.uid ?? 0;
    return MimeConverter.toEmailMessage(
      msg,
      id: _messageId(folder, uid),
      accountId: account.id,
      folderId: folder.id,
      uid: uid,
    );
  }

  // ─── Folders ───────────────────────────────────────────────────────

  Future<List<MailFolder>> fetchFolders() => _run((c) async {
        final boxes = await c.listMailboxes(recursive: true);
        final folders = <MailFolder>[];
        for (final box in boxes) {
          final selectable =
              !box.flags.contains(enough.MailboxFlag.noSelect) &&
                  !box.flags.contains(enough.MailboxFlag.nonExistent);
          var unseen = 0;
          var total = 0;
          if (selectable) {
            try {
              final status = await c.statusMailbox(
                box,
                [enough.StatusFlags.messages, enough.StatusFlags.unseen],
              );
              unseen = status.messagesUnseen;
              total = status.messagesExists;
            } catch (_) {
              // Some servers refuse STATUS on certain folders.
            }
          }
          folders.add(MailFolder(
            id: MailFolder.makeId(account.id, box.encodedPath),
            accountId: account.id,
            name: box.name,
            path: box.encodedPath,
            type: _folderType(box),
            unreadCount: unseen,
            totalCount: total,
            delimiter: box.pathSeparator,
            isSelectable: selectable,
          ));
        }
        return folders;
      });

  static FolderType _folderType(enough.Mailbox box) {
    if (box.isInbox) return FolderType.inbox;
    if (box.isSent) return FolderType.sent;
    if (box.isDrafts) return FolderType.drafts;
    if (box.isTrash) return FolderType.trash;
    if (box.isJunk) return FolderType.spam;
    if (box.isArchive || box.hasFlag(enough.MailboxFlag.all)) {
      return FolderType.archive;
    }
    if (box.hasFlag(enough.MailboxFlag.flagged)) return FolderType.starred;
    return MailFolder.detectType(box.name);
  }

  Future<MailFolder> createFolder(String name, {MailFolder? parent}) =>
      _run((c) async {
        final delimiter =
            parent?.delimiter ?? c.serverInfo.pathSeparator ?? '/';
        final decoded =
            parent == null ? name : '${decodePath(parent.path)}$delimiter$name';
        enough.Mailbox box;
        try {
          box = await c.createMailbox(decoded);
        } on enough.ImapException catch (e) {
          // enough_mail verifies the new mailbox with `LIST <path> %`, which
          // lists its children rather than the mailbox itself on some
          // servers. The CREATE succeeded; find the mailbox ourselves.
          if (!(e.message?.contains('Unable to find just created') ?? false)) {
            rethrow;
          }
          final all = await c.listMailboxes(recursive: true);
          box = all.firstWhere(
            (b) => b.path == decoded,
            orElse: () => throw Exception('Folder "$name" was not created'),
          );
        }
        return MailFolder(
          id: MailFolder.makeId(account.id, box.encodedPath),
          accountId: account.id,
          name: box.name,
          path: box.encodedPath,
          type: FolderType.other,
          delimiter: delimiter,
        );
      });

  Future<MailFolder> renameFolder(MailFolder folder, String newName) =>
      _run((c) async {
        final parent = folder.parentPath;
        final newDecoded = parent == null
            ? newName
            : '${decodePath(parent)}${folder.delimiter}$newName';
        await c.renameMailbox(_mailbox(folder), newDecoded);
        final encoded = enough.Mailbox.encode(newDecoded, folder.delimiter);
        return folder.copyWith(
          id: MailFolder.makeId(account.id, encoded),
          name: newName,
          path: encoded,
        );
      });

  Future<void> deleteFolder(MailFolder folder) =>
      _run((c) => c.deleteMailbox(_mailbox(folder)));

  // ─── Sync ──────────────────────────────────────────────────────────

  /// Fetches the newest [limit] messages of [folder] and downloads the full
  /// content of those not in [cachedUids] (up to [autoDownloadLimit]).
  Future<FolderSnapshot> syncFolder(
    MailFolder folder, {
    required Set<int> cachedUids,
    int limit = 50,
  }) =>
      _run((c) async {
        final box = await _select(c, folder);
        final validityChanged = folder.uidValidity != null &&
            box.uidValidity != null &&
            folder.uidValidity != box.uidValidity;
        final exists = box.messagesExists;
        final updatedFolder = folder.copyWith(
          totalCount: exists,
          uidValidity: box.uidValidity,
        );
        if (exists == 0) {
          return FolderSnapshot(
            folder: updatedFolder.copyWith(unreadCount: 0),
            messages: const [],
            downloads: const [],
            existingUids: const {},
            uidValidityChanged: validityChanged,
          );
        }

        final start = (exists - limit + 1).clamp(1, exists);
        final fetch = await c.fetchMessages(
          enough.MessageSequence.fromRange(start, exists),
          _headerFetch,
        );
        final messages = fetch.messages
            .where((m) => m.uid != null)
            .map((m) => _convert(m, folder))
            .toList();

        final known = validityChanged ? <int>{} : cachedUids;
        final toDownload = messages
            .where((m) =>
                !known.contains(m.uid) &&
                (m.size ?? 0) <= autoDownloadLimit)
            .map((m) => m.uid!)
            .toList();
        final downloads = await _download(c, folder, toDownload);

        // UIDs >= the oldest fetched one, to detect deletions.
        final minUid = messages
            .map((m) => m.uid!)
            .fold<int>(1 << 31, (a, b) => a < b ? a : b);
        final search = await c.uidSearchMessages(searchCriteria: 'UID $minUid:*');
        final existing = (search.matchingSequence?.toList() ?? const <int>[])
            .toSet();

        var unseen = 0;
        try {
          final unseenSearch = await c.searchMessages(searchCriteria: 'UNSEEN');
          unseen = unseenSearch.matchingSequence?.length ?? 0;
        } catch (_) {
          unseen = messages.where((m) => !m.isRead).length;
        }

        return FolderSnapshot(
          folder: updatedFolder.copyWith(unreadCount: unseen),
          messages: messages,
          downloads: downloads,
          existingUids: existing,
          uidValidityChanged: validityChanged,
        );
      });

  /// Fetches up to [limit] messages older than [oldestUid].
  Future<FolderSnapshot> fetchOlder(
    MailFolder folder, {
    required int oldestUid,
    int limit = 50,
  }) =>
      _run((c) async {
        await _select(c, folder);
        final probe = await c.uidFetchMessages(
          enough.MessageSequence.fromId(oldestUid, isUid: true),
          '(UID)',
        );
        final seq = probe.messages.firstOrNull?.sequenceId;
        if (seq == null || seq <= 1) {
          return FolderSnapshot(
            folder: folder,
            messages: const [],
            downloads: const [],
            existingUids: const {},
            uidValidityChanged: false,
          );
        }
        final end = seq - 1;
        final start = (end - limit + 1).clamp(1, end);
        final fetch = await c.fetchMessages(
          enough.MessageSequence.fromRange(start, end),
          _headerFetch,
        );
        final messages = fetch.messages
            .where((m) => m.uid != null)
            .map((m) => _convert(m, folder))
            .toList();
        final downloads = await _download(
          c,
          folder,
          messages
              .where((m) => (m.size ?? 0) <= autoDownloadLimit)
              .map((m) => m.uid!)
              .toList(),
        );
        return FolderSnapshot(
          folder: folder,
          messages: messages,
          downloads: downloads,
          existingUids: messages.map((m) => m.uid!).toSet(),
          uidValidityChanged: false,
        );
      });

  /// Downloads full messages (BODY.PEEK[] so the \Seen flag is untouched),
  /// in batches of roughly 4 MB.
  Future<List<DownloadedMessage>> _download(
    enough.ImapClient c,
    MailFolder folder,
    List<int> uids,
  ) async {
    final result = <DownloadedMessage>[];
    const batchSize = 16;
    for (var i = 0; i < uids.length; i += batchSize) {
      final batch = uids.sublist(i, (i + batchSize).clamp(0, uids.length));
      final fetch = await c.uidFetchMessages(
        enough.MessageSequence.fromIds(batch, isUid: true),
        '(UID FLAGS RFC822.SIZE BODY.PEEK[])',
      );
      for (final msg in fetch.messages) {
        if (msg.uid == null) continue;
        result.add(DownloadedMessage(
          _convert(msg, folder),
          MimeConverter.sourceBytes(msg),
        ));
      }
    }
    return result;
  }

  Future<DownloadedMessage?> fetchFullMessage(
    MailFolder folder,
    EmailMessage message,
  ) =>
      _run((c) async {
        final uid = message.uid;
        if (uid == null) return null;
        await _select(c, folder);
        final result = await _download(c, folder, [uid]);
        return result.firstOrNull;
      });

  /// Fetches headers for specific UIDs (e.g. server search results).
  Future<List<EmailMessage>> fetchHeaders(MailFolder folder, List<int> uids) =>
      _run((c) async {
        if (uids.isEmpty) return <EmailMessage>[];
        await _select(c, folder);
        final fetch = await c.uidFetchMessages(
          enough.MessageSequence.fromIds(uids, isUid: true),
          _headerFetch,
        );
        return fetch.messages
            .where((m) => m.uid != null)
            .map((m) => _convert(m, folder))
            .toList();
      });

  // ─── Flags, delete, move ───────────────────────────────────────────

  Future<void> setFlags(
    MailFolder folder,
    List<int> uids, {
    bool? seen,
    bool? flagged,
    bool? answered,
  }) =>
      _run((c) async {
        if (uids.isEmpty) return;
        await _select(c, folder);
        final seq = enough.MessageSequence.fromIds(uids, isUid: true);
        Future<void> store(String flag, bool? value) async {
          if (value == null) return;
          await c.uidStore(
            seq,
            [flag],
            action: value ? enough.StoreAction.add : enough.StoreAction.remove,
            silent: true,
          );
        }

        await store(enough.MessageFlags.seen, seen);
        await store(enough.MessageFlags.flagged, flagged);
        await store(enough.MessageFlags.answered, answered);
      });

  /// Permanently removes messages from [folder].
  Future<void> expungeMessages(MailFolder folder, List<int> uids) =>
      _run((c) async {
        if (uids.isEmpty) return;
        await _select(c, folder);
        final seq = enough.MessageSequence.fromIds(uids, isUid: true);
        await c.uidStore(seq, [enough.MessageFlags.deleted],
            action: enough.StoreAction.add, silent: true);
        if (c.serverInfo.supports('UIDPLUS')) {
          await c.uidExpunge(seq);
        } else {
          await c.expunge();
        }
      });

  /// Moves messages and returns a map of old UID to new UID when the server
  /// reports them (COPYUID), otherwise an empty map.
  Future<Map<int, int>> moveMessages(
    MailFolder from,
    MailFolder to,
    List<int> uids,
  ) =>
      _run((c) async {
        if (uids.isEmpty) return <int, int>{};
        await _select(c, from);
        final seq = enough.MessageSequence.fromIds(uids, isUid: true);
        final target = decodePath(to.path);
        enough.GenericImapResult result;
        if (c.serverInfo.supports('MOVE')) {
          result = await c.uidMove(seq, targetMailboxPath: target);
        } else {
          result = await c.uidCopy(seq, targetMailboxPath: target);
          await c.uidStore(seq, [enough.MessageFlags.deleted],
              action: enough.StoreAction.add, silent: true);
          if (c.serverInfo.supports('UIDPLUS')) {
            await c.uidExpunge(seq);
          } else {
            await c.expunge();
          }
        }
        final copyUid = result.responseCodeCopyUid;
        final mapping = <int, int>{};
        final original = copyUid?.originalSequence?.toList();
        final targetIds = copyUid?.targetSequence.toList();
        if (original != null &&
            targetIds != null &&
            original.length == targetIds.length) {
          for (var i = 0; i < original.length; i++) {
            mapping[original[i]] = targetIds[i];
          }
        }
        return mapping;
      });

  /// Appends a raw message (e.g. to Sent or Drafts). Returns the new UID
  /// when the server reports it (APPENDUID).
  Future<int?> appendMessage(
    MailFolder folder,
    String rawMessage, {
    List<String> flags = const [],
  }) =>
      _run((c) async {
        final result = await c.appendMessageText(
          rawMessage,
          flags: flags,
          targetMailboxPath: decodePath(folder.path),
        );
        return result.responseCodeAppendUid?.targetSequence.toList().firstOrNull;
      });

  /// Server-side search in [folder]; returns matching UIDs (newest first).
  Future<List<int>> search(MailFolder folder, String query) =>
      _run((c) async {
        await _select(c, folder);
        final q = query.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
        final isAscii = q.codeUnits.every((u) => u < 128);
        final criteria = 'OR OR OR SUBJECT "$q" FROM "$q" TO "$q" BODY "$q"';
        final result = await c.uidSearchMessages(
          searchCriteria: isAscii ? criteria : 'CHARSET UTF-8 $criteria',
        );
        final uids = result.matchingSequence?.toList() ?? const <int>[];
        return uids.reversed.toList();
      });
}

// ─── POP3 ────────────────────────────────────────────────────────────

/// POP3 implementation. POP3 only offers an inbox; every operation opens a
/// short session (servers lock the mailbox while a session is open).
class Pop3Backend {
  final EmailAccount account;
  final AsyncLock _lock = AsyncLock();

  Pop3Backend(this.account);

  Future<T> _session<T>(Future<T> Function(enough.PopClient c) op) {
    return _lock.run(() async {
      final client = enough.PopClient(
        onBadCertificate: _certificateHandler(account),
      );
      try {
        await client.connectToServer(
          account.incomingHost,
          account.incomingPort,
          isSecure: account.incomingSecurity == ConnectionSecurity.ssl,
        );
        if (account.incomingSecurity == ConnectionSecurity.starttls) {
          await client.startTls();
        }
      } catch (e) {
        throw MailConnectionException(_describe(e), e);
      }
      if (account.usesOAuth) {
        try {
          await client.disconnect();
        } catch (_) {}
        throw const MailAuthenticationException(
            'POP3 can\'t be used with Microsoft sign-in. Choose IMAP in '
            'Account Settings.');
      }
      try {
        await client.login(account.username, account.password);
      } on enough.PopException catch (e) {
        try {
          await client.disconnect();
        } catch (_) {}
        throw MailAuthenticationException('Login failed: ${e.message}');
      }
      try {
        final result = await op(client);
        await client.quit();
        return result;
      } catch (e) {
        try {
          await client.disconnect();
        } catch (_) {}
        if (_isConnectionError(e)) {
          throw MailConnectionException(_describe(e), e);
        }
        rethrow;
      }
    });
  }

  /// Verifies that the account can log in.
  Future<void> checkConnection() => _session((c) => c.status());

  String messageId(String inboxFolderId, String popUid) =>
      '$inboxFolderId|pop:$popUid';

  /// Downloads messages whose UIDL is not in [knownUids] (newest first, at
  /// most [limit]). When the account does not leave messages on the server
  /// they are deleted after the download.
  Future<List<DownloadedMessage>> fetchNewMessages(
    MailFolder inbox, {
    required Set<String> knownUids,
    int limit = 200,
  }) =>
      _session((c) async {
        final listings = await c.uidList();
        final fresh = listings
            .where((l) => l.uid != null && !knownUids.contains(l.uid))
            .toList()
          ..sort((a, b) => b.id.compareTo(a.id));
        final result = <DownloadedMessage>[];
        for (final listing in fresh.take(limit)) {
          final mime = await c.retrieve(listing.id);
          final message = MimeConverter.toEmailMessage(
            mime,
            id: messageId(inbox.id, listing.uid!),
            accountId: account.id,
            folderId: inbox.id,
            popUid: listing.uid,
            isRead: false,
          );
          result.add(DownloadedMessage(
            message.copyWith(size: listing.sizeInBytes),
            MimeConverter.sourceBytes(mime),
          ));
          if (!account.leaveMessagesOnServer) await c.delete(listing.id);
        }
        return result;
      });

  /// Deletes the messages with the given UIDLs from the server.
  Future<void> deleteFromServer(Set<String> popUids) => _session((c) async {
        if (popUids.isEmpty) return;
        final listings = await c.uidList();
        for (final l in listings) {
          if (l.uid != null && popUids.contains(l.uid)) await c.delete(l.id);
        }
      });
}

// ─── SMTP ────────────────────────────────────────────────────────────

class SmtpSender {
  SmtpSender._();

  /// Sends [message] to [recipients] (To, Cc and Bcc) through the account's
  /// SMTP server.
  static Future<void> send(
    EmailAccount account,
    enough.MimeMessage message,
    List<EmailAddress> recipients,
  ) async {
    final domain = account.emailAddress.contains('@')
        ? account.emailAddress.split('@').last
        : 'localhost';
    final client = await _open(account, domain);
    try {
      await client.sendMessage(
        message,
        from: enough.MailAddress(account.displayName, account.emailAddress),
        recipients: recipients
            .map((r) => enough.MailAddress(r.displayName, r.address))
            .toList(),
        use8BitEncoding: client.serverInfo.supports8BitMime,
      );
    } catch (e) {
      if (_isConnectionError(e)) {
        throw MailConnectionException(_describe(e), e);
      }
      throw Exception('Sending failed: ${_describe(e)}');
    } finally {
      await _close(client);
    }
  }

  /// Verifies the SMTP settings (connect, TLS, login) without sending.
  static Future<void> checkConnection(EmailAccount account) async {
    await _close(await _open(account, 'localhost', errorPrefix: 'SMTP: '));
  }

  /// Connects, secures and logs in; the caller closes the client.
  static Future<enough.SmtpClient> _open(EmailAccount account, String domain,
      {String errorPrefix = ''}) async {
    final client = enough.SmtpClient(
      domain,
      onBadCertificate: _certificateHandler(account),
    );
    try {
      await client.connectToServer(
        account.smtpHost,
        account.smtpPort,
        isSecure: account.smtpSecurity == ConnectionSecurity.ssl,
      );
      await client.ehlo();
      if (account.smtpSecurity == ConnectionSecurity.starttls) {
        await client.startTls();
      }
    } catch (e) {
      // No session to QUIT: sending a command would wait forever.
      await _close(client, quit: false);
      throw MailConnectionException('$errorPrefix${_describe(e)}', e);
    }
    try {
      await _authenticate(client, account);
    } catch (e) {
      await _close(client);
      if (e is! MailAuthenticationException && _isConnectionError(e)) {
        throw MailConnectionException('$errorPrefix${_describe(e)}', e);
      }
      rethrow;
    }
    return client;
  }

  static Future<void> _authenticate(
      enough.SmtpClient client, EmailAccount account) async {
    if (account.usesOAuth) {
      final token = await TokenManager.instance.accessToken(account);
      try {
        await client.sendCommand(_XOAuth2Command(account.username, token));
      } on enough.SmtpException catch (e) {
        final code = e.response.code;
        if (code == null || !const {500, 501, 502, 504}.contains(code)) {
          throw MailAuthenticationException('SMTP sign-in failed: '
              '${explainMicrosoftError(e.message ?? e.toString())}');
        }
        // The server wants the token after a 334 prompt instead.
        try {
          await client.authenticate(
              account.username, token, enough.AuthMechanism.xoauth2);
        } on enough.SmtpException catch (e) {
          throw MailAuthenticationException('SMTP sign-in failed: '
              '${explainMicrosoftError(e.message ?? e.toString())}');
        }
      }
      return;
    }
    final mechanisms = client.serverInfo.authMechanisms;
    if (account.username.isEmpty || mechanisms.isEmpty) return;
    final mechanism = passwordMechanism(mechanisms);
    if (mechanism == null) {
      throw const MailAuthenticationException(
          'SMTP login failed: the server only accepts sign-in methods Look '
          'In does not support with a password.');
    }
    try {
      await client.authenticate(account.username, account.password, mechanism);
    } on enough.SmtpException catch (e) {
      throw MailAuthenticationException(
          'SMTP login failed: ${e.message ?? e.toString()}');
    }
  }

  /// The mechanism to send a password with: PLAIN, then LOGIN, then
  /// CRAM-MD5. Never XOAUTH2, which expects a token, not a password.
  static enough.AuthMechanism? passwordMechanism(
      List<enough.AuthMechanism> offered) {
    for (final m in const [
      enough.AuthMechanism.plain,
      enough.AuthMechanism.login,
      enough.AuthMechanism.cramMd5,
    ]) {
      if (offered.contains(m)) return m;
    }
    return null;
  }

  static Future<void> _close(enough.SmtpClient client,
      {bool quit = true}) async {
    if (quit) {
      try {
        await client.quit().timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    try {
      await client.disconnect();
    } catch (_) {}
  }
}

/// `AUTH XOAUTH2` with the token on the command line (SASL initial
/// response, RFC 4954), as Thunderbird sends it. Exchange Online accepts
/// this and the two-step form; some servers (GreenMail) only this one.
class _XOAuth2Command extends smtp.SmtpCommand {
  _XOAuth2Command(String user, String token)
      : super('AUTH XOAUTH2 ${base64.encode(utf8.encode(
            'user=$user\u0001auth=Bearer $token\u0001\u0001'))}');

  bool _answeredChallenge = false;

  /// A 334 here carries a base64 JSON error; an empty line ends the
  /// exchange so that the server sends its final error code.
  @override
  String? nextCommand(enough.SmtpResponse response) {
    if (response.code == 334 && !_answeredChallenge) {
      _answeredChallenge = true;
      return '';
    }
    return null;
  }

  @override
  bool isCommandDone(enough.SmtpResponse response) =>
      response.code != 334 || _answeredChallenge;

  @override
  String toString() => 'AUTH XOAUTH2 <token>';
}

/// Adds what to do about Microsoft's common IMAP/SMTP sign-in errors.
String explainMicrosoftError(String message) {
  final m = message.toLowerCase();
  if (m.contains('smtpclientauthentication is disabled') ||
      m.contains('5.7.139')) {
    return '$message\nYour organization has turned off SMTP sign-in (SMTP '
        'AUTH) for this mailbox. An administrator can allow it (Microsoft 365 '
        'admin center > Users > Mail > Manage email apps > Authenticated '
        'SMTP).';
  }
  if (m.contains('authenticated but not connected')) {
    return '$message\nIMAP is probably turned off for this mailbox. In '
        'Outlook.com, allow it under Settings > Mail > Forwarding and IMAP; '
        'for Microsoft 365, ask your administrator to enable IMAP.';
  }
  if (m.contains('authenticate failed') || m.contains('authentication unsuccessful')) {
    return '$message\nThe mailbox may not allow IMAP/SMTP sign-in, or the '
        'app registration lacks the IMAP.AccessAsUser.All and SMTP.Send '
        'permissions.';
  }
  return message;
}

/// Tests incoming and outgoing settings of [account]. Returns null on
/// success or a user-readable error message.
Future<String?> testAccountConnection(EmailAccount account) async {
  try {
    if (account.isPop3) {
      await Pop3Backend(account).checkConnection();
    } else {
      final backend = ImapBackend(account);
      await backend.connect();
      await backend.disconnect();
    }
  } catch (e) {
    return 'Incoming (${account.protocol.label}): $e';
  }
  try {
    await SmtpSender.checkConnection(account);
  } catch (e) {
    return 'Outgoing (SMTP): $e';
  }
  return null;
}
