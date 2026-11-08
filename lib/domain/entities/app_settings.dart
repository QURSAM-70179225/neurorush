enum AppThemeMode { system, light, dark }

class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.soundOn = true,
    this.hapticsOn = true,
    this.largeText = false,
    this.colorBlindMode = false,
    this.onboardingDone = false,
  });

  final AppThemeMode themeMode;
  final bool soundOn;
  final bool hapticsOn;
  final bool largeText;
  final bool colorBlindMode;
  final bool onboardingDone;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    bool? soundOn,
    bool? hapticsOn,
    bool? largeText,
    bool? colorBlindMode,
    bool? onboardingDone,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        soundOn: soundOn ?? this.soundOn,
        hapticsOn: hapticsOn ?? this.hapticsOn,
        largeText: largeText ?? this.largeText,
        colorBlindMode: colorBlindMode ?? this.colorBlindMode,
        onboardingDone: onboardingDone ?? this.onboardingDone,
      );

  Map<String, dynamic> toMap() => {
        'themeMode': themeMode.name,
        'soundOn': soundOn,
        'hapticsOn': hapticsOn,
        'largeText': largeText,
        'colorBlindMode': colorBlindMode,
        'onboardingDone': onboardingDone,
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
      );
}
