import '../logic/streak_logic.dart';

/// Locally stored progression that cannot be derived from game history.
class ProgressState {
  const ProgressState({
    this.freezes = 1,
    this.frozenDays = const {},
    this.freezeAwardDays = const {},
    this.brainTestDone = false,
  });

  /// Streak freezes the player owns (new players start with one).
  final int freezes;
  final Set<DateTime> frozenDays;

  /// Days on which a milestone freeze was already awarded.
  final Set<DateTime> freezeAwardDays;
  final bool brainTestDone;

  ProgressState copyWith({
    int? freezes,
    Set<DateTime>? frozenDays,
    Set<DateTime>? freezeAwardDays,
    bool? brainTestDone,
  }) =>
      ProgressState(
        freezes: freezes ?? this.freezes,
        frozenDays: frozenDays ?? this.frozenDays,
        freezeAwardDays: freezeAwardDays ?? this.freezeAwardDays,
        brainTestDone: brainTestDone ?? this.brainTestDone,
      );

  static String _d(DateTime d) => dayOf(d).toIso8601String().substring(0, 10);
  static Set<DateTime> _parse(Object? v) =>
      v is List ? v.whereType<String>().map((s) => DateTime.parse(s)).toSet() : <DateTime>{};

  Map<String, dynamic> toMap() => {
        'freezes': freezes,
        'frozenDays': frozenDays.map(_d).toList(),
        'freezeAwardDays': freezeAwardDays.map(_d).toList(),
        'brainTestDone': brainTestDone,
      };

  factory ProgressState.fromMap(Map<dynamic, dynamic> m) => ProgressState(
        freezes: (m['freezes'] as num?)?.toInt() ?? 1,
        frozenDays: _parse(m['frozenDays']),
        freezeAwardDays: _parse(m['freezeAwardDays']),
        brainTestDone: m['brainTestDone'] as bool? ?? false,
      );
}
