import 'push_service.dart';

/// Where a notification should take the player.
String routeForPush(PushEvent e) => switch (e.type) {
      'battle_invite' when (e.data['code'] as String?)?.isNotEmpty ?? false => '/battle/join/${e.data['code']}',
      'friend_beat' when e.data['gameId'] is String => '/play/${e.data['gameId']}',
      'friend_request' => '/friends',
      _ => '/home',
    };
