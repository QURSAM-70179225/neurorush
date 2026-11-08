import 'dart:async';

import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/auth_repository.dart';

/// Offline-only authentication used when Firebase is not configured or could
/// not start. Supports guest play; cloud accounts report a clear error.
class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository(this._box) : _current = _read(_box);

  final Box<dynamic> _box;
  UserProfile? _current;
  final _controller = StreamController<UserProfile?>.broadcast();

  static const _uidKey = 'guest_uid';
  static const _unavailable = AuthFailure(
    'Online accounts are unavailable right now. You can keep playing as a guest '
    'and upgrade later — your progress is saved on this device.',
  );

  static UserProfile? _read(Box<dynamic> box) {
    final uid = box.get(_uidKey);
    return uid is String ? UserProfile(uid: uid, provider: AuthProviderKind.guest) : null;
  }

  @override
  bool get supportsCloudAccounts => false;

  @override
  UserProfile? get currentUser => _current;

  @override
  Stream<UserProfile?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  void _emit(UserProfile? u) {
    _current = u;
    _controller.add(u);
  }

  @override
  Future<UserProfile> continueAsGuest() async {
    final existing = _current;
    if (existing != null) return existing;
    final uid = 'local-${const Uuid().v4()}';
    await _box.put(_uidKey, uid);
    final user = UserProfile(uid: uid, provider: AuthProviderKind.guest);
    _emit(user);
    return user;
  }

  @override
  Future<UserProfile> signInWithGoogle() => Future.error(_unavailable);
  @override
  Future<UserProfile> signInWithEmail(String email, String password) => Future.error(_unavailable);
  @override
  Future<UserProfile> registerWithEmail(String e, String p, String n) => Future.error(_unavailable);
  @override
  Future<void> sendPasswordReset(String email) => Future.error(_unavailable);
  @override
  Future<UserProfile> upgradeGuestWithGoogle() => Future.error(_unavailable);
  @override
  Future<UserProfile> upgradeGuestWithEmail(String e, String p, String n) => Future.error(_unavailable);

  @override
  Future<void> signOut() async {
    // The local guest id is kept so signing back in as guest restores the
    // same progress on this device.
    _emit(null);
  }
}
