import 'skill.dart';

/// Every playable mini-game. New games are added here and picked up by the
/// games list, routing and history automatically.
enum GameType {
  memoryGrid(
    id: 'memory_grid',
    title: 'Memory Grid',
    tagline: 'Remember the glowing tiles',
    howToPlay:
        'Tiles light up for a moment. Tap every tile that glowed. Patterns get bigger as you improve.',
    skill: Skill.memory,
    starThresholds: [600, 1500, 2600],
  ),
  colorClash(
    id: 'color_clash',
    title: 'Color Clash',
    tagline: 'Tap the ink, not the word',
    howToPlay:
        'A color word appears in a different ink. Tap the name of the INK color as fast as you can.',
    skill: Skill.focus,
    starThresholds: [1000, 2500, 4500],
  ),
  speedMath(
    id: 'speed_math',
    title: 'Speed Math',
    tagline: 'Beat the shrinking timer bar',
    howToPlay:
        'Pick the right answer before the bar runs out. Streaks multiply your points.',
    skill: Skill.speed,
    starThresholds: [800, 1800, 3000],
  ),
  shapeMatch(
    id: 'shape_match',
    title: 'Shape Match',
    tagline: 'Same as before? Yes or no',
    howToPlay:
        'Does this shape match the previous one? Only the shape counts, not the color. At higher levels, compare with the shape 2 cards back!',
    skill: Skill.speed,
    starThresholds: [700, 1700, 2900],
  ),
  numberSequence(
    id: 'number_sequence',
    title: 'Number Sequence',
    tagline: 'Crack the hidden pattern',
    howToPlay: 'Find the number that comes next in the sequence. Patterns get trickier as you level up.',
    skill: Skill.logic,
    starThresholds: [400, 1000, 1800],
  ),
  wordScramble(
    id: 'word_scramble',
    title: 'Word Scramble',
    tagline: 'Unscramble words · English & اردو',
    howToPlay:
        'Tap the letters in the right order to rebuild the word. Tap a placed letter to remove it. Words get longer as you improve.',
    skill: Skill.language,
    starThresholds: [400, 1000, 1800],
  ),
  oddOneOut(
    id: 'odd_one_out',
    title: 'Odd One Out',
    tagline: 'Spot the one that is different',
    howToPlay: 'One icon is different from all the others. Find it and tap it — the grid keeps growing!',
    skill: Skill.focus,
    starThresholds: [600, 1500, 2700],
  ),
  pathRecall(
    id: 'path_recall',
    title: 'Path Recall',
    tagline: 'Watch the path, then redraw it',
    howToPlay:
        'Watch the path light up, then trace it from the start: drag your finger or tap each square in order.',
    skill: Skill.memory,
    starThresholds: [500, 1300, 2300],
  );

  const GameType({
    required this.id,
    required this.title,
    required this.tagline,
    required this.howToPlay,
    required this.skill,
    required this.starThresholds,
  });

  /// Stable identifier used in storage, routes and (later) Firestore.
  final String id;
  final String title;
  final String tagline;
  final String howToPlay;
  final Skill skill;

  /// Scores needed for 1, 2 and 3 stars (index 0..2). 3 stars additionally
  /// requires 80% accuracy, see [Rewards.starsFor].
  final List<int> starThresholds;

  /// Length of one round, in seconds.
  static const int roundSeconds = 60;

  static GameType? fromId(String id) {
    for (final t in values) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// The game that follows this one in the catalogue (wraps around).
  GameType get next => values[(index + 1) % values.length];
}
