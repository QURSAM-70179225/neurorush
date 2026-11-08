import '../games/word_scramble_logic.dart';

enum AppThemeMode { system, light, dark }

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

  AppSettings copyWith({
    AppThemeMode? themeMode,
    bool? soundOn,
    bool? hapticsOn,
    bool? largeText,
    bool? colorBlindMode,
    bool? onboardingDone,
    WordLanguage? wordLanguage,
    bool? brainTestOffered,
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
      );
}
