import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/user_profile.dart';
import '../../providers/app_providers.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final stats = ref.watch(playerStatsProvider);
    final cloud = ref.watch(authRepositoryProvider).supportsCloudAccounts;
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
                    Text(user.name, style: theme.textTheme.headlineSmall),
                    Text(user.email ?? providerLabel, style: theme.textTheme.bodyMedium),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
