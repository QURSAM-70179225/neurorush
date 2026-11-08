import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../providers/app_providers.dart';

class _Page {
  const _Page(this.icon, this.title, this.body, this.gradient);
  final IconData icon;
  final String title;
  final String body;
  final List<Color> gradient;
}

const _pages = [
  _Page(Icons.psychology_rounded, 'Train your brain\nin 60 seconds',
      'Fast mini-games for memory, focus, speed, logic and language.',
      [AppPalette.violet, AppPalette.pink]),
  _Page(Icons.auto_graph_rounded, 'Games that adapt to you',
      'Every right answer makes it harder, every slip makes it easier — always at the edge of your ability.',
      [Color(0xFF06B6D4), Color(0xFF2563EB)]),
  _Page(Icons.local_fire_department_rounded, 'Combos, stars & XP',
      'Chain correct answers to multiply your score, earn up to 3 stars and level up every day.',
      [AppPalette.flame, AppPalette.pink]),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() => ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingDone: true));

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _done, child: const Text('Skip')),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: p.gradient),
                            boxShadow: [BoxShadow(color: p.gradient.first.withValues(alpha: 0.4), blurRadius: 40)],
                          ),
                          child: Icon(p.icon, size: 96, color: Colors.white),
                        )
                            .animate(key: ValueKey(i))
                            .scale(duration: 500.ms, curve: Curves.easeOutBack)
                            .then()
                            .shimmer(duration: 1200.ms),
                        const SizedBox(height: 40),
                        Text(p.title, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                        const SizedBox(height: 16),
                        Text(p.body, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.all(4),
                  width: i == _index ? 28 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: i == _index ? AppPalette.violet : theme.disabledColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: last
                      ? _done
                      : () => _controller.nextPage(
                          duration: const Duration(milliseconds: 350), curve: Curves.easeOut),
                  child: Text(last ? "Let's go!" : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
