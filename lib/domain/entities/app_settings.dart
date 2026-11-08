import '../games/word_scramble_logic.dart';

enum AppThemeMode {
  system,
  light,
  dark,
  neonPulse,
  neonOcean,
  neonSunset;

  /// Premium theme id used for purchases, or null for free modes.
  String? get premiumId => switch (this) {
        AppThemeMode.neonPulse => 'neon_pulse',
        AppThemeMode.neonOcean => 'neon_ocean',
        AppThemeMode.neonSunset => 'neon_sunset',
        _ => null,
      };

  String get label => switch (this) {
        AppThemeMode.system => 'System',
        AppThemeMode.light => 'Light',
        AppThemeMode.dark => 'Dark',
        AppThemeMode.neonPulse => 'Neon Pulse',
        AppThemeMode.neonOcean => 'Neon Ocean',
        AppThemeMode.neonSunset => 'Neon Sunset',
      };
}

class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.soundOn = true,
    this.hapticsOn = true,
    this.largeText = false,
    this.colorBlindMode = false,
    this.onboardingDone = false,
    this.wordLanguage = WordLanguage.english,
    this.brainTestOffered = false,
    this.notifyStreak = true,
    this.notifyWorkout = true,
    this.notifyFriends = true,
    this.notifyBattle = true,
  });

  final AppThemeMode themeMode;
  final bool soundOn;
  final bool hapticsOn;
  final bool largeText;
  final bool colorBlindMode;
  final bool onboardingDone;

  /// Language used by Word Scramble.
  final WordLanguage wordLanguage;

  /// Whether the Brain Test was already offered after sign-up.
  final bool brainTestOffered;

  // Push notification preferences.
  final bool notifyStreak;
  final bool notifyWorkout;
  final bool notifyFriends;
  final bool notifyBattle;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    bool? soundOn,
    bool? hapticsOn,
    bool? largeText,
    bool? colorBlindMode,
    bool? onboardingDone,
    WordLanguage? wordLanguage,
    bool? brainTestOffered,
    bool? notifyStreak,
    bool? notifyWorkout,
    bool? notifyFriends,
    bool? notifyBattle,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        soundOn: soundOn ?? this.soundOn,
        hapticsOn: hapticsOn ?? this.hapticsOn,
        largeText: largeText ?? this.largeText,
        colorBlindMode: colorBlindMode ?? this.colorBlindMode,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        wordLanguage: wordLanguage ?? this.wordLanguage,
        brainTestOffered: brainTestOffered ?? this.brainTestOffered,
        notifyStreak: notifyStreak ?? this.notifyStreak,
        notifyWorkout: notifyWorkout ?? this.notifyWorkout,
        notifyFriends: notifyFriends ?? this.notifyFriends,
        notifyBattle: notifyBattle ?? this.notifyBattle,
      );

  Map<String, dynamic> toMap() => {
        'themeMode': themeMode.name,
        'soundOn': soundOn,
        'hapticsOn': hapticsOn,
        'largeText': largeText,
        'colorBlindMode': colorBlindMode,
        'onboardingDone': onboardingDone,
        'wordLanguage': wordLanguage.name,
        'brainTestOffered': brainTestOffered,
        'notifyStreak': notifyStreak,
        'notifyWorkout': notifyWorkout,
        'notifyFriends': notifyFriends,
        'notifyBattle': notifyBattle,
      };

  factory AppSettings.fromMap(Map<dynamic, dynamic> m) => AppSettings(
        themeMode: AppThemeMode.values.firstWhere(
          (t) => t.name == m['themeMode'],
          orElse: () => AppThemeMode.system,
        ),
        soundOn: m['soundOn'] as bool? ?? true,
        hapticsOn: m['hapticsOn'] as bool? ?? true,
        largeText: m['largeText'] as bool? ?? false,
        colorBlindMode: m['colorBlindMode'] as bool? ?? false,
        onboardingDone: m['onboardingDone'] as bool? ?? false,
        wordLanguage: WordLanguage.values.firstWhere(
          (l) => l.name == m['wordLanguage'],
          orElse: () => WordLanguage.english,
        ),
        brainTestOffered: m['brainTestOffered'] as bool? ?? false,
        notifyStreak: m['notifyStreak'] as bool? ?? true,
        notifyWorkout: m['notifyWorkout'] as bool? ?? true,
        notifyFriends: m['notifyFriends'] as bool? ?? true,
        notifyBattle: m['notifyBattle'] as bool? ?? true,
      );
}
