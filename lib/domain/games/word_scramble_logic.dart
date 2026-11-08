import 'dart:math' as math;

import 'package:characters/characters.dart';

import 'word_lists.dart';

enum WordLanguage {
  english('English'),
  urdu('اردو');

  const WordLanguage(this.label);
  final String label;

  bool get isRtl => this == WordLanguage.urdu;
}

class ScrambleQuestion {
  const ScrambleQuestion({required this.word, required this.tiles, required this.language});

  final String word;

  /// The word's letters (grapheme clusters) in scrambled order.
  final List<String> tiles;
  final WordLanguage language;

  int get length => tiles.length;
}

class WordScrambleLogic {
  const WordScrambleLogic._();

  static const int fastMs = 4000;

  static List<String> wordsFor(WordLanguage lang) =>
      lang == WordLanguage.english ? WordLists.english : WordLists.urdu;

  static final Map<WordLanguage, Set<String>> _dictionary = {
    for (final l in WordLanguage.values) l: wordsFor(l).toSet(),
  };

  static int targetLength(int level, WordLanguage lang) {
    final l = level.clamp(1, 10);
    if (lang == WordLanguage.english) return 4 + (l - 1) ~/ 2; // 4..8
    return l <= 3 ? 3 : (l <= 6 ? 4 : (l <= 9 ? 5 : 6)); // 3..6
  }

  static List<String> lettersOf(String word) => word.characters.toList();

  static ScrambleQuestion generate(
    math.Random r,
    int level,
    WordLanguage lang, {
    Set<String> avoid = const {},
  }) {
    final words = wordsFor(lang);
    var len = targetLength(level, lang);
    var pool = <String>[];
    // Fall back to shorter words if a length is exhausted.
    while (len >= 3) {
      pool = words.where((w) => lettersOf(w).length == len && !avoid.contains(w)).toList();
      if (pool.isNotEmpty) break;
      len--;
    }
    if (pool.isEmpty) pool = words.where((w) => !avoid.contains(w)).toList();
    if (pool.isEmpty) pool = words;
    final word = pool[r.nextInt(pool.length)];
    return ScrambleQuestion(word: word, tiles: scramble(r, word), language: lang);
  }

  /// Shuffles the letters so the original word is not shown as-is (unless all
  /// letters are identical, which no listed word has).
  static List<String> scramble(math.Random r, String word) {
    final letters = lettersOf(word);
    final tiles = [...letters];
    for (var i = 0; i < 20; i++) {
      tiles.shuffle(r);
      if (tiles.join() != word) break;
    }
    return tiles;
  }

  /// Accepts the target word or any other listed word made from exactly the
  /// same letters (e.g. "listen" / "silent").
  static bool isCorrect(String attempt, ScrambleQuestion q) {
    if (attempt == q.word) return true;
    if (!(_dictionary[q.language]?.contains(attempt) ?? false)) return false;
    final a = lettersOf(attempt)..sort();
    final b = lettersOf(q.word)..sort();
    return a.join() == b.join();
  }

  static int basePoints(ScrambleQuestion q, int level) => q.length * 12 + level * 4;
}
