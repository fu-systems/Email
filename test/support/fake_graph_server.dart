import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart';

/// A mail folder of the fake mailbox.
class FakeGraphFolder {
  final String id;
  String displayName;
  final String? parentId;
  final String? wellKnown;

  FakeGraphFolder(this.id, this.displayName, {this.parentId, this.wellKnown});
}

/// A message of the fake mailbox, kept as MIME.
class FakeGraphMessage {
  final String id;
  String folderId;
  final String mime;
  bool isRead;
  bool flagged;
  final DateTime received;
  final bool isDraft;

  FakeGraphMessage(
    this.id,
    this.folderId,
    this.mime, {
    this.isRead = false,
    this.flagged = false,
    required this.received,
    this.isDraft = false,
  });
}

class _Reply {
  final int status;
  final Object? json;
  final List<int>? bytes;
  final Map<String, String> headers;

  const _Reply(this.status, {this.json, this.bytes, this.headers = const {}});

  static _Reply error(int status, String code, String message) => _Reply(
    status,
    json: {
      'error': {'code': code, 'message': message},
    },
  );
}

/// A small stand-in for Microsoft Graph's mail API: folders, messages as
/// MIME, delta sync (with paging and expired delta links), moves, deletes,
/// drafts, sendMail, search, `$batch` and throttling.
class FakeGraphServer {
  late final HttpServer _server;

  /// Upload sessions live elsewhere, like Exchange's upload URLs.
  late final HttpServer _uploadServer;
  String get baseUrl => 'http://127.0.0.1:${_server.port}/v1.0';

  final folders = <String, FakeGraphFolder>{};
  final messages = <String, FakeGraphMessage>{};

  /// MIME of every message sent (sendMail, or a draft sent).
  final sent = <String>[];

  /// Attachments added to messages after they were created: name → size.
  final addedAttachments = <String, Map<String, int>>{};

  /// Attachments of the messages in [sent], by position.
  final sentAttachments = <Map<String, int>>[];

  /// The Authorization header of every upload (should be none).
  final uploadAuthorization = <String?>[];

  final _uploads =
      <
        String,
        ({String messageId, String name, int size, BytesBuilder data})
      >{};

  /// "METHOD /path" of every request, including those inside `$batch`.
  final requests = <String>[];

  /// Tokens that are refused with 401 (e.g. one "revoked" early).
  final rejectedTokens = <String>{};

  /// Every token that came with a request.
  final seenTokens = <String>[];

  /// The next [throttle] requests are answered 429 with [retryAfter].
  int throttle = 0;
  String retryAfter = '0';

  /// Delta links stop working (410), as when Exchange discards them.
  bool expireDeltaLinks = false;

  final _changes = <({int seq, String folderId, String messageId})>[];
  var _seq = 0;
  var _nextId = 0;
  final _pages = <String, ({List<Map<String, dynamic>> items, String last})>{};

  static Future<FakeGraphServer> start({int port = 0}) async {
    final fake = FakeGraphServer._();
    fake._server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    fake._server.listen(fake._handle);
    fake._uploadServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fake._uploadServer.listen(fake._handleUpload);
    return fake;
  }

  FakeGraphServer._() {
    for (final (id, name, wellKnown) in [
      ('f-inbox', 'Inbox', 'inbox'),
      ('f-drafts', 'Drafts', 'drafts'),
      ('f-sent', 'Sent Items', 'sentitems'),
      ('f-deleted', 'Deleted Items', 'deleteditems'),
      ('f-junk', 'Junk Email', 'junkemail'),
      ('f-archive', 'Archive', 'archive'),
      ('f-outbox', 'Outbox', 'outbox'),
    ]) {
      folders[id] = FakeGraphFolder(id, name, wellKnown: wellKnown);
    }
    folders['f-projects'] = FakeGraphFolder(
      'f-projects',
      'Projects',
      parentId: 'f-inbox',
    );
  }

  Future<void> close() async {
    await _server.close(force: true);
    await _uploadServer.close(force: true);
  }

