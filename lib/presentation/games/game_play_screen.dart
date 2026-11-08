import 'package:flutter/material.dart';

import '../../domain/entities/game_type.dart';
import '../game/game_session.dart';
import '../game/game_shell.dart';
import 'color_clash_game.dart';
import 'memory_grid_game.dart';
import 'number_sequence_game.dart';
import 'odd_one_out_game.dart';
import 'path_recall_game.dart';
import 'shape_match_game.dart';
import 'speed_math_game.dart';
import 'word_scramble_game.dart';

/// Route target for /play/:gameId.
class GamePlayScreen extends StatelessWidget {
  const GamePlayScreen({super.key, required this.type});
  final GameType type;

  @override
  Widget build(BuildContext context) {
    return GameShell(
      type: type,
      introExtra: introExtraFor(type),
      builder: gameBuilderFor(type),
    );
  }
}

Widget? introExtraFor(GameType type) => type == GameType.wordScramble ? const WordLanguagePicker() : null;

/// Builds the mini-game widget for [type].
Widget Function(BuildContext, GameSession) gameBuilderFor(GameType type) => (context, session) => switch (type) {
      GameType.memoryGrid => MemoryGridGame(session: session),
      GameType.colorClash => ColorClashGame(session: session),
      GameType.speedMath => SpeedMathGame(session: session),
      GameType.shapeMatch => ShapeMatchGame(session: session),
      GameType.numberSequence => NumberSequenceGame(session: session),
      GameType.wordScramble => WordScrambleGame(session: session),
      GameType.oddOneOut => OddOneOutGame(session: session),
      GameType.pathRecall => PathRecallGame(session: session),
    };
