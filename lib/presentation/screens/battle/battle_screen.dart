import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/battle.dart';
import '../../providers/app_providers.dart';
import '../../providers/battle_providers.dart';
import '../../providers/cloud_providers.dart';
import '../../widgets/cloud_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/text_prompt_dialog.dart';

/// Battle tab: quick match, practice vs Neo, invite codes, recent battles.
class BattleScreen extends ConsumerWidget {
  const BattleScreen({super.key});

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    try {
      final (id, _) = await ref.read(battleRepositoryProvider).createInvite();
      if (context.mounted) context.push('/battle/$id');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(cloudErrorText(e))));
    }
  }

  Future<void> _bot(BuildContext context, WidgetRef ref) async {
    try {
      final id = await ref.read(battleRepositoryProvider).startBotBattle();
      if (context.mounted) context.push('/battle/$id');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(cloudErrorText(e))));
    }
  }

  Future<void> _join(BuildContext context) async {
    final code = await showTextPrompt(
      context,
      title: 'Join a battle',
      confirmLabel: 'Join',
      label: '6-character code',
      maxLength: 6,
      capitalization: TextCapitalization.characters,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]'))],
      validator: (v) => v.length == 6 ? null : 'Codes have 6 characters',
    );
    if (code != null && context.mounted) context.push('/battle/join/${code.toUpperCase()}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final available = ref.watch(battleRepositoryProvider).isAvailable && ref.watch(currentUidProvider) != null;
    final profile = ref.watch(cloudProfileProvider).value;
    final uid = ref.watch(currentUidProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Brain Battle')),
      body: !available
          ? const Center(
              child: InfoState(icon: Icons.cloud_off_rounded, message: 'Live battles need an online account. Connect and sign in to battle.'),
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(recentBattlesProvider),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppPalette.flame, AppPalette.pink]),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 48),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Semantics(
                            label: '${profile?.trophies ?? 0} trophies. ${profile?.battleWins ?? 0} wins, ${profile?.battleLosses ?? 0} losses',
                            excludeSemantics: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${profile?.trophies ?? 0} trophies',
                                    style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
                                Text(
                                  '${profile?.battleWins ?? 0} W · ${profile?.battleLosses ?? 0} L · ${profile?.battleDraws ?? 0} D',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('8 questions · same for both players · speed counts', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => context.push('/battle/search'),
                    icon: const Icon(Icons.bolt_rounded),
                    label: const Text('Quick match'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _invite(context, ref),
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('Invite'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _join(context),
                          icon: const Icon(Icons.vpn_key_rounded),
                          label: const Text('Join code'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => _bot(context, ref),
                    icon: const Icon(Icons.smart_toy_rounded),
                    label: const Text('Practice vs Neo (bot)'),
                  ),
                  const SectionHeader('Recent battles'),
                  ref.watch(recentBattlesProvider).when(
                        loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
                        error: (e, _) => InfoState(icon: Icons.wifi_off_rounded, message: cloudErrorText(e)),
                        data: (list) => list.isEmpty
                            ? const InfoState(icon: Icons.sports_kabaddi_rounded, message: 'No battles yet. Start a quick match!')
                            : Column(children: [for (final b in list) _RecentBattle(battle: b, myUid: uid!)]),
                      ),
                ],
              ),
            ),
    );
  }
}

class _RecentBattle extends StatelessWidget {
  const _RecentBattle({required this.battle, required this.myUid});
  final Battle battle;
  final String myUid;

  @override
  Widget build(BuildContext context) {
    final s = BattleSummary(battle: battle, myUid: myUid);
    final (label, color) = s.draw ? ('Draw', AppPalette.amber) : s.won ? ('Won', AppPalette.mint) : ('Lost', AppPalette.flame);
    final delta = battle.trophyDelta[myUid] ?? 0;
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color, child: Text(label[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
        title: Text('$label vs ${s.opponentName}'),
        subtitle: Text('${s.myScore} – ${s.opponentScore}${battle.mode == BattleMode.bot ? ' · practice' : ''}'),
        trailing: Text('${delta >= 0 ? '+' : ''}$delta 🏆', style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
