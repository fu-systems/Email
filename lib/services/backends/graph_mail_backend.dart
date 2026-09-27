import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart' as enough;

import '../../models/email_account.dart';
import '../../models/email_message.dart';
import '../../models/folder.dart';
import '../../models/outgoing_message.dart';
import '../mail_backend.dart';
import '../mime_converter.dart';
import '../oauth/oauth_config.dart';
import '../oauth/token_manager.dart';
import 'graph_client.dart';
import 'remote_mail_backend.dart';

/// Mail through Microsoft Graph, for Outlook.com and Microsoft 365.
///
/// Folders come from `/me/mailFolders`; each folder is kept up to date with
/// its delta link (stored as [MailFolder.syncState]). Messages are fetched
/// as MIME (`$value`), so reading, attachments and replies work exactly as
/// for IMAP. Sending uses `sendMail`, which files the Sent Items copy, so
/// it also works where the organization turned off SMTP sign-in.
class GraphMailBackend extends RemoteMailBackend {
  @override
  final EmailAccount account;
  final GraphClient client;

  GraphMailBackend(this.account, {GraphClient? client, TokenManager? tokens})
    : client =
          client ??
          GraphClient(
            ({bool forceRefresh = false}) =>
                (tokens ?? TokenManager.instance).accessToken(
                  account,
                  resource: OAuthResource.graph,
                  forceRefresh: forceRefresh,
                ),
          );

  /// Message properties the message list needs.
  static const messageFields =
      'id,subject,from,toRecipients,ccRecipients,receivedDateTime,isRead,'
      'flag,hasAttachments,bodyPreview,importance,internetMessageId,isDraft';

  static const _folderFields =
      'id,displayName,parentFolderId,childFolderCount,unreadItemCount,'
      'totalItemCount';

  /// How many of the newest messages a folder starts with.
  static const initialWindow = 200;

  /// New messages downloaded in full while syncing (the rest on demand).
  static const autoDownloadCount = 25;

  /// Messages per "More messages on the server".
  static const olderBatch = 50;

  static const wellKnownFolders = {
    'inbox': FolderType.inbox,
    'sentitems': FolderType.sent,
    'drafts': FolderType.drafts,
    'deleteditems': FolderType.trash,
    'junkemail': FolderType.spam,
    'archive': FolderType.archive,
    'outbox': FolderType.outbox,
  };

  static String _quote(String id) => Uri.encodeComponent(id);

  static String _utc(DateTime time) =>
      '${time.toUtc().toIso8601String().split('.').first}Z';

  // ─── Account ───────────────────────────────────────────────────────

  @override
  Future<void> connect() async {
    // Checks the sign-in and that Graph may read the mailbox.
    await client.getJson('/me/mailFolders/inbox', query: {r'$select': 'id'});
  }

  @override
  Future<void> disconnect() async {}

  /// The signed-in user's address and name (for account setup).
  Future<({String? address, String? name})> me() async {
    final me = await client.getJson(
      '/me',
      query: {r'$select': 'mail,userPrincipalName,displayName'},
    );
    final mail = me['mail'] as String?;
    return (
      address: mail != null && mail.isNotEmpty
          ? mail
          : me['userPrincipalName'] as String?,
      name: me['displayName'] as String?,
    );
  }

  // ─── Folders ───────────────────────────────────────────────────────

