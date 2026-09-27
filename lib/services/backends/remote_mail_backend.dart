import 'package:enough_mail/enough_mail.dart' as enough;

import '../../models/email_account.dart';
import '../../models/email_message.dart';
import '../../models/folder.dart';
import '../../models/outgoing_message.dart';
import '../mail_backend.dart';

/// What a folder sync found on the server.
class FolderSyncResult {
  /// The folder with refreshed counts and sync state.
  final MailFolder folder;

  /// New and changed messages (headers; bodies for those in [downloads]).
  final List<EmailMessage> messages;

  /// Full copies of some of [messages], for reading offline.
  final List<DownloadedMessage> downloads;

  /// Ids of cached messages that are no longer on the server.
  final Set<String> removedIds;

  /// Every cached message is stale (e.g. IMAP UIDVALIDITY changed).
  final bool reset;

  const FolderSyncResult({
    required this.folder,
    this.messages = const [],
    this.downloads = const [],
    this.removedIds = const {},
    this.reset = false,
  });
}

/// A mail service whose folders live on the server: IMAP with SMTP, or
/// Microsoft Graph. (POP3 accounts keep their folders locally.)
///
/// Messages are addressed by their [EmailMessage.serverRef]: the IMAP UID
/// or the Graph message id.
abstract class RemoteMailBackend {
  EmailAccount get account;

  /// Connects and signs in, so problems show up early.
  Future<void> connect();

  Future<void> disconnect();

  /// All folders; per-folder sync state is carried over from [previous].
  Future<List<MailFolder>> fetchFolders(List<MailFolder> previous);

  Future<MailFolder> createFolder(String name, {MailFolder? parent});

  Future<MailFolder> renameFolder(MailFolder folder, String newName);

  Future<void> deleteFolder(MailFolder folder);

  /// The newest messages of [folder], compared with the [cached] ones.
  Future<FolderSyncResult> syncFolder(
    MailFolder folder,
    List<EmailMessage> cached,
  );

  /// A batch of messages older than the oldest of [cached].
  Future<FolderSyncResult> fetchOlder(
    MailFolder folder,
    List<EmailMessage> cached,
  );

  Future<DownloadedMessage?> fetchFullMessage(
    MailFolder folder,
    EmailMessage message,
  );

  Future<void> setFlags(
    MailFolder folder,
    List<String> refs, {
    bool? seen,
    bool? flagged,
    bool? answered,
  });

  /// Deletes permanently (as opposed to moving to Deleted Items).
  Future<void> deleteMessages(MailFolder folder, List<String> refs);

  /// Moves messages; returns their new references where the server says.
  Future<Map<String, String>> moveMessages(
    MailFolder source,
    MailFolder target,
    List<String> refs,
  );

  /// Stores a message (a draft, or a copy of a sent one); returns its
  /// reference when the server reports it.
  Future<String?> appendMessage(
    MailFolder folder,
    String raw, {
    bool seen = true,
    bool draft = false,
  });

  /// Sends [mime], built from [message].
  Future<void> send(enough.MimeMessage mime, OutgoingMessage message);

  /// Whether sending files the copy in Sent Items by itself.
  bool get savesSentCopy;

  /// Messages in [folder] matching [query] on the server; [cached] ones are
  /// returned as cached.
  Future<List<EmailMessage>> search(
    MailFolder folder,
    String query,
    List<EmailMessage> cached,
  );

  /// Local id of the message [ref] in [folder].
  String messageId(MailFolder folder, String ref) =>
      '${account.id}|${folder.path}|$ref';

  /// [message] with its server reference replaced by [ref].
  EmailMessage withRef(EmailMessage message, String? ref);
}

/// IMAP for folders and messages, SMTP for sending.
class ImapMailBackend extends RemoteMailBackend {
  @override
  final EmailAccount account;
  final ImapBackend imap;

  ImapMailBackend(this.account) : imap = ImapBackend(account);

  static List<int> _uids(List<String> refs) =>
      refs.map(int.tryParse).whereType<int>().toList();

  @override
  Future<void> connect() => imap.connect();

  @override
  Future<void> disconnect() => imap.disconnect();

  @override
  Future<List<MailFolder>> fetchFolders(List<MailFolder> previous) async {
    final byPath = {for (final f in previous) f.path: f};
    final remote = await imap.fetchFolders();
    // UIDVALIDITY is refreshed when each folder is synced.
    return [
      for (final f in remote)
        f.copyWith(uidValidity: byPath[f.path]?.uidValidity),
    ];
  }

