import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../domain/games/path_recall_logic.dart';
import '../game/game_session.dart';
import '../providers/app_providers.dart';
import 'path_recall_board.dart';

enum _Phase { waiting, showing, input, success, failed }

class PathRecallGame extends ConsumerStatefulWidget {
  const PathRecallGame({super.key, required this.session});
  final GameSession session;

  @override
  ConsumerState<PathRecallGame> createState() => PathRecallGameState();
}

class PathRecallGameState extends ConsumerState<PathRecallGame> {
  late final PathRecallBoard board;
  PathRecallConfig _config = PathRecallLogic.configFor(1);
  List<int> _path = const [];
  final List<int> _drawn = [];
  _Phase _phase = _Phase.waiting;
  Timer? _timer;
  final Stopwatch _inputWatch = Stopwatch();

  GameSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    board = PathRecallBoard(onCell: _onCell, colors: _colors(false, false));
    _s.running.addListener(_onRunningChanged);
  }

  @override
  void dispose() {
    _s.running.removeListener(_onRunningChanged);
    _timer?.cancel();
    super.dispose();
  }

  PathBoardColors _colors(bool dark, bool colorBlind) => PathBoardColors(
        tile: dark ? const Color(0xFF2A2250) : const Color(0xFFE9E5FF),
        path: AppPalette.cyan,
        player: AppPalette.correct(colorBlind),
        wrong: AppPalette.wrong(colorBlind),
        start: AppPalette.amber,
      );

  void _onRunningChanged() {
    board.paused = !_s.isRunning;
    if (_s.isRunning) {
      _inputWatch.start();
      // An interrupted reveal restarts with a new path (no peeking while paused).
      if (_phase == _Phase.waiting || _phase == _Phase.showing) _startRound();
      if (_phase == _Phase.success || _phase == _Phase.failed) _scheduleNext(300);
    } else {
      _inputWatch.stop();
      _timer?.cancel();
      if (_phase == _Phase.showing) setState(() => _phase = _Phase.waiting);
    }
  }

  void _startRound() {
    _timer?.cancel();
    final cfg = PathRecallLogic.configFor(_s.level);
    final path = PathRecallLogic.generatePath(_s.random, cfg);
    setState(() {
      _config = cfg;
      _path = path;
      _drawn.clear();
      _phase = _Phase.showing;
    });
    board.setupRound(cfg.gridSize, path);
    board.startReveal(cfg.stepMs, () {
      if (!mounted || !_s.isRunning) return;
      board
        ..inputEnabled = true
        ..showStart = true;
      setState(() => _phase = _Phase.input);
      _inputWatch
        ..reset()
        ..start();
    });
  }

  void _scheduleNext(int ms) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: ms), () {
      if (mounted && _s.isRunning) _startRound();
    });
  }

  /// The path of the current round (for tests).
  @visibleForTesting
  List<int> get debugPath => _path;

  void _onCell(int cell) {
    if (_phase != _Phase.input || !_s.isRunning) return;
    if (_drawn.contains(cell)) return; // finger lingering on traced cells
    final expected = _path[_drawn.length];
    if (cell == expected) {
      _s.feedback.tapHaptic();
      setState(() => _drawn.add(cell));
      board.drawn = List.of(_drawn);
      if (_drawn.length == _path.length) {
        final perStep = _inputWatch.elapsedMilliseconds ~/ _path.length;
        _s.registerCorrect(
          basePoints: PathRecallLogic.basePoints(_config, _s.level),
          reactionMs: perStep,
          fast: perStep < 350,
        );
        board.inputEnabled = false;
        setState(() => _phase = _Phase.success);
        _scheduleNext(600);
      }
    } else {
      _s.registerWrong(reactionMs: _inputWatch.elapsedMilliseconds);
      board
        ..inputEnabled = false
        ..wrongCell = cell
        ..showFullPath = true;
      setState(() => _phase = _Phase.failed);
      _scheduleNext(1200);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorBlind = ref.watch(settingsProvider.select((s) => s.colorBlindMode));
    final theme = Theme.of(context);
    board.colors = _colors(theme.brightness == Brightness.dark, colorBlind);
    final status = switch (_phase) {
      _Phase.waiting => 'Get ready…',
      _Phase.showing => 'Watch the path (${_path.length} steps)',
      _Phase.input => 'Trace it from the gold ring · ${_drawn.length}/${_path.length}',
      _Phase.success => 'Perfect path!',
      _Phase.failed => 'Off track — here was the path',
    };
    return Column(
      children: [
        const SizedBox(height: 8),
        Semantics(liveRegion: true, child: Text(status, style: theme.textTheme.titleMedium, textAlign: TextAlign.center)),
        const SizedBox(height: 12),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Semantics(
                label: 'Path board ${_config.gridSize} by ${_config.gridSize}. '
                    'This game needs you to watch and trace a path on screen.',
                child: GameWidget<PathRecallBoard>(game: board),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Grid ${_config.gridSize}×${_config.gridSize}', style: theme.textTheme.bodySmall),
      ],
    );
  }
}
