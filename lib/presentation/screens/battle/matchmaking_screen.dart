import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../providers/app_providers.dart';
import '../../providers/battle_providers.dart';
import '../../widgets/cloud_widgets.dart';

/// Finds a random opponent; offers a practice bot after a while.
class MatchmakingScreen extends ConsumerStatefulWidget {
  const MatchmakingScreen({super.key, this.botOfferAfter = const Duration(seconds: 20)});
  final Duration botOfferAfter;

  @override
  ConsumerState<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends ConsumerState<MatchmakingScreen> {
  StreamSubscription<String?>? _sub;
  Timer? _ticker;
  int _seconds = 0;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    if (!_done) ref.read(battleRepositoryProvider).cancelMatch().catchError((Object _) {});
    super.dispose();
  }

  void _go(String battleId) {
    if (_done || !mounted) return;
    _done = true;
    context.pushReplacement('/battle/$battleId');
  }

  Future<void> _search() async {
    final repo = ref.read(battleRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    setState(() {
      _error = null;
      _seconds = 0;
    });
    try {
      final r = await repo.findMatch();
      if (r.battleId != null) return _go(r.battleId!);
      _sub = repo.watchMatch(uid!).listen((id) {
        if (id != null) _go(id);
      });
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
        // Queue entries expire after a minute; rejoin to stay visible.
        if (_seconds % 45 == 0) repo.findMatch().then((r) => r.battleId != null ? _go(r.battleId!) : null, onError: (Object _) {});
      });
    } catch (e) {
      if (mounted) setState(() => _error = cloudErrorText(e));
    }
  }

  Future<void> _playBot() async {
    try {
      await ref.read(battleRepositoryProvider).cancelMatch();
      final id = await ref.read(battleRepositoryProvider).startBotBattle();
      _go(id);
    } catch (e) {
      if (mounted) setState(() => _error = cloudErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Quick match')),
      body: Center(
        child: _error != null
            ? InfoState(icon: Icons.wifi_off_rounded, message: _error!, action: 'Try again', onAction: _search)
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 96, height: 96, child: CircularProgressIndicator(strokeWidth: 6, color: AppPalette.pink)),
                    const SizedBox(height: 24),
                    Semantics(liveRegion: true, child: Text('Looking for an opponent…', style: theme.textTheme.titleLarge)),
                    const SizedBox(height: 6),
                    Text('${_seconds}s', style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 32),
                    if (_seconds >= widget.botOfferAfter.inSeconds) ...[
                      const Text('Nobody free right now?'),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _playBot,
                        icon: const Icon(Icons.smart_toy_rounded),
                        label: const Text('Practice vs Neo instead'),
                      ),
                    ],
                    TextButton(onPressed: () => context.pop(), child: const Text('Cancel')),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Deep-link target for invite codes (from the Join dialog or a push).
class JoinBattleScreen extends ConsumerStatefulWidget {
  const JoinBattleScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<JoinBattleScreen> createState() => _JoinBattleScreenState();
}

class _JoinBattleScreenState extends ConsumerState<JoinBattleScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    setState(() => _error = null);
    try {
      final id = await ref.read(battleRepositoryProvider).joinInvite(widget.code);
      if (mounted) context.pushReplacement('/battle/$id');
    } catch (e) {
      if (mounted) setState(() => _error = cloudErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Code ${widget.code}')),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : InfoState(icon: Icons.error_outline_rounded, message: _error!, action: 'Back', onAction: () => context.pop()),
        ),
      );
}
