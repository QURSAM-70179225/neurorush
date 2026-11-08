import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'domain/entities/app_settings.dart';
import 'presentation/providers/app_providers.dart';
import 'presentation/providers/shop_providers.dart';
import 'presentation/widgets/push_listener.dart';

class NeuroRushApp extends ConsumerWidget {
  const NeuroRushApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    final mode = settings.themeMode;
    // A premium theme is only used while the player owns it (e.g. after a refund it falls back to dark).
    final premium = mode.premiumId;
    final owned = premium == null || ref.watch(entitlementsProvider).ownsTheme(premium, DateTime.now());
    final neon = premium != null && owned;
    return MaterialApp.router(
      title: 'NeuroRush',
      debugShowCheckedModeBanner: false,
      theme: neon ? AppTheme.neon(mode) : AppTheme.light(),
      darkTheme: neon ? AppTheme.neon(mode) : AppTheme.dark(),
      themeMode: switch (mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        _ => ThemeMode.dark,
      },
      routerConfig: router,
      scaffoldMessengerKey: scaffoldMessengerKey,
      builder: (context, child) {
        final app = PushListener(child: child!);
        if (!settings.largeText) return app;
        final mq = MediaQuery.of(context);
        // Respect the system scale and add 25% on top, capped for layout safety.
        final scale = (mq.textScaler.scale(1) * 1.25).clamp(1.0, 2.0);
        return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(scale)), child: app);
      },
    );
  }
}
