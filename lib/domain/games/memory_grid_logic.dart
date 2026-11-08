import 'dart:math' as math;

/// Parameters for one Memory Grid round at a given difficulty level.
class MemoryGridConfig {
  const MemoryGridConfig({
    required this.gridSize,
    required this.tileCount,
    required this.showMs,
  });

  /// Grid is [gridSize] x [gridSize].
  final int gridSize;

  /// Number of tiles that light up.
  final int tileCount;

  /// How long the pattern stays visible.
  final int showMs;

  int get cellCount => gridSize * gridSize;
}

class MemoryGridLogic {
  const MemoryGridLogic._();

  static MemoryGridConfig configFor(int level) {
    final l = level.clamp(1, 10);
    final gridSize = l <= 2
        ? 3
        : l <= 4
            ? 4
            : l <= 7
                ? 5
                : 6;
    // Never light more than ~45% of the board so it stays readable.
    final maxTiles = (gridSize * gridSize * 0.45).floor();
    final tileCount = math.min(2 + l, maxTiles);
    final showMs = math.max(700, 1300 + tileCount * 90 - l * 60);
    return MemoryGridConfig(gridSize: gridSize, tileCount: tileCount, showMs: showMs);
  }

  /// Picks [MemoryGridConfig.tileCount] distinct cell indexes.
  static Set<int> generatePattern(math.Random random, MemoryGridConfig config) {
    final cells = List<int>.generate(config.cellCount, (i) => i)..shuffle(random);
    return cells.take(config.tileCount).toSet();
  }

  /// Points for completing a round: larger patterns are worth more.
  static int basePoints(MemoryGridConfig config, int level) =>
      config.tileCount * 10 + level * 5;
}
