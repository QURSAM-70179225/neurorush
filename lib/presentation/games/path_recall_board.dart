import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';

class PathBoardColors {
  const PathBoardColors({
    required this.tile,
    required this.path,
    required this.player,
    required this.wrong,
    required this.start,
  });
  final Color tile;
  final Color path;
  final Color player;
  final Color wrong;
  final Color start;
}

/// Flame board for Path Recall: animates the path with a moving "comet"
/// head, then lets the player trace it with drags or taps. Game rules live in
/// the Flutter widget; this class only renders and reports cells.
class PathRecallBoard extends FlameGame with TapCallbacks, DragCallbacks {
  PathRecallBoard({required this.onCell, required this.colors});

  /// Called when the player's finger enters a cell during input.
  final void Function(int cell) onCell;
  PathBoardColors colors;

  int gridSize = 4;
  List<int> path = const [];
  List<int> drawn = const [];
  int? wrongCell;
  bool inputEnabled = false;
  bool showFullPath = false;
  bool showStart = false;

  double _revealSteps = -1; // < 0 = not revealing
  double _stepSeconds = 0.4;
  void Function()? _onRevealDone;
  int? _lastDragCell;

  static const _gapFraction = 0.12;

  @override
  Color backgroundColor() => const Color(0x00000000);

  void setupRound(int size, List<int> newPath) {
    gridSize = size;
    path = newPath;
    drawn = const [];
    wrongCell = null;
    inputEnabled = false;
    showFullPath = false;
    showStart = false;
    _revealSteps = -1;
  }

  void startReveal(int stepMs, void Function() onDone) {
    _stepSeconds = stepMs / 1000;
    _revealSteps = 0;
    _onRevealDone = onDone;
  }

  bool get isRevealing => _revealSteps >= 0;

  // --- geometry -----------------------------------------------------------

  double get _side => math.min(size.x, size.y);
  Offset get _origin => Offset((size.x - _side) / 2, (size.y - _side) / 2);
  double get _cell => _side / (gridSize + (gridSize - 1) * _gapFraction);
  double get _gap => _cell * _gapFraction;

  Rect cellRect(int i) {
    final r = i ~/ gridSize, c = i % gridSize;
    final o = _origin;
    return Rect.fromLTWH(o.dx + c * (_cell + _gap), o.dy + r * (_cell + _gap), _cell, _cell);
  }

  /// Centre of cell [i] in board (widget-local) coordinates.
  Offset cellCenter(int i) => cellRect(i).center;

  int? cellAt(Offset p) {
    for (var i = 0; i < gridSize * gridSize; i++) {
      // Slightly shrunk hit box so diagonal drags don't clip corners.
      if (cellRect(i).deflate(_cell * 0.08).contains(p)) return i;
    }
    return null;
  }

  // --- loop ---------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);
    if (_revealSteps >= 0) {
      _revealSteps += dt / _stepSeconds;
      if (_revealSteps >= path.length + 0.8) {
        _revealSteps = -1;
        final cb = _onRevealDone;
        _onRevealDone = null;
        cb?.call();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (size.x <= 0) return;
    final radius = Radius.circular(_cell * 0.2);
    final tilePaint = Paint()..color = colors.tile;
    for (var i = 0; i < gridSize * gridSize; i++) {
      canvas.drawRRect(RRect.fromRectAndRadius(cellRect(i), radius), tilePaint);
    }

    // Path being revealed (or shown again after a mistake).
    final revealUpTo = showFullPath ? path.length.toDouble() : (_revealSteps >= 0 ? _revealSteps : 0.0);
    if (revealUpTo > 0) {
      for (var k = 0; k < path.length && k < revealUpTo; k++) {
        final age = (revealUpTo - k).clamp(0.0, 1.0);
        final p = Paint()..color = colors.path.withValues(alpha: 0.35 + 0.65 * age);
        canvas.drawRRect(RRect.fromRectAndRadius(cellRect(path[k]).deflate(_cell * 0.06), radius), p);
      }
      _drawLine(canvas, path, revealUpTo, colors.path);
      if (!showFullPath) {
        final head = _pointAlong(path, math.min(revealUpTo, path.length - 1.0));
        canvas.drawCircle(head, _cell * 0.22, Paint()..color = const Color(0xFFFFFFFF));
        canvas.drawCircle(head, _cell * 0.14, Paint()..color = colors.path);
      }
    }

    if (showStart && path.isNotEmpty && drawn.isEmpty) {
      canvas.drawCircle(
        cellCenter(path.first),
        _cell * 0.3,
        Paint()
          ..color = colors.start
          ..style = PaintingStyle.stroke
          ..strokeWidth = _cell * 0.08,
      );
    }

    // Player trace.
    for (final c in drawn) {
      canvas.drawRRect(RRect.fromRectAndRadius(cellRect(c).deflate(_cell * 0.06), radius), Paint()..color = colors.player);
    }
    _drawLine(canvas, drawn, drawn.length.toDouble(), const Color(0xFFFFFFFF));

    final w = wrongCell;
    if (w != null) {
      canvas.drawRRect(RRect.fromRectAndRadius(cellRect(w).deflate(_cell * 0.06), radius), Paint()..color = colors.wrong);
    }
  }

  Offset _pointAlong(List<int> cells, double t) {
    final i = t.floor().clamp(0, cells.length - 1);
    final j = math.min(i + 1, cells.length - 1);
    final f = (t - i).clamp(0.0, 1.0);
    return Offset.lerp(cellCenter(cells[i]), cellCenter(cells[j]), f)!;
  }

  void _drawLine(Canvas canvas, List<int> cells, double upTo, Color color) {
    if (cells.length < 2 || upTo <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = _cell * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final p = Path()..moveTo(cellCenter(cells.first).dx, cellCenter(cells.first).dy);
    final end = math.min(upTo, cells.length - 1.0);
    for (var k = 1; k <= end.floor(); k++) {
      final c = cellCenter(cells[k]);
      p.lineTo(c.dx, c.dy);
    }
    if (end % 1 > 0) {
      final pt = _pointAlong(cells, end);
      p.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(p, paint);
  }

  // --- input --------------------------------------------------------------

  void _emit(Offset p) {
    if (!inputEnabled) return;
    final c = cellAt(p);
    if (c == null || c == _lastDragCell) return;
    _lastDragCell = c;
    onCell(c);
  }

  @override
  void onTapDown(TapDownEvent event) {
    _lastDragCell = null;
    _emit(event.canvasPosition.toOffset());
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _lastDragCell = null;
    _emit(event.canvasPosition.toOffset());
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    _emit(event.canvasEndPosition.toOffset());
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _lastDragCell = null;
  }
}
