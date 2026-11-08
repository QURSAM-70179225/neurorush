import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/cloud_models.dart';
import '../../../domain/entities/countries.dart';
import '../../../domain/entities/game_type.dart';
import '../../../domain/logic/weeks.dart';
import '../../providers/app_providers.dart';
import '../../providers/cloud_providers.dart';
import '../../widgets/cloud_widgets.dart';
import '../../widgets/common.dart';

/// Weekly boards (global, country, friends) plus personal records.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  /// null = weekly XP.
  GameType? _game;

  @override
  Widget build(BuildContext context) {
    final country = ref.watch(myCountryProvider);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Leaderboard'),
          actions: const [Padding(padding: EdgeInsets.only(right: 12), child: _ResetCountdown())],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'Global'),
              Tab(text: '${countryFlag(country)} ${countryName(country) ?? country}'),
              const Tab(text: 'Friends'),
              const Tab(text: 'Records'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _Board(scope: LeaderboardScope.global, game: _game, onGame: (g) => setState(() => _game = g)),
            _Board(scope: LeaderboardScope.country, game: _game, onGame: (g) => setState(() => _game = g)),
            _Board(scope: LeaderboardScope.friends, game: _game, onGame: (g) => setState(() => _game = g)),
            const PersonalRecords(),
          ],
        ),
      ),
    );
  }
}

class _ResetCountdown extends ConsumerStatefulWidget {
  const _ResetCountdown();

  @override
  ConsumerState<_ResetCountdown> createState() => _ResetCountdownState();
}

class _ResetCountdownState extends ConsumerState<_ResetCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final left = nextWeeklyReset(now).difference(now.toUtc());
    final text = left.inDays > 0 ? '${left.inDays}d ${left.inHours % 24}h' : '${left.inHours}h ${left.inMinutes % 60}m';
    return Semantics(
      label: 'Weekly boards reset in $text',
      excludeSemantics: true,
      child: Chip(avatar: const Icon(Icons.timer_outlined, size: 18), label: Text('Resets in $text')),
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.scope, required this.game, required this.onGame});
  final LeaderboardScope scope;
  final GameType? game;
  final ValueChanged<GameType?> onGame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cloud = ref.watch(cloudRepositoryProvider);
    final uid = ref.watch(currentUidProvider);
    if (!cloud.isAvailable || uid == null) {
      return const Center(
        child: InfoState(
          icon: Icons.cloud_off_rounded,
          message: 'Leaderboards need an online account. Your personal records are in the Records tab.',
        ),
      );
    }
    final friends = scope == LeaderboardScope.friends ? ref.watch(friendUidsProvider).value ?? const <String>[] : const <String>[];
    final query = LeaderboardQuery(
      scope: scope,
      weekId: ref.watch(currentWeekIdProvider),
      gameId: game?.id,
      country: ref.watch(myCountryProvider),
      friendUids: friends,
    );
    final page = ref.watch(leaderboardProvider(query));
    final unit = game == null ? 'XP' : 'pts';

    return RefreshIndicator(
      onRefresh: () => ref.refresh(leaderboardProvider(query).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _MetricChip(label: 'Weekly XP', selected: game == null, onTap: () => onGame(null)),
                for (final g in GameType.values)
                  _MetricChip(label: g.title, selected: game == g, onTap: () => onGame(g)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (scope == LeaderboardScope.friends && friends.isEmpty)
            InfoState(
              icon: Icons.group_add_rounded,
              message: 'Add friends to compete with them every week.',
              action: 'Find friends',
              onAction: () => context.push('/friends'),
            )
          else
            page.when(
              loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => InfoState(
                icon: Icons.wifi_off_rounded,
                message: cloudErrorText(e),
                action: 'Retry',
                onAction: () => ref.invalidate(leaderboardProvider(query)),
              ),
              data: (p) => Column(
                children: [
                  if (p.me case final me?)
                    _Row(entry: me, unit: unit, isMe: true, pinned: true)
                  else
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.sports_esports_rounded),
                        title: Text(game == null
                            ? 'Finish a round this week to get on the board.'
                            : 'Play a full ${game!.title} round this week to get on the board.'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (p.entries.isEmpty)
                    const InfoState(icon: Icons.emoji_events_outlined, message: 'No scores yet this week. Be the first!')
                  else
                    for (final e in p.entries) _Row(entry: e, unit: unit, isMe: e.uid == uid),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.unit, required this.isMe, this.pinned = false});
  final LeaderboardEntry entry;
  final String unit;
  final bool isMe;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medal = switch (entry.rank) { 1 => AppPalette.amber, 2 => const Color(0xFFB0BEC5), 3 => const Color(0xFFCD7F32), _ => null };
    final value = NumberFormat.decimalPattern().format(entry.value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        label: '${pinned ? 'Your position: ' : ''}Rank ${entry.rank}, ${entry.name}, $value $unit',
        excludeSemantics: true,
        child: Card(
          color: isMe ? AppPalette.violet.withValues(alpha: pinned ? 0.18 : 0.1) : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: medal ?? theme.colorScheme.surfaceContainerHighest,
              child: Text('${entry.rank}',
                  style: TextStyle(fontWeight: FontWeight.w900, color: medal != null ? Colors.white : null)),
            ),
            title: Text(isMe ? '${entry.name} (you)' : entry.name, style: theme.textTheme.titleSmall),
            subtitle: Text([
              if (entry.username != null) '@${entry.username}',
              'Lv ${entry.level}',
              if (entry.country != null) countryFlag(entry.country!),
            ].join(' · ')),
            trailing: Text('$value $unit', style: theme.textTheme.titleMedium),
          ),
        ),
      ),
    );
  }
}

/// Personal bests stored on this device.
class PersonalRecords extends ConsumerWidget {
  const PersonalRecords({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(playerStatsProvider);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('Your personal bests.', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        StatGrid(children: [
          StatTile(icon: Icons.sports_esports_rounded, label: 'Rounds played', value: '${stats.gamesPlayed}'),
          StatTile(
            icon: Icons.flash_on_rounded,
            label: 'Fastest reaction',
            value: formatMs(stats.bestReactionMs),
            color: AppPalette.amber,
          ),
        ]),
        const SectionHeader('Best scores'),
        for (final t in GameType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                leading: CircleAvatar(
                  backgroundColor: AppPalette.violet.withValues(alpha: 0.15),
                  child: Icon(AppPalette.gameIcon(t), color: AppPalette.violet),
                ),
                title: Text(t.title, style: theme.textTheme.titleSmall),
                subtitle: Text(switch (stats.bestResults[t]) {
                  final r? => 'Set ${DateFormat.yMMMd().format(r.playedAt)} · ${r.accuracyPercent}% accuracy',
                  null => 'Not played yet',
                }),
                trailing: stats.bestResults[t] == null
                    ? FilledButton.tonal(onPressed: () => context.push('/play/${t.id}'), child: const Text('Play'))
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${stats.bestScoreFor(t)}', style: theme.textTheme.titleMedium),
                          StarRow(stars: stats.bestResults[t]!.stars, size: 14),
                        ],
                      ),
                onTap: stats.bestResults[t] == null ? null : () => context.push('/results', extra: stats.bestResults[t]),
              ),
            ),
          ),
      ],
    );
  }
}
