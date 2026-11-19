import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/battle.dart';
import '../../../domain/games/color_clash_logic.dart';
import '../../../domain/repositories/cloud_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/battle_providers.dart';
import '../../providers/telemetry_providers.dart';
import '../../widgets/cloud_widgets.dart';
import '../../widgets/confetti_burst.dart';

/// A live 1v1 battle. Questions change on the server's schedule; each answer
/// is checked and timed by the server; scores update through the battle doc.
class LiveBattleScreen extends ConsumerStatefulWidget {
  const LiveBattleScreen({super.key, required this.battleId});
  final String battleId;

  @override
  ConsumerState<LiveBattleScreen> createState() => _LiveBattleScreenState();
}

class _LiveBattleScreenState extends ConsumerState<LiveBattleScreen> {
  Timer? _ticker;
  final Map<int, AnswerResult?> _mine = {}; // null = submitting
  int _lastIndex = -2;
  bool _finishing = false;
  final _confetti = GlobalKey<ConfettiBurstState>();
  bool _celebrated = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _answer(Battle b, int index, int choice) async {
    if (_mine.containsKey(index)) return;
    setState(() => _mine[index] = null);
    ref.read(feedbackServiceProvider).tapHaptic();
    try {
      final r = await ref.read(battleRepositoryProvider).submitAnswer(b.id, index, choice);
      final fx = ref.read(feedbackServiceProvider);
      r.correct ? fx.correct() : fx.wrong();
      if (mounted) setState(() => _mine[index] = r);
    } on CloudFailure {
      // Question closed (too late) — counts as no answer.
      if (mounted) setState(() => _mine[index] = const AnswerResult(correct: false, answerIndex: -1, points: 0));
    } catch (_) {
      if (mounted) setState(() => _mine.remove(index));
    }
  }

  void _onQuestionChanged(Battle b, int index) {
    if (index == _lastIndex) return;
    _lastIndex = index;
    if (b.mode == BattleMode.bot && index >= 0) ref.read(battleRepositoryProvider).tick(b.id).catchError((Object _) {});
    if (index >= 0 && index < b.count) ref.read(feedbackServiceProvider).countdownTick();
    if (index >= b.count) _finish(b);
  }

  Future<void> _finish(Battle b) async {
    if (_finishing) return;
    _finishing = true;
    for (var attempt = 0; attempt < 5 && mounted; attempt++) {
      try {
        await ref.read(battleRepositoryProvider).finish(b.id);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
    _finishing = false;
  }

  Future<bool> _confirmLeave(Battle? b) async {
    if (b == null || b.status != BattleStatus.active) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Leave the battle?'),
        content: const Text('Unanswered questions score zero and the battle still counts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leave')),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider)!;
    final async = ref.watch(battleProvider(widget.battleId));
    final b = async.value;
    final now = ref.read(serverClockProvider).now();

    Widget body;
    if (b == null) {
      body = async.hasError
          ? Center(child: InfoState(icon: Icons.wifi_off_rounded, message: cloudErrorText(async.error!)))
          : const Center(child: CircularProgressIndicator());
    } else if (b.status == BattleStatus.waiting) {
      body = _WaitingForFriend(code: b.inviteCode ?? '');
    } else if (b.status == BattleStatus.expired) {
      body = const Center(child: InfoState(icon: Icons.timer_off_rounded, message: 'This invite expired.'));
    } else if (b.status == BattleStatus.finished) {
      final s = BattleSummary(battle: b, myUid: uid);
      if (!_celebrated) {
        _celebrated = true;
        ref.read(analyticsProvider).battleEnd(mode: b.mode.name, outcome: s.draw ? 'draw' : (s.won ? 'win' : 'loss'));
        if (s.won) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _confetti.currentState?.play());
          ref.read(feedbackServiceProvider).finish();
        }
      }
      body = _Result(summary: s);
    } else {
      final index = b.questionAt(now);
      WidgetsBinding.instance.addPostFrameCallback((_) => _onQuestionChanged(b, index));
      body = Column(
        children: [
          _ScoreBar(battle: b, myUid: uid, mine: _mine, current: index),
          Expanded(
            child: index < 0
                ? _Countdown(battle: b, myUid: uid, seconds: b.startAt!.difference(now).inMilliseconds / 1000)
                : index >= b.count
                    ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Counting the points…'),
                      ]))
                    : _QuestionView(
                        key: ValueKey(index),
                        battle: b,
                        index: index,
                        timeLeft: b.timeLeft(index, now),
                        result: _mine[index],
                        submitted: _mine.containsKey(index),
                        onAnswer: (c) => _answer(b, index, c),
                      ),
          ),
        ],
      );
    }

    return PopScope(
      canPop: b == null || b.status != BattleStatus.active,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave(b) && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(b?.mode == BattleMode.bot ? 'Practice battle' : 'Brain Battle')),
        body: Stack(
          children: [
            SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: body)),
            Positioned.fill(child: ConfettiBurst(key: _confetti)),
          ],
        ),
      ),
    );
  }
}

