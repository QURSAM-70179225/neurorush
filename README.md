# NeuroRush

Fast, adaptive brain-training mini-games for Android (Flutter + Riverpod + Hive + Flame + Firebase + Groq).

| | |
|---|---|
| Setup and release guide | [SETUP.md](SETUP.md) |
| Store listing, Data safety, rating | [docs/store/](docs/store/) |
| Screenshots | [docs/store/screenshots/](docs/store/screenshots/), [docs/screenshots/](docs/screenshots/) |

### Tests
| Suite | Command | Count |
|---|---|---|
| Flutter unit + widget (incl. accessibility guidelines) | `flutter test` | 151 |
| Cloud Functions unit | `cd functions && npm test` | 69 |
| Firestore security rules (emulator) | `npm run test:rules` | 21 |
| End-to-end callables on Auth/Firestore/Functions/Pub/Sub emulators | `npm run test:emulators` | 17 |
| Live AI prompts against Groq | `npm run smoke:groq` | manual |

## Status: all 7 phases complete
| Phase | Scope | State |
|---|---|---|
| 1 | Setup, auth (Google / email / guest + upgrade), navigation, 3 mini-games, local scoring | ✅ |
| 2 | 5 more games (8 total), 50 XP levels, streaks + freezes, Brain Score, radar, Brain Test, Daily Workout, progress charts | ✅ |
| 3 | Offline-first cloud sync, server-validated scores, weekly leaderboards (global / country / friends), friends, 30 achievements | ✅ |
| 4 | AI Brain Coach after the daily workout, Endless Mode with AI-generated, independently verified puzzles (Groq via Cloud Functions only) | ✅ |
| 5 | Live 1v1 battles (quick match, invite codes, friend challenges, practice bot; server-refereed), push notifications (streak, workout, friend beat your score, requests, challenges) | ✅ |
| 6 | AdMob (consent, capped interstitials, server-verified rewarded ads), Play Billing (Remove Ads, coins, themes, Pro subscription; server verification, RTDN), coin shop, neon themes, Remote Config, server-side streaks, App Check, privacy policy, account deletion | ✅ |
| 7 | Firebase Analytics + Crashlytics, Lottie confetti, automated accessibility checks, app icon, release signing + R8, release AAB (~13.4 MB per device), store listing (EN/UR), Data safety, screenshots, CI | ✅ |

### Online architecture (Phase 3)
- **Single source of truth:** the server is the only writer of competitive data (XP, scores, leaderboards, badges, friendships). The client calls Cloud Functions, and `firestore.rules` blocks direct writes.
- **Offline-first:** finished rounds are saved to Hive first (`syncState: pending`), then uploaded by `SyncNotifier`. Uploads happen after each round, at launch or resume, when connectivity returns, and from Profile → Cloud sync. On sign-in, rounds from other devices are downloaded.
- **Per-player local data:** history and progress on the device are stored per uid, so another account on the same phone starts fresh.
- **Achievements:** `shared/achievements.json` is read by both the app (unlocks offline) and Cloud Functions (grants them online).

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
functions/                      Cloud Functions (TypeScript) + jest unit / rules / emulator tests
shared/achievements.json        badge catalogue used by app and server
firestore.rules, firestore.indexes.json, firebase.json
```

## Run
```bash
flutter pub get
flutter test
flutter run            # Android device/emulator
flutter build appbundle --release   # see SETUP.md §9 for the full release command
```

Regenerate artwork with `python3 tool/make_branding.py && dart run flutter_launcher_icons` and the confetti with `python3 tool/make_confetti_lottie.py`.
Without `android/app/google-services.json` the app runs in **offline guest mode**. See [SETUP.md](SETUP.md) to enable accounts.
