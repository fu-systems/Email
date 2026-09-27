import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/services/dns_mx.dart';

/// Builds a DNS response to [query] with MX answers, using a compression
/// pointer to the question name for the owner of every answer and for the
/// shared suffix of the exchange hosts.
Uint8List mxResponse(Uint8List query, List<(int, String)> answers,
    {int rcode = 0, bool truncated = false}) {
  final b = BytesBuilder();
  b.add([query[0], query[1], 0x81 | (truncated ? 0x02 : 0), 0x80 | rcode]);
  b.add([0, 1, 0, answers.length, 0, 0, 0, 0]);
  b.add(query.sublist(12)); // question
  for (final (pref, host) in answers) {
    // "mx1" + pointer to the question name (offset 12) when the host ends
    // with the queried domain; otherwise the full name.
    final rdata = BytesBuilder()..add([pref >> 8, pref & 0xff]);
    final domain = _questionName(query);
    if (host.endsWith('.$domain')) {
      final label = host.substring(0, host.length - domain.length - 1);
      for (final l in label.split('.')) {
        rdata
          ..addByte(l.length)
          ..add(l.codeUnits);
      }
      rdata.add([0xc0, 12]);
    } else {
      for (final l in host.split('.')) {
        rdata
          ..addByte(l.length)
          ..add(l.codeUnits);
      }
      rdata.addByte(0);
    }
    final bytes = rdata.toBytes();
    b.add([0xc0, 12, 0, 15, 0, 1, 0, 0, 1, 44, bytes.length >> 8,
        bytes.length & 0xff]);
    b.add(bytes);
  }
  return b.toBytes();
}

String _questionName(Uint8List query) {
  final labels = <String>[];
  var i = 12;
  while (query[i] != 0) {
    labels.add(String.fromCharCodes(query, i + 1, i + 1 + query[i]));
    i += query[i] + 1;
  }
  return labels.join('.');
}

/// A UDP (and optional TCP) nameserver on a local port.
class FakeDns {
  final RawDatagramSocket udp;
  final ServerSocket? tcp;
  int queries = 0;

  FakeDns._(this.udp, this.tcp);

  static Future<FakeDns> start(
      Uint8List Function(Uint8List query) respond,
      {Uint8List Function(Uint8List query)? respondTcp}) async {
    final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    ServerSocket? tcp;
    if (respondTcp != null) {
      tcp = await ServerSocket.bind(InternetAddress.loopbackIPv4, udp.port);
    }
    final dns = FakeDns._(udp, tcp);
    udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = udp.receive();
      if (d == null) return;
      dns.queries++;
      udp.send(respond(d.data), d.address, d.port);
    });
    tcp?.listen((client) {
      final buffer = BytesBuilder();
      client.listen((chunk) {
        buffer.add(chunk);
        final bytes = buffer.toBytes();
        if (bytes.length < 2) return;
        final length = (bytes[0] << 8) | bytes[1];
        if (bytes.length < length + 2) return;
        final reply = respondTcp!(Uint8List.sublistView(bytes, 2));
        client.add([reply.length >> 8, reply.length & 0xff, ...reply]);
        client.close();
      });
    });
    return dns;
  }

  int get port => udp.port;

  void close() {
    udp.close();
    tcp?.close();
  }
}

void main() {
  test('query layout', () {
    final q = DnsMx.buildQuery('example.com', id: 0x1234);
    expect(q.sublist(0, 12), [0x12, 0x34, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
    expect(q.sublist(12),
        [7, ...'example'.codeUnits, 3, ...'com'.codeUnits, 0, 0, 15, 0, 1]);
  });

  test('parses MX answers with compressed names, sorted by preference', () {
    final q = DnsMx.buildQuery('contoso.com', id: 7);
    final r = mxResponse(q, [
      (20, 'backup.mail.protection.outlook.com'),
      (10, 'mx1.contoso.com'),
    ]);
    final records = DnsMx.parseMxResponse(r, id: 7)!;
    expect(records.map((m) => '${m.preference} ${m.host}'),
        ['10 mx1.contoso.com', '20 backup.mail.protection.outlook.com']);
  });

  test('NXDOMAIN is an empty answer; other errors and wrong ids are null',
      () {
    final q = DnsMx.buildQuery('nope.test', id: 9);
    expect(DnsMx.parseMxResponse(mxResponse(q, [], rcode: 3), id: 9), isEmpty);
    expect(DnsMx.parseMxResponse(mxResponse(q, [], rcode: 2), id: 9), isNull);
    expect(DnsMx.parseMxResponse(mxResponse(q, []), id: 10), isNull);
    expect(DnsMx.parseMxResponse(Uint8List(5)), isNull);
  });

  test('a compression loop does not hang', () {
    final q = DnsMx.buildQuery('loop.test', id: 1);
    final b = BytesBuilder()
      ..add([0, 1, 0x81, 0x80, 0, 1, 0, 1, 0, 0, 0, 0])
      ..add(q.sublist(12));
    final answerAt = b.length;
    // Exchange name is a pointer to itself.
    final pointerAt = answerAt + 12 + 2;
    b.add([0xc0, 12, 0, 15, 0, 1, 0, 0, 0, 60, 0, 4, 0, 10,
        0xc0 | (pointerAt >> 8), pointerAt & 0xff]);
    expect(() => DnsMx.parseMxResponse(b.toBytes(), id: 1),
        throwsFormatException);
  });

  test('resolv.conf parsing', () async {
    final servers = await DnsMx.systemNameservers(contents: '''
# comment
nameserver 10.0.0.1
nameserver fe80::1%eth0
options timeout:2
''');
    expect(servers.map((a) => a.address), ['10.0.0.1', 'fe80::1']);
    expect((await DnsMx.systemNameservers(contents: '')).single.address,
        '127.0.0.53');
  });

  test('looks up over UDP against a local server', () async {
    final dns = await FakeDns.start(
        (q) => mxResponse(q, [(0, 'contoso-com.mail.protection.outlook.com')]));
    addTearDown(dns.close);
    final records = await DnsMx.lookup('contoso.com',
        nameservers: [InternetAddress.loopbackIPv4], port: dns.port);
    expect(records.single.host, 'contoso-com.mail.protection.outlook.com');
  });

  test('retries a truncated answer over TCP', () async {
    final dns = await FakeDns.start(
      (q) => mxResponse(q, [], truncated: true),
      respondTcp: (q) => mxResponse(q, [(5, 'mx.big.test'), (1, 'a.big.test')]),
    );
    addTearDown(dns.close);
    final records = await DnsMx.lookup('big.test',
        nameservers: [InternetAddress.loopbackIPv4], port: dns.port);
    expect(records.map((r) => r.host), ['a.big.test', 'mx.big.test']);
  });

  test('moves on when a nameserver does not answer', () async {
    final dns =
        await FakeDns.start((q) => mxResponse(q, [(10, 'mx.example.org')]));
    addTearDown(dns.close);
    // Nothing listens on 127.0.0.2, so the first server never answers.
    final records = await DnsMx.lookup('example.org',
        nameservers: [InternetAddress('127.0.0.2'), InternetAddress.loopbackIPv4],
        port: dns.port,
        timeout: const Duration(milliseconds: 300));
    expect(records.single.host, 'mx.example.org');
  });
}
