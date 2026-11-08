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
