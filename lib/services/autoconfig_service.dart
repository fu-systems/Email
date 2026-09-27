import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/email_account.dart';
import 'dns_mx.dart';

/// Server settings discovered for an email address.
class DiscoveredSettings {
  final String source;
  final IncomingProtocol protocol;
  final String incomingHost;
  final int incomingPort;
  final ConnectionSecurity incomingSecurity;
  final String smtpHost;
  final int smtpPort;
  final ConnectionSecurity smtpSecurity;

  /// Whether the login is the full address (`%EMAILADDRESS%`) or only the
  /// local part (`%EMAILLOCALPART%`).
  final bool usernameIsLocalPart;

  const DiscoveredSettings({
    required this.source,
    required this.protocol,
    required this.incomingHost,
    required this.incomingPort,
    required this.incomingSecurity,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSecurity,
    this.usernameIsLocalPart = false,
  });
}

/// Discovers mail server settings like Thunderbird does: the provider's
/// own autoconfig file, then Mozilla's ISP database (ISPDB), keyed by the
/// address' domain and then by its MX domain.
class AutoconfigService {
  AutoconfigService._();

  static const _timeout = Duration(seconds: 6);

  /// Returns discovered settings for [email], or null when none are found.
  static Future<DiscoveredSettings?> discover(String email) async {
    final at = email.lastIndexOf('@');
    if (at < 0) return null;
    final domain = email.substring(at + 1).trim().toLowerCase();
    if (domain.isEmpty) return null;

    final urls = [
      'https://autoconfig.$domain/mail/config-v1.1.xml?emailaddress=${Uri.encodeComponent(email)}',
      'https://$domain/.well-known/autoconfig/mail/config-v1.1.xml',
      'https://autoconfig.thunderbird.net/v1.1/$domain',
    ];
    for (final url in urls) {
      final xml = await _fetch(url);
      final parsed = xml == null ? null : parseConfig(xml, source: url);
      if (parsed != null) return parsed;
    }

    // Hosted domains: look up the ISPDB entry of the MX provider (e.g. a
    // custom domain hosted by Google Workspace or Fastmail).
    final mxDomain = await _mxBaseDomain(domain);
    if (mxDomain != null && mxDomain != domain) {
      final xml = await _fetch('https://autoconfig.thunderbird.net/v1.1/$mxDomain');
      final parsed = xml == null ? null : parseConfig(xml, source: 'MX: $mxDomain');
      if (parsed != null) return parsed;
    }
    return null;
  }

  static Future<String?> _fetch(String url) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) return null;
      return await response.transform(utf8.decoder).join().timeout(_timeout);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// MX hosts of [domain], most preferred first. Uses Look In's own DNS
  /// client, falling back to `dig`/`host`.
  static Future<List<String>> mxHosts(String domain) async {
    try {
      final records = await DnsMx.lookup(domain);
      if (records.isNotEmpty) return records.map((r) => r.host).toList();
    } catch (_) {}
    return _mxHostsFromTools(domain);
  }

  static Future<List<String>> _mxHostsFromTools(String domain) async {
    for (final cmd in [
      ['dig', '+short', 'MX', domain],
      ['host', '-t', 'MX', domain],
    ]) {
      try {
        final result = await Process.run(cmd.first, cmd.sublist(1))
            .timeout(const Duration(seconds: 4));
        final output = (result.stdout as String).toLowerCase();
        if (result.exitCode != 0 || output.trim().isEmpty) continue;
        final hosts = [
          for (final m in RegExp(r'(\d+)\s+([a-z0-9-]+(?:\.[a-z0-9-]+)+)\.?\s*$',
                  multiLine: true)
              .allMatches(output))
            (int.parse(m.group(1)!), m.group(2)!),
        ]..sort((a, b) => a.$1.compareTo(b.$1));
        if (hosts.isNotEmpty) return [for (final h in hosts) h.$2];
      } catch (_) {}
    }
    return const [];
  }

  /// Registrable domain of the first MX host, e.g. `aspmx.l.google.com`
  /// → `google.com`.
  static Future<String?> _mxBaseDomain(String domain) async {
    final hosts = await mxHosts(domain);
    if (hosts.isEmpty) return null;
    final parts = hosts.first.split('.');
    if (parts.length < 2) return null;
    return parts.sublist(parts.length - 2).join('.');
  }

  /// Parses a Thunderbird autoconfig (clientConfig v1.1) document. Prefers
  /// IMAP over POP3 and SSL/TLS over STARTTLS.
  static DiscoveredSettings? parseConfig(String xml, {String source = ''}) {
    List<Map<String, String>> servers(String tag) {
      final result = <Map<String, String>>[];
      final re = RegExp('<$tag\\s+type="([^"]+)"\\s*>(.*?)</$tag>', dotAll: true);
      for (final m in re.allMatches(xml)) {
        String? field(String name) => RegExp('<$name>\\s*(.*?)\\s*</$name>', dotAll: true)
            .firstMatch(m.group(2)!)
            ?.group(1);
        result.add({
          'type': m.group(1)!.toLowerCase(),
          'hostname': field('hostname') ?? '',
          'port': field('port') ?? '',
          'socketType': (field('socketType') ?? '').toUpperCase(),
          'username': field('username') ?? '',
        });
      }
      return result;
    }

    ConnectionSecurity security(String socketType) {
      switch (socketType) {
        case 'SSL':
          return ConnectionSecurity.ssl;
        case 'STARTTLS':
          return ConnectionSecurity.starttls;
        default:
          return ConnectionSecurity.none;
      }
    }

    int rank(Map<String, String> s) =>
        (s['type'] == 'imap' ? 0 : 10) +
        (s['socketType'] == 'SSL' ? 0 : s['socketType'] == 'STARTTLS' ? 1 : 5);

    final incoming = servers('incomingServer')
        .where((s) =>
            (s['type'] == 'imap' || s['type'] == 'pop3') &&
            s['hostname']!.isNotEmpty &&
            int.tryParse(s['port']!) != null)
        .toList()
      ..sort((a, b) => rank(a).compareTo(rank(b)));
    final outgoing = servers('outgoingServer')
        .where((s) =>
            s['type'] == 'smtp' &&
            s['hostname']!.isNotEmpty &&
            int.tryParse(s['port']!) != null)
        .toList()
      ..sort((a, b) => rank(a).compareTo(rank(b)));
    if (incoming.isEmpty || outgoing.isEmpty) return null;
    final inc = incoming.first;
    final out = outgoing.first;
    return DiscoveredSettings(
      source: source,
      protocol: inc['type'] == 'pop3' ? IncomingProtocol.pop3 : IncomingProtocol.imap,
      incomingHost: inc['hostname']!,
      incomingPort: int.parse(inc['port']!),
      incomingSecurity: security(inc['socketType']!),
      smtpHost: out['hostname']!,
      smtpPort: int.parse(out['port']!),
      smtpSecurity: security(out['socketType']!),
      usernameIsLocalPart: inc['username']!.contains('%EMAILLOCALPART%'),
    );
  }
}
