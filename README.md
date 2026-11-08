# NeuroRush

Fast, adaptive brain-training mini-games for Android (Flutter + Riverpod + Hive + Firebase).

## Status: Phase 2 complete
| Phase | Scope | State |
|---|---|---|
| 1 | Setup, auth (Google / email / guest + upgrade), navigation, 3 mini-games, local scoring | ✅ |
| 2 | 5 more games (8 total), 50 XP levels, streaks + freezes, Brain Score, radar, Brain Test, Daily Workout, progress charts | ✅ |
| 3 | Firebase sync, leaderboards, friends, achievements | next |
| 4–7 | AI coach, battles, ads/IAP, rules, release | planned |

### Games
| Game | Skill | Notes |
|---|---|---|
| Memory Grid | Memory | grid 3×3 → 6×6 |
| Path Recall | Memory | rendered with **Flame**; drag or tap to trace |
| Color Clash | Focus | Stroop; misleading label colours from level 5 |
| Odd One Out | Focus | grid 2×2 → 7×7; different / similar / rotated icons |
| Speed Math | Speed | + − × ÷, precedence, squares, percentages |
| Shape Match | Speed | 1-back, then 2-back from level 7; colour is a distractor |
| Number Sequence | Logic | 12 pattern families; rule shown after a mistake |
| Word Scramble | Language | English (320 words) and Urdu (135 words); valid anagrams accepted |

### Progression rules
- **XP levels:** level *n → n+1* costs `100 + 40·(n−1)` XP; 50 levels, 10 titles × 5 ranks (Rookie Brain I … Neuron Master).
- **Streak:** consecutive days with ≥1 finished round. A freeze is spent automatically for a missed day; one free freeze every 7-day streak (max 2). Phase 6 adds freezes from rewarded ads.
- **Brain Score (0–1000):** 5 skills × 0–200. Each round is rated 0–1 = 55% score-per-minute vs. the 3-star target + 30% accuracy + 15% level reached; a skill is the decay-weighted (×0.8) average of its last 12 rounds.
- **Daily Workout:** 3 games for the 3 weakest skills, same for the whole day.
- **Brain Test:** 5 × 24 s rounds offered once after sign-up (and from Home until done).

## Architecture
```
lib/
  main.dart / app.dart          bootstrap (Hive, Firebase with offline fallback), MaterialApp.router
  core/                         theme, router (go_router + auth/onboarding redirects), sound & haptics
  domain/                       pure Dart, no Flutter
    entities/                   GameType, GameResult, UserProfile, AppSettings, Skill
    logic/                      AdaptiveDifficulty, ScoreTracker, Rewards, PlayerStats, XpLevels, StreakLogic, BrainScore, DailyWorkout
    games/                      seeded generators for all 8 games + word lists
    repositories/               interfaces
  data/                         Hive store + repositories, Firebase / local auth
  presentation/
    providers/                  Riverpod providers
    game/                       GameSession + GameShell (intro, 3-2-1-GO, 60 s clock, HUD, pause, save)
    games/                      8 mini-game widgets (+ Flame board for Path Recall)
    screens/                    onboarding, auth, brain test, shell (5 tabs), home, games, results, brain score, battle, records, profile, settings
test/                           unit (domain, data) + widget (app flow, game flow) tests
```

## Run
```bash
flutter pub get
flutter test
flutter run            # Android device/emulator
```
Without `android/app/google-services.json` the app runs in **offline guest mode**. See [SETUP.md](SETUP.md) to enable accounts.
