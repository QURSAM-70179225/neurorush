import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'domain/entities/app_settings.dart';
import 'presentation/providers/app_providers.dart';

class NeuroRushApp extends ConsumerWidget {
  const NeuroRushApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'NeuroRush',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (settings.themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      routerConfig: router,
      builder: (context, child) {
        if (!settings.largeText) return child!;
        final mq = MediaQuery.of(context);
        // Respect the system scale and add 25% on top, capped for layout safety.
        final scale = (mq.textScaler.scale(1) * 1.25).clamp(1.0, 2.0);
        return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(scale)), child: child!);
      },
    );
  }
}
