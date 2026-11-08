import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// A notification the user tapped or that arrived in the foreground.
class PushEvent {
  const PushEvent({required this.data, this.title, this.body, required this.opened});
  final Map<String, dynamic> data;
  final String? title;
  final String? body;

  /// True when the user tapped the notification (app opened from it).
  final bool opened;

  String? get type => data['type'] as String?;
}

abstract interface class PushService {
  /// Asks for permission (Android 13+) and returns this device's push target
  /// (its Firebase Installation ID), or null when not allowed or unavailable.
  Future<String?> register();
  Stream<String> get tokenRefreshes;
  Stream<PushEvent> get events;
}

class NoopPushService implements PushService {
  const NoopPushService();
  @override
  Future<String?> register() async => null;
  @override
  Stream<String> get tokenRefreshes => const Stream.empty();
  @override
  Stream<PushEvent> get events => const Stream.empty();
}

class FirebasePushService implements PushService {
  FirebasePushService(this._fcm);
  final FirebaseMessaging _fcm;
  final _events = StreamController<PushEvent>.broadcast();
  bool _listening = false;

  void _listen() {
    if (_listening) return;
    _listening = true;
    FirebaseMessaging.onMessage.listen((m) => _events.add(_event(m, opened: false)));
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _events.add(_event(m, opened: true)));
    _fcm.getInitialMessage().then((m) {
      if (m != null) _events.add(_event(m, opened: true));
    });
  }

  static PushEvent _event(RemoteMessage m, {required bool opened}) =>
      PushEvent(data: m.data, title: m.notification?.title, body: m.notification?.body, opened: opened);

  @override
  Future<String?> register() async {
    _listen();
    try {
      final settings = await _fcm.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
      final fid = _fcm.onRegistered.first.timeout(const Duration(seconds: 20));
      await _fcm.register();
      return await fid;
    } catch (e) {
      debugPrint('Push registration failed: $e');
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes => _fcm.onRegistered;

  @override
  Stream<PushEvent> get events {
    _listen();
    return _events.stream;
  }
}
