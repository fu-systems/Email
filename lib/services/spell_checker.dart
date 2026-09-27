import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'data_store.dart';

/// A word in a text and where it is.
@immutable
class WordSpan {
  final int start;
  final int end;
  final String word;

  const WordSpan(this.start, this.end, this.word);

  /// Whether a caret at [offset] is in (or right after) the word.
  bool contains(int offset) => offset >= start && offset <= end;

  @override
  bool operator ==(Object other) =>
      other is WordSpan &&
      other.start == start &&
      other.end == end &&
      other.word == word;

  @override
  int get hashCode => Object.hash(start, end, word);

  @override
  String toString() => '$word@$start';
}

final _word = RegExp(
  r"[\p{L}\p{M}\p{N}_]+(?:['’][\p{L}\p{M}\p{N}_]+)*",
  unicode: true,
);
final _address = RegExp(
  r'(?:\b[a-z][a-z0-9+.-]*://|\bwww\.)\S+'
  r'|[\p{L}\p{N}._%+-]+@[\p{L}\p{N}-]+(?:\.[\p{L}\p{N}-]+)+'
  r'|(?<![\p{L}\p{N}])(?:~|\.{1,2})?/[\p{L}\p{N}._/-]+',
  caseSensitive: false,
  unicode: true,
);
final _digitOrUnderscore = RegExp(r'[\p{N}_]', unicode: true);

/// The words of [text] worth checking. Like Word, it skips words in
/// UPPERCASE, words with numbers, and Internet and file addresses.
List<WordSpan> wordsToCheck(String text) {
  final addresses = _address.allMatches(text).toList();
  bool inAddress(int start) =>
      addresses.any((m) => start >= m.start && start < m.end);
  final words = <WordSpan>[];
  for (final m in _word.allMatches(text)) {
    final word = m[0]!;
    if (word.length < 2) continue;
    if (word.contains(_digitOrUnderscore)) continue;
    if (word == word.toUpperCase() && word != word.toLowerCase()) continue;
    if (inAddress(m.start)) continue;
    words.add(WordSpan(m.start, m.end, word));
  }
  return words;
}

class SpellCheckerException implements Exception {
  final String message;
  const SpellCheckerException(this.message);

  @override
  String toString() => message;
}

/// Looks words up in a dictionary.
abstract class SpellingBackend {
  /// Suggestions for each word, or null for words spelled correctly.
  Future<List<List<String>?>> lookup(List<String> words);

  Future<void> close();
}

/// A spelling program in ispell pipe mode (`hunspell -a`, `enchant-2 -a`).
///
/// Every word goes on its own line after `^`; in terse mode (`!`) the
/// program answers with `&`/`#`/`?` lines for misspellings and ends each
/// answer with an empty line.
class IspellBackend implements SpellingBackend {
  final Process _process;
  final _waiting = Queue<Completer<List<String>?>>();
  final _answer = <String>[];
  final _ready = Completer<void>();
  final _stderr = StringBuffer();
  bool _closed = false;

  IspellBackend._(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: _onDone);
    _process.stderr
        .transform(utf8.decoder)
        .listen(_stderr.write, onError: (_) {});
  }

  /// Starts [executable] (hunspell or enchant-2) for [language].
  static Future<IspellBackend> start(
    String executable,
    String language, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final isHunspell = p.basename(executable).startsWith('hunspell');
    final Process process;
    try {
      process = await Process.start(executable, [
        '-a',
        if (isHunspell) ...['-i', 'utf-8'],
        '-d',
        language,
      ]);
    } on ProcessException catch (e) {
      throw SpellCheckerException('Could not start $executable: ${e.message}');
    }
    final backend = IspellBackend._(process);
    try {
      await backend._ready.future.timeout(timeout);
    } catch (_) {
      process.kill();
      final detail = backend._stderr.toString().trim();
      throw SpellCheckerException(
        detail.isEmpty ? '$executable did not start' : detail,
      );
    }
    process.stdin.writeln('!');
    return backend;
  }

  void _onLine(String line) {
    if (!_ready.isCompleted) {
      // The version banner, e.g. "@(#) International Ispell Version...".
      _ready.complete();
      return;
    }
    if (line.isNotEmpty) {
      _answer.add(line);
      return;
    }
    if (_waiting.isEmpty) return;
    _waiting.removeFirst().complete(parseAnswer(_answer));
    _answer.clear();
  }

  void _onDone() {
    _closed = true;
    const error = SpellCheckerException('The spelling program stopped');
    if (!_ready.isCompleted) _ready.completeError(error);
    while (_waiting.isNotEmpty) {
      _waiting.removeFirst().completeError(error);
    }
  }

  /// Suggestions from an answer, or null when the word is correct.
  @visibleForTesting
  static List<String>? parseAnswer(List<String> lines) {
    for (final line in lines) {
      if (line.startsWith('#')) return const [];
      if (line.startsWith('&') || line.startsWith('?')) {
        final colon = line.indexOf(': ');
        if (colon < 0) return const [];
        return line
            .substring(colon + 2)
            .split(', ')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }
    return null;
  }

  @override
  Future<List<List<String>?>> lookup(List<String> words) {
    if (_closed) {
      return Future.error(
        const SpellCheckerException('The spelling program stopped'),
      );
    }
    final answers = <Future<List<String>?>>[];
    final buffer = StringBuffer();
    for (final word in words) {
      final completer = Completer<List<String>?>();
      _waiting.add(completer);
      answers.add(completer.future);
      // A line break would start a new request.
      buffer.writeln('^${word.replaceAll(RegExp(r'\s'), '')}');
    }
    _process.stdin.write(buffer);
    return Future.wait(answers);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _process.stdin.close();
    } catch (_) {}
    _process.kill();
  }
}

