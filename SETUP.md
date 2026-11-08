# Setup guide

Covers Phases 1–3: Authentication, Firestore and Cloud Functions. Later phases add Groq, AdMob, Billing and release signing.

## 1. Tools
- Flutter stable (built and tested with 3.47.9 / Dart 3.13)
- Android Studio with Android SDK 36, JDK 17+
- Firebase CLI: `npm i -g firebase-tools`, then `firebase login`

## 2. Firebase project
1. Go to https://console.firebase.google.com and click **Add project**, e.g. `neurorush-prod`.
2. Click **Add app → Android**:
   - Package name: `com.neurorush.app`
   - Debug SHA-1: `cd android && ./gradlew signingReport` (copy the SHA-1 of the `debug` variant)
3. Download `google-services.json` and put it in `android/app/`.
   The Gradle build applies the Google Services plugin automatically when that file is present.

## 3. Enable sign-in methods
Open **Authentication → Sign-in method** and enable:
- **Anonymous** (used for guest mode, so guests can later upgrade without losing progress)
- **Email/Password**
- **Google** (set a support email). After enabling it, download `google-services.json` again
  so it contains the OAuth web client that Google Sign-In needs.

Before release, also add the **release** and **Play App Signing** SHA-1/SHA-256 fingerprints
(Play Console → Setup → App integrity) to the Firebase Android app, then download the json once more.

## 4. Run
```bash
flutter pub get
flutter run
```
If Firebase can't start (missing json, or no network on first launch), the app falls back to a local
guest profile stored with Hive, and every game still works offline.

## 5. Firestore and Cloud Functions (Phase 3)

Cloud Functions need the **Blaze (pay-as-you-go)** plan. The free tier still applies, so a small game costs little or nothing.

1. In the Firebase console:
   - Open **Build → Firestore Database → Create database**.
   - Pick **Production mode** and the location `asia-south1 (Mumbai)`, closest to Pakistan.
   - The functions also run in `asia-south1`.
2. Install the tools and select your project:
   ```bash
   npm install -g firebase-tools
   firebase login
   firebase use --add          # pick your project
   ```
3. Deploy the rules, indexes and functions from the repository root:
   ```bash
   cd functions && npm ci && cd ..
   firebase deploy --only firestore:rules,firestore:indexes,functions
   ```
   Indexes take a few minutes to build. Until they finish, the country leaderboard shows an error.

What gets deployed:

| Function | Type | Purpose |
|---|---|---|
| `submitGameSession` | callable | validates a round (anti-cheat), recomputes stars/XP, updates profile, weekly leaderboard, achievements |
| `claimUsername` | callable | unique usernames (`usernames/{name}` index) |
| `sendFriendRequest` / `respondFriendRequest` / `removeFriend` | callable | friends system |
| `weeklyLeaderboardReset` | scheduled, Mon 00:05 UTC | closes last week, gives the top 3 trophies (30/20/10), deletes boards older than 12 weeks |

### Firestore schema

| Path | Written by | Fields |
|---|---|---|
| `users/{uid}` | client: `displayName, country, photoUrl, currentStreak, bestStreak, streakDay, lastActiveAt` · server: everything else | `username, xp, level, rounds, bestScores{gameId}, brainScore, skills{memory,focus,speed,logic,language}, skillRatings{skill:[…12]}, stats{threeStarRounds, perfectRounds, maxCombo, fastestReactionMs, gamesTried{}, maxDifficulty, friends}, trophies, lastSessionAt, createdAt` |
| `users/{uid}/private/{doc}` | owner | private per-user data |
| `usernames/{name}` | server | `uid, createdAt` |
| `gameSessions/{id}` | server | the round + `uid, stars, xp, accuracy, weekId, playedAt, createdAt` |
| `leaderboards/{weekId}` | server | `weekId, finalized, winners[], startsAt, endsAt` |
| `leaderboards/{weekId}/entries/{uid}` | server | `uid, username, displayName, country, level, xp, rounds, bestScores{gameId}, updatedAt` |
| `friends/{uid}/list/{friendUid}` | server | `uid, since` |
| `friends/{uid}/requests/{fromUid}` | server (owner may delete) | `fromUid, fromUsername, fromDisplayName, createdAt` |
| `achievements/{uid}` | server | `unlocked{badgeId: timestamp}` |
| `dailyWorkouts/{uid}/days/{yyyy-MM-dd}` | owner | `games[], completed[], updatedAt` |
| `purchases/{id}` | server (Phase 6) | — |
| `battles/{id}` | server (Phase 5) | — |

Indexes are in `firestore.indexes.json`. Rules are in `firestore.rules`.

### Anti-cheat
Every round is checked on the server before it counts:
- **Length:** the round is 60 s (or 24 s for the Brain Test).
- **Timing:** it was not played in the future or more than 14 days ago, and it does not overlap another round by the same player.
- **Answer count:** within the game's fastest humanly possible answer rate.
- **Score:** between the minimum and maximum possible for that many correct answers (×5 combo cap).
- **Combo:** no longer than the number of correct answers.
- **Reactions:** fastest ≥ 100 ms, average ≥ 150 ms, and the two consistent with each other.

Stars and XP are recalculated on the server, and the client's numbers are never used. A rejected round stays visible on the device, but it doesn't count towards online XP, leaderboards or badges.

## 6. Developing against local emulators (no cloud costs)
```bash
cd functions && npm ci && npm run build && cd ..
firebase emulators:start --only auth,firestore,functions --project demo-neurorush
flutter run --dart-define=USE_EMULATORS=true                      # Android emulator (host 10.0.2.2)
flutter run --dart-define=USE_EMULATORS=true --dart-define=EMULATOR_HOST=192.168.1.20   # real phone on your Wi-Fi
```

### Backend tests
```bash
cd functions
npm test                 # unit tests: validation, rewards, achievements, weeks
npm run test:rules       # security rules on the Firestore emulator (needs Java 11+)
npm run test:emulators   # end-to-end: real callables on Auth + Firestore + Functions emulators
```
