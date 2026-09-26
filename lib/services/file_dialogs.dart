import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../widgets/common.dart';

/// Native open/save dialogs with fallbacks.
///
/// Tries the XDG desktop portal (via file_picker) first, then `zenity` or
/// `kdialog`, and finally an in-app prompt for a file path, so that file
/// dialogs work on every desktop environment and window manager.
class FileDialogs {
  FileDialogs._();

  /// Lets the user pick one or more files. Returns absolute paths.
  static Future<List<String>> pickFiles(
    BuildContext context, {
    String title = 'Open',
    List<String>? extensions,
    bool multiple = true,
  }) async {
    try {
      if (multiple) {
        final files = await FilePicker.pickFiles(
          dialogTitle: title,
          type: extensions == null ? FileType.any : FileType.custom,
          allowedExtensions: extensions,
        );
        final paths = files.map((f) => f.path).whereType<String>().toList();
        return paths;
      }
      final file = await FilePicker.pickFile(
        dialogTitle: title,
        type: extensions == null ? FileType.any : FileType.custom,
        allowedExtensions: extensions,
      );
      return [if (file?.path != null) file!.path!];
    } catch (_) {
      // Portal unavailable: fall through to the command-line dialogs.
    }

    final zenity = await _run('zenity', [
      '--file-selection',
      '--title=$title',
      if (multiple) '--multiple',
      '--separator=\n',
      if (extensions != null)
        '--file-filter=${extensions.map((e) => '*.$e').join(' ')}',
    ]);
    if (zenity.ran) return _lines(zenity.output ?? '');
    final kdialog = await _run('kdialog', [
      '--title',
      title,
      '--getopenfilename',
      _home(),
      if (extensions != null) extensions.map((e) => '*.$e').join(' '),
      if (multiple) ...['--multiple', '--separate-output'],
    ]);
    if (kdialog.ran) return _lines(kdialog.output ?? '');

    if (!context.mounted) return const [];
    final typed = await showTextInputDialog(
      context,
      title: title,
      label: 'File path',
      initialValue: '${_home()}/',
      confirmLabel: 'Open',
    );
    if (typed == null) return const [];
    return File(typed).existsSync() ? [typed] : const [];
  }

  /// Asks where to save [bytes] and writes them. Returns the saved path, or
  /// null when cancelled.
  static Future<String?> saveFile(
    BuildContext context, {
    required String fileName,
    required Uint8List bytes,
    String title = 'Save As',
    String mimeType = 'application/octet-stream',
    List<String>? extensions,
  }) async {
    final safeName = sanitizeFileName(fileName);
    try {
      final uri = await FilePicker.saveFile(
        fileName: safeName,
        bytes: bytes,
        mimeType: mimeType,
        dialogTitle: title,
        initialDirectory: downloadsDirectory(),
        allowedExtensions: extensions,
      );
      if (uri == null) return null;
      final path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
      // Some portal backends only return the path; make sure it's written.
      if (uri.scheme == 'file') {
        final file = File(path);
        if (!await file.exists() || await file.length() != bytes.length) {
          await file.writeAsBytes(bytes, flush: true);
        }
      }
      return path;
    } catch (_) {
      // Portal unavailable: fall through.
    }

    final initial = p.join(downloadsDirectory(), safeName);
    String? chosen;
    final zenity = await _run('zenity', [
      '--file-selection',
      '--save',
      '--confirm-overwrite',
      '--title=$title',
      '--filename=$initial',
    ]);
    final kdialog = zenity.ran
        ? zenity
        : await _run('kdialog', ['--title', title, '--getsavefilename', initial]);
    if (kdialog.ran) {
      chosen = kdialog.output;
    } else {
      if (!context.mounted) return null;
      chosen = await showTextInputDialog(
        context,
        title: title,
        label: 'Save to',
        initialValue: initial,
        confirmLabel: 'Save',
      );
    }
    final path = chosen?.trim();
    if (path == null || path.isEmpty) return null;
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Lets the user choose a directory. Returns its path or null.
  static Future<String?> pickDirectory(
    BuildContext context, {
    String title = 'Select Folder',
  }) async {
    try {
      return await FilePicker.getDirectoryPath(
        dialogTitle: title,
        initialDirectory: downloadsDirectory(),
      );
    } catch (_) {
      // Portal unavailable: fall through.
    }
    final zenity = await _run('zenity', [
      '--file-selection',
      '--directory',
      '--title=$title',
      '--filename=${downloadsDirectory()}/',
    ]);
    if (zenity.ran) return zenity.output;
    final kdialog = await _run(
        'kdialog', ['--title', title, '--getexistingdirectory', downloadsDirectory()]);
    if (kdialog.ran) return kdialog.output;
    if (!context.mounted) return null;
    final typed = await showTextInputDialog(
      context,
      title: title,
      label: 'Folder',
      initialValue: downloadsDirectory(),
      confirmLabel: 'Select',
    );
    if (typed == null || !Directory(typed).existsSync()) return null;
    return typed;
  }

  /// Opens a file with the desktop's default application.
  static Future<bool> openWithDefaultApp(String path) async {
    try {
      final result = await Process.run('xdg-open', [path]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Writes [bytes] to a temporary file and opens it with the default app.
  static Future<bool> openBytes(String fileName, Uint8List bytes) async {
    final dir = await Directory.systemTemp.createTemp('look_in_');
    final file = File(p.join(dir.path, sanitizeFileName(fileName)));
    await file.writeAsBytes(bytes, flush: true);
    return openWithDefaultApp(file.path);
  }

  /// Removes path separators and control characters from a file name.
  static String sanitizeFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'^\.+'), '')
        .trim();
    return cleaned.isEmpty ? 'attachment' : cleaned;
  }

  static String _home() => Platform.environment['HOME'] ?? '/';

  /// The user's Downloads directory (XDG), falling back to $HOME.
  static String downloadsDirectory() {
    final home = _home();
    try {
      final config = File(p.join(home, '.config', 'user-dirs.dirs'));
      if (config.existsSync()) {
        final match = RegExp(r'^XDG_DOWNLOAD_DIR="(.+)"$', multiLine: true)
            .firstMatch(config.readAsStringSync());
        if (match != null) {
          final dir = match.group(1)!.replaceAll(r'$HOME', home);
          if (Directory(dir).existsSync()) return dir;
        }
      }
    } catch (_) {}
    final downloads = p.join(home, 'Downloads');
    return Directory(downloads).existsSync() ? downloads : home;
  }

  /// Runs a dialog program. [ran] is false when the program is missing (or
  /// could not open a window); [output] is null when the user cancelled.
  static Future<({bool ran, String? output})> _run(
      String program, List<String> args) async {
    try {
      final result = await Process.run(program, args);
      // zenity/kdialog exit with 1 on cancel; other codes mean failure.
      if (result.exitCode > 1) return (ran: false, output: null);
      final out = (result.stdout as String).trim();
      return (
        ran: true,
        output: result.exitCode == 0 && out.isNotEmpty ? out : null,
      );
    } catch (_) {
      return (ran: false, output: null);
    }
  }

  static List<String> _lines(String text) =>
      text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
}