  Future<void> _handleUpload(HttpRequest request) async {
    uploadAuthorization.add(
      request.headers.value(HttpHeaders.authorizationHeader),
    );
    final key = request.uri.pathSegments.last;
    final upload = _uploads[key];
    final range = RegExp(
      r'bytes (\d+)-(\d+)/(\d+)',
    ).firstMatch(request.headers.value('content-range') ?? '');
    final chunk = await request.fold<List<int>>([], (a, b) => a..addAll(b));
    final response = request.response;
    if (upload == null ||
        range == null ||
        int.parse(range[1]!) != upload.data.length) {
      response.statusCode = 416;
    } else {
      upload.data.add(chunk);
      if (upload.data.length >= upload.size) {
        _uploads.remove(key);
        addedAttachments.putIfAbsent(upload.messageId, () => {})[upload.name] =
            upload.data.length;
        response.statusCode = 201;
      } else {
        response.statusCode = 200;
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'nextExpectedRanges': ['${upload.data.length}-'],
          }),
        );
      }
    }
    await response.close();
  }

  String _newId(String prefix) =>
      // Immutable ids are long and contain characters like '-' and '='.
      '$prefix-AAMkAGI2=${(++_nextId).toString().padLeft(6, '0')}';

  FakeGraphFolder? folder(String idOrWellKnown) =>
      folders[idOrWellKnown] ??
      folders.values.where((f) => f.wellKnown == idOrWellKnown).firstOrNull;

  void _changed(String folderId, String messageId) =>
      _changes.add((seq: ++_seq, folderId: folderId, messageId: messageId));

  /// Puts a message in a folder (by well-known name or id).
  String addMessage(
    String folderName,
    String mime, {
    bool isRead = false,
    bool flagged = false,
    DateTime? received,
    bool isDraft = false,
  }) {
    final target = folder(folderName)!;
    final id = _newId('msg');
    messages[id] = FakeGraphMessage(
      id,
      target.id,
      mime,
      isRead: isRead,
      flagged: flagged,
      received: received ?? DateTime.now().toUtc(),
      isDraft: isDraft,
    );
    _changed(target.id, id);
    return id;
  }

  void setRead(String id, bool read) {
    messages[id]!.isRead = read;
    _changed(messages[id]!.folderId, id);
  }

  void remove(String id) {
    final m = messages.remove(id)!;
    _changed(m.folderId, id);
  }

  List<FakeGraphMessage> messagesIn(String folderName) {
    final f = folder(folderName)!;
    return messages.values.where((m) => m.folderId == f.id).toList();
  }

  // ─── JSON ──────────────────────────────────────────────────────────

  Map<String, dynamic> _folderJson(FakeGraphFolder f) {
    final inside = messages.values.where((m) => m.folderId == f.id);
    return {
      'id': f.id,
      'displayName': f.displayName,
      'parentFolderId': f.parentId ?? 'root',
      'childFolderCount': folders.values
          .where((c) => c.parentId == f.id)
          .length,
      'unreadItemCount': inside.where((m) => !m.isRead).length,
      'totalItemCount': inside.length,
    };
  }

  static Map<String, dynamic> _recipient(MailAddress a) => {
    'emailAddress': {'name': a.personalName ?? '', 'address': a.email},
  };

  Map<String, dynamic> messageJson(FakeGraphMessage m) {
    final mime = MimeMessage.parseFromText(m.mime);
    final text = mime.decodeTextPlainPart() ?? '';
    final importance = (mime.getHeaderValue('importance') ?? '').toLowerCase();
    return {
      'id': m.id,
      'subject': mime.decodeSubject() ?? '',
      'from': ?mime.from?.map(_recipient).firstOrNull,
      'toRecipients': (mime.to ?? const []).map(_recipient).toList(),
      'ccRecipients': (mime.cc ?? const []).map(_recipient).toList(),
      'receivedDateTime': m.received.toUtc().toIso8601String(),
      'isRead': m.isRead,
      'isDraft': m.isDraft,
      'flag': {'flagStatus': m.flagged ? 'flagged' : 'notFlagged'},
      'hasAttachments': mime.hasAttachments(),
      'bodyPreview': text.length > 255 ? text.substring(0, 255) : text,
      'importance': importance == 'high' || importance == 'low'
          ? importance
          : 'normal',
      'internetMessageId': mime.getHeaderValue('message-id'),
      'parentFolderId': m.folderId,
    };
  }

  // ─── Requests ──────────────────────────────────────────────────────

  Future<void> _handle(HttpRequest request) async {
    final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
    final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final headers = <String, String>{};
    request.headers.forEach((k, v) => headers[k.toLowerCase()] = v.join(','));
    _Reply reply;
    if (!auth.startsWith('Bearer ') || auth.length <= 7) {
      reply = _Reply.error(401, 'InvalidAuthenticationToken', 'No token');
    } else if (rejectedTokens.contains(auth.substring(7))) {
      seenTokens.add(auth.substring(7));
      reply = _Reply.error(401, 'InvalidAuthenticationToken', 'Expired');
    } else if (throttle > 0) {
      throttle--;
      requests.add('${request.method} ${request.uri.path} (throttled)');
      reply = _Reply.error(429, 'TooManyRequests', 'Slow down');
      reply = _Reply(
        429,
        json: reply.json,
        headers: {'Retry-After': retryAfter},
      );
    } else {
      seenTokens.add(auth.substring(7));
      try {
        reply = await _dispatch(request.method, request.uri, headers, body);
      } catch (e, s) {
        reply = _Reply.error(500, 'InternalServerError', '$e\n$s');
      }
    }
    final response = request.response..statusCode = reply.status;
    reply.headers.forEach(response.headers.set);
    if (reply.bytes != null) {
      response.headers.contentType = ContentType.text;
      response.add(reply.bytes!);
    } else if (reply.json != null) {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(reply.json));
    }
    await response.close();
  }

  String _mimeFromBody(List<int> body) =>
      utf8.decode(base64.decode(utf8.decode(body).trim()));

  Future<_Reply> _dispatch(
    String method,
    Uri uri,
    Map<String, String> headers,
    List<int> body,
  ) async {
    var segments = uri.pathSegments;
    if (segments.isNotEmpty && segments.first == 'v1.0') {
      segments = segments.sublist(1);
    }
    requests.add('$method /${segments.join('/')}');
    Map<String, dynamic> json() => body.isEmpty
        ? const {}
        : (jsonDecode(utf8.decode(body)) as Map).cast<String, dynamic>();
    final q = uri.queryParameters;

    if (segments.length == 1 && segments[0] == r'$batch') {
      final answers = [];
      for (final raw in (json()['requests'] as List)) {
        final item = (raw as Map).cast<String, dynamic>();
        final inner = Uri.parse('http://x/v1.0${item['url']}');
        final reply = await _dispatch(
          item['method'] as String,
          inner,
          const {},
          item['body'] == null
              ? const []
              : utf8.encode(jsonEncode(item['body'])),
        );
        answers.add({
          'id': item['id'],
          'status': reply.status,
          'headers': reply.headers,
          'body': ?reply.json,
        });
      }
      return _Reply(200, json: {'responses': answers});
    }
    if (segments.isEmpty || segments[0] != 'me') {
      return _Reply.error(404, 'NotFound', uri.path);
    }
    final path = segments.sublist(1);

    if (path.isEmpty) {
      return const _Reply(
        200,
        json: {
          'displayName': 'Ann Example',
          'mail': 'ann@outlook.com',
          'userPrincipalName': 'ann@outlook.com',
        },
      );
    }

    if (path[0] == 'sendMail' && method == 'POST') {
      final mime = _mimeFromBody(body);
      sent.add(mime);
      // Exchange files the copy in Sent Items.
      addMessage('sentitems', mime, isRead: true);
      return const _Reply(202);
    }

    if (path[0] == 'mailFolders') {
      return _folders(method, path.sublist(1), q, headers, body, json);
    }

    if (path[0] == 'messages') {
      if (path.length == 1 && method == 'POST') {
        return _createFromMime('drafts', body);
      }
      final m = messages[path[1]];
      if (m == null) {
        return _Reply.error(404, 'ErrorItemNotFound', 'No message');
      }
      if (path.length == 3 && path[2] == 'send' && method == 'POST') {
        sent.add(m.mime);
        sentAttachments.add(addedAttachments[m.id] ?? const {});
        m.folderId = folder('sentitems')!.id;
        _changed(folder('drafts')!.id, m.id);
        _changed(m.folderId, m.id);
        return const _Reply(202);
      }
      if (path.length == 3 && path[2] == 'attachments' && method == 'POST') {
        final item = json();
        addedAttachments.putIfAbsent(m.id, () => {})[item['name'] as String] =
            base64.decode(item['contentBytes'] as String).length;
        return const _Reply(201, json: {'id': 'att'});
      }
      if (path.length == 4 && path[3] == 'createUploadSession') {
        final item = (json()['AttachmentItem'] as Map).cast<String, dynamic>();
        final key = 'up${++_nextId}';
        _uploads[key] = (
          messageId: m.id,
          name: item['name'] as String,
          size: item['size'] as int,
          data: BytesBuilder(),
        );
        return _Reply(
          201,
          json: {
            'uploadUrl': 'http://127.0.0.1:${_uploadServer.port}/upload/$key',
          },
        );
      }
      if (path.length == 3 && path[2] == r'$value') {
        return _Reply(200, bytes: utf8.encode(m.mime));
      }
      if (path.length == 3 && path[2] == 'move' && method == 'POST') {
        final target = folder(json()['destinationId'] as String);
        if (target == null) {
          return _Reply.error(404, 'ErrorItemNotFound', 'No folder');
        }
        _changed(m.folderId, m.id);
        m.folderId = target.id;
        _changed(target.id, m.id);
        return _Reply(201, json: messageJson(m));
      }
      if (method == 'PATCH') {
        final changes = json();
        if (changes['isRead'] is bool) m.isRead = changes['isRead'] as bool;
        final flag = (changes['flag'] as Map?)?['flagStatus'];
        if (flag != null) m.flagged = flag == 'flagged';
        _changed(m.folderId, m.id);
        return _Reply(200, json: messageJson(m));
      }
      if (method == 'DELETE') {
        remove(m.id);
        return const _Reply(204);
      }
      if (method == 'GET') return _Reply(200, json: messageJson(m));
    }
    return _Reply.error(400, 'BadRequest', '$method ${uri.path}');
  }

  _Reply _createFromMime(String folderName, List<int> body) {
    final id = addMessage(
      folderName,
      _mimeFromBody(body),
      isRead: true,
      isDraft: true,
    );
    return _Reply(201, json: messageJson(messages[id]!));
  }

  Future<_Reply> _folders(
    String method,
    List<String> path,
    Map<String, String> q,
    Map<String, String> headers,
    List<int> body,
    Map<String, dynamic> Function() json,
  ) async {
    if (path.isEmpty) {
      if (method == 'POST') {
        final f = FakeGraphFolder(
          _newId('fld'),
          json()['displayName'] as String,
        );
        folders[f.id] = f;
        return _Reply(201, json: _folderJson(f));
      }
      return _Reply(
        200,
        json: {
          'value': [
            for (final f in folders.values)
              if (f.parentId == null) _folderJson(f),
          ],
        },
      );
    }
    final f = folder(path[0]);
    if (f == null) return _Reply.error(404, 'ErrorItemNotFound', 'No folder');
    if (path.length == 1) {
      switch (method) {
        case 'GET':
          return _Reply(200, json: _folderJson(f));
        case 'PATCH':
          f.displayName = json()['displayName'] as String;
          return _Reply(200, json: _folderJson(f));
        case 'DELETE':
          folders.remove(f.id);
          messages.removeWhere((_, m) => m.folderId == f.id);
          return const _Reply(204);
      }
    }
    if (path[1] == 'childFolders') {
      if (method == 'POST') {
        final child = FakeGraphFolder(
          _newId('fld'),
          json()['displayName'] as String,
          parentId: f.id,
        );
        folders[child.id] = child;
        return _Reply(201, json: _folderJson(child));
      }
      return _Reply(
        200,
        json: {
          'value': [
            for (final c in folders.values)
              if (c.parentId == f.id) _folderJson(c),
          ],
        },
      );
    }
    if (path[1] == 'messages') {
      if (path.length == 3 && path[2] == 'delta') {
        return _delta(f, q, headers);
      }
      if (method == 'POST') return _createFromMime(f.id, body);
      return _list(f, q);
    }
    return _Reply.error(400, 'BadRequest', path.join('/'));
  }

  static DateTime? _filterDate(String? filter, String op) {
    if (filter == null) return null;
    final match = RegExp('receivedDateTime $op (\\S+)').firstMatch(filter);
    return match == null ? null : DateTime.parse(match[1]!);
  }

  List<FakeGraphMessage> _newestFirst(FakeGraphFolder f) =>
      messages.values.where((m) => m.folderId == f.id).toList()
        ..sort((a, b) => b.received.compareTo(a.received));

  _Reply _list(FakeGraphFolder f, Map<String, String> q) {
    var list = _newestFirst(f);
    final before = _filterDate(q[r'$filter'], 'lt');
    if (before != null) {
      list = list.where((m) => m.received.isBefore(before)).toList();
    }
    final search = q[r'$search']?.replaceAll('"', '').toLowerCase();
    if (search != null) {
      list = list.where((m) => m.mime.toLowerCase().contains(search)).toList();
    }
    final skip = int.tryParse(q[r'$skip'] ?? '') ?? 0;
    final top = int.tryParse(q[r'$top'] ?? '') ?? 10;
    return _Reply(
      200,
      json: {'value': list.skip(skip).take(top).map(messageJson).toList()},
    );
  }

  _Reply _delta(
    FakeGraphFolder f,
    Map<String, String> q,
    Map<String, String> headers,
  ) {
    final pageSize =
        int.tryParse(
          RegExp(
                r'odata\.maxpagesize=(\d+)',
              ).firstMatch(headers['prefer'] ?? '')?.group(1) ??
              '',
        ) ??
        50;
    final deltaBase = '$baseUrl/me/mailFolders/${f.id}/messages/delta';
    final skipToken = q[r'$skiptoken'];
    List<Map<String, dynamic>> items;
    String last;
    if (skipToken != null) {
      final stored = _pages.remove(skipToken);
      if (stored == null) {
        return _Reply.error(410, 'SyncStateNotFound', 'Unknown skip token');
      }
      items = stored.items;
      last = stored.last;
    } else if (q[r'$deltatoken'] != null) {
      if (expireDeltaLinks) {
        return _Reply.error(410, 'SyncStateNotFound', 'The delta link expired');
      }
      final since = int.parse(q[r'$deltatoken']!);
      final ids = <String>{
        for (final c in _changes)
          if (c.seq > since && c.folderId == f.id) c.messageId,
      };
      items = [
        for (final id in ids)
          if (messages[id]?.folderId == f.id)
            messageJson(messages[id]!)
          else
            {
              'id': id,
              '@removed': {'reason': 'deleted'},
            },
      ];
      last = '$deltaBase?\$deltatoken=$_seq';
    } else {
      final since = _filterDate(q[r'$filter'], 'ge');
      items = [
        for (final m in _newestFirst(f))
          if (since == null || !m.received.isBefore(since)) messageJson(m),
      ];
      last = '$deltaBase?\$deltatoken=$_seq';
    }
    if (items.length > pageSize) {
      final key = 'page${++_nextId}';
      _pages[key] = (items: items.sublist(pageSize), last: last);
      return _Reply(
        200,
        json: {
          'value': items.sublist(0, pageSize),
          '@odata.nextLink': '$deltaBase?\$skiptoken=$key',
        },
      );
    }
    return _Reply(200, json: {'value': items, '@odata.deltaLink': last});
  }
}

/// A plain message for tests.
String fakeMime({
  required String subject,
  String from = 'Bob Example <bob@example.com>',
  String to = 'Ann Example <ann@outlook.com>',
  String body = 'Hello',
  String? messageId,
  DateTime? date,
}) =>
    'From: $from\r\n'
    'To: $to\r\n'
    'Subject: $subject\r\n'
    'Date: ${_rfcDate(date ?? DateTime.now())}\r\n'
    'Message-ID: ${messageId ?? '<${subject.hashCode.abs()}.${DateTime.now().microsecondsSinceEpoch}@example.com>'}\r\n'
    'MIME-Version: 1.0\r\n'
    'Content-Type: text/plain; charset=utf-8\r\n'
    '\r\n'
    '$body\r\n';

String _rfcDate(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[u.weekday - 1]}, ${u.day} ${months[u.month - 1]} ${u.year} '
      '${two(u.hour)}:${two(u.minute)}:${two(u.second)} +0000';
}
