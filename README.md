# NeuroRush

Fast, adaptive brain-training mini-games for Android (Flutter + Riverpod + Hive + Firebase).

## Status: Phase 1 complete
| Phase | Scope | State |
|---|---|---|
| 1 | Setup, auth (Google / email / guest + upgrade), navigation, 3 mini-games, local scoring | ✅ |
| 2 | Remaining 5 games, XP levels, streaks, Brain Score, radar chart | next |
| 3–7 | Sync, leaderboards, friends, AI coach, battles, ads/IAP, rules, release | planned |

## Architecture
```
lib/
  main.dart / app.dart          bootstrap (Hive, Firebase with offline fallback), MaterialApp.router
  core/                         theme, router (go_router + auth/onboarding redirects), sound & haptics
  domain/                       pure Dart, no Flutter
    entities/                   GameType, GameResult, UserProfile, AppSettings, Skill
    logic/                      AdaptiveDifficulty, ScoreTracker (combo), Rewards (stars/XP), PlayerStats
    games/                      seeded question generators: Memory Grid, Color Clash, Speed Math
    repositories/               interfaces
  data/                         Hive store + repositories, Firebase / local auth
  presentation/
    providers/                  Riverpod providers
    game/                       GameSession + GameShell (intro, 3-2-1-GO, 60 s clock, HUD, pause, save)
    games/                      the mini-game widgets
    screens/                    onboarding, auth, shell (5 tabs), home, games, results, battle, records, profile, settings
test/                           unit (domain, data) + widget (app flow, game flow) tests
```

## Run
```bash
flutter pub get
flutter test
flutter run            # Android device/emulator
```
Without `android/app/google-services.json` the app runs in **offline guest mode**. See [SETUP.md](SETUP.md) to enable accounts.
