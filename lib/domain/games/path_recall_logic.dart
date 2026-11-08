import 'dart:math' as math;

class PathRecallConfig {
  const PathRecallConfig({required this.gridSize, required this.length, required this.stepMs});
  final int gridSize;

  /// Number of cells in the path.
  final int length;

  /// Time each step is shown while the path is revealed.
  final int stepMs;

  int get cellCount => gridSize * gridSize;
}

class PathRecallLogic {
  const PathRecallLogic._();

  static PathRecallConfig configFor(int level) {
    final l = level.clamp(1, 10);
    final size = l <= 3 ? 4 : (l <= 6 ? 5 : 6);
    final length = math.min(3 + l, size * size ~/ 2);
    return PathRecallConfig(gridSize: size, length: length, stepMs: math.max(240, 520 - l * 28));
  }

  static bool isAdjacent(int a, int b, int size) {
    final ar = a ~/ size, ac = a % size, br = b ~/ size, bc = b % size;
    return (ar - br).abs() + (ac - bc).abs() == 1;
  }

  static List<int> neighbours(int cell, int size) {
    final r = cell ~/ size, c = cell % size;
    return [
      if (r > 0) cell - size,
      if (r < size - 1) cell + size,
      if (c > 0) cell - 1,
      if (c < size - 1) cell + 1,
    ];
  }

  /// A self-avoiding walk of orthogonally adjacent cells.
  static List<int> generatePath(math.Random r, PathRecallConfig cfg) {
    for (var attempt = 0; attempt < 200; attempt++) {
      final path = [r.nextInt(cfg.cellCount)];
      while (path.length < cfg.length) {
        final options = neighbours(path.last, cfg.gridSize).where((n) => !path.contains(n)).toList();
        if (options.isEmpty) break;
        path.add(options[r.nextInt(options.length)]);
      }
      if (path.length == cfg.length) return path;
    }
    // Unreachable for the configured sizes; a snake path always fits.
    return List.generate(cfg.length, (i) {
      final row = i ~/ cfg.gridSize, col = i % cfg.gridSize;
      return row * cfg.gridSize + (row.isEven ? col : cfg.gridSize - 1 - col);
    });
  }

  static int basePoints(PathRecallConfig cfg, int level) => cfg.length * 12 + level * 5;
}
