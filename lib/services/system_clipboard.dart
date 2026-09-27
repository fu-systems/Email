import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Reads formats Flutter's clipboard API doesn't offer (pictures, HTML,
/// copied files) with `wl-paste` on Wayland or `xclip` on X11.
///
/// Without either program the formats are simply not available and
/// pasting falls back to text.
class SystemClipboard {
  const SystemClipboard();

  /// Replaced in tests.
  static SystemClipboard instance = const SystemClipboard();

  static const _timeout = Duration(seconds: 3);

  List<String>? _command(List<String> args, {required bool list}) {
    final env = Platform.environment;
    String? find(String name) {
      for (final dir in (env['PATH'] ?? '/usr/bin:/bin').split(':')) {
        if (dir.isEmpty) continue;
        final path = p.join(dir, name);
        if (File(path).existsSync()) return path;
      }
      return null;
    }

    if ((env['WAYLAND_DISPLAY'] ?? '').isNotEmpty) {
      final wlPaste = find('wl-paste');
      if (wlPaste != null) {
        return list
            ? [wlPaste, '--list-types']
            : [wlPaste, '--no-newline', '--type', ...args];
      }
    }
    if ((env['DISPLAY'] ?? '').isNotEmpty) {
      final xclip = find('xclip');
      if (xclip != null) {
        return list
            ? [xclip, '-selection', 'clipboard', '-t', 'TARGETS', '-o']
            : [xclip, '-selection', 'clipboard', '-t', ...args, '-o'];
      }
    }
    return null;
  }

  Future<Uint8List?> _run(List<String>? command) async {
    if (command == null) return null;
    try {
      final result = await Process.run(
        command.first,
        command.sublist(1),
        stdoutEncoding: null,
      ).timeout(_timeout);
      if (result.exitCode != 0) return null;
      return Uint8List.fromList(result.stdout as List<int>);
    } catch (e) {
      debugPrint('Clipboard: $e');
      return null;
    }
  }

  /// The formats (MIME types) on the clipboard.
  Future<List<String>> types() async {
    final out = await _run(_command(const [], list: true));
    if (out == null) return const [];
    return const LineSplitter()
        .convert(utf8.decode(out, allowMalformed: true))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  /// The clipboard's content in [type].
  Future<Uint8List?> read(String type) => _run(_command([type], list: false));

  Future<String?> readText(String type) async {
    final bytes = await read(type);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }
}

/// What a paste brings in, besides plain text.
sealed class ClipboardContent {
  const ClipboardContent();
}

/// Files copied in a file manager.
class ClipboardFiles extends ClipboardContent {
  final List<String> paths;
  const ClipboardFiles(this.paths);
}

/// A picture (e.g. a screenshot), saved to [path].
class ClipboardPicture extends ClipboardContent {
  final String path;
  const ClipboardPicture(this.path);
}

/// Formatted text copied from a web page or document.
class ClipboardHtml extends ClipboardContent {
  final String html;
  const ClipboardHtml(this.html);
}

const _pictureTypes = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'image/bmp': 'bmp',
};

/// Reads the richest content on the clipboard: copied files, then a
/// picture, then HTML. Null when there is only text (or nothing).
Future<ClipboardContent?> readClipboardContent({
  SystemClipboard? clipboard,
}) async {
  clipboard ??= SystemClipboard.instance;
  final types = await clipboard.types();
  if (types.isEmpty) return null;

  if (types.contains('text/uri-list') ||
      types.contains('x-special/gnome-copied-files')) {
    final gnome = types.contains('x-special/gnome-copied-files');
    final text = await clipboard.readText(
      gnome ? 'x-special/gnome-copied-files' : 'text/uri-list',
    );
    final paths = <String>[];
    for (final line in const LineSplitter().convert(text ?? '')) {
      final uri = Uri.tryParse(line.trim());
      if (uri == null || uri.scheme != 'file') continue;
      final path = uri.toFilePath();
      if (File(path).existsSync()) paths.add(path);
    }
    if (paths.isNotEmpty) return ClipboardFiles(paths);
  }

  for (final entry in _pictureTypes.entries) {
    if (!types.contains(entry.key)) continue;
    final bytes = await clipboard.read(entry.key);
    if (bytes == null || bytes.isEmpty) continue;
    return ClipboardPicture(await savePastedPicture(bytes, entry.value));
  }

  if (types.contains('text/html')) {
    final html = await clipboard.readText('text/html');
    if (html != null && html.trim().isNotEmpty) return ClipboardHtml(html);
  }
  return null;
}

var _pasteCount = 0;

/// Saves a pasted picture to a temporary file named like Outlook's
/// ("image001.png"), for the editor and the message's inline parts.
Future<String> savePastedPicture(
  Uint8List bytes, [
  String extension = 'png',
]) async {
  // Small files: written synchronously, so the paste completes at once.
  final dir = Directory.systemTemp.createTempSync('look_in_paste_');
  _pasteCount++;
  final name = 'image${_pasteCount.toString().padLeft(3, '0')}.$extension';
  final file = File(p.join(dir.path, name))..writeAsBytesSync(bytes);
  return file.path;
}
