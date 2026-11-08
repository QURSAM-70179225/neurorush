import 'package:flutter/material.dart';

import '../../domain/entities/game_type.dart';
import '../game/game_shell.dart';
import 'color_clash_game.dart';
import 'memory_grid_game.dart';
import 'speed_math_game.dart';

/// Route target for /play/:gameId.
class GamePlayScreen extends StatelessWidget {
  const GamePlayScreen({super.key, required this.type});
  final GameType type;

  @override
  Widget build(BuildContext context) {
    return GameShell(
      type: type,
      builder: (context, session) => switch (type) {
        GameType.memoryGrid => MemoryGridGame(session: session),
        GameType.colorClash => ColorClashGame(session: session),
        GameType.speedMath => SpeedMathGame(session: session),
      },
    );
  }
}
