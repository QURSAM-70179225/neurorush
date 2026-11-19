import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/legal.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/app_settings.dart';
import '../../../domain/entities/shop.dart';
import '../../providers/app_providers.dart';
import '../../providers/cloud_providers.dart';
import '../../providers/shop_providers.dart';
import '../../widgets/cloud_widgets.dart';
import '../../widgets/common.dart';

class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  Future<void> _spend(BuildContext context, WidgetRef ref, String item, String success) =>
      runCloudAction(context, () => ref.read(cloudRepositoryProvider).spendCoins(item), success: success);

  Future<void> _freezeAd(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final claim = await watchRewardedAd(ref, RewardType.streakFreeze);
      messenger.showSnackBar(SnackBar(
        content: Text(switch (claim) {
          null => 'Watch the whole ad to earn the reward.',
          RewardClaim(applied: true) => '🧊 Streak freeze added!',
          RewardClaim(reason: 'pending') => 'Reward is being verified — it will appear shortly.',
          RewardClaim(reason: 'max_freezes') => 'You already hold the maximum number of freezes.',
          RewardClaim(reason: 'daily_limit') => 'Daily reward limit reached. Try again tomorrow.',
          _ => 'Reward could not be applied.',
        }),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(cloudErrorText(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cloud = ref.watch(cloudRepositoryProvider);
    final uid = ref.watch(currentUidProvider);
    ref.listen(shopProvider.select((s) => s.message), (_, msg) {
      if (msg != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(msg)));
      }
    });
    if (!cloud.isAvailable || uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shop')),
        body: const Center(child: InfoState(icon: Icons.cloud_off_rounded, message: 'The shop needs an online account.')),
      );
    }
    final shop = ref.watch(shopProvider);
    final e = ref.watch(entitlementsProvider);
    final config = ref.watch(appConfigProvider);
    final now = DateTime.now();
    final freezes = ref.watch(freezesProvider);
    StoreProduct? product(String id) => shop.products[id];

    Widget buyButton(String id, {String? owned}) {
      if (owned != null) return Chip(label: Text(owned), avatar: const Icon(Icons.check_rounded, size: 18));
      final p = product(id);
      return FilledButton(
        onPressed: p == null || shop.busy ? null : () => ref.read(shopProvider.notifier).buy(id),
        child: Text(p?.price ?? 'Unavailable'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Semantics(
              label: '${e.coins} coins',
              excludeSemantics: true,
              child: Chip(avatar: const Icon(Icons.monetization_on_rounded, color: AppPalette.amber), label: Text('${e.coins}')),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (shop.busy) const LinearProgressIndicator(),
          if (!shop.available)
            const Card(
              child: ListTile(
                leading: Icon(Icons.store_mall_directory_outlined),
                title: Text('Google Play purchases are unavailable on this device right now.'),
                subtitle: Text('Coin items and rewarded ads still work.'),
              ),
            ),
          // --- Pro ---
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: AppPalette.brandGradient, borderRadius: BorderRadius.circular(28)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 32),
                  const SizedBox(width: 8),
                  Flexible(child: Text('NeuroRush Pro', style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white))),
                ]),
                const SizedBox(height: 10),
                for (final b in const [
                  'No ads, ever',
                  'Unlimited Endless Mode puzzles',
                  'All neon themes',
                  'Advanced stats: 30-day skill trends',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(b, style: const TextStyle(color: Colors.white))),
                    ]),
                  ),
                const SizedBox(height: 12),
                if (e.proActive(now)) ...[
                  Text('Active until ${DateFormat.yMMMd().format(e.proExpiresAt!)}', style: const TextStyle(color: Colors.white)),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => launchUrl(Legal.manageSubscription(ProductIds.pro), mode: LaunchMode.externalApplication),
                    child: const Text('Manage subscription'),
                  ),
                ] else
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppPalette.violet),
                    onPressed: product(ProductIds.pro) == null || shop.busy ? null : () => ref.read(shopProvider.notifier).buy(ProductIds.pro),
                    child: Text(product(ProductIds.pro) == null ? 'Unavailable' : 'Subscribe · ${product(ProductIds.pro)!.price} / month'),
                  ),
                const SizedBox(height: 4),
                const Text('Renews monthly. Cancel anytime in Google Play.', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SectionHeader('No ads'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.block_rounded),
              title: const Text('Remove ads'),
              subtitle: const Text('One-time purchase. Rewarded ads stay optional.'),
              trailing: buyButton(ProductIds.removeAds, owned: e.removeAds ? 'Owned' : (e.proActive(now) ? 'In Pro' : null)),
            ),
          ),
          const SectionHeader('Coins'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Earn coins by playing', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final line in const [
                    'Stars in every round',
                    'Your first round each day, plus a bonus every 7-day streak',
                    'Levelling up and unlocking badges',
                    'Winning battles and solving Endless puzzles',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        const Icon(Icons.monetization_on_rounded, size: 16, color: AppPalette.amber),
                        const SizedBox(width: 8),
                        Expanded(child: Text(line)),
                      ]),
                    ),
                  const SizedBox(height: 4),
                  Text('Up to ${config.coinsDailyCap} coins a day from rounds, battles and puzzles; level-ups and badges always pay.',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
          for (final (id, label) in const [
            (ProductIds.coinsSmall, 'Handful of coins'),
            (ProductIds.coinsMedium, 'Bag of coins'),
            (ProductIds.coinsLarge, 'Chest of coins'),
          ])
            Card(
              child: ListTile(
                leading: const Icon(Icons.monetization_on_rounded, color: AppPalette.amber),
                title: Text(product(id)?.title.replaceAll(RegExp(r'\s*\(.*\)$'), '') ?? label),
                trailing: buyButton(id),
              ),
            ),
          const SectionHeader('Streak freezes'),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.ac_unit_rounded, color: AppPalette.cyan),
                title: Text('You have $freezes'),
                subtitle: const Text('A freeze saves your streak when you miss a day (max 3).'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _spend(context, ref, 'streak_freeze', '🧊 Streak freeze added!'),
                      icon: const Icon(Icons.monetization_on_rounded),
                      label: Text('${config.freezePriceCoins} coins'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _freezeAd(context, ref),
                      icon: const Icon(Icons.ondemand_video_rounded),
                      label: const Text('Watch ad'),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          const SectionHeader('Neon themes'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.palette_rounded),
              title: const Text('All neon themes'),
              subtitle: const Text('Unlock all 3 forever'),
              trailing: buyButton(
                ProductIds.premiumThemes,
                owned: AppThemeMode.values.where((m) => m.premiumId != null).every((m) => e.ownsTheme(m.premiumId!, now)) ? 'Owned' : null,
              ),
            ),
          ),
          for (final m in AppThemeMode.values.where((m) => m.premiumId != null))
            Card(
              child: ListTile(
                leading: _Swatch(mode: m),
                title: Text(m.label),
                trailing: e.ownsTheme(m.premiumId!, now)
                    ? FilledButton.tonal(
                        onPressed: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(themeMode: m)),
                        child: const Text('Use'),
                      )
                    : OutlinedButton(
                        onPressed: () => _spend(context, ref, 'theme:${m.premiumId}', '${m.label} unlocked!'),
                        child: Text('${config.themePriceCoins} coins'),
                      ),
              ),
            ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: shop.busy ? null : () => ref.read(shopProvider.notifier).restore(),
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Restore purchases'),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.mode});
  final AppThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final (bg, a, b) = AppTheme.preview(mode);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircleAvatar(radius: 6, backgroundColor: a),
        const SizedBox(width: 3),
        CircleAvatar(radius: 6, backgroundColor: b),
      ]),
    );
  }
}
