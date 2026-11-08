import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/cloud_models.dart';
import '../../../domain/entities/countries.dart';
import '../../../domain/entities/skill.dart';
import '../../../domain/logic/brain_score.dart';
import '../../../domain/repositories/cloud_repository.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../providers/battle_providers.dart';
import '../../providers/cloud_providers.dart';
import '../../widgets/brain_widgets.dart';
import '../../widgets/cloud_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/text_prompt_dialog.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _username = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final name = _username.text.trim().replaceFirst('@', '');
    if (name.isEmpty || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await ref.read(cloudRepositoryProvider).sendFriendRequest(name);
      _username.clear();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(switch (r) {
              FriendRequestResult.requested => 'Friend request sent to @$name',
              FriendRequestResult.friends => 'You and @$name are now friends!',
              FriendRequestResult.alreadyFriends => 'You are already friends with @$name',
            }),
          ),
        );
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(cloudErrorText(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = ref.watch(cloudRepositoryProvider);
    if (!cloud.isAvailable) {
      return Scaffold(
        appBar: AppBar(title: const Text('Friends')),
        body: const Center(
          child: InfoState(
            icon: Icons.cloud_off_rounded,
            message: 'Friends need an online account. Connect and sign in to add friends.',
          ),
        ),
      );
    }
    final profile = ref.watch(cloudProfileProvider).value;
    final requests = ref.watch(friendRequestsProvider).value ?? const <FriendRequest>[];
    final friends = ref.watch(friendProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(friendProfilesProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.alternate_email_rounded),
                title: Text(profile?.username == null ? 'No username yet' : '@${profile!.username}'),
                subtitle: const Text('Friends add you with this username'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (profile?.username != null)
                      IconButton(
                        tooltip: 'Copy username',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: profile!.username!));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Username copied')));
                        },
                      ),
                    TextButton(
                      onPressed: () => showUsernameDialog(context, ref),
                      child: Text(profile?.username == null ? 'Choose' : 'Change'),
                    ),
                  ],
                ),
              ),
            ),
            const SectionHeader('Add a friend'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _username,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Username', prefixText: '@ '),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Add'),
                ),
              ],
            ),
            if (requests.isNotEmpty) ...[
              SectionHeader('Requests (${requests.length})'),
              for (final r in requests)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1_rounded)),
                    title: Text(r.fromDisplayName ?? '@${r.fromUsername}'),
                    subtitle: Text('@${r.fromUsername} wants to be friends'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Decline',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => runCloudAction(
                            context,
                            () => ref.read(cloudRepositoryProvider).respondFriendRequest(r.fromUid, accept: false),
                          ),
                        ),
                        IconButton.filled(
                          tooltip: 'Accept',
                          icon: const Icon(Icons.check_rounded),
                          onPressed: () => runCloudAction(
                            context,
                            () => ref.read(cloudRepositoryProvider).respondFriendRequest(r.fromUid, accept: true),
                            success: 'You and @${r.fromUsername} are now friends!',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            const SectionHeader('Your friends'),
            friends.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => InfoState(icon: Icons.wifi_off_rounded, message: cloudErrorText(e)),
              data: (list) => list.isEmpty
                  ? const InfoState(
                      icon: Icons.group_outlined,
                      message: 'No friends yet. Add someone by username above!',
                    )
                  : Column(children: [for (final f in list) _FriendTile(friend: f)]),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile({required this.friend});
  final CloudProfile friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final streak = friend.visibleStreak(now);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          onTap: () => showFriendSheet(context, ref, friend),
          leading: CircleAvatar(
            backgroundColor: AppPalette.violet,
            child: Text(
              friend.name.characters.first.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ),
          title: Text(friend.name, style: theme.textTheme.titleSmall),
          subtitle: Text(
            [
              'Lv ${friend.level}',
              'Brain ${friend.brainScore}',
              if (friend.country != null) countryFlag(friend.country!),
            ].join(' · '),
          ),
          trailing: Semantics(
            label: '$streak day streak',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_fire_department_rounded, color: streak > 0 ? AppPalette.flame : theme.disabledColor),
                Text('$streak', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showFriendSheet(BuildContext context, WidgetRef ref, CloudProfile f) {
  final now = ref.read(clockProvider)();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(f.name, style: Theme.of(c).textTheme.headlineSmall),
            if (f.username != null) Text('@${f.username}'),
            const SizedBox(height: 12),
            StatGrid(
              children: [
                StatTile(icon: Icons.trending_up_rounded, label: 'Level', value: '${f.level}'),
                StatTile(
                  icon: Icons.local_fire_department_rounded,
                  label: 'Streak',
                  value: '${f.visibleStreak(now)}',
                  color: AppPalette.flame,
                ),
                StatTile(
                  icon: Icons.psychology_rounded,
                  label: 'Brain Score',
                  value: '${f.brainScore}',
                  color: AppPalette.pink,
                ),
                StatTile(
                  icon: Icons.emoji_events_rounded,
                  label: 'Trophies',
                  value: '${f.trophies}',
                  color: AppPalette.amber,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SkillRadarChart(score: BrainScore({for (final s in Skill.values) s: f.skills[s] ?? 0}), size: 240),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.bolt_rounded),
              label: const Text('Challenge to a battle'),
              onPressed: () async {
                Navigator.pop(c);
                try {
                  final (id, code, notified) = await ref.read(battleRepositoryProvider).challengeFriend(f.uid);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(notified ? 'Challenge sent to ${f.name}!' : '${f.name} has notifications off — share code $code'),
                  ));
                  context.push('/battle/$id');
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(cloudErrorText(e))));
                }
              },
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error),
              icon: const Icon(Icons.person_remove_rounded),
              label: const Text('Remove friend'),
              onPressed: () async {
                Navigator.pop(c);
                final ok = await runCloudAction(
                  context,
                  () => ref.read(cloudRepositoryProvider).removeFriend(f.uid),
                  success: '${f.name} removed from friends',
                );
                if (ok) ref.invalidate(friendProfilesProvider);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Dialog to choose or change the unique username.
Future<void> showUsernameDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(cloudProfileProvider).value?.username ?? '';
  final name = await showTextPrompt(
    context,
    title: 'Choose a username',
    confirmLabel: 'Save',
    initial: current,
    prefixText: '@ ',
    helperText: '3–20 letters, numbers or _',
    validator: (v) => RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(v) ? null : 'Use 3–20 letters, numbers or _',
  );
  if (name == null || name.toLowerCase() == current || !context.mounted) return;
  await runCloudAction(context, () async {
    final saved = await ref.read(cloudRepositoryProvider).claimUsername(name);
    if (saved.isEmpty) throw const CloudFailure('Could not save username.');
  }, success: 'Username saved');
}
