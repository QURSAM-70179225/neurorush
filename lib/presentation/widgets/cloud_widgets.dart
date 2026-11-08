import 'package:flutter/material.dart';

import '../../domain/repositories/cloud_repository.dart';

/// Friendly message for cloud errors.
String cloudErrorText(Object e) => switch (e) {
  CloudUnavailable(:final message) => message,
  CloudFailure(:final message) => message,
  _ => 'Something went wrong. Please try again.',
};

/// Centered icon + message (+ optional action) for empty and error states.
class InfoState extends StatelessWidget {
  const InfoState({super.key, required this.icon, required this.message, this.action, this.onAction});
  final IconData icon;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.primary.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          if (action != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    );
  }
}

/// Runs [action], showing a snackbar with [success] or the error message.
Future<bool> runCloudAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (success != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(cloudErrorText(e))));
    return false;
  }
}
