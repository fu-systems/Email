import 'dart:io';

import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/services/spell_checker.dart';
import 'package:look_in/widgets/compose/spelling.dart';
import 'package:path/path.dart' as p;

/// Knows every word except those in [misspelled].
class FakeSpellingBackend implements SpellingBackend {
  final Map<String, List<String>> misspelled;
  final lookups = <String>[];
  bool closed = false;

  FakeSpellingBackend(this.misspelled);

  @override
  Future<List<List<String>?>> lookup(List<String> words) async {
    lookups.addAll(words);
    return [for (final w in words) misspelled[w]];
  }

  @override
  Future<void> close() async => closed = true;
}

void main() {
  group('wordsToCheck', () {
    List<String> words(String text) =>
        wordsToCheck(text).map((w) => w.word).toList();

    test('finds words with their offsets', () {
      final spans = wordsToCheck('Helo  wörld, don’t stop.');
      expect(spans.map((w) => w.word), ['Helo', 'wörld', 'don’t', 'stop']);
      expect(spans[1].start, 6);
      expect(spans[1].end, 11);
      expect(spans[2], const WordSpan(13, 18, 'don’t'));
    });

    test('skips what Word skips', () {
      expect(words('Call NASA about ISO9001 and B2B deals'), [
        'Call',
        'about',
        'and',
        'deals',
      ]);
      expect(words('see https://exmaple.com/pth?q=zz or www.fooo.org now'), [
        'see',
        'or',
        'now',
      ]);
      expect(words('mail bobb@exmaple.com today'), ['mail', 'today']);
      expect(words('open ~/Docmuents/fille.txt and/or /usr/shre'), [
        'open',
        'and',
        'or',
      ]);
      expect(words('a b snake_case x'), isEmpty);
    });
  });

  group('IspellBackend.parseAnswer', () {
    test('reads suggestions and correct words', () {
      expect(IspellBackend.parseAnswer(const []), isNull);
      expect(IspellBackend.parseAnswer(const ['*']), isNull);
      expect(
        IspellBackend.parseAnswer(const ['& helo 3 1: hole, help, hello']),
        ['hole', 'help', 'hello'],
      );
      expect(IspellBackend.parseAnswer(const ['# Qwzx 1']), isEmpty);
      expect(IspellBackend.parseAnswer(const ['? colour 1 1: color']), [
        'color',
      ]);
    });
  });

  group('SpellChecker', () {
    test('checks each word once and honors the user dictionary', () async {
      final backend = FakeSpellingBackend({
        'Helo': ['Hello', 'Help'],
        'wrld': ['world'],
        'Contoso': [],
      });
      Set<String>? saved;
      final checker = SpellChecker(
        backend,
        language: 'en_US',
        dictionary: const ['contoso'],
        onDictionaryChanged: (words) => saved = words,
      );

      final first = await checker.check('Helo wrld, Helo Contoso');
      expect(first.map((w) => w.word), ['Helo', 'wrld', 'Helo']);
      expect(backend.lookups, ['Helo', 'wrld'], reason: 'cached, deduped');
      expect(checker.knownSuggestions('Helo'), ['Hello', 'Help']);
      expect(await checker.suggestions('wrld'), ['world']);

      checker.ignoreAll('wrld');
      checker.addToDictionary('Helo');
      expect(saved, {'contoso', 'Helo'});
      expect(await checker.check('Helo wrld'), isEmpty);
      checker.removeFromDictionary('Helo');
      expect((await checker.check('Helo')).single.word, 'Helo');
      expect(backend.lookups, ['Helo', 'wrld']);

      await checker.close();
      expect(backend.closed, isTrue);
    });
  });

  test('languageDisplayName', () {
    expect(languageDisplayName('en_US'), 'English (United States)');
    expect(languageDisplayName('de_CH'), 'German (Switzerland)');
    expect(languageDisplayName('fr'), 'French');
    expect(languageDisplayName('xx_YY'), 'xx_YY');
  });

  group('SpellingSetup', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('spelling'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('finds hunspell and its dictionaries', () async {
      final bin = Directory(p.join(dir.path, 'bin'))..createSync();
      File(p.join(bin.path, 'hunspell')).writeAsStringSync('');
      final dicts = Directory(p.join(dir.path, 'dicts'))..createSync();
      for (final name in ['en_GB', 'de_DE', 'hyph_de_DE']) {
        File(p.join(dicts.path, '$name.dic')).writeAsStringSync('');
        File(p.join(dicts.path, '$name.aff')).writeAsStringSync('');
      }
      File(p.join(dicts.path, 'fr_FR.dic')).writeAsStringSync('');

      final setup = await SpellingSetup.detect(
        environment: {'PATH': bin.path, 'DICPATH': dicts.path},
      );
      expect(setup, isNotNull);
      expect(setup!.executable, p.join(bin.path, 'hunspell'));
      expect(setup.languages, containsAll(['de_DE', 'en_GB']));
      expect(setup.languages, isNot(contains('fr_FR')), reason: 'no .aff');
      expect(setup.languages, isNot(contains('hyph_de_DE')));
      expect(setup.dictionaryFor('en_GB'), p.join(dicts.path, 'en_GB'));

      expect(
        setup.defaultLanguage(environment: {'LANG': 'de_AT.UTF-8'}),
        'de_DE',
      );
      expect(
        setup.defaultLanguage(
          preferred: 'en_GB',
          environment: {'LANG': 'de_DE.UTF-8'},
        ),
        'en_GB',
      );
    });

    test('is null without a spelling program', () async {
      expect(
        await SpellingSetup.detect(environment: {'PATH': dir.path}),
        isNull,
      );
    });
  });

  group('IspellBackend', () {
    test('speaks the ispell pipe protocol', () async {
      // A stand-in for hunspell -a that doesn't know "helo" and "wrld".
      final script =
          File(
            p.join(
              Directory.systemTemp.createTempSync('ispell').path,
              'ispell',
            ),
          )..writeAsStringSync(r'''#!/bin/sh
echo "@(#) International Ispell Version 3.2.06 (but really Fake 1.0)"
while IFS= read -r line; do
  case "$line" in
    '!') ;;
    '^helo') echo "& helo 2 1: hello, help"; echo ;;
    '^wrld') echo "# wrld 1"; echo ;;
    ^*) echo ;;
  esac
done
''');
      await Process.run('chmod', ['+x', script.path]);
      final backend = await IspellBackend.start(script.path, 'en_US');
      expect(await backend.lookup(['helo', 'hello', 'wrld']), [
        ['hello', 'help'],
        null,
        <String>[],
      ]);
      expect(await backend.lookup(['fine']), [null]);
      await backend.close();
      await expectLater(
        backend.lookup(['again']),
        throwsA(isA<SpellCheckerException>()),
      );
    });

    test('reports a program that fails to start', () async {
      await expectLater(
        IspellBackend.start('/nonexistent/hunspell', 'en_US'),
        throwsA(isA<SpellCheckerException>()),
      );
    });

    final hunspell = SpellingSetup.findExecutable(
      'hunspell',
      Platform.environment,
    );
    final hasEnglish =
        File('/usr/share/hunspell/en_US.dic').existsSync() ||
        File('/usr/share/myspell/en_US.dic').existsSync();
    test(
      'works with the real hunspell',
      () async {
        final backend = await IspellBackend.start(hunspell!, 'en_US');
        final answers = await backend.lookup(['helo', 'hello', 'teh', 'naïve']);
        expect(answers[0], contains('hello'));
        expect(answers[1], isNull);
        expect(answers[2], contains('the'));
        expect(answers[3], contains('naive'));
        await backend.close();
      },
      skip: hunspell == null || !hasEnglish
          ? 'hunspell with an en_US dictionary is not installed'
          : false,
    );
  });

  group('SpellingHighlighter.touches', () {
    const word = WordSpan(10, 14, 'helo');
    test('edits in or next to the word', () {
      expect(
        SpellingHighlighter.touches(
          Delta()
            ..retain(12)
            ..insert('x'),
          word,
        ),
        isTrue,
      );
      expect(
        SpellingHighlighter.touches(
          Delta()
            ..retain(14)
            ..insert('x'),
          word,
        ),
        isTrue,
      );
      expect(
        SpellingHighlighter.touches(
          Delta()
            ..retain(8)
            ..delete(3),
          word,
        ),
        isTrue,
      );
    });
    test('edits elsewhere and formatting', () {
      expect(
        SpellingHighlighter.touches(Delta()..insert('abc'), word),
        isFalse,
      );
      expect(
        SpellingHighlighter.touches(
          Delta()
            ..retain(20)
            ..delete(2),
          word,
        ),
        isFalse,
      );
      expect(
        SpellingHighlighter.touches(
          Delta()
            ..retain(10)
            ..retain(4, {'bold': true}),
          word,
        ),
        isFalse,
      );
    });
  });
}
