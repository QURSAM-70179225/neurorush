/// Estimates the server's clock from timestamps returned by Cloud Functions,
/// so both players see questions change at the same moment.
class ServerClock {
  ServerClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  Duration _offset = Duration.zero;
  Duration? _bestRoundTrip;

  Duration get offset => _offset;

  DateTime now() => _now().add(_offset);

  /// Records a server timestamp received for a request sent at [sentAt].
  /// Keeps the sample with the shortest round trip (least network noise).
  void sample({required DateTime sentAt, required DateTime receivedAt, required int serverNowMs}) {
    final rtt = receivedAt.difference(sentAt);
    if (_bestRoundTrip != null && rtt > _bestRoundTrip! * 2) return;
    final mid = sentAt.add(rtt ~/ 2);
    final offset = DateTime.fromMillisecondsSinceEpoch(serverNowMs).difference(mid);
    if (_bestRoundTrip == null || rtt <= _bestRoundTrip!) {
      _bestRoundTrip = rtt;
      _offset = offset;
    }
  }
}
