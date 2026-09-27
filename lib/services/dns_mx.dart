import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// One MX record: lower [preference] values are tried first.
class MxRecord {
  final int preference;
  final String host;

  const MxRecord(this.preference, this.host);

  @override
  String toString() => '$preference $host';
}

/// Looks up MX records with a minimal DNS client (UDP, falling back to TCP
/// for truncated answers), using the nameservers in `/etc/resolv.conf`.
///
/// Dart's standard library can only resolve addresses, and the `dig`/`host`
/// tools are missing on many desktops and inside Flatpak.
class DnsMx {
  DnsMx._();

  static const _typeMx = 15;
  static const _classIn = 1;

  /// MX records for [domain] sorted by preference; empty when there are
  /// none or no nameserver answered.
  static Future<List<MxRecord>> lookup(
    String domain, {
    List<InternetAddress>? nameservers,
    Duration timeout = const Duration(seconds: 3),
    int port = 53,
  }) async {
    final servers = nameservers ?? await systemNameservers();
    for (final server in servers) {
      try {
        final id = Random.secure().nextInt(0x10000);
        final query = buildQuery(domain, id: id);
        var response = await _udp(server, port, query, timeout);
        if (response == null) continue;
        if (_isTruncated(response)) {
          response = await _tcp(server, port, query, timeout) ?? response;
        }
        final records = parseMxResponse(response, id: id);
        if (records != null) return records;
      } catch (_) {
        // Try the next nameserver.
      }
    }
    return const [];
  }

  /// Nameservers from `/etc/resolv.conf` (or [contents]), defaulting to
  /// the local resolver.
  static Future<List<InternetAddress>> systemNameservers(
      {String? contents}) async {
    String text;
    try {
      text = contents ?? await File('/etc/resolv.conf').readAsString();
    } catch (_) {
      text = '';
    }
    final servers = <InternetAddress>[];
    for (final line in text.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts[0] == 'nameserver') {
        // Strip IPv6 zone ids such as fe80::1%eth0.
        final address = InternetAddress.tryParse(parts[1].split('%').first);
        if (address != null) servers.add(address);
      }
    }
    return servers.isEmpty ? [InternetAddress('127.0.0.53')] : servers;
  }

  /// A standard recursive query for the MX records of [domain].
  static Uint8List buildQuery(String domain, {required int id}) {
    final builder = BytesBuilder();
    builder.add([id >> 8, id & 0xff, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]);
    for (final label in domain.split('.').where((l) => l.isNotEmpty)) {
      final bytes = label.codeUnits;
      if (bytes.length > 63) throw ArgumentError('DNS label too long: $label');
      builder
        ..addByte(bytes.length)
        ..add(bytes);
    }
    builder.add([0, 0, _typeMx, 0, _classIn]);
    return builder.toBytes();
  }

  static bool _isTruncated(Uint8List r) => r.length > 2 && (r[2] & 0x02) != 0;

  /// Parses a response to [buildQuery]. Returns null for a malformed or
  /// mismatched response (try another server), an empty list when the
  /// domain has no MX records.
  static List<MxRecord>? parseMxResponse(Uint8List r, {int? id}) {
    if (r.length < 12) return null;
    if (id != null && ((r[0] << 8) | r[1]) != id) return null;
    if ((r[2] & 0x80) == 0) return null; // not a response
    final rcode = r[3] & 0x0f;
    if (rcode == 3) return const []; // NXDOMAIN
    if (rcode != 0) return null;
    final questions = (r[4] << 8) | r[5];
    final answers = (r[6] << 8) | r[7];
    var offset = 12;
    for (var i = 0; i < questions; i++) {
      offset = _skipName(r, offset) + 4;
    }
    final records = <MxRecord>[];
    for (var i = 0; i < answers; i++) {
      offset = _skipName(r, offset);
      if (offset + 10 > r.length) return null;
      final type = (r[offset] << 8) | r[offset + 1];
      final length = (r[offset + 8] << 8) | r[offset + 9];
      offset += 10;
      if (offset + length > r.length) return null;
      if (type == _typeMx && length >= 3) {
        final preference = (r[offset] << 8) | r[offset + 1];
        final host = _readName(r, offset + 2);
        if (host.isNotEmpty) records.add(MxRecord(preference, host));
      }
      offset += length;
    }
    records.sort((a, b) => a.preference.compareTo(b.preference));
    return records;
  }

  static int _skipName(Uint8List r, int offset) {
    while (offset < r.length) {
      final len = r[offset];
      if (len == 0) return offset + 1;
      if ((len & 0xc0) == 0xc0) return offset + 2;
      offset += len + 1;
    }
    throw const FormatException('Truncated DNS name');
  }

  static String _readName(Uint8List r, int offset) {
    final labels = <String>[];
    var jumps = 0;
    while (offset < r.length) {
      final len = r[offset];
      if (len == 0) break;
      if ((len & 0xc0) == 0xc0) {
        if (offset + 1 >= r.length || ++jumps > 20) {
          throw const FormatException('Bad DNS compression pointer');
        }
        offset = ((len & 0x3f) << 8) | r[offset + 1];
        continue;
      }
      if (offset + 1 + len > r.length) {
        throw const FormatException('Truncated DNS label');
      }
      labels.add(String.fromCharCodes(r, offset + 1, offset + 1 + len));
      offset += len + 1;
    }
    return labels.join('.').toLowerCase();
  }

  static Future<Uint8List?> _udp(InternetAddress server, int port,
      Uint8List query, Duration timeout) async {
    final socket = await RawDatagramSocket.bind(
        server.type == InternetAddressType.IPv6
            ? InternetAddress.anyIPv6
            : InternetAddress.anyIPv4,
        0);
    try {
      final completer = Completer<Uint8List?>();
      socket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        final datagram = socket.receive();
        if (datagram != null && datagram.address == server) {
          completer.complete(datagram.data);
        }
      });
      socket.send(query, server, port);
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      socket.close();
    }
  }

  static Future<Uint8List?> _tcp(InternetAddress server, int port,
      Uint8List query, Duration timeout) async {
    final socket = await Socket.connect(server, port, timeout: timeout);
    try {
      socket.add([query.length >> 8, query.length & 0xff, ...query]);
      await socket.flush();
      final buffer = BytesBuilder();
      await for (final chunk in socket.timeout(timeout)) {
        buffer.add(chunk);
        final bytes = buffer.toBytes();
        if (bytes.length >= 2) {
          final length = (bytes[0] << 8) | bytes[1];
          if (bytes.length >= length + 2) {
            return Uint8List.sublistView(bytes, 2, length + 2);
          }
        }
      }
      return null;
    } finally {
      socket.destroy();
    }
  }
}
