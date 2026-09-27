import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../services/spell_checker.dart';
import '../../theme/outlook_theme.dart';
import '../common.dart';

/// Red wavy underline for words not in the dictionary.
const misspelledStyle = TextStyle(
  decoration: TextDecoration.underline,
  decorationStyle: TextDecorationStyle.wavy,
  decorationColor: Color(0xFFE81123),
);

/// Checks the message as it is typed and underlines misspelled words.
class SpellingHighlighter extends ChangeNotifier {
  final QuillController controller;
  final SpellChecker checker;
  final Duration delay;

  Document? _document;
  StreamSubscription<DocChange>? _changes;
  List<WordSpan> _misspelled = const [];
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  SpellingHighlighter(
    this.controller,
    this.checker, {
    this.delay = const Duration(milliseconds: 400),
  }) {
    controller.addListener(_onController);
    checker.addListener(_checkSoon);
    _attach();
  }

  /// Misspelled words, in document offsets.
  List<WordSpan> get misspelled => _misspelled;

  /// The misspelled word at the caret (or selected), if any.
  WordSpan? wordAt(TextSelection selection) {
    if (!selection.isValid) return null;
    for (final w in _misspelled) {
      if (selection.isCollapsed
          ? w.contains(selection.baseOffset)
          : selection.start >= w.start && selection.end <= w.end) {
        return w;
      }
    }
    return null;
  }

  void _onController() {
    if (!identical(controller.document, _document)) _attach();
  }

  void _attach() {
    _changes?.cancel();
    _document = controller.document;
    _misspelled = const [];
    _changes = _document!.changes.listen(_onChange);
    _checkSoon(immediately: true);
  }

  void _onChange(DocChange change) {
    _generation++;
    // Keep underlines on their words until the next check; drop those
    // the edit touched.
    final delta = change.change;
    _misspelled = [
      for (final w in _misspelled)
        if (!touches(delta, w))
          () {
            final start = delta.transformPosition(w.start, force: false);
            return WordSpan(start, start + w.end - w.start, w.word);
          }(),
    ];
    _checkSoon();
  }

  /// Whether [delta] inserts or deletes text in or next to [word].
  @visibleForTesting
  static bool touches(Delta delta, WordSpan word) {
    var pos = 0;
    for (final op in delta.toList()) {
      if (op.isRetain) {
        pos += op.length!;
      } else if (op.isInsert) {
        if (pos >= word.start && pos <= word.end) return true;
      } else if (op.isDelete) {
        final end = pos + op.length!;
        if (pos <= word.end && end >= word.start) return true;
        pos = end;
      }
      if (pos > word.end) return false;
    }
    return false;
  }

  void _checkSoon({bool immediately = false}) {
    _timer?.cancel();
    _timer = Timer(immediately ? Duration.zero : delay, _check);
  }

  Future<void> _check() async {
    final generation = _generation;
    final document = _document;
    if (document == null || _disposed) return;
    final List<WordSpan> result;
    try {
      result = await checker.check(document.toPlainText());
    } catch (_) {
      return;
    }
    if (_disposed ||
        generation != _generation ||
        !identical(document, _document)) {
      return;
    }
    if (_sameWords(result, _misspelled)) return;
    _misspelled = result;
    notifyListeners();
  }

