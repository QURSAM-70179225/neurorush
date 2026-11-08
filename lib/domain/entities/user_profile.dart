enum AuthProviderKind { guest, google, email }

/// The signed-in player. Guests have a real (anonymous or local) id so their
/// progress can later be attached to a full account.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.provider,
    this.displayName,
    this.email,
    this.photoUrl,
  });

  final String uid;
  final AuthProviderKind provider;
  final String? displayName;
  final String? email;
  final String? photoUrl;

  bool get isGuest => provider == AuthProviderKind.guest;

  String get name {
    final n = displayName?.trim();
    if (n != null && n.isNotEmpty) return n;
    final e = email;
    if (e != null && e.contains('@')) return e.split('@').first;
    return 'Guest';
  }

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.uid == uid &&
      other.provider == provider &&
      other.displayName == displayName &&
      other.email == email &&
      other.photoUrl == photoUrl;

  @override
  int get hashCode => Object.hash(uid, provider, displayName, email, photoUrl);
}
