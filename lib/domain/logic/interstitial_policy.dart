/// Frequency capping for interstitial ads: at most one every [everyNGames]
/// finished rounds and never more often than [minInterval]. Ads are only
/// offered between rounds (never during gameplay) and never to players who
/// bought Remove Ads or have Pro.
class InterstitialPolicy {
  InterstitialPolicy({required this.everyNGames, required this.minInterval});

  final int everyNGames;
  final Duration minInterval;
  int _gamesSinceAd = 0;
  DateTime? _lastShown;

  void gameFinished() => _gamesSinceAd++;

  bool shouldShow(DateTime now, {required bool adFree}) {
    if (adFree || everyNGames <= 0) return false;
    if (_gamesSinceAd < everyNGames) return false;
    final last = _lastShown;
    return last == null || now.difference(last) >= minInterval;
  }

  void shown(DateTime now) {
    _gamesSinceAd = 0;
    _lastShown = now;
  }
}