/// The spelling program and the dictionaries installed on this computer.
class SpellingSetup {
  final String executable;

  /// Dictionary names such as `en_US`, sorted.
  final List<String> languages;

  /// Where hunspell dictionaries are (without the extension), for those
  /// outside hunspell's own search path.
  final Map<String, String> paths;

  const SpellingSetup(this.executable, this.languages, {this.paths = const {}});

  /// The `-d` argument for [language].
  String dictionaryFor(String language) => paths[language] ?? language;

  /// Folders hunspell searches for `.dic`/`.aff` pairs.
  static List<String> dictionaryFolders(Map<String, String> env) => [
    ...?env['DICPATH']?.split(':').where((d) => d.isNotEmpty),
    if (env['HOME'] case final String home) ...[
      p.join(home, '.local', 'share', 'hunspell'),
    ],
    '/app/share/hunspell',
    '/usr/share/hunspell',
    '/usr/share/myspell',
    '/usr/share/myspell/dicts',
    '/usr/local/share/hunspell',
  ];

  /// Finds hunspell (or enchant-2) and its dictionaries; null when there
  /// is no spelling program or no dictionary.
  static Future<SpellingSetup?> detect({
    Map<String, String>? environment,
  }) async {
    final env = environment ?? Platform.environment;
    final hunspell = findExecutable('hunspell', env);
    if (hunspell != null) {
      final paths = <String, String>{};
      for (final folder in dictionaryFolders(env)) {
        final dir = Directory(folder);
        if (!dir.existsSync()) continue;
        try {
          for (final entry in dir.listSync()) {
            if (!entry.path.endsWith('.dic')) continue;
            final name = p.basenameWithoutExtension(entry.path);
            if (name.startsWith('hyph_') || name.startsWith('th_')) continue;
            if (File(p.setExtension(entry.path, '.aff')).existsSync()) {
              paths.putIfAbsent(name, () => p.withoutExtension(entry.path));
            }
          }
        } on FileSystemException {
          continue;
        }
      }
      if (paths.isNotEmpty) {
        return SpellingSetup(
          hunspell,
          paths.keys.toList()..sort(),
          paths: paths,
        );
      }
    }
    final enchant = findExecutable('enchant-2', env);
    final lsmod = findExecutable('enchant-lsmod-2', env);
    if (enchant != null && lsmod != null) {
      try {
        final result = await Process.run(lsmod, ['-list-dicts']);
        final languages =
            LineSplitter.split(result.stdout as String)
                .map((l) => l.trim().split(RegExp(r'\s+')).first)
                .where((l) => l.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        if (languages.isNotEmpty) return SpellingSetup(enchant, languages);
      } catch (_) {}
    }
    return null;
  }

  static String? findExecutable(String name, Map<String, String> env) {
    for (final dir in (env['PATH'] ?? '/usr/bin:/bin').split(':')) {
      if (dir.isEmpty) continue;
      final path = p.join(dir, name);
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// The dictionary to use: [preferred] when installed, else the one for
  /// the system language, else US English, else the first one.
  String defaultLanguage({
    String? preferred,
    Map<String, String>? environment,
  }) {
    if (preferred != null && languages.contains(preferred)) return preferred;
    final env = environment ?? Platform.environment;
    for (final key in ['LC_ALL', 'LC_MESSAGES', 'LANG']) {
      final value = env[key];
      if (value == null || value.isEmpty) continue;
      final locale = value.split('.').first.split('@').first;
      if (languages.contains(locale)) return locale;
      final lang = locale.split('_').first;
      final match = languages.where((l) => l.split('_').first == lang);
      if (match.isNotEmpty) return match.first;
    }
    if (languages.contains('en_US')) return 'en_US';
    return languages.first;
  }
}

const _languageNames = {
  'en': 'English',
  'de': 'German',
  'fr': 'French',
  'es': 'Spanish',
  'it': 'Italian',
  'pt': 'Portuguese',
  'nl': 'Dutch',
  'sv': 'Swedish',
  'da': 'Danish',
  'nb': 'Norwegian (Bokmål)',
  'nn': 'Norwegian (Nynorsk)',
  'fi': 'Finnish',
  'pl': 'Polish',
  'cs': 'Czech',
  'sk': 'Slovak',
  'hu': 'Hungarian',
  'ro': 'Romanian',
  'ru': 'Russian',
  'uk': 'Ukrainian',
  'el': 'Greek',
  'tr': 'Turkish',
  'ca': 'Catalan',
  'ga': 'Irish',
  'cy': 'Welsh',
};

const _regionNames = {
  'US': 'United States',
  'GB': 'United Kingdom',
  'AU': 'Australia',
  'CA': 'Canada',
  'NZ': 'New Zealand',
  'IE': 'Ireland',
  'ZA': 'South Africa',
  'IN': 'India',
  'DE': 'Germany',
  'AT': 'Austria',
  'CH': 'Switzerland',
  'FR': 'France',
  'BE': 'Belgium',
  'ES': 'Spain',
  'MX': 'Mexico',
  'AR': 'Argentina',
  'IT': 'Italy',
  'PT': 'Portugal',
  'BR': 'Brazil',
  'NL': 'Netherlands',
};

/// "English (United States)" for `en_US`; unknown codes stay as they are.
String languageDisplayName(String code) {
  final parts = code.split(RegExp('[_-]'));
  final language = _languageNames[parts.first.toLowerCase()];
  if (language == null) return code;
  if (parts.length < 2) return language;
  final region = _regionNames[parts[1].toUpperCase()] ?? parts[1];
  return '$language ($region)';
}

/// Checks words against a dictionary, remembering the answers, the words
/// the user added to the dictionary and those ignored for this session.
class SpellChecker extends ChangeNotifier {
  final SpellingBackend _backend;
  final String language;
  final Set<String> _dictionary;
  final void Function(Set<String> words)? _onDictionaryChanged;
  final _cache = <String, List<String>?>{};
  final _ignored = <String>{};
  Future<void> _pending = Future.value();

  SpellChecker(
    this._backend, {
    required this.language,
    Iterable<String> dictionary = const [],
    this._onDictionaryChanged,
  }) : _dictionary = dictionary.toSet();

  Set<String> get dictionary => Set.unmodifiable(_dictionary);

  bool _accepted(String word) =>
      _ignored.contains(word) ||
      _dictionary.contains(word) ||
      _dictionary.contains(word.toLowerCase());

  /// The misspelled words of [text].
  Future<List<WordSpan>> check(String text) async {
    final words = wordsToCheck(text);
    await _lookUp(words.map((w) => w.word));
    return [
      for (final w in words)
        if (!_accepted(w.word) && _cache[w.word] != null) w,
    ];
  }

  /// Whether [word] is spelled correctly (as far as known so far).
  bool isKnown(String word) => _accepted(word) || _cache[word] == null;

  Future<void> _lookUp(Iterable<String> words) {
    final previous = _pending;
    final result = previous.then((_) async {
      final unknown = words
          .where((w) => !_cache.containsKey(w) && !_accepted(w))
          .toSet()
          .toList();
      if (unknown.isEmpty) return;
      final answers = await _backend.lookup(unknown);
      for (var i = 0; i < unknown.length; i++) {
        _cache[unknown[i]] = answers[i];
      }
    });
    // One lookup at a time; a failure doesn't block the next one.
    _pending = result.catchError((_) {});
    return result;
  }

  /// Suggestions for a misspelled [word] (empty when there are none).
  Future<List<String>> suggestions(String word) async {
    await _lookUp([word]);
    return _cache[word] ?? const [];
  }

  /// Suggestions already known for [word], without asking the dictionary.
  List<String> knownSuggestions(String word) => _cache[word] ?? const [];

  /// Ignore All: accepts [word] until Look In closes.
  void ignoreAll(String word) {
    _ignored.add(word);
    notifyListeners();
  }

  /// Add to Dictionary: accepts [word] from now on.
  void addToDictionary(String word) {
    if (!_dictionary.add(word)) return;
    _onDictionaryChanged?.call(dictionary);
    notifyListeners();
  }

  void removeFromDictionary(String word) {
    if (!_dictionary.remove(word)) return;
    _onDictionaryChanged?.call(dictionary);
    notifyListeners();
  }

  Future<void> close() => _backend.close();
}

/// The app's spell checker and its options (File > Options > Mail).
class Spelling {
  Spelling._();

  static const asYouTypeKey = 'spelling.asYouType';
  static const beforeSendKey = 'spelling.beforeSend';
  static const languageKey = 'spelling.language';
  static const dictionaryKey = 'spelling.dictionary';

  // Results are kept as values, not futures: a future belongs to the zone
  // it was created in.
  static SpellingSetup? _setup;
  static bool _detected = false;
  static DataStore? _checkerStore;
  static SpellChecker? _opened;
  static bool _unavailable = false;
  static Future<SpellChecker?>? _opening;
  static int _generation = 0;

  /// Replaces spelling program detection (tests).
  static Future<SpellingSetup?> Function() detect = SpellingSetup.detect;

  /// Replaces how the dictionary is opened (tests).
  static Future<SpellingBackend> Function(String executable, String language)
  startBackend = IspellBackend.start;

  static Future<SpellingSetup?> setup() async {
    if (_detected) return _setup;
    final setup = await detect();
    _setup = setup;
    _detected = true;
    return setup;
  }

  static bool asYouType(DataStore store) =>
      store.getBool(asYouTypeKey, defaultValue: true);

  static bool beforeSend(DataStore store) => store.getBool(beforeSendKey);

  static List<String> savedDictionary(DataStore store) {
    final raw = store.getString(dictionaryKey);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  /// The spell checker for the chosen language, started on first use;
  /// null when no spelling program or dictionary is installed.
  static Future<SpellChecker?> checker([DataStore? store]) {
    store ??= DataStore.instance;
    if (identical(_checkerStore, store)) {
      if (_opened != null || _unavailable) return Future.value(_opened);
      if (_opening case final Future<SpellChecker?> opening) return opening;
    } else if (_checkerStore != null) {
      unawaited(reset());
    }
    _checkerStore = store;
    final generation = ++_generation;
    final opening = _open(store).then((checker) {
      if (generation != _generation) {
        // Reset while it was starting.
        unawaited(checker?.close());
        return null;
      }
      _opened = checker;
      _unavailable = checker == null;
      _opening = null;
      return checker;
    });
    _opening = opening;
    return opening;
  }

  static Future<SpellChecker?> _open(DataStore store) async {
    final setup = await Spelling.setup();
    if (setup == null) return null;
    final language = setup.defaultLanguage(
      preferred: store.getString(languageKey),
    );
    try {
      final backend = await startBackend(
        setup.executable,
        setup.dictionaryFor(language),
      );
      return SpellChecker(
        backend,
        language: language,
        dictionary: savedDictionary(store),
        onDictionaryChanged: (words) =>
            store.setString(dictionaryKey, jsonEncode(words.toList()..sort())),
      );
    } catch (e) {
      debugPrint('Spell checking is not available: $e');
      return null;
    }
  }

  /// Switches the dictionary language; the next [checker] call opens it.
  static Future<void> setLanguage(DataStore store, String language) async {
    store.setString(languageKey, language);
    await reset();
  }

  /// Closes the current checker (and forgets detection results when
  /// [redetect] is set).
  static Future<void> reset({bool redetect = false}) async {
    final previous = _opened;
    _generation++;
    _opened = null;
    _unavailable = false;
    _opening = null;
    _checkerStore = null;
    if (redetect) {
      _setup = null;
      _detected = false;
    }
    await previous?.close();
  }
}