  @override
  Future<MailFolder> createFolder(String name, {MailFolder? parent}) =>
      imap.createFolder(name, parent: parent);

  @override
  Future<MailFolder> renameFolder(MailFolder folder, String newName) =>
      imap.renameFolder(folder, newName);

  @override
  Future<void> deleteFolder(MailFolder folder) => imap.deleteFolder(folder);

  @override
  Future<FolderSyncResult> syncFolder(
    MailFolder folder,
    List<EmailMessage> cached,
  ) async {
    final cachedUids = cached.map((m) => m.uid).whereType<int>().toSet();
    final snapshot = await imap.syncFolder(folder, cachedUids: cachedUids);
    Iterable<EmailMessage> removed;
    if (snapshot.uidValidityChanged) {
      removed = cached;
    } else if (snapshot.messages.isNotEmpty) {
      final minUid = snapshot.messages
          .map((m) => m.uid!)
          .reduce((a, b) => a < b ? a : b);
      // Deleted on the server, and local placeholders (moved while
      // offline) that the server listing now replaces.
      removed = cached.where(
        (m) =>
            m.uid == null ||
            (m.uid! >= minUid && !snapshot.existingUids.contains(m.uid)),
      );
    } else if (snapshot.folder.totalCount == 0) {
      removed = cached;
    } else {
      removed = const [];
    }
    return FolderSyncResult(
      folder: snapshot.folder,
      messages: snapshot.messages,
      downloads: snapshot.downloads,
      removedIds: removed.map((m) => m.id).toSet(),
      reset: snapshot.uidValidityChanged,
    );
  }

  @override
  Future<FolderSyncResult> fetchOlder(
    MailFolder folder,
    List<EmailMessage> cached,
  ) async {
    final oldest = cached
        .map((m) => m.uid)
        .whereType<int>()
        .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    if (oldest == null) return FolderSyncResult(folder: folder);
    final snapshot = await imap.fetchOlder(folder, oldestUid: oldest);
    return FolderSyncResult(
      folder: folder,
      messages: snapshot.messages,
      downloads: snapshot.downloads,
    );
  }

  @override
  Future<DownloadedMessage?> fetchFullMessage(
    MailFolder folder,
    EmailMessage message,
  ) => imap.fetchFullMessage(folder, message);

  @override
  Future<void> setFlags(
    MailFolder folder,
    List<String> refs, {
    bool? seen,
    bool? flagged,
    bool? answered,
  }) => imap.setFlags(
    folder,
    _uids(refs),
    seen: seen,
    flagged: flagged,
    answered: answered,
  );

  @override
  Future<void> deleteMessages(MailFolder folder, List<String> refs) =>
      imap.expungeMessages(folder, _uids(refs));

  @override
  Future<Map<String, String>> moveMessages(
    MailFolder source,
    MailFolder target,
    List<String> refs,
  ) async {
    final map = await imap.moveMessages(source, target, _uids(refs));
    return {for (final e in map.entries) '${e.key}': '${e.value}'};
  }

  @override
  Future<String?> appendMessage(
    MailFolder folder,
    String raw, {
    bool seen = true,
    bool draft = false,
  }) async {
    final uid = await imap.appendMessage(
      folder,
      raw,
      flags: [if (seen) r'\Seen', if (draft) r'\Draft'],
    );
    return uid?.toString();
  }

  @override
  Future<void> send(enough.MimeMessage mime, OutgoingMessage message) =>
      SmtpSender.send(account, mime, message.allRecipients);

  @override
  bool get savesSentCopy => false;

  @override
  Future<List<EmailMessage>> search(
    MailFolder folder,
    String query,
    List<EmailMessage> cached,
  ) async {
    final uids = await imap.search(folder, query);
    final byUid = {
      for (final m in cached)
        if (m.uid != null) m.uid!: m,
    };
    final missing = uids.where((u) => !byUid.containsKey(u)).take(100).toList();
    return [
      ...uids.where(byUid.containsKey).map((u) => byUid[u]!),
      ...await imap.fetchHeaders(folder, missing),
    ];
  }

  @override
  EmailMessage withRef(EmailMessage message, String? ref) =>
      EmailMessage.fromMap({
        ...message.toMap(),
        'uid': ref == null ? null : int.tryParse(ref),
        'remoteId': null,
      });
}
