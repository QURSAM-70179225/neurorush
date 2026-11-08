import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/app_settings.dart';
import '../../../domain/games/word_scramble_logic.dart';
import '../../providers/app_providers.dart';
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
              child: SegmentedButton<AppThemeMode>(
                segments: const [
                  ButtonSegment(value: AppThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                  ButtonSegment(value: AppThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                  ButtonSegment(value: AppThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) => n.update((x) => x.copyWith(themeMode: v.first)),
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
