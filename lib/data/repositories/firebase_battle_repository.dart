import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/battle.dart';
import '../../domain/logic/server_clock.dart';
import '../../domain/repositories/battle_repository.dart';
import '../../domain/repositories/cloud_repository.dart';

class FirebaseBattleRepository implements BattleRepository {
  FirebaseBattleRepository(this._db, this._functions, this._clock);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final ServerClock _clock;

  @override
  bool get isAvailable => true;

  Future<Map<String, dynamic>> _call(String name, [Map<String, Object?> data = const {}]) async {
    final sent = DateTime.now();
    try {
      final res = await _functions.httpsCallable(name).call<Object?>(data).timeout(const Duration(seconds: 20));
      final out = res.data is Map ? Map<String, dynamic>.from(res.data! as Map) : <String, dynamic>{};
      final serverNow = out['serverNow'];
      if (serverNow is num) {
        _clock.sample(sentAt: sent, receivedAt: DateTime.now(), serverNowMs: serverNow.toInt());
      }
      return out;
    } on FirebaseFunctionsException catch (e) {
      if (const {'unavailable', 'deadline-exceeded', 'internal', 'unknown'}.contains(e.code)) throw const CloudUnavailable();
      throw CloudFailure(e.message ?? e.code, code: e.code);
    } on TimeoutException {
      throw const CloudUnavailable();
    }
  }

  static int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : d;

  static Battle parse(String id, Map<String, dynamic> d) {
    final info = Map<String, dynamic>.from(d['playerInfo'] as Map? ?? {});
    final players = [
      for (final uid in (d['players'] as List? ?? const []).cast<String>())
        () {
          final p = Map<String, dynamic>.from(info[uid] as Map? ?? {});
          return BattlePlayer(
            uid: uid,
            username: p['username'] as String?,
            displayName: p['displayName'] as String?,
            trophies: _i(p['trophies']),
            level: _i(p['level'], 1),
          );
        }(),
    ];
    final answers = <String, Map<int, BattleAnswer>>{};
    (d['answers'] as Map? ?? {}).forEach((uid, m) {
      answers[uid as String] = {
        for (final e in (m as Map).entries)
          int.parse('${e.key}'): BattleAnswer(
            correct: (e.value as Map)['correct'] == true,
            points: _i((e.value as Map)['points']),
            ms: _i((e.value as Map)['ms']),
          ),
      };
    });
    return Battle(
      id: id,
      mode: BattleMode.values.firstWhere((m) => m.name == d['mode'], orElse: () => BattleMode.random),
      status: BattleStatus.values.firstWhere((s) => s.name == d['status'], orElse: () => BattleStatus.waiting),
      players: players,
      questions: [for (final q in d['questions'] as List? ?? const []) BattleQuestion.fromMap(q as Map)],
      questionMs: _i(d['questionMs'], 8000),
      startAt: (d['startAt'] as Timestamp?)?.toDate(),
      endsAt: (d['endsAt'] as Timestamp?)?.toDate(),
      scores: {for (final e in (d['scores'] as Map? ?? {}).entries) e.key as String: _i(e.value)},
      answers: answers,
      inviteCode: d['inviteCode'] as String?,
      winner: d['winner'] as String?,
      trophyDelta: {for (final e in (d['trophyDelta'] as Map? ?? {}).entries) e.key as String: _i(e.value)},
      coinDelta: {for (final e in (d['coinDelta'] as Map? ?? {}).entries) e.key as String: _i(e.value)},
    );
  }

  @override
  Future<MatchResult> findMatch() async {
    final r = await _call('findMatch');
    return MatchResult(battleId: r['battleId'] as String?);
  }

  @override
  Future<void> cancelMatch() => _call('cancelMatch');

  @override
  Stream<String?> watchMatch(String uid) =>
      _db.doc('matchQueue/$uid').snapshots().map((s) => s.data()?['battleId'] as String?).handleError((Object _) {});

  @override
  Future<String> startBotBattle() async => (await _call('startBotBattle'))['battleId'] as String;

  @override
  Future<(String, String)> createInvite() async {
    final r = await _call('createInvite');
    return (r['battleId'] as String, r['code'] as String);
  }

  @override
  Future<String> joinInvite(String code) async => (await _call('joinInvite', {'code': code}))['battleId'] as String;

  @override
  Future<(String, String, bool)> challengeFriend(String friendUid) async {
    final r = await _call('challengeFriend', {'friendUid': friendUid});
    return (r['battleId'] as String, r['code'] as String, r['notified'] == true);
  }

  @override
  Stream<Battle?> watchBattle(String battleId) =>
      _db.doc('battles/$battleId').snapshots().map((s) => s.exists ? parse(s.id, s.data()!) : null);

  @override
  Future<AnswerResult> submitAnswer(String battleId, int index, int choice) async {
    final r = await _call('submitBattleAnswer', {'battleId': battleId, 'index': index, 'choice': choice});
    return AnswerResult(correct: r['correct'] == true, answerIndex: _i(r['answerIndex']), points: _i(r['points']));
  }

  @override
  Future<void> tick(String battleId) => _call('tickBattle', {'battleId': battleId});

  @override
  Future<void> finish(String battleId) => _call('finishBattle', {'battleId': battleId});

  @override
  Future<List<Battle>> recentBattles(String uid) async {
    try {
      final s = await _db
          .collection('battles')
          .where('players', arrayContains: uid)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();
      return [for (final d in s.docs) parse(d.id, d.data())].where((b) => b.status == BattleStatus.finished).toList();
    } on FirebaseException catch (e) {
      throw e.code == 'unavailable' ? const CloudUnavailable() : CloudFailure(e.message ?? e.code);
    }
  }
}
