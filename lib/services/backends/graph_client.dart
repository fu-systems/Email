import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../mail_backend.dart';

/// An error answer from Microsoft Graph.
class GraphException implements Exception {
  final int status;
  final String code;
  final String message;

  const GraphException(this.status, this.code, this.message);

  bool get isNotFound => status == 404 || code == 'ErrorItemNotFound';

  /// The app registration lacks a permission, or it wasn't granted.
  bool get isAccessDenied => const {
    'ErrorAccessDenied',
    'AccessDenied',
    'Authorization_RequestDenied',
  }.contains(code);

  /// The delta link can't be used any more; sync starts over.
  bool get isSyncStateGone =>
      status == 410 ||
      const {
        'SyncStateNotFound',
        'SyncStateInvalid',
        'syncStateNotFound',
        'resyncRequired',
      }.contains(code);

  @override
  String toString() => switch (code) {
    _ when isAccessDenied =>
      'Microsoft denied access to the mailbox. The app registration needs '
          'the Mail.ReadWrite and Mail.Send permissions, and your '
          'organization may need to grant admin consent. ($message)',
    'MailboxNotEnabledForRESTAPI' || 'MailboxNotSupportedForRESTAPI' =>
      'This mailbox can\'t be reached through Microsoft Graph (for example '
          'an on-premises Exchange mailbox). Use IMAP and SMTP instead. '
          '($message)',
    _ => message.isEmpty ? 'Microsoft Graph error $status ($code)' : message,
  };
}

/// An answer from Microsoft Graph.
class GraphResponse {
  final int status;
  final Map<String, String> headers;
  final Uint8List body;

  GraphResponse(this.status, this.headers, this.body);

  bool get ok => status >= 200 && status < 300;

  Map<String, dynamic> get json {
    if (body.isEmpty) return const {};
    final decoded = jsonDecode(utf8.decode(body));
    return decoded is Map<String, dynamic> ? decoded : const {};
  }
}

/// One request of a `$batch`.
class GraphBatchRequest {
  final String method;

  /// Relative to the Graph version root, e.g. `/me/messages/{id}`.
  final String url;
  final Map<String, dynamic>? body;

  const GraphBatchRequest(this.method, this.url, [this.body]);
}

/// Microsoft Graph over HTTPS: signing requests, retrying when throttled,
/// following pages and batching.
///
/// Requests ask for immutable ids, so a message keeps its id when it is
/// moved. At most [maxConcurrent] requests run at once per mailbox, as
/// Microsoft recommends.
class GraphClient {
  /// Graph's address; `LOOKIN_GRAPH_BASE` replaces it for tests and the
  /// offline demo.
  static String baseUrl = 'https://graph.microsoft.com/v1.0';

  /// An access token; with `forceRefresh` a new one.
  final Future<String> Function({bool forceRefresh}) token;
  final HttpClient _http;
  final int maxConcurrent;
  final int maxRetries;

  /// Longest wait for a throttled request before giving up.
  final Duration maxRetryAfter;

  int _running = 0;
  final _queue = Queue<Completer<void>>();

  GraphClient(
    this.token, {
    HttpClient? httpClient,
    this.maxConcurrent = 4,
    this.maxRetries = 4,
    this.maxRetryAfter = const Duration(seconds: 60),
  }) : _http =
           httpClient ??
           (HttpClient()
             ..connectionTimeout = const Duration(seconds: 20)
             ..idleTimeout = const Duration(seconds: 30));

  void close() => _http.close();