  @override
  Future<List<MailFolder>> fetchFolders(List<MailFolder> previous) async {
    final names = wellKnownFolders.keys.toList();
    final answers = await client.batch([
      for (final name in names)
        GraphBatchRequest('GET', '/me/mailFolders/$name?\$select=id'),
    ]);
    final typeById = <String, FolderType>{};
    for (var i = 0; i < names.length; i++) {
      final id = answers[i].ok ? answers[i].json['id'] as String? : null;
      if (id != null) typeById[id] = wellKnownFolders[names[i]]!;
    }

    final byRemoteId = {
      for (final f in previous)
        if (f.remoteId != null) f.remoteId!: f,
    };
    final folders = <MailFolder>[];
    Future<void> walk(String url, String? parentPath) async {
      final items = await client.getAll(
        url,
        query: {r'$select': _folderFields, r'$top': '250'},
      );
      for (final item in items) {
        final id = item['id'] as String;
        final type = typeById[id] ?? FolderType.other;
        // Look In shows its own Outbox.
        if (type == FolderType.outbox) continue;
        final name = (item['displayName'] as String?) ?? '';
        final segment = name.replaceAll('/', '∕');
        final path = parentPath == null ? segment : '$parentPath/$segment';
        folders.add(
          MailFolder(
            id: MailFolder.makeId(account.id, path),
            accountId: account.id,
            name: name,
            path: path,
            // Graph names its special folders; guess only if it didn't
            // answer.
            type: typeById.isEmpty ? MailFolder.detectType(name) : type,
            unreadCount: item['unreadItemCount'] as int? ?? 0,
            totalCount: item['totalItemCount'] as int? ?? 0,
            remoteId: id,
            syncState: byRemoteId[id]?.syncState,
          ),
        );
        if ((item['childFolderCount'] as int? ?? 0) > 0) {
          await walk('/me/mailFolders/${_quote(id)}/childFolders', path);
        }
      }
    }

    await walk('/me/mailFolders', null);
    return folders;
  }

  MailFolder _folderFromJson(Map<String, dynamic> item, String path) {
    return MailFolder(
      id: MailFolder.makeId(account.id, path),
      accountId: account.id,
      name: item['displayName'] as String? ?? path.split('/').last,
      path: path,
      unreadCount: item['unreadItemCount'] as int? ?? 0,
      totalCount: item['totalItemCount'] as int? ?? 0,
      remoteId: item['id'] as String?,
    );
  }

  String _remote(MailFolder folder) {
    final id = folder.remoteId;
    if (id == null) {
      throw GraphException(
        404,
        'ErrorItemNotFound',
        'The folder ${folder.name} is not on the server any more',
      );
    }
    return id;
  }

  @override
  Future<MailFolder> createFolder(String name, {MailFolder? parent}) async {
    final url = parent == null
        ? '/me/mailFolders'
        : '/me/mailFolders/${_quote(_remote(parent))}/childFolders';
    final created = (await client.request(
      'POST',
      url,
      json: {'displayName': name},
    )).json;
    final segment = name.replaceAll('/', '∕');
    return _folderFromJson(
      created,
      parent == null ? segment : '${parent.path}/$segment',
    );
  }

  @override
  Future<MailFolder> renameFolder(MailFolder folder, String newName) async {
    final updated = (await client.request(
      'PATCH',
      '/me/mailFolders/${_quote(_remote(folder))}',
      json: {'displayName': newName},
    )).json;
    final parent = folder.parentPath;
    final segment = newName.replaceAll('/', '∕');
    return _folderFromJson(
      updated,
      parent == null ? segment : '$parent/$segment',
    ).copyWith(type: folder.type, syncState: folder.syncState);
  }

  @override
  Future<void> deleteFolder(MailFolder folder) async {
    await client.request(
      'DELETE',
      '/me/mailFolders/${_quote(_remote(folder))}',
    );
  }

  // ─── Messages ──────────────────────────────────────────────────────

  static EmailAddress _address(Object? raw) {
    final email = (raw is Map ? raw['emailAddress'] : null) as Map?;
    final name = email?['name'] as String?;
    return EmailAddress(
      address: email?['address'] as String? ?? '',
      displayName: name == null || name.isEmpty ? null : name,
    );
  }

  static List<EmailAddress> _addresses(Object? raw) => [
    for (final r in (raw as List? ?? const [])) _address(r),
  ];

