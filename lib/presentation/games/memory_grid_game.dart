import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../domain/games/memory_grid_logic.dart';
import '../game/game_session.dart';
import '../providers/app_providers.dart';

enum _RoundPhase { waiting, showing, input, success, failed }

class MemoryGridGame extends ConsumerStatefulWidget {
  const MemoryGridGame({super.key, required this.session});
  final GameSession session;

  @override
  ConsumerState<MemoryGridGame> createState() => _MemoryGridGameState();
}

class _MemoryGridGameState extends ConsumerState<MemoryGridGame> {
  MemoryGridConfig _config = MemoryGridLogic.configFor(1);
  Set<int> _pattern = {};
  final Set<int> _found = {};
  int? _wrongCell;
  _RoundPhase _phase = _RoundPhase.waiting;
  Timer? _timer;
  final Stopwatch _inputWatch = Stopwatch();

  GameSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _s.running.addListener(_onRunningChanged);
  }

  @override
  void dispose() {
    _s.running.removeListener(_onRunningChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _onRunningChanged() {
    if (_s.isRunning) {
      _inputWatch.start();
      // A pattern interrupted by a pause is replaced by a fresh one, so
      // pausing can't be used to study the board.
      if (_phase == _RoundPhase.waiting || _phase == _RoundPhase.showing) _startRound();
      if (_phase == _RoundPhase.success || _phase == _RoundPhase.failed) _scheduleNext(300);
    } else {
      _inputWatch.stop();
      _timer?.cancel();
      if (_phase == _RoundPhase.showing) setState(() => _phase = _RoundPhase.waiting);
    }
  }

  void _startRound() {
    _timer?.cancel();
    final config = MemoryGridLogic.configFor(_s.level);
    setState(() {
      _config = config;
      _pattern = MemoryGridLogic.generatePattern(_s.random, config);
      _found.clear();
      _wrongCell = null;
      _phase = _RoundPhase.showing;
    });
    _timer = Timer(Duration(milliseconds: config.showMs), () {
      if (!mounted || !_s.isRunning) return;
      setState(() => _phase = _RoundPhase.input);
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

  void _onTap(int index) {
    if (_phase != _RoundPhase.input || !_s.isRunning || _found.contains(index)) return;
    if (_pattern.contains(index)) {
      _s.feedback.tapHaptic();
      setState(() => _found.add(index));
      if (_found.length == _pattern.length) {
        final perTile = _inputWatch.elapsedMilliseconds ~/ _pattern.length;
        _s.registerCorrect(
          basePoints: MemoryGridLogic.basePoints(_config, _s.level),
          reactionMs: perTile,
          fast: perTile < 450,
        );
        setState(() => _phase = _RoundPhase.success);
        _scheduleNext(550);
      }
    } else {
      _s.registerWrong(reactionMs: _inputWatch.elapsedMilliseconds);
      setState(() {
        _wrongCell = index;
        _phase = _RoundPhase.failed;
      });
      _scheduleNext(1000);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorBlind = ref.watch(settingsProvider.select((s) => s.colorBlindMode));
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final status = switch (_phase) {
      _RoundPhase.waiting => 'Get ready…',
      _RoundPhase.showing => 'Memorise ${_pattern.length} tiles',
      _RoundPhase.input => 'Tap the tiles · ${_found.length}/${_pattern.length}',
      _RoundPhase.success => 'Perfect!',
      _RoundPhase.failed => 'Missed — here they were',
    };

    return Column(
      children: [
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(status, style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(builder: (context, c) {
                final n = _config.gridSize;
                const gap = 8.0;
                final cell = (c.maxWidth - gap * (n - 1)) / n;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: List.generate(_config.cellCount, (i) {
                    final inPattern = _pattern.contains(i);
                    final Color color;
                    if (_phase == _RoundPhase.showing && inPattern) {
                      color = AppPalette.cyan;
                    } else if (_found.contains(i)) {
                      color = AppPalette.correct(colorBlind);
                    } else if (i == _wrongCell) {
                      color = AppPalette.wrong(colorBlind);
                    } else if (_phase == _RoundPhase.failed && inPattern) {
                      color = AppPalette.cyan.withValues(alpha: 0.55);
                    } else {
                      color = dark ? const Color(0xFF2A2250) : Colors.white;
                    }
                    final lit = _phase == _RoundPhase.showing && inPattern;
                    final row = i ~/ n + 1, col = i % n + 1;
                    return Semantics(
                      button: true,
                      label: 'Tile row $row column $col${lit ? ', lit' : ''}'
                          '${_found.contains(i) ? ', found' : ''}',
                      child: GestureDetector(
                        onTapDown: (_) => _onTap(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          width: cell,
                          height: cell,
                          transform: Matrix4.diagonal3Values(lit ? 1.04 : 1, lit ? 1.04 : 1, 1),
                          transformAlignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(cell * 0.18),
                            boxShadow: [
                              if (lit)
                                BoxShadow(color: AppPalette.cyan.withValues(alpha: 0.6), blurRadius: 16),
                              if (!lit)
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: dark ? 0.3 : 0.06),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Grid ${_config.gridSize}×${_config.gridSize}', style: theme.textTheme.bodySmall),
      ],
    );
  }
}
