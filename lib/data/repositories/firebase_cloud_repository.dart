import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/ai_models.dart';
import '../../domain/entities/cloud_models.dart';
import '../../domain/entities/game_result.dart';
import '../../domain/entities/game_type.dart';
import '../../domain/entities/shop.dart';
import '../../domain/entities/skill.dart';
import '../../domain/repositories/cloud_repository.dart';

/// Region of the Cloud Functions (closest to Pakistan).
const functionsRegion = 'asia-south1';

class FirebaseCloudRepository implements CloudRepository {
  FirebaseCloudRepository(this._db, this._functions);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  @override
  bool get isAvailable => true;

  // --- helpers --------------------------------------------------------------

  static const _retryable = {'unavailable', 'deadline-exceeded', 'internal', 'unknown', 'aborted'};

  Future<Map<String, dynamic>> _call(String name, Map<String, Object?> data) async {
    try {
      // AI calls (generate + verify) can take longer than plain writes.
      final res = await _functions
          .httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
          .call<Object?>(data)
          .timeout(const Duration(seconds: 65));
      final out = res.data;
      return out is Map ? Map<String, dynamic>.from(out) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      if (_retryable.contains(e.code)) throw const CloudUnavailable();
      throw CloudFailure(e.message ?? 'Request failed (${e.code}).', code: e.code);
    } on TimeoutException {
      throw const CloudUnavailable();
    } on FirebaseException catch (e) {
      throw e.code == 'unavailable' ? const CloudUnavailable() : CloudFailure(e.message ?? e.code);
    }
  }