  /// A message of the list from Graph's JSON.
  EmailMessage messageFromJson(Map<String, dynamic> item, MailFolder folder) {
    final id = item['id'] as String;
    final flag = (item['flag'] as Map?)?['flagStatus'];
    final subject = (item['subject'] as String?) ?? '';
    return EmailMessage(
      id: messageId(folder, id),
      accountId: account.id,
      folderId: folder.id,
      subject: subject.isEmpty ? '(No Subject)' : subject,
      from: item['from'] == null
          ? const EmailAddress(address: '')
          : _address(item['from']),
      to: _addresses(item['toRecipients']),
      cc: _addresses(item['ccRecipients']),
      date:
          DateTime.tryParse(
            item['receivedDateTime'] as String? ?? '',
          )?.toLocal() ??
          DateTime.now(),
      messageId: item['internetMessageId'] as String?,
      importance: switch (item['importance']) {
        'high' => MessageImportance.high,
        'low' => MessageImportance.low,
        _ => MessageImportance.normal,
      },
      preview: ((item['bodyPreview'] as String?) ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
      isRead: item['isRead'] == true,
      isFlagged: flag == 'flagged',
      isDraft: item['isDraft'] == true,
      hasAttachments: item['hasAttachments'] == true,
      remoteId: id,
    );
  }

  Future<String> _initialDeltaUrl(String folderId) async {
    final query = <String, String>{r'$select': messageFields};
    // Start with the newest messages: find the date of the last one.
    final probe = await client.getJson(
      '/me/mailFolders/${_quote(folderId)}/messages',
      query: {
        r'$select': 'receivedDateTime',
        r'$orderby': 'receivedDateTime desc',
        r'$top': '1',
        r'$skip': '${initialWindow - 1}',
      },
    );
    final last = (probe['value'] as List? ?? const []).firstOrNull as Map?;
    final since = DateTime.tryParse(last?['receivedDateTime'] as String? ?? '');
    if (since != null) {
      query[r'$filter'] = 'receivedDateTime ge ${_utc(since)}';
    }
    return client
        .buildUri('/me/mailFolders/${_quote(folderId)}/messages/delta', query)
        .toString();
  }

  @override
  Future<FolderSyncResult> syncFolder(
    MailFolder folder,
    List<EmailMessage> cached,
  ) async {
    final folderId = _remote(folder);
    var initial = folder.syncState == null;
    var url = folder.syncState ?? await _initialDeltaUrl(folderId);
    final changed = <String, EmailMessage>{};
    final removed = <String>{};
    String? deltaLink;
    while (deltaLink == null) {
      final Map<String, dynamic> page;
      try {
        page = await client.getJson(url, pageSize: 100);
      } on GraphException catch (e) {
        if (!e.isSyncStateGone || initial) rethrow;
        // The delta link expired: list the folder again.
        initial = true;
        changed.clear();
        removed.clear();
        url = await _initialDeltaUrl(folderId);
        continue;
      }
      for (final raw in (page['value'] as List? ?? const [])) {
        final item = (raw as Map).cast<String, dynamic>();
        final ref = item['id'] as String;
        final id = messageId(folder, ref);
        if (item['@removed'] != null) {
          changed.remove(id);
          removed.add(id);
        } else {
          removed.remove(id);
          changed[id] = messageFromJson(item, folder);
        }
      }
      final next = page['@odata.nextLink'] as String?;
      deltaLink = page['@odata.deltaLink'] as String?;
      if (next != null) {
        url = next;
      } else if (deltaLink == null) {
        throw const GraphException(
          500,
          'InvalidDelta',
          'Microsoft Graph ended a sync without a delta link',
        );
      }
    }

    if (initial && cached.isNotEmpty) {
      // A full listing: cached messages it doesn't mention are gone, as
      // far as the listing reaches (older ones were loaded separately).
      final oldest = changed.values
          .map((m) => m.date)
          .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
      for (final m in cached) {
        if (changed.containsKey(m.id)) continue;
        if (m.remoteId == null || oldest == null || !m.date.isBefore(oldest)) {
          removed.add(m.id);
        }
      }
    }

    // Counts come from the folder itself.
    var updated = folder.copyWith(syncState: deltaLink);
    try {
      final info = await client.getJson(
        '/me/mailFolders/${_quote(folderId)}',
        query: {r'$select': 'unreadItemCount,totalItemCount'},
      );
      updated = updated.copyWith(
        unreadCount: info['unreadItemCount'] as int?,
        totalCount: info['totalItemCount'] as int?,
      );
    } on GraphException {
      // Keep the previous counts.
    }

    final cachedIds = {for (final m in cached) m.id};
    final fresh =
        changed.values.where((m) => !cachedIds.contains(m.id)).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final downloads = await _downloadAll(
      folder,
      fresh.take(autoDownloadCount).toList(),
    );
    return FolderSyncResult(
      folder: updated,
      messages: changed.values.toList(),
      downloads: downloads,
      removedIds: removed,
    );
  }

  @override
  Future<FolderSyncResult> fetchOlder(
    MailFolder folder,
    List<EmailMessage> cached,
  ) async {
    final oldest = cached
        .where((m) => m.remoteId != null)
        .map((m) => m.date)
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    if (oldest == null) return FolderSyncResult(folder: folder);
    final page = await client.getJson(
      '/me/mailFolders/${_quote(_remote(folder))}/messages',
      query: {
        r'$select': messageFields,
        r'$filter': 'receivedDateTime lt ${_utc(oldest)}',
        r'$orderby': 'receivedDateTime desc',
        r'$top': '$olderBatch',
      },
    );
    final messages = [
      for (final raw in (page['value'] as List? ?? const []))
        messageFromJson((raw as Map).cast(), folder),
    ];
    return FolderSyncResult(
      folder: folder,
      messages: messages,
      downloads: await _downloadAll(
        folder,
        messages.take(autoDownloadCount).toList(),
      ),
    );
  }

  Future<List<DownloadedMessage>> _downloadAll(
    MailFolder folder,
    List<EmailMessage> messages,
  ) async {
    // The client limits how many run at once.
    final results = await Future.wait(
      messages.map((m) async {
        try {
          return await fetchFullMessage(folder, m);
        } on GraphException {
          return null;
        }
      }),
    );
    return results.whereType<DownloadedMessage>().toList();
  }

  @override
  Future<DownloadedMessage?> fetchFullMessage(
    MailFolder folder,
    EmailMessage message,
  ) async {
    final ref = message.remoteId;
    if (ref == null) return null;
    final response = await client.request(
      'GET',
      '/me/messages/${_quote(ref)}/\$value',
    );
    final mime = MimeConverter.parseBytes(response.body);
    final parsed = MimeConverter.toEmailMessage(
      mime,
      id: message.id,
      accountId: account.id,
      folderId: folder.id,
      isRead: message.isRead,
    );
    return DownloadedMessage(
      parsed.copyWith(
        remoteId: ref,
        isFlagged: message.isFlagged,
        isDraft: message.isDraft,
        // Graph's received time, as in the list.
        date: message.date,
      ),
      response.body,
    );
  }

  @override
  Future<void> setFlags(
    MailFolder folder,
    List<String> refs, {
    bool? seen,
    bool? flagged,
    bool? answered,
  }) async {
    // Graph has no "answered" flag to set; Exchange tracks replies itself.
    final changes = <String, dynamic>{
      'isRead': ?seen,
      if (flagged != null)
        'flag': {'flagStatus': flagged ? 'flagged' : 'notFlagged'},
    };
    if (changes.isEmpty || refs.isEmpty) return;
    final answers = await client.batch([
      for (final ref in refs)
        GraphBatchRequest('PATCH', '/me/messages/${_quote(ref)}', changes),
    ]);
    client.checkAll(answers, allowed: {404});
  }

  @override
  Future<void> deleteMessages(MailFolder folder, List<String> refs) async {
    if (refs.isEmpty) return;
    final answers = await client.batch([
      for (final ref in refs)
        GraphBatchRequest('DELETE', '/me/messages/${_quote(ref)}'),
    ]);
    client.checkAll(answers, allowed: {404});
  }

  @override
  Future<Map<String, String>> moveMessages(
    MailFolder source,
    MailFolder target,
    List<String> refs,
  ) async {
    if (refs.isEmpty) return const {};
    final destination = _remote(target);
    final answers = await client.batch([
      for (final ref in refs)
        GraphBatchRequest('POST', '/me/messages/${_quote(ref)}/move', {
          'destinationId': destination,
        }),
    ]);
    client.checkAll(answers);
    return {
      for (var i = 0; i < refs.length; i++)
        refs[i]: answers[i].json['id'] as String? ?? refs[i],
    };
  }

  @override
  Future<String?> appendMessage(
    MailFolder folder,
    String raw, {
    bool seen = true,
    bool draft = false,
  }) async {
    // Graph creates messages from MIME as drafts.
    final created = await client.request(
      'POST',
      '/me/mailFolders/${_quote(_remote(folder))}/messages',
      body: utf8.encode(base64.encode(utf8.encode(raw))),
      contentType: 'text/plain',
    );
    return created.json['id'] as String?;
  }

  /// Largest message (as MIME) sent in one request; Graph takes 4 MB,
  /// which base64 makes 3 MB of message.
  static const mimeSendLimit = 3 * 1024 * 1024;

  /// Attachment size above which an upload session is used.
  static const uploadSessionThreshold = 3 * 1024 * 1024;

  /// Upload session chunks: a multiple of 320 KiB, below 4 MB.
  static const uploadChunkSize = 12 * 320 * 1024;

  static List<int> _base64Body(String mime) =>
      utf8.encode(base64.encode(utf8.encode(mime)));

  static void _addBcc(enough.MimeMessage mime, OutgoingMessage message) {
    // Graph takes the recipients from the headers, Bcc included.
    if (message.bcc.isNotEmpty) {
      mime.setHeader('Bcc', message.bcc.map((a) => a.toString()).join(', '));
    }
  }

  @override
  Future<void> send(enough.MimeMessage mime, OutgoingMessage message) async {
    _addBcc(mime, message);
    final raw = mime.renderMessage();
    if (raw.length <= mimeSendLimit) {
      await client.request(
        'POST',
        '/me/sendMail',
        body: _base64Body(raw),
        contentType: 'text/plain',
      );
      return;
    }
    await _sendLarge(message);
  }

  /// Too large for one request: a draft from the message without its
  /// attachments (so threading headers are kept), the attachments added
  /// one by one, then the draft sent.
  Future<void> _sendLarge(OutgoingMessage message) async {
    final files = message.attachments
        .where((a) => !a.isInline && a.localPath != null)
        .toList();
    final slim = await MimeConverter.buildMimeMessage(
      message.copyWith(
        attachments: message.attachments
            .where((a) => !files.contains(a))
            .toList(),
      ),
      account,
    );
    _addBcc(slim, message);
    final raw = slim.renderMessage();
    if (raw.length > mimeSendLimit) {
      throw const GraphException(
        413,
        'MessageTooLarge',
        'The message text and pictures in it are larger than Microsoft '
            'Graph accepts (3 MB). Send large pictures as attachments.',
      );
    }
    final draft = await client.request(
      'POST',
      '/me/mailFolders/drafts/messages',
      body: _base64Body(raw),
      contentType: 'text/plain',
    );
    final id = draft.json['id'] as String;
    try {
      for (final file in files) {
        await _attach(id, file);
      }
      await client.request('POST', '/me/messages/${_quote(id)}/send');
    } catch (_) {
      try {
        await client.request('DELETE', '/me/messages/${_quote(id)}');
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _attach(String messageId, Attachment attachment) async {
    final bytes = await File(attachment.localPath!).readAsBytes();
    final base = '/me/messages/${_quote(messageId)}/attachments';
    if (bytes.length < uploadSessionThreshold) {
      await client.request(
        'POST',
        base,
        json: {
          '@odata.type': '#microsoft.graph.fileAttachment',
          'name': attachment.fileName,
          'contentType': attachment.mimeType,
          'contentBytes': base64.encode(bytes),
        },
      );
      return;
    }
    final session = await client.request(
      'POST',
      '$base/createUploadSession',
      json: {
        'AttachmentItem': {
          'attachmentType': 'file',
          'name': attachment.fileName,
          'size': bytes.length,
          'contentType': attachment.mimeType,
        },
      },
    );
    final uploadUrl = Uri.parse(session.json['uploadUrl'] as String);
    for (var start = 0; start < bytes.length; start += uploadChunkSize) {
      final end = start + uploadChunkSize < bytes.length
          ? start + uploadChunkSize
          : bytes.length;
      await client.uploadChunk(
        uploadUrl,
        bytes.sublist(start, end),
        start: start,
        total: bytes.length,
      );
    }
  }

  @override
  bool get savesSentCopy => true;

  @override
  Future<List<EmailMessage>> search(
    MailFolder folder,
    String query,
    List<EmailMessage> cached,
  ) async {
    final page = await client.getJson(
      '/me/mailFolders/${_quote(_remote(folder))}/messages',
      query: {
        r'$search': '"${query.replaceAll('"', '')}"',
        r'$select': messageFields,
        r'$top': '100',
      },
    );
    final byId = {for (final m in cached) m.id: m};
    return [
      for (final raw in (page['value'] as List? ?? const []))
        () {
          final m = messageFromJson((raw as Map).cast(), folder);
          return byId[m.id] ?? m;
        }(),
    ];
  }

  @override
  EmailMessage withRef(EmailMessage message, String? ref) =>
      EmailMessage.fromMap({...message.toMap(), 'uid': null, 'remoteId': ref});
}