  /// The address of [pathOrUrl] (relative to [baseUrl], or absolute) with
  /// [query] added.
  Uri buildUri(String pathOrUrl, Map<String, String>? query) {
    final base = pathOrUrl.startsWith('http')
        ? Uri.parse(pathOrUrl)
        : Uri.parse('$baseUrl$pathOrUrl');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: {...base.queryParameters, ...query});
  }

  Future<void> _acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final waiter = Completer<void>();
    _queue.add(waiter);
    await waiter.future;
  }

  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
    } else {
      _running--;
    }
  }

  /// Sends a request and returns a successful answer; throws
  /// [GraphException] for error answers, [MailConnectionException] when
  /// Graph can't be reached and [MailAuthenticationException] when the
  /// sign-in is refused.
  Future<GraphResponse> request(
    String method,
    String pathOrUrl, {
    Map<String, String>? query,
    Object? json,
    List<int>? body,
    String? contentType,
    Map<String, String> headers = const {},
    int? pageSize,
    List<String> prefer = const [],
  }) async {
    final uri = buildUri(pathOrUrl, query);
    // Links from answers (next pages, delta links) must lead back to Graph
    // before they get the token.
    if (uri.origin != Uri.parse(baseUrl).origin) {
      throw GraphException(
        400,
        'UnexpectedHost',
        'Refusing to send the sign-in to ${uri.host}',
      );
    }
    var forceRefresh = false;
    for (var attempt = 0; ; attempt++) {
      final response = await _send(
        method,
        uri,
        json: json,
        body: body,
        contentType: contentType,
        headers: headers,
        pageSize: pageSize,
        prefer: prefer,
        forceRefresh: forceRefresh,
      );
      if (response.ok) return response;
      if (response.status == 401 && !forceRefresh) {
        // Expired or revoked early: try once with a fresh token.
        forceRefresh = true;
        continue;
      }
      if (_isRetryable(response.status) && attempt < maxRetries) {
        await Future<void>.delayed(_retryDelay(response.headers, attempt));
        continue;
      }
      throw _error(response);
    }
  }

  static bool _isRetryable(int status) =>
      status == 429 || status == 503 || status == 504;

  Duration _retryDelay(Map<String, String> headers, int attempt) {
    final seconds = int.tryParse(headers['retry-after'] ?? '');
    final delay = seconds != null
        ? Duration(seconds: seconds)
        : Duration(milliseconds: 500 * math.pow(2, attempt).toInt());
    return delay > maxRetryAfter ? maxRetryAfter : delay;
  }

  Exception _error(GraphResponse response) {
    var code = '';
    var message = '';
    try {
      final error = response.json['error'];
      if (error is Map) {
        code = '${error['code'] ?? ''}';
        message = '${error['message'] ?? ''}';
      }
    } catch (_) {}
    if (response.status == 401) {
      return MailAuthenticationException(
        'Microsoft refused the sign-in. Sign in again in Account Settings. '
        '(${message.isEmpty ? code : message})',
      );
    }
    if (_isRetryable(response.status) || response.status == 502) {
      return MailConnectionException(
        'Microsoft Graph is busy (${response.status}). Try again later.',
      );
    }
    return GraphException(response.status, code, message);
  }

  Future<GraphResponse> _send(
    String method,
    Uri uri, {
    Object? json,
    List<int>? body,
    String? contentType,
    required Map<String, String> headers,
    int? pageSize,
    List<String> prefer = const [],
    required bool forceRefresh,
  }) async {
    final accessToken = await token(forceRefresh: forceRefresh);
    await _acquire();
    try {
      final request = await _http.openUrl(method, uri);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        'Prefer',
        [
          'IdType="ImmutableId"',
          if (pageSize != null) 'odata.maxpagesize=$pageSize',
          ...prefer,
        ].join(', '),
      );
      headers.forEach(request.headers.set);
      List<int>? payload = body;
      if (json != null) {
        payload = utf8.encode(jsonEncode(json));
        request.headers.contentType = ContentType.json;
      } else if (contentType != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      }
      if (payload != null) {
        request.contentLength = payload.length;
        request.add(payload);
      } else if (method != 'GET' && method != 'DELETE') {
        request.contentLength = 0;
      }
      final response = await request.close().timeout(
        const Duration(seconds: 90),
      );
      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add).timeout(const Duration(seconds: 120));
      final responseHeaders = <String, String>{};
      response.headers.forEach(
        (name, values) =>
            responseHeaders[name.toLowerCase()] = values.join(','),
      );
      return GraphResponse(
        response.statusCode,
        responseHeaders,
        builder.takeBytes(),
      );
    } on SocketException catch (e) {
      throw MailConnectionException(
        'Cannot reach Microsoft Graph: ${e.osError?.message ?? e.message}',
        e,
      );
    } on HandshakeException catch (e) {
      throw MailConnectionException(
        'Secure connection to Microsoft Graph failed: ${e.message}',
        e,
      );
    } on TimeoutException catch (e) {
      throw MailConnectionException(
        'Microsoft Graph did not respond in time',
        e,
      );
    } on HttpException catch (e) {
      throw MailConnectionException('Microsoft Graph: ${e.message}', e);
    } finally {
      _release();
    }
  }

  /// Uploads part of a file to an upload session. The session's address
  /// carries its own authorization, so no token is sent.
  Future<GraphResponse> uploadChunk(
    Uri uploadUrl,
    List<int> chunk, {
    required int start,
    required int total,
  }) async {
    for (var attempt = 0; ; attempt++) {
      await _acquire();
      GraphResponse response;
      try {
        final request = await _http.openUrl('PUT', uploadUrl);
        request.headers.set(
          'Content-Range',
          'bytes $start-${start + chunk.length - 1}/$total',
        );
        request.contentLength = chunk.length;
        request.add(chunk);
        final answer = await request.close().timeout(
          const Duration(seconds: 120),
        );
        final builder = BytesBuilder(copy: false);
        await answer.forEach(builder.add);
        final headers = <String, String>{};
        answer.headers.forEach(
          (name, values) => headers[name.toLowerCase()] = values.join(','),
        );
        response = GraphResponse(
          answer.statusCode,
          headers,
          builder.takeBytes(),
        );
      } on SocketException catch (e) {
        throw MailConnectionException(
          'Uploading the attachment failed: ${e.osError?.message ?? e.message}',
          e,
        );
      } on TimeoutException catch (e) {
        throw MailConnectionException('Uploading the attachment timed out', e);
      } finally {
        _release();
      }
      if (response.ok) return response;
      if (_isRetryable(response.status) && attempt < maxRetries) {
        await Future<void>.delayed(_retryDelay(response.headers, attempt));
        continue;
      }
      throw _error(response);
    }
  }

  Future<Map<String, dynamic>> getJson(
    String pathOrUrl, {
    Map<String, String>? query,
    int? pageSize,
    List<String> prefer = const [],
  }) async => (await request(
    'GET',
    pathOrUrl,
    query: query,
    pageSize: pageSize,
    prefer: prefer,
  )).json;

  /// All items of a collection, following `@odata.nextLink`.
  Future<List<Map<String, dynamic>>> getAll(
    String pathOrUrl, {
    Map<String, String>? query,
    int pageSize = 100,
    List<String> prefer = const [],
  }) async {
    final items = <Map<String, dynamic>>[];
    String? next = buildUri(pathOrUrl, query).toString();
    while (next != null) {
      final page = await getJson(next, pageSize: pageSize, prefer: prefer);
      items.addAll((page['value'] as List? ?? const []).cast());
      next = page['@odata.nextLink'] as String?;
    }
    return items;
  }

  /// Sends up to 20 requests at a time through `$batch`; the answers come
  /// back in the order of [requests]. Throttled ones are retried.
  Future<List<GraphResponse>> batch(List<GraphBatchRequest> requests) async {
    final results = List<GraphResponse?>.filled(requests.length, null);
    for (var start = 0; start < requests.length; start += 20) {
      var pending = [
        for (var i = start; i < math.min(start + 20, requests.length); i++) i,
      ];
      for (var attempt = 0; pending.isNotEmpty; attempt++) {
        final response = await request(
          'POST',
          '/\$batch',
          json: {
            'requests': [
              for (final i in pending)
                {
                  'id': '$i',
                  'method': requests[i].method,
                  'url': requests[i].url,
                  'headers': {
                    'Prefer': 'IdType="ImmutableId"',
                    if (requests[i].body != null)
                      'Content-Type': 'application/json',
                  },
                  'body': ?requests[i].body,
                },
            ],
          },
        );
        final retry = <int>[];
        var wait = Duration.zero;
        for (final raw in (response.json['responses'] as List? ?? const [])) {
          final item = (raw as Map).cast<String, dynamic>();
          final index = int.parse('${item['id']}');
          final status = item['status'] as int? ?? 500;
          final headers = {
            for (final e in ((item['headers'] as Map?) ?? const {}).entries)
              '${e.key}'.toLowerCase(): '${e.value}',
          };
          if (_isRetryable(status) && attempt < maxRetries) {
            retry.add(index);
            final delay = _retryDelay(headers, attempt);
            if (delay > wait) wait = delay;
            continue;
          }
          final body = item['body'];
          results[index] = GraphResponse(
            status,
            headers,
            body == null
                ? Uint8List(0)
                : Uint8List.fromList(utf8.encode(jsonEncode(body))),
          );
        }
        pending = retry;
        if (pending.isNotEmpty) await Future<void>.delayed(wait);
      }
    }
    return [
      for (final r in results) r ?? GraphResponse(500, const {}, Uint8List(0)),
    ];
  }

  /// Raises the error of the first failed answer, ignoring [allowed]
  /// statuses (such as 404 for something already deleted).
  void checkAll(List<GraphResponse> responses, {Set<int> allowed = const {}}) {
    for (final r in responses) {
      if (r.ok || allowed.contains(r.status)) continue;
      throw _error(r);
    }
  }
}