  Future<T> _read<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') throw const CloudUnavailable();
      throw CloudFailure(e.message ?? e.code);
    }
  }

  static int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

  static Entitlements _entitlements(Map<String, dynamic> d) {
    final e = d['entitlements'] is Map ? Map<String, dynamic>.from(d['entitlements'] as Map) : const <String, dynamic>{};
    final exp = e['proExpiresAt'];
    return Entitlements(
      removeAds: e['removeAds'] == true,
      pro: e['pro'] == true,
      proExpiresAt: exp is Timestamp ? exp.toDate() : (exp is num ? DateTime.fromMillisecondsSinceEpoch(exp.toInt()) : null),
      themes: [for (final t in (e['themes'] as List? ?? const [])) '$t'],
      coins: _int(d['coins']),
      freezes: _int(d['freezes'], 1),
    );
  }

  static CloudProfile _profile(String uid, Map<String, dynamic> d) {
    final skills = d['skills'] is Map ? Map<String, dynamic>.from(d['skills'] as Map) : const <String, dynamic>{};
    final stats = d['stats'] is Map ? Map<String, dynamic>.from(d['stats'] as Map) : const <String, dynamic>{};
    return CloudProfile(
      uid: uid,
      username: d['username'] as String?,
      displayName: d['displayName'] as String?,
      country: d['country'] as String?,
      photoUrl: d['photoUrl'] as String?,
      xp: _int(d['xp']),
      level: _int(d['level'], 1),
      rounds: _int(d['rounds']),
      brainScore: _int(d['brainScore']),
      skills: {for (final s in Skill.values) s: _int(skills[s.name])},
      currentStreak: _int(d['currentStreak']),
      bestStreak: _int(d['bestStreak']),
      streakDay: d['streakDay'] as String?,
      friends: _int(stats['friends']),
      trophies: _int(d['trophies']),
      battleWins: _int((d['battleStats'] as Map?)?['wins']),
      battleLosses: _int((d['battleStats'] as Map?)?['losses']),
      battleDraws: _int((d['battleStats'] as Map?)?['draws']),
      entitlements: _entitlements(d),
      lastActiveAt: (d['lastActiveAt'] as Timestamp?)?.toDate(),
    );
  }

  // --- sessions -------------------------------------------------------------

  @override
  Future<SubmitOutcome> submitSession(GameResult result) async {
    final r = await _call('submitGameSession', {
      'session': result.toSubmitPayload(),
      // Streaks are counted in the player's local days.
      'tzOffsetMinutes': result.playedAt.timeZoneOffset.inMinutes,
    });
    final status = SubmitStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => SubmitStatus.rejected);
    return SubmitOutcome(
      status: status,
      reason: r['reason'] as String?,
      newAchievements: [for (final a in (r['newAchievements'] as List? ?? const [])) a as String],
    );
  }

  @override
  Future<List<GameResult>> fetchRecentSessions(String uid, {int limit = 300}) => _read(() async {
        final snap = await _db
            .collection('gameSessions')
            .where('uid', isEqualTo: uid)
            .orderBy('playedAt', descending: true)
            .limit(limit)
            .get();
        return [
          for (final d in snap.docs)
            if (GameType.fromId(d.data()['gameId'] as String? ?? '') case final type?)
              GameResult(
                id: d.id,
                gameType: type,
                score: _int(d['score']),
                correct: _int(d['correct']),
                wrong: _int(d['wrong']),
                maxCombo: _int(d['maxCombo']),
                maxLevel: _int(d['maxLevel'], 1),
                avgReactionMs: (d.data()['avgReactionMs'] as num?)?.toInt(),
                bestReactionMs: (d.data()['bestReactionMs'] as num?)?.toInt(),
                stars: _int(d['stars']),
                xp: _int(d['xp']),
                playedAt: (d['playedAt'] as Timestamp).toDate(),
                durationSeconds: _int(d['durationSeconds'], 60),
                syncState: SyncState.synced,
                ownerUid: uid,
              ),
        ];
      });

  // --- profiles -------------------------------------------------------------

  @override
  Stream<CloudProfile?> watchProfile(String uid) => _db
      .doc('users/$uid')
      .snapshots()
      .map((s) => s.exists ? _profile(uid, s.data()!) : null)
      .handleError((Object _) {});

  @override
  Future<List<CloudProfile>> fetchProfiles(List<String> uids) => _read(() async {
        final out = <CloudProfile>[];
        for (var i = 0; i < uids.length; i += 30) {
          final chunk = uids.sublist(i, i + 30 > uids.length ? uids.length : i + 30);
          final snap = await _db.collection('users').where(FieldPath.documentId, whereIn: chunk).get();
          out.addAll(snap.docs.map((d) => _profile(d.id, d.data())));
        }
        return out;
      });

  @override
  Future<void> updateProfile(String uid, Map<String, Object?> fields) =>
      _read(() => _db.doc('users/$uid').set({...fields, 'lastActiveAt': FieldValue.serverTimestamp()}, SetOptions(merge: true)));

  @override
  Future<String> claimUsername(String username) async {
    final r = await _call('claimUsername', {'username': username});
    return r['username'] as String;
  }

  // --- leaderboards ---------------------------------------------------------

  LeaderboardEntry _entry(Map<String, dynamic> d, String field, int rank) {
    Object? cur = d;
    for (final part in field.split('.')) {
      cur = cur is Map ? cur[part] : null;
    }
    return LeaderboardEntry(
      uid: d['uid'] as String,
      value: cur is num ? cur.toInt() : 0,
      rank: rank,
      username: d['username'] as String?,
      displayName: d['displayName'] as String?,
      country: d['country'] as String?,
      level: _int(d['level'], 1),
    );
  }

  @override
  Future<LeaderboardPage> leaderboard(LeaderboardQuery q, String myUid) => _read(() async {
        final entries = _db.collection('leaderboards/${q.weekId}/entries');
        final field = q.field;

        if (q.scope == LeaderboardScope.friends) {
          final uids = {...q.friendUids, myUid}.toList();
          final docs = <Map<String, dynamic>>[];
          for (var i = 0; i < uids.length; i += 30) {
            final chunk = uids.sublist(i, i + 30 > uids.length ? uids.length : i + 30);
            final snap = await entries.where(FieldPath.documentId, whereIn: chunk).get();
            docs.addAll(snap.docs.map((d) => d.data()));
          }
          final ranked = docs.map((d) => _entry(d, field, 0)).where((e) => e.value > 0).toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final list = [
            for (var i = 0; i < ranked.length; i++)
              LeaderboardEntry(
                uid: ranked[i].uid,
                value: ranked[i].value,
                rank: i + 1,
                username: ranked[i].username,
                displayName: ranked[i].displayName,
                country: ranked[i].country,
                level: ranked[i].level,
              ),
          ];
          return LeaderboardPage(entries: list, me: list.where((e) => e.uid == myUid).firstOrNull);
        }

        Query<Map<String, dynamic>> base = entries;
        if (q.scope == LeaderboardScope.country) base = base.where('country', isEqualTo: q.country);
        final top = await base.orderBy(field, descending: true).limit(50).get();
        final list = [for (final (i, d) in top.docs.indexed) _entry(d.data(), field, i + 1)];

        LeaderboardEntry? me = list.where((e) => e.uid == myUid).firstOrNull;
        if (me == null) {
          final mine = await entries.doc(myUid).get();
          final data = mine.data();
          if (data != null && (q.scope != LeaderboardScope.country || data['country'] == q.country)) {
            final value = _entry(data, field, 0).value;
            if (value > 0) {
              final ahead = await base.where(field, isGreaterThan: value).count().get();
              me = _entry(data, field, (ahead.count ?? 0) + 1);
            }
          }
        }
        return LeaderboardPage(entries: list, me: me);
      });

  // --- friends --------------------------------------------------------------

  @override
  Stream<List<String>> watchFriendUids(String uid) =>
      _db.collection('friends/$uid/list').snapshots().map((s) => [for (final d in s.docs) d.id]).handleError((Object _) {});

  @override
  Stream<List<FriendRequest>> watchFriendRequests(String uid) => _db
      .collection('friends/$uid/requests')
      .snapshots()
      .map((s) => [
            for (final d in s.docs)
              FriendRequest(
                fromUid: d.id,
                fromUsername: d.data()['fromUsername'] as String? ?? 'player',
                fromDisplayName: d.data()['fromDisplayName'] as String?,
              ),
          ])
      .handleError((Object _) {});

  @override
  Future<FriendRequestResult> sendFriendRequest(String username) async {
    final r = await _call('sendFriendRequest', {'username': username});
    return switch (r['status']) {
      'friends' => FriendRequestResult.friends,
      'already_friends' => FriendRequestResult.alreadyFriends,
      _ => FriendRequestResult.requested,
    };
  }

  @override
  Future<void> respondFriendRequest(String fromUid, {required bool accept}) =>
      _call('respondFriendRequest', {'fromUid': fromUid, 'accept': accept});

  @override
  Future<void> removeFriend(String friendUid) => _call('removeFriend', {'friendUid': friendUid});

  // --- achievements & workouts ---------------------------------------------

  @override
  Stream<Map<String, DateTime>> watchUnlockedAchievements(String uid) => _db
      .doc('achievements/$uid')
      .snapshots()
      .map((s) {
        final raw = s.data()?['unlocked'];
        if (raw is! Map) return <String, DateTime>{};
        return {
          for (final e in raw.entries)
            e.key as String: e.value is Timestamp ? (e.value as Timestamp).toDate() : DateTime.now(),
        };
      })
      .handleError((Object _) {});

  @override
  Future<void> saveDailyWorkout(String uid, String day, List<String> games, List<String> completed) => _read(
        () => _db.doc('dailyWorkouts/$uid/days/$day').set({
          'games': games,
          'completed': completed,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );

  // --- AI ---------------------------------------------------------------------

  @override
  Future<CoachTip> getCoachTip(String day, int tzOffsetMinutes) async {
    final r = await _call('getBrainCoachTip', {'day': day, 'tzOffsetMinutes': tzOffsetMinutes});
    final tip = CoachTip.tryFromMap(r);
    if (tip == null) throw const CloudFailure('The coach could not answer right now.');
    return tip;
  }

  @override
  Future<EndlessPuzzle> getEndlessPuzzle({bool newRun = false}) async {
    final r = await _call('getEndlessPuzzle', {'newRun': newRun});
    return EndlessPuzzle(
      id: r['puzzleId'] as String,
      kind: r['kind'] as String? ?? 'logic',
      question: r['question'] as String,
      choices: [for (final c in r['choices'] as List) '$c'],
      difficulty: _int(r['difficulty'], 1),
      isAi: r['source'] == 'ai',
      run: _int(r['run']),
      lives: _int(r['lives'], 3),
      bestRun: _int(r['bestRun']),
      remainingToday: (r['remainingToday'] as num?)?.toInt(),
    );
  }

  @override
  Future<EndlessVerdict> submitEndlessAnswer(String puzzleId, int answerIndex) async {
    final r = await _call('submitEndlessAnswer', {'puzzleId': puzzleId, 'answerIndex': answerIndex});
    return EndlessVerdict(
      correct: r['correct'] == true,
      answerIndex: _int(r['answerIndex']),
      explanation: r['explanation'] as String? ?? '',
      run: _int(r['run']),
      lives: _int(r['lives']),
      bestRun: _int(r['bestRun']),
      gameOver: r['gameOver'] == true,
      timedOut: r['timedOut'] == true,
    );
  }

  // --- shop & account --------------------------------------------------------

  @override
  Future<Entitlements> verifyPurchase(String productId, String purchaseToken) async {
    final r = await _call('verifyPurchase', {'productId': productId, 'purchaseToken': purchaseToken});
    final exp = r['proExpiresAt'];
    return Entitlements(
      removeAds: r['removeAds'] == true,
      pro: r['pro'] == true,
      proExpiresAt: exp is num ? DateTime.fromMillisecondsSinceEpoch(exp.toInt()) : null,
      themes: [for (final t in (r['themes'] as List? ?? const [])) '$t'],
      coins: _int(r['coins']),
    );
  }

  @override
  Future<CoinSpend> spendCoins(String item) async {
    final r = await _call('spendCoins', {'item': item});
    return CoinSpend(coins: _int(r['coins']), freezes: _int(r['freezes']));
  }

  @override
  Future<RewardClaim> claimAdReward(String nonce) async {
    final r = await _call('claimAdReward', {'nonce': nonce});
    return RewardClaim(applied: r['applied'] == true, reason: r['reason'] as String?);
  }

  @override
  Future<void> deleteAccount() => _call('deleteAccount', {'confirm': 'DELETE'});
}
