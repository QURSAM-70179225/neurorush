import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// One-shot Lottie confetti (assets/lottie/confetti.json). Call
/// [ConfettiBurstState.play] to fire it. Does nothing when the system asks to
/// reduce motion.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => ConfettiBurstState();
}

class ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  bool _visible = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void play() {
    if (!mounted || MediaQuery.of(context).disableAnimations) return;
    setState(() => _visible = true);
    if (_controller.duration != null) _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Lottie.asset(
          'assets/lottie/confetti.json',
          controller: _controller,
          fit: BoxFit.cover,
          onLoaded: (c) {
            _controller.duration = c.duration;
            _controller.forward(from: 0).whenComplete(() {
              if (mounted) setState(() => _visible = false);
            });
          },
        ),
      ),
    );
  }
}
