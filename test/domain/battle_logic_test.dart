import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/core/push/push_routes.dart';
import 'package:neurorush/core/push/push_service.dart';
import 'package:neurorush/domain/entities/battle.dart';
import 'package:neurorush/domain/logic/server_clock.dart';
import 'package:neurorush/domain/repositories/push_repository.dart';

void main() {
  test('server clock uses the sample with the shortest round trip', () {
    var local = DateTime.utc(2026, 1, 1, 12);
    final clock = ServerClock(now: () => local);
    // Server is 5 s ahead; 200 ms round trip.
    clock.sample(sentAt: local, receivedAt: local.add(const Duration(milliseconds: 200)), serverNowMs: local.add(const Duration(milliseconds: 5100)).millisecondsSinceEpoch);
    expect(clock.offset, const Duration(seconds: 5));
    // A slow, noisy sample is ignored.
    clock.sample(sentAt: local, receivedAt: local.add(const Duration(seconds: 3)), serverNowMs: local.millisecondsSinceEpoch);
    expect(clock.offset, const Duration(seconds: 5));
    local = local.add(const Duration(seconds: 1));
    expect(clock.now(), local.add(const Duration(seconds: 5)));
  });

  test('battle timing', () {
    final start = DateTime.utc(2026, 1, 1, 12);
    final b = Battle(
      id: 'b', mode: BattleMode.random, status: BattleStatus.active, players: const [],
      questions: List.filled(8, const BattleQuestion(type: 'math', prompt: '1 + 1', choices: ['1', '2', '3', '4'])),
      questionMs: 8000, scores: const {}, answers: const {}, startAt: start,
    );
    expect(b.questionAt(start.subtract(const Duration(seconds: 1))), -1);
    expect(b.questionAt(start), 0);
    expect(b.questionAt(start.add(const Duration(seconds: 17))), 2);
    expect(b.questionAt(start.add(const Duration(minutes: 5))), 8);
    expect(b.timeLeft(2, start.add(const Duration(seconds: 17))), const Duration(seconds: 7));
  });

  test('reminder hours in UTC for local 7 pm / 8 am', () {
    expect(utcHourFor(19, 300), 14); // Pakistan UTC+5
    expect(utcHourFor(8, 300), 3);
    expect(utcHourFor(19, 330), 13); // India UTC+5:30 → 18:30 local
    expect(utcHourFor(8, -300), 13); // New York UTC−5
    expect(utcHourFor(1, 600), 15); // wraps to previous UTC day
  });

  test('notification routing', () {
    PushEvent e(Map<String, dynamic> d) => PushEvent(data: d, opened: true);
    expect(routeForPush(e({'type': 'battle_invite', 'code': 'ABC234'})), '/battle/join/ABC234');
    expect(routeForPush(e({'type': 'friend_beat', 'gameId': 'speed_math'})), '/play/speed_math');
    expect(routeForPush(e({'type': 'friend_request'})), '/friends');
    expect(routeForPush(e({'type': 'streak_reminder'})), '/home');
    expect(routeForPush(e({'type': 'battle_invite'})), '/home');
  });
}
