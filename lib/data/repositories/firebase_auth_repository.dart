import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/auth_repository.dart';

/// Firebase Authentication: anonymous guests, Google and email/password, and
/// upgrading a guest to a full account without losing their uid.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth, {GoogleSignIn? googleSignIn})
      : _google = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _google;
  Future<void>? _googleInit;

  @override
  bool get supportsCloudAccounts => true;

  @override
  UserProfile? get currentUser => _map(_auth.currentUser);

  @override
  Stream<UserProfile?> authStateChanges() => _auth.userChanges().map(_map);

  static UserProfile? _map(User? u) {
    if (u == null) return null;
    final AuthProviderKind kind;
    if (u.isAnonymous) {
      kind = AuthProviderKind.guest;
    } else if (u.providerData.any((p) => p.providerId == GoogleAuthProvider.PROVIDER_ID)) {
      kind = AuthProviderKind.google;
    } else {
      kind = AuthProviderKind.email;
    }
    return UserProfile(
      uid: u.uid,
      provider: kind,
      displayName: u.displayName,
      email: u.email,
      photoUrl: u.photoURL,
    );
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e.code));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthFailure('Google sign-in was cancelled.');
      }
      throw AuthFailure('Google sign-in failed (${e.code.name}). Please try again.');
    }
  }

  static String _message(String code) => switch (code) {
        'invalid-email' => 'That email address looks invalid.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          'Email or password is incorrect.',
        'email-already-in-use' => 'An account already exists for that email. Try signing in.',
        'weak-password' => 'Please choose a stronger password (at least 6 characters).',
        'credential-already-in-use' =>
          'That account is already linked to another player. Sign out and sign in with it instead.',
        'provider-already-linked' => 'This account is already upgraded.',
        'network-request-failed' => 'No internet connection. Check your network and try again.',
        'too-many-requests' => 'Too many attempts. Please wait a moment and try again.',
        'operation-not-allowed' => 'This sign-in method is not enabled for NeuroRush yet.',
        _ => 'Something went wrong ($code). Please try again.',
      };

  User _requireUser(UserCredential c) {
    final u = c.user;
    if (u == null) throw const AuthFailure('Sign-in did not complete. Please try again.');
    return u;
  }

  @override
  Future<UserProfile> continueAsGuest() => _guard(() async {
        final existing = _auth.currentUser;
        if (existing != null) return _map(existing)!;
        return _map(_requireUser(await _auth.signInAnonymously()))!;
      });

  Future<AuthCredential> _googleCredential() async {
    _googleInit ??= _google.initialize();
    await _googleInit;
    final account = await _google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthFailure('Google did not return an ID token. Check the SHA-1 setup.');
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  @override
  Future<UserProfile> signInWithGoogle() => _guard(() async {
        final cred = await _googleCredential();
        return _map(_requireUser(await _auth.signInWithCredential(cred)))!;
      });

  @override
  Future<UserProfile> signInWithEmail(String email, String password) => _guard(() async {
        final c = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
        return _map(_requireUser(c))!;
      });

  @override
  Future<UserProfile> registerWithEmail(String email, String password, String displayName) =>
      _guard(() async {
        final c = await _auth.createUserWithEmailAndPassword(
            email: email.trim(), password: password);
        final u = _requireUser(c);
        await u.updateDisplayName(displayName.trim());
        await u.reload();
        return _map(_auth.currentUser ?? u)!;
      });

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  User _requireGuest() {
    final u = _auth.currentUser;
    if (u == null || !u.isAnonymous) {
      throw const AuthFailure('Only guest accounts can be upgraded.');
    }
    return u;
  }

  @override
  Future<UserProfile> upgradeGuestWithGoogle() => _guard(() async {
        final guest = _requireGuest();
        final cred = await _googleCredential();
        final linked = _requireUser(await guest.linkWithCredential(cred));
        await linked.reload();
        return _map(_auth.currentUser ?? linked)!;
      });

  @override
  Future<UserProfile> upgradeGuestWithEmail(String email, String password, String displayName) =>
      _guard(() async {
        final guest = _requireGuest();
        final cred = EmailAuthProvider.credential(email: email.trim(), password: password);
        final linked = _requireUser(await guest.linkWithCredential(cred));
        await linked.updateDisplayName(displayName.trim());
        await linked.reload();
        return _map(_auth.currentUser ?? linked)!;
      });

  @override
  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {
      // Not signed in with Google or plugin not initialised; nothing to do.
    }
    await _auth.signOut();
  }
}
