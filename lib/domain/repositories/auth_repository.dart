import '../entities/user_profile.dart';

/// Thrown for any user-facing authentication failure. [message] is safe to
/// show in the UI.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class AuthRepository {
  /// True when cloud accounts (Google / email) are available in this build.
  bool get supportsCloudAccounts;

  UserProfile? get currentUser;
  Stream<UserProfile?> authStateChanges();

  Future<UserProfile> continueAsGuest();
  Future<UserProfile> signInWithGoogle();
  Future<UserProfile> signInWithEmail(String email, String password);
  Future<UserProfile> registerWithEmail(String email, String password, String displayName);
  Future<void> sendPasswordReset(String email);

  /// Attaches a Google account to the current guest so progress is kept.
  Future<UserProfile> upgradeGuestWithGoogle();

  /// Attaches email/password credentials to the current guest.
  Future<UserProfile> upgradeGuestWithEmail(String email, String password, String displayName);

  Future<void> signOut();
}
