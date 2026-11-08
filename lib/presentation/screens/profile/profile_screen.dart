import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/user_profile.dart';
import '../../providers/app_providers.dart';
import '../../../domain/entities/countries.dart';
import '../../providers/cloud_providers.dart';
import '../../widgets/brain_widgets.dart';
import '../../widgets/cloud_widgets.dart';
import '../../widgets/text_prompt_dialog.dart';
import '../../providers/shop_providers.dart';
import '../../widgets/common.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref, UserProfile user) async {
    final repo = ref.read(authRepositoryProvider);
    final guestCloud = user.isGuest && repo.supportsCloudAccounts;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(guestCloud
            ? 'You are playing as a guest. If you sign out without saving your progress to an '
                'account, you will not be able to sign back in to this guest profile.'
            : 'You can sign back in at any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await repo.signOut();
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref, UserProfile user) async {
    final confirm = await showTextPrompt(
      context,
      title: 'Delete your account?',
      confirmLabel: 'Delete forever',
      label: 'Type DELETE to confirm',
      helperText: 'This permanently removes your profile, scores, streaks, friends and coins. It cannot be undone.',
      validator: (v) => v == 'DELETE' ? null : 'Type DELETE in capitals',
    );
    if (confirm != 'DELETE' || !context.mounted) return;
    final cloud = ref.read(cloudRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (cloud.isAvailable) await cloud.deleteAccount();
      await ref.read(gameHistoryProvider.notifier).clear();
      await ref.read(progressProvider.notifier).reset();
      await ref.read(authRepositoryProvider).signOut();
      messenger.showSnackBar(const SnackBar(content: Text('Your account and data were deleted.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(cloudErrorText(e))));
    }
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    final profile = ref.read(cloudProfileProvider).value;
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditProfileSheet(
        initialName: profile?.displayName ?? ref.read(currentUserProvider)?.displayName ?? '',
        initialCountry: ref.read(myCountryProvider),
      ),
    );
    if (result == null || !context.mounted) return;
    final (displayName, country) = result;
    await runCloudAction(
      context,
      () => ref.read(cloudRepositoryProvider).updateProfile(uid, {
        'displayName': displayName.isEmpty ? null : displayName,
        'country': country,
      }),
      success: 'Profile updated',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final stats = ref.watch(playerStatsProvider);
    final cloud = ref.watch(authRepositoryProvider).supportsCloudAccounts;
    final level = ref.watch(levelProvider);
    final streak = ref.watch(streakProvider);
    final brain = ref.watch(brainScoreProvider);
    final cloudProfile = ref.watch(cloudProfileProvider).value;
    final badges = ref.watch(unlockedAchievementsProvider).length;
    final badgeTotal = ref.watch(achievementCatalogProvider).length;
    final requests = ref.watch(friendRequestsProvider).value?.length ?? 0;
    final theme = Theme.of(context);
    if (user == null) return const Scaffold(body: SizedBox.shrink());

    final providerLabel = switch (user.provider) {
      AuthProviderKind.guest => 'Guest',
      AuthProviderKind.google => 'Google account',
      AuthProviderKind.email => 'Email account',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: AppPalette.violet,
                foregroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                child: Text(user.name.characters.first.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cloudProfile?.name ?? user.name, style: theme.textTheme.headlineSmall),
                    Text(
                      [
                        if (cloudProfile?.username != null) '@${cloudProfile!.username}' else user.email ?? providerLabel,
                        if (cloudProfile?.country != null) countryFlag(cloudProfile!.country!),
                      ].join('  '),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (user.isGuest && cloud) ...[
            const SizedBox(height: 16),
            Card(
              color: AppPalette.amber.withValues(alpha: 0.18),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.shield_rounded, color: AppPalette.flame),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Save your progress with a free account.')),
                    FilledButton(onPressed: () => context.push('/upgrade'), child: const Text('Save')),
                  ],
                ),
              ),
            ),
          ],
          if (cloud) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _editProfile(context, ref),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Edit name & country'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: LevelBar(info: level))),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.emoji_events_rounded, color: AppPalette.amber),
                  title: const Text('Achievements'),
                  subtitle: Text('$badges of $badgeTotal unlocked'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/achievements'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Badge(
                    isLabelVisible: requests > 0,
                    label: Text('$requests'),
                    child: const Icon(Icons.group_rounded, color: AppPalette.cyan),
                  ),
                  title: const Text('Friends'),
                  subtitle: Text(cloud ? '${cloudProfile?.friends ?? 0} friends' : 'Needs an online account'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/friends'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.storefront_rounded, color: AppPalette.pink),
                  title: const Text('Shop'),
                  subtitle: Text(cloud ? '${ref.watch(entitlementsProvider).coins} coins · Pro, themes, freezes' : 'Needs an online account'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/shop'),
                ),
                const Divider(height: 1),
                const _SyncTile(),
              ],
            ),
          ),
          const SizedBox(height: 10),
          StatGrid(children: [
            StatTile(
              icon: Icons.local_fire_department_rounded,
              label: 'Day streak · best ${streak.best}',
              value: '${streak.current}',
              color: AppPalette.flame,
            ),
            StatTile(icon: Icons.ac_unit_rounded, label: 'Streak freezes', value: '${ref.watch(freezesProvider)}', color: AppPalette.cyan),
          ]),
          SectionHeader('Brain Score: ${brain.total}',
              trailing: TextButton(onPressed: () => context.push('/brain'), child: const Text('Details'))),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => context.push('/brain'),
              child: Padding(padding: const EdgeInsets.all(12), child: SkillRadarChart(score: brain, size: 240)),
            ),
          ),
          const SectionHeader('Your stats'),
          StatGrid(
                  children: [
              StatTile(icon: Icons.bolt_rounded, label: 'Total XP', value: '${stats.totalXp}'),
              StatTile(icon: Icons.sports_esports_rounded, label: 'Rounds', value: '${stats.gamesPlayed}', color: AppPalette.cyan),
              StatTile(icon: Icons.star_rounded, label: 'Stars', value: '${stats.totalStars}', color: AppPalette.amber),
              StatTile(
                  icon: Icons.track_changes_rounded,
                  label: 'Accuracy',
                  value: stats.gamesPlayed == 0 ? '—' : '${(stats.averageAccuracy * 100).round()}%',
                  color: AppPalette.mint),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.settings_rounded),
                  title: const Text('Settings & accessibility'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/settings'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Sign out'),
                  onTap: () => _signOut(context, ref, user),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.delete_forever_rounded, color: theme.colorScheme.error),
                  title: Text('Delete account', style: TextStyle(color: theme.colorScheme.error)),
                  onTap: () => _deleteAccount(context, ref, user),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncTile extends ConsumerWidget {
  const _SyncTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncProvider);
    final pending = ref.watch(pendingSyncCountProvider);
    final (icon, text) = switch (status.phase) {
      SyncPhase.unavailable => (Icons.phone_android_rounded, 'Progress is saved on this device'),
      SyncPhase.syncing => (Icons.sync_rounded, 'Syncing…'),
      SyncPhase.offline => (Icons.cloud_off_rounded, pending > 0 ? '$pending rounds will sync when you are online' : 'Offline'),
      SyncPhase.error => (Icons.error_outline_rounded, status.message ?? 'Sync failed'),
      SyncPhase.idle => pending > 0
          ? (Icons.cloud_upload_rounded, '$pending rounds waiting to sync')
          : (Icons.cloud_done_rounded, 'All progress backed up'),
    };
    return ListTile(
      leading: Icon(icon),
      title: const Text('Cloud sync'),
      subtitle: Text(text),
      trailing: status.phase == SyncPhase.unavailable
          ? null
          : IconButton(
              tooltip: 'Sync now',
              onPressed: status.phase == SyncPhase.syncing ? null : () => ref.read(syncProvider.notifier).sync(),
              icon: const Icon(Icons.refresh_rounded),
            ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.initialName, required this.initialCountry});
  final String initialName;
  final String initialCountry;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final _name = TextEditingController(text: widget.initialName);
  late String _country = widget.initialCountry;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit profile', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: _name, maxLength: 30, decoration: const InputDecoration(labelText: 'Display name')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _country,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Country (for the country leaderboard)'),
              items: [
                for (final (code, label) in countries)
                  DropdownMenuItem(value: code, child: Text('${countryFlag(code)}  $label', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _country = v ?? _country),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(context, (_name.text.trim(), _country)), child: const Text('Save')),
          ],
        ),
      );
}