class _WaitingForFriend extends StatelessWidget {
  const _WaitingForFriend({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Share this code with a friend', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          Semantics(
            label: 'Battle code ${code.split('').join(' ')}',
            excludeSemantics: true,
            child: Text(code, style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 8)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy code'),
          ),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          const Text('Waiting for your friend to join… (code valid for 30 minutes)'),
        ],
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.battle, required this.myUid, required this.mine, required this.current});
  final Battle battle;
  final String myUid;
  final Map<int, AnswerResult?> mine;
  final int current;

  @override
  Widget build(BuildContext context) {
    final opp = battle.opponentOf(myUid);
    final oppAnswers = battle.answers[opp?.uid] ?? const {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _PlayerScore(name: 'You', score: battle.scores[myUid] ?? 0, color: AppPalette.violet)),
                const Text('VS', style: TextStyle(fontWeight: FontWeight.w900)),
                Expanded(
                  child: _PlayerScore(name: opp?.name ?? '…', score: battle.scores[opp?.uid] ?? 0, color: AppPalette.pink, alignEnd: true),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < battle.count; i++)
                  Expanded(
                    child: Column(
                      children: [
                        _Dot(color: switch (mine[i]) {
                          final r? => r.correct ? AppPalette.mint : AppPalette.flame,
                          null => i == current ? AppPalette.violet.withValues(alpha: 0.5) : Theme.of(context).disabledColor.withValues(alpha: 0.3),
                        }),
                        const SizedBox(height: 3),
                        _Dot(color: oppAnswers.containsKey(i) ? AppPalette.pink : Theme.of(context).disabledColor.withValues(alpha: 0.3), small: true),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerScore extends StatelessWidget {
  const _PlayerScore({required this.name, required this.score, required this.color, this.alignEnd = false});
  final String name;
  final int score;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$name $score points',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(name, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
            Text('$score', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: color))
                .animate(key: ValueKey(score))
                .scale(begin: const Offset(1.2, 1.2), duration: 200.ms),
          ],
        ),
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.small = false});
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
        width: small ? 8 : 12,
        height: small ? 8 : 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.battle, required this.myUid, required this.seconds});
  final Battle battle;
  final String myUid;
  final double seconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opp = battle.opponentOf(myUid);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('You vs ${opp?.name ?? '…'}', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          if (opp != null) Text('Level ${opp.level} · ${opp.trophies} trophies', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          Semantics(
            liveRegion: true,
            child: Text('${seconds.ceil().clamp(0, 99)}', style: theme.textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w900)),
          ),
          const Text('Get ready!'),
        ],
      ),
    );
  }
}

class _QuestionView extends ConsumerWidget {
  const _QuestionView({
    super.key,
    required this.battle,
    required this.index,
    required this.timeLeft,
    required this.result,
    required this.submitted,
    required this.onAnswer,
  });