  static bool _sameWords(List<WordSpan> a, List<WordSpan> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Text spans for the editor with misspelled words underlined.
  InlineSpan buildSpan(
    BuildContext context,
    Node node,
    int nodeOffset,
    String text,
    TextStyle? style,
    GestureRecognizer? recognizer,
  ) {
    if (_misspelled.isEmpty || text.isEmpty) {
      return defaultSpanBuilder(
        context,
        node,
        nodeOffset,
        text,
        style,
        recognizer,
      );
    }
    final start = node.documentOffset + nodeOffset;
    final end = start + text.length;
    final children = <InlineSpan>[];
    var pos = start;
    for (final w in _misspelled) {
      if (w.end <= start || w.start >= end) continue;
      final s = math.max(w.start, pos);
      final e = math.min(w.end, end);
      if (e <= s) continue;
      if (s > pos) {
        children.add(
          TextSpan(
            text: text.substring(pos - start, s - start),
            recognizer: recognizer,
          ),
        );
      }
      children.add(
        TextSpan(
          text: text.substring(s - start, e - start),
          style: misspelledStyle,
          recognizer: recognizer,
        ),
      );
      pos = e;
    }
    if (children.isEmpty) {
      return defaultSpanBuilder(
        context,
        node,
        nodeOffset,
        text,
        style,
        recognizer,
      );
    }
    if (pos < end) {
      children.add(
        TextSpan(text: text.substring(pos - start), recognizer: recognizer),
      );
    }
    return TextSpan(style: style, children: children);
  }

  /// Replaces [word] with [replacement], keeping the word's formatting.
  void replace(WordSpan word, String replacement) =>
      replaceInQuill(controller, word, replacement);

  /// The editor's right-click menu with suggestions for a misspelled word
  /// at the click.
  Widget contextMenu(BuildContext context, QuillRawEditorState state) {
    final word = wordAt(controller.selection);
    final items = <ContextMenuButtonItem>[
      if (word != null) ...[
        for (final s in checker.knownSuggestions(word.word).take(5))
          ContextMenuButtonItem(
            label: s,
            onPressed: () {
              state.hideToolbar();
              replace(word, s);
            },
          ),
        if (checker.knownSuggestions(word.word).isEmpty)
          const ContextMenuButtonItem(
            label: '(No Spelling Suggestions)',
            onPressed: null,
          ),
        ContextMenuButtonItem(
          label: 'Ignore All',
          onPressed: () {
            state.hideToolbar();
            checker.ignoreAll(word.word);
          },
        ),
        ContextMenuButtonItem(
          label: 'Add to Dictionary',
          onPressed: () {
            state.hideToolbar();
            checker.addToDictionary(word.word);
          },
        ),
      ],
      ...state.contextMenuButtonItems,
    ];
    return TextFieldTapRegion(
      child: AdaptiveTextSelectionToolbar.buttonItems(
        buttonItems: items,
        anchors: state.contextMenuAnchors,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _changes?.cancel();
    controller.removeListener(_onController);
    checker.removeListener(_checkSoon);
    super.dispose();
  }
}

/// Replaces [word] in a Quill document. The new text goes in after the
/// word first, so it takes the word's formatting.
void replaceInQuill(QuillController controller, WordSpan word, String text) {
  controller.replaceText(word.end, 0, text, null);
  controller.replaceText(
    word.start,
    word.end - word.start,
    '',
    TextSelection.collapsed(offset: word.start + text.length),
  );
}

/// Spell checking for plain-text messages (TextField).
class PlainTextSpellCheckService extends SpellCheckService {
  final SpellChecker checker;

  PlainTextSpellCheckService(this.checker);

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    try {
      final words = await checker.check(text);
      return [
        for (final w in words)
          SuggestionSpan(
            TextRange(start: w.start, end: w.end),
            checker.knownSuggestions(w.word),
          ),
      ];
    } catch (_) {
      return null;
    }
  }
}

/// Right-click menu for a plain-text message with spelling suggestions.
Widget plainTextSpellingMenu(
  BuildContext context,
  EditableTextState state,
  SpellChecker? checker,
) {
  final value = state.textEditingValue;
  final span = value.selection.isValid
      ? state.findSuggestionSpanAtCursorIndex(value.selection.baseOffset)
      : null;
  final word = span?.range.textInside(value.text);
  void replaceWith(String text) {
    state.hideToolbar();
    state.userUpdateTextEditingValue(
      TextEditingValue(
        text: value.text.replaceRange(span!.range.start, span.range.end, text),
        selection: TextSelection.collapsed(
          offset: span.range.start + text.length,
        ),
      ),
      SelectionChangedCause.toolbar,
    );
  }

  final items = <ContextMenuButtonItem>[
    if (span != null && word != null && checker != null) ...[
      for (final s in span.suggestions.take(5))
        ContextMenuButtonItem(label: s, onPressed: () => replaceWith(s)),
      if (span.suggestions.isEmpty)
        const ContextMenuButtonItem(
          label: '(No Spelling Suggestions)',
          onPressed: null,
        ),
      ContextMenuButtonItem(
        label: 'Ignore All',
        onPressed: () {
          state.hideToolbar();
          checker.ignoreAll(word);
          // Check again so the underline goes away.
          replaceWith(word);
        },
      ),
      ContextMenuButtonItem(
        label: 'Add to Dictionary',
        onPressed: () {
          state.hideToolbar();
          checker.addToDictionary(word);
          replaceWith(word);
        },
      ),
    ],
    ...state.contextMenuButtonItems,
  ];
  return AdaptiveTextSelectionToolbar.buttonItems(
    buttonItems: items,
    anchors: state.contextMenuAnchors,
  );
}

/// The text the Spelling dialog works through.
abstract class SpellingTarget {
  String get text;
  void select(WordSpan word);
  void replace(WordSpan word, String replacement);
}

class QuillSpellingTarget implements SpellingTarget {
  final QuillController controller;
  QuillSpellingTarget(this.controller);

  @override
  String get text => controller.document.toPlainText();

  @override
  void select(WordSpan word) => controller.updateSelection(
    TextSelection(baseOffset: word.start, extentOffset: word.end),
    ChangeSource.local,
  );

  @override
  void replace(WordSpan word, String replacement) =>
      replaceInQuill(controller, word, replacement);
}

class TextSpellingTarget implements SpellingTarget {
  final TextEditingController controller;

  /// Text after this offset (the quoted original) is not checked.
  final int Function()? checkedLength;

  TextSpellingTarget(this.controller, {this.checkedLength});

  @override
  String get text {
    final text = controller.text;
    final length = checkedLength?.call();
    return length == null
        ? text
        : text.substring(0, math.min(length, text.length));
  }

  @override
  void select(WordSpan word) => controller.selection = TextSelection(
    baseOffset: word.start,
    extentOffset: word.end,
  );

  @override
  void replace(WordSpan word, String replacement) {
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(word.start, word.end, replacement),
      selection: TextSelection.collapsed(
        offset: word.start + replacement.length,
      ),
    );
  }
}

/// Review > Spelling & Grammar (F7): goes through the misspelled words one
/// at a time. Returns true when the check ran to the end, false when it
/// was cancelled.
Future<bool> showSpellingDialog(
  BuildContext context, {
  required SpellingTarget target,
  required SpellChecker checker,
  bool announceCompletion = true,
}) async {
  final first = await _nextMisspelling(target, checker, 0, const {});
  if (!context.mounted) return false;
  if (first != null) target.select(first);
  final complete = first == null
      ? true
      : await showDialog<bool>(
              context: context,
              barrierColor: Colors.black12,
              builder: (_) => _SpellingDialog(
                target: target,
                checker: checker,
                first: first,
              ),
            ) ??
            false;
  if (complete && announceCompletion && context.mounted) {
    await showConfirmDialog(
      context,
      title: 'Look In',
      message: 'The spelling check is complete.',
      confirmLabel: 'OK',
      showCancel: false,
    );
  }
  return complete;
}

Future<WordSpan?> _nextMisspelling(
  SpellingTarget target,
  SpellChecker checker,
  int from,
  Set<int> ignoredOnce,
) async {
  final words = await checker.check(target.text);
  for (final w in words) {
    if (w.start >= from && !ignoredOnce.contains(w.start)) return w;
  }
  return null;
}

class _SpellingDialog extends StatefulWidget {
  final SpellingTarget target;
  final SpellChecker checker;
  final WordSpan first;

