import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/push/push_routes.dart';
import '../../core/push/push_service.dart';
import '../../core/router/app_router.dart';
import '../providers/battle_providers.dart';

/// App-wide key so notifications can show banners from anywhere.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Opens the right screen when a notification is tapped, and shows a banner
/// with an "Open" action for notifications that arrive while the app is open.
class PushListener extends ConsumerStatefulWidget {
  const PushListener({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PushListener> createState() => _PushListenerState();
}

class _PushListenerState extends ConsumerState<PushListener> {
  StreamSubscription<PushEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(pushServiceProvider).events.listen(_handle);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _handle(PushEvent e) {
    final route = routeForPush(e);
    final router = ref.read(routerProvider);
    if (e.opened) {
      router.push(route);
      return;
    }
    scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
      content: Text([e.title, e.body].whereType<String>().join(' — ')),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'Open', onPressed: () => router.push(route)),
    ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