  final Battle battle;
  final int index;
  final Duration timeLeft;
  final AnswerResult? result;
  final bool submitted;
  final ValueChanged<int> onAnswer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final q = battle.questions[index];
    final colorBlind = ref.watch(settingsProvider.select((s) => s.colorBlindMode));
    final palette = colorBlind ? ColorClashPalettes.colorBlindSafe : ColorClashPalettes.standard;
    final fraction = timeLeft.inMilliseconds / battle.questionMs;

    String label(String c) => q.type == 'stroop' ? palette[int.parse(c)].name : c;

    final Widget prompt = switch (q.type) {
      'stroop' => Semantics(
          label: 'The word ${palette[q.word!].name} in ${palette[q.ink!].name} ink. Tap the ink colour.',
          excludeSemantics: true,
          child: Column(children: [
            const Text('Tap the INK colour'),
            Text(palette[q.word!].name,
                style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Color(palette[q.ink!].argb))),
          ]),
        ),
      'sequence' => Column(children: [
          const Text('What comes next?'),
          Text(q.prompt!, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
        ]),
      _ => Column(children: [
          const Text('Solve'),
          Text('${q.prompt} = ?', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900)),
        ]),
    };

    return Column(
      children: [
        const SizedBox(height: 8),
        Text('Question ${index + 1} of ${battle.count}', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        ExcludeSemantics(
          child: LinearProgressIndicator(
            value: fraction.clamp(0, 1),
            minHeight: 8,
            borderRadius: BorderRadius.circular(6),
            color: fraction < 0.3 ? Colors.redAccent : AppPalette.violet,
          ),
        ),
        Expanded(child: Center(child: FittedBox(child: prompt).animate().fadeIn(duration: 150.ms).scale(begin: const Offset(0.9, 0.9)))),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: [
            for (var i = 0; i < q.choices.length; i++)
              _ChoiceButton(
                text: label(q.choices[i]),
                color: result == null
                    ? null
                    : i == result!.answerIndex
                        ? AppPalette.correct(colorBlind)
                        : null,
                onTap: submitted ? null : () => onAnswer(i),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 24,
          child: result == null
              ? (submitted ? const Text('Checking…') : null)
              : Semantics(
                  liveRegion: true,
                  child: Text(
                    result!.answerIndex < 0 ? 'Too late!' : (result!.correct ? '+${result!.points} points!' : 'Not this time'),
                    style: theme.textTheme.titleMedium?.copyWith(color: result!.correct ? AppPalette.mint : AppPalette.flame),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({required this.text, required this.onTap, this.color});
  final String text;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Material(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Center(
            child: Text(text,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color != null ? Colors.white : null)),
          ),
        ),
      );
}

class _Result extends ConsumerWidget {
  const _Result({required this.summary});
  final BattleSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = summary;
    final delta = s.battle.trophyDelta[s.myUid] ?? 0;
    final (title, color) = s.draw ? ('It’s a draw!', AppPalette.amber) : s.won ? ('You won!', AppPalette.mint) : ('You lost', AppPalette.flame);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.won ? Icons.emoji_events_rounded : Icons.sports_kabaddi_rounded, size: 80, color: color),
          Semantics(liveRegion: true, child: Text(title, style: theme.textTheme.headlineMedium?.copyWith(color: color))),
          const SizedBox(height: 8),
          Text('${s.myScore} – ${s.opponentScore} vs ${s.opponentName}', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('${delta >= 0 ? '+' : ''}$delta trophies', style: theme.textTheme.titleLarge),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () async {
              if (s.battle.mode == BattleMode.bot) {
                try {
                  final id = await ref.read(battleRepositoryProvider).startBotBattle();
                  if (context.mounted) context.pushReplacement('/battle/$id');
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(cloudErrorText(e))));
                }
              } else {
                context.pushReplacement('/battle/search');
              }
            },
            icon: const Icon(Icons.replay_rounded),
            label: Text(s.battle.mode == BattleMode.bot ? 'Practice again' : 'Find another match'),
          ),
          TextButton(onPressed: () => context.pop(), child: const Text('Back to Battle')),
        ],
      ),
    );
  }
}