  const _SpellingDialog({
    required this.target,
    required this.checker,
    required this.first,
  });

  @override
  State<_SpellingDialog> createState() => _SpellingDialogState();
}

class _SpellingDialogState extends State<_SpellingDialog> {
  late WordSpan _word = widget.first;
  List<String> _suggestions = const [];
  final _changeTo = TextEditingController();
  int? _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The caller selected the first word.
    _show(_word, select: false);
  }

  @override
  void dispose() {
    _changeTo.dispose();
    super.dispose();
  }

  void _show(WordSpan word, {bool select = true}) {
    _word = word;
    if (select) widget.target.select(word);
    _suggestions = widget.checker.knownSuggestions(word.word);
    _selected = _suggestions.isEmpty ? null : 0;
    _changeTo.text = _suggestions.isEmpty ? word.word : _suggestions.first;
  }

  Future<void> _continueFrom(int offset) async {
    setState(() => _busy = true);
    final next = await _nextMisspelling(
      widget.target,
      widget.checker,
      offset,
      const {},
    );
    if (!mounted) return;
    if (next == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _show(next);
    });
  }

  void _ignoreOnce() => _continueFrom(_word.end);

  void _ignoreAll() {
    widget.checker.ignoreAll(_word.word);
    _continueFrom(_word.start);
  }

  void _add() {
    widget.checker.addToDictionary(_word.word);
    _continueFrom(_word.start);
  }

  void _change() {
    final text = _changeTo.text;
    widget.target.replace(_word, text);
    _continueFrom(_word.start + text.length);
  }

  Future<void> _changeAll() async {
    final text = _changeTo.text;
    final same = (await widget.checker.check(
      widget.target.text,
    )).where((w) => w.word == _word.word).toList();
    // Last first, so earlier offsets stay valid.
    for (final w in same.reversed) {
      widget.target.replace(w, text);
    }
    await _continueFrom(_word.start + text.length);
  }

  /// The paragraph around the word, for the "Not in Dictionary" box.
  InlineSpan _context() {
    final text = widget.target.text;
    var start = text.lastIndexOf('\n', math.max(0, _word.start - 1)) + 1;
    var end = text.indexOf('\n', _word.end);
    if (end < 0) end = text.length;
    start = math.max(start, _word.start - 160);
    end = math.min(end, _word.end + 160);
    return TextSpan(
      children: [
        TextSpan(text: text.substring(start, _word.start)),
        TextSpan(
          text: text.substring(_word.start, _word.end),
          style: const TextStyle(color: Color(0xFFE81123)),
        ),
        TextSpan(text: text.substring(_word.end, end)),
      ],
    );
  }

  Widget _button(
    String label,
    VoidCallback? onPressed, {
    bool primary = false,
  }) {
    final child = Text(label);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        width: 150,
        child: primary
            ? ElevatedButton(onPressed: _busy ? null : onPressed, child: child)
            : OutlinedButton(onPressed: _busy ? null : onPressed, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final box = BoxDecoration(
      color: Colors.white,
      border: Border.all(color: OutlookTheme.dividerColor),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(false),
      },
      child: OutlookDialog(
        title: 'Spelling: ${languageDisplayName(widget.checker.language)}',
        width: 560,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Not in Dictionary:'),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    height: 86,
                    padding: const EdgeInsets.all(8),
                    decoration: box,
                    child: SingleChildScrollView(
                      child: Text.rich(
                        _context(),
                        style: const TextStyle(
                          fontSize: 13,
                          color: OutlookTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    _button('Ignore Once', _ignoreOnce),
                    _button('Ignore All', _ignoreAll),
                    _button('Add to Dictionary', _add),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text('Suggestions:'),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 110,
                        decoration: box,
                        child: _suggestions.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: Text(
                                  '(No Spelling Suggestions)',
                                  style: TextStyle(
                                    color: OutlookTheme.textMuted,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _suggestions.length,
                                itemExtent: 24,
                                itemBuilder: (context, i) => Material(
                                  color: i == _selected
                                      ? OutlookTheme.selectedItemBackground
                                      : Colors.transparent,
                                  child: InkWell(
                                    onTap: () => setState(() {
                                      _selected = i;
                                      _changeTo.text = _suggestions[i];
                                    }),
                                    onDoubleTap: () {
                                      _changeTo.text = _suggestions[i];
                                      _change();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(_suggestions[i]),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Change to:'),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _changeTo,
                              autofocus: true,
                              onSubmitted: (_) => _change(),
                              decoration: const InputDecoration(isDense: true),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    _button('Change', _change, primary: true),
                    _button('Change All', _changeAll),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
