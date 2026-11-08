import 'package:flutter/material.dart';

/// Thin bar that drains as the per-question timer runs out.
class QuestionTimerBar extends StatelessWidget {
  const QuestionTimerBar({super.key, required this.controller, required this.color});
  final AnimationController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final left = 1 - controller.value;
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: left,
              minHeight: 10,
              backgroundColor: color.withValues(alpha: 0.15),
              color: left < 0.3 ? Colors.redAccent : color,
            ),
          );
        },
      ),
    );
  }
}
