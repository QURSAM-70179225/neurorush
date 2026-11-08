import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/legal.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/app_settings.dart';
import '../../../domain/games/word_scramble_logic.dart';
import '../../providers/app_providers.dart';
import '../../providers/shop_providers.dart';
import '../../widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _resetProgress(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset progress on this device?'),
        content: const Text('This permanently deletes all saved rounds, scores, XP, streaks and Brain Score stored on this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(gameHistoryProvider.notifier).clear();
    await ref.read(progressProvider.notifier).reset();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Local progress deleted.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const SectionHeader('Appearance'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SegmentedButton<AppThemeMode>(
                    segments: const [
                      ButtonSegment(value: AppThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                      ButtonSegment(value: AppThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                      ButtonSegment(value: AppThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                    ],
                    emptySelectionAllowed: true,
                    selected: s.themeMode.premiumId == null ? {s.themeMode} : {},
                    onSelectionChanged: (v) {
                      if (v.isNotEmpty) n.update((x) => x.copyWith(themeMode: v.first));
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final m in AppThemeMode.values.where((m) => m.premiumId != null))
                        Expanded(child: _NeonThemeTile(mode: m, selected: s.themeMode == m)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SectionHeader('Word Scramble language'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<WordLanguage>(
                segments: [for (final l in WordLanguage.values) ButtonSegment(value: l, label: Text(l.label))],
                selected: {s.wordLanguage},
                onSelectionChanged: (v) => n.update((x) => x.copyWith(wordLanguage: v.first)),
              ),
            ),
          ),
          const SectionHeader('Sound & feel'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_rounded),
                  title: const Text('Sound effects'),
                  value: s.soundOn,
                  onChanged: (v) => n.update((x) => x.copyWith(soundOn: v)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.vibration_rounded),
                  title: const Text('Haptic feedback'),
                  value: s.hapticsOn,
                  onChanged: (v) => n.update((x) => x.copyWith(hapticsOn: v)),
                ),
              ],
            ),
          ),
          const SectionHeader('Notifications'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.local_fire_department_rounded),
                  title: const Text('Streak reminders'),
                  subtitle: const Text('At 7 pm if you haven’t played'),
                  value: s.notifyStreak,
                  onChanged: (v) => n.update((x) => x.copyWith(notifyStreak: v)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.fitness_center_rounded),
                  title: const Text('Daily workout ready'),
                  subtitle: const Text('At 8 am'),
                  value: s.notifyWorkout,
                  onChanged: (v) => n.update((x) => x.copyWith(notifyWorkout: v)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.group_rounded),
                  title: const Text('Friends'),
                  subtitle: const Text('Requests and “your friend beat your score”'),
                  value: s.notifyFriends,
                  onChanged: (v) => n.update((x) => x.copyWith(notifyFriends: v)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.bolt_rounded),
                  title: const Text('Battle challenges'),
                  value: s.notifyBattle,
                  onChanged: (v) => n.update((x) => x.copyWith(notifyBattle: v)),
                ),
              ],
            ),
          ),
          const SectionHeader('Accessibility'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.text_increase_rounded),
                  title: const Text('Large text'),
                  subtitle: const Text('Makes all text 25% bigger'),
                  value: s.largeText,
                  onChanged: (v) => n.update((x) => x.copyWith(largeText: v)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.palette_outlined),
                  title: const Text('Color-blind safe colors'),
                  subtitle: const Text('Uses a palette that stays distinct with color-vision deficiency'),
                  value: s.colorBlindMode,
                  onChanged: (v) => n.update((x) => x.copyWith(colorBlindMode: v)),
                ),
              ],
            ),
          ),
          const SectionHeader('Privacy'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_rounded),
                  title: const Text('Privacy policy'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/privacy'),
                ),
                FutureBuilder<bool>(
                  future: ref.read(adsServiceProvider).privacyOptionsRequired(),
                  builder: (_, snap) => snap.data == true
                      ? ListTile(
                          leading: const Icon(Icons.ads_click_rounded),
                          title: const Text('Ad privacy choices'),
                          onTap: () => ref.read(adsServiceProvider).showPrivacyOptions(),
                        )
                      : const SizedBox.shrink(),
                ),
                if (Legal.supportEmail.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.mail_outline_rounded),
                    title: const Text('Contact support'),
                    subtitle: const Text(Legal.supportEmail),
                    onTap: () => launchUrl(Uri(scheme: 'mailto', path: Legal.supportEmail, query: 'subject=NeuroRush support')),
                  ),
              ],
            ),
          ),
          const SectionHeader('Data'),
          Card(
            child: ListTile(
              leading: Icon(Icons.delete_forever_rounded, color: Theme.of(context).colorScheme.error),
              title: const Text('Reset progress on this device'),
              onTap: () => _resetProgress(context, ref),
            ),
          ),
          const SizedBox(height: 24),
          const Center(child: Text('NeuroRush 1.0.0')),
        ],
      ),
    );
  }
}

class _NeonThemeTile extends ConsumerWidget {
  const _NeonThemeTile({required this.mode, required this.selected});
  final AppThemeMode mode;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (bg, a, b) = AppTheme.preview(mode);
    final owned = ref.watch(entitlementsProvider).ownsTheme(mode.premiumId!, DateTime.now());
    return Semantics(
      button: true,
      selected: selected,
      label: '${mode.label} theme${owned ? '' : ', locked'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => owned
            ? ref.read(settingsProvider.notifier).update((s) => s.copyWith(themeMode: mode))
            : context.push('/shop'),
        child: Container(
          height: 76,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? a : Colors.transparent, width: 3),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                CircleAvatar(radius: 7, backgroundColor: a),
                const SizedBox(width: 4),
                CircleAvatar(radius: 7, backgroundColor: b),
                if (!owned) ...[const SizedBox(width: 4), const Icon(Icons.lock_rounded, size: 14, color: Colors.white70)],
              ]),
              const SizedBox(height: 6),
              Text(mode.label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
