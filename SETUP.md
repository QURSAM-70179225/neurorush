# Setup guide

Covers Phases 1–6: Authentication, Firestore, Cloud Functions, Groq AI, battles, push notifications, AdMob, Google Play Billing, Remote Config, App Check, privacy and account deletion. Phase 7 adds release signing and the store listing.

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

## 5b. Groq AI (Phase 4)

The Groq key lives **only** in Cloud Functions, stored as a Secret Manager secret. It never ships in the app.

1. Create a key at https://console.groq.com/keys.
2. Store it as a secret, then check it against the real API:
   ```bash
   firebase functions:secrets:set GROQ_API_KEY     # paste the key when asked
   cd functions && GROQ_API_KEY=gsk_... npm run smoke:groq
   ```
   (`functions:secrets:set` replaces the old `functions:config:set`, which is deprecated.)
3. Optional: choose the model with a parameter. The default is `llama-3.3-70b-versatile`. Put it in `functions/.env.<your-project-id>`:
   ```
   GROQ_MODEL=llama-3.1-8b-instant
   ```
4. Deploy: `firebase deploy --only functions`.

| Function | Purpose |
|---|---|
| `getBrainCoachTip` | After the Daily Workout, reads that day's accepted rounds and the player's skills. It asks Groq for one tip and one brain fact (numbers only, no user text in the prompt) and caches the result in `coachTips/{uid}_{day}`. If Groq fails it returns a written tip; after 3 failed tries it stops calling Groq for that day. |
| `getEndlessPuzzle` | Asks Groq to write a puzzle (sequence, riddle or logic) at a difficulty set by the current run. A second Groq call has to solve it independently and confidently, and sequences must also pass a rule check, or the puzzle is thrown away. Puzzles are stored in `endlessPuzzles` with the answer; clients cannot read that collection. Free players get 10 a day and `users.entitlements.pro` is unlimited. If Groq is down, an algorithmic number-sequence puzzle is served. |
| `submitEndlessAnswer` | Checks the answer on the server (late answers after 60 s count as wrong) and updates the run, lives (3) and best run in `users.endless`. |

## 5c. Battles and push notifications (Phase 5)

There is no extra console setup for Android. Cloud Messaging is already on for Firebase projects, and `google-services.json` connects the app. On Android 13+ the app asks for notification permission after sign-in. Players can switch each notification type on or off in **Settings → Notifications**.

| Function | Type | Purpose |
|---|---|---|
| `findMatch` / `cancelMatch` | callable | random matchmaking queue (`matchQueue/{uid}`; the waiting player listens for `battleId`) |
| `startBotBattle` | callable | practice battle against Neo (bot answers are pre-planned and revealed on schedule) |
| `createInvite` / `joinInvite` | callable | 6-character invite codes (valid 30 min) |
| `challengeFriend` | callable | invite a friend and push them the code |
| `submitBattleAnswer` | callable | checks the answer against hidden `battles/{id}/secret/answers` and times it on the server: 100 points + up to 100 for speed |
| `tickBattle` | callable | moves practice battles along and keeps the app's clock in sync with the server |
| `finishBattle` | callable | idempotent result: winner and trophies (ranked +30/−20, invite +15/−10, practice +10/0; never below 0) and `users.battleStats` |
| `cleanupBattles` | every 10 min | finishes abandoned battles, expires invites, clears the stale queue |
| `hourlyReminders` | hourly | streak reminder at the player's local 19:00 if their streak would break; "workout ready" at local 08:00 |
| `notifyFriendsOnNewBest` | Firestore trigger | "Your friend beat your score!" when a weekly best overtakes a friend's |

How a battle works:
- Both players see the same 8 questions (math, colour-word, number sequence).
- Each question is open for a fixed window (8 s) from `startAt`.
- The app estimates the server clock from every function response, so both phones switch questions at the same moment.
- Scores update live through a Firestore listener on `battles/{id}`.

Pushes go to Firebase Installation IDs (the current FCM API). Devices the server can no longer reach are removed from the list automatically.

## 5d. Money, privacy and hardening (Phase 6)

### AdMob
1. In AdMob, create the app (Android, package `com.neurorush.app`) and two ad units: **Interstitial** and **Rewarded**.
2. **App ID:** put it in `android/gradle.properties`:
   ```
   admobAppId=ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY
   ```
   Without it, Google's test app ID is used.
3. **Ad unit IDs:** pass them at build time (step 7). Without them, Google's test units are used.
4. **Rewarded ad → Server-side verification:** set the callback URL to
   `https://asia-south1-<your-project-id>.cloudfunctions.net/admobSsv`.
   Rewards are granted only after AdMob calls this URL with a valid signature.
5. **Privacy & messaging:** create a **GDPR** message (and **US states** if needed). The app shows Google's consent form (UMP) before loading ads where it's required. Players can change their choice in Settings → Ad privacy choices.

### Google Play Billing
1. In Play Console → **Monetize → Products**, create:

   | Product id | Type | Grants |
   |---|---|---|
   | `remove_ads` | In-app (one-time) | no interstitial ads |
   | `premium_themes` | In-app (one-time) | all 3 neon themes |
   | `coins_small` / `coins_medium` / `coins_large` | In-app (consumable) | 500 / 1,200 / 3,000 coins (Remote Config) |
   | `neurorush_pro` | Subscription, base plan `monthly` (auto-renewing) | no ads, unlimited Endless Mode, all themes, 30-day stats |

2. **Users and permissions:** invite the Functions service account (`<project-id>@appspot.gserviceaccount.com`, or the default compute account shown in Cloud Console → IAM). Give it **View financial data** and **Manage orders and subscriptions**. `verifyPurchase` uses it to call the Google Play Developer API.
3. **Real-time developer notifications:**
   - Create the Pub/Sub topic `play-billing` in the Firebase project's Google Cloud console.
   - Grant `google-play-developer-notifications@system.gserviceaccount.com` the **Pub/Sub Publisher** role on it.
   - In Play Console → Monetization setup, enter `projects/<project-id>/topics/play-billing`.
   - Renewals, cancellations and refunds then update entitlements automatically (`playBillingNotifications`), and `recheckSubscriptions` runs daily as a safety net.
4. **Testing:** add license testers in Play Console and upload an internal-testing build (step 7). Purchases only work in a build installed from Play.

How a purchase flows:
- The app attaches the obfuscated account ID `sha256("neurorush:"+uid)`.
- `verifyPurchase` checks the purchase with Google and records it once in `purchases/{sha256(token)}`, then grants it.
- It acknowledges or consumes the purchase only after granting, so a failure never loses a paid item. The app finishes the purchase with Play only after the server confirms.
- A purchase verified while offline is re-delivered by Play at the next start.

### Remote Config
Create these keys in **two** templates: **Client** (app display and ad frequency) and **Server** (Firebase console → Remote Config → Server). The server template's prices are the ones actually charged.

| Key | Default | Template | Meaning |
|---|---|---|---|
| `interstitial_every_n_games` | 3 | client | at most one interstitial per N finished rounds |
| `interstitial_min_interval_seconds` | 120 | client | minimum time between interstitials |
| `ads_enabled` | true | client | kill switch for interstitials |
| `theme_price_coins` | 300 | client + server | price of one neon theme |
| `freeze_price_coins` | 100 | client + server | price of one streak freeze |
| `free_endless_per_day` | 10 | client + server | free Endless puzzles per day |
| `coins_small_amount` / `coins_medium_amount` / `coins_large_amount` | 500 / 1200 / 3000 | server | coins per pack |
| `rewarded_daily_limit` | 10 | server | rewarded-ad grants per player per day |

### Streaks and freezes (server-side)
- **Streaks:** `submitGameSession` counts the streak in the player's local days (the app sends its time-zone offset).
- **Freezes:** it uses freezes for missed days and awards one every 7 days (max 3). Freezes can also be bought with coins or earned from a rewarded ad.
- **Client writes blocked:** `firestore.rules` no longer lets the app write its own streak, freezes, coins or entitlements.

### App Check (Play Integrity)
1. Firebase console → App Check → register the Android app with **Play Integrity**, using the SHA-256 of your *Play app signing* key.
2. While developing, debug builds use the debug provider. Copy the debug token from logcat and add it under App Check → Manage debug tokens.
3. Turn on enforcement for the Cloud Functions by putting this in `functions/.env.<project-id>`, then redeploying the functions:
   ```
   ENFORCE_APP_CHECK=true
   ```
   Once on, calls that don't come from your genuine app are rejected.

### Privacy policy and account deletion (required by Google Play)
- In the app: Settings → Privacy policy, and Profile → **Delete account**. Deletion calls `deleteAccount`, which removes the profile, rounds, friends, leaderboard entries, achievements, Endless and coach data, push registrations and the sign-in account. Purchase records stay for legal reasons but are unlinked from the account.
- On the web: build and host the two pages Play asks for:
  ```bash
  tool/build_legal_pages.sh support@yourdomain.com
  firebase deploy --only hosting
  ```
  In Play Console → App content, enter `https://<project-id>.web.app/privacy` and `https://<project-id>.web.app/delete-account`.

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
| `coachTips/{uid}_{day}` | server | `uid, day, tip, funFact, focusSkill, source (ai/fallback), attempts, createdAt` |
| `endlessPuzzles/{id}` | server (never client-readable) | `uid, kind, question, choices[4], answerIndex, explanation, difficulty, source, answered, correct, givenIndex, createdAt, answeredAt` |
| `users/{uid}.endless` | server | `day, used, run, lives, bestRun, solved, activePuzzleId, recent[hash…50]` |
| `purchases/{sha256(token)}` | server only | `uid, productId, kind, orderId, purchaseToken, coins, expiresAt, consumed, voided, createdAt` |
| `rewardGrants/{sha256(transactionId)}` | server only (AdMob SSV) | `uid, reward, nonce, sessionId, claimed, result, verifiedAt, claimedAt` |
| `users/{uid}` (server, Phase 6) | | `coins, freezes, currentStreak, bestStreak, streakDay, entitlements{removeAds, pro, proExpiresAt, themes[]}, adRewards{day,count}, pendingBoosts{sessionId}` |
| `battles/{id}` | server; readable by its 2 players | `mode (random/invite/bot), status (waiting/active/finished/expired), players[2], playerInfo{uid:{username,displayName,trophies,level}}, questions[8] (no answers), count, questionMs, startAt, endsAt, scores{uid}, answers{uid:{i:{correct,points,ms}}}, winner, trophyDelta{uid}, inviteCode, host, createdAt, finishedAt` |
| `battles/{id}/secret/answers` | server only | `answers[8]`, `bot[8]{correct,ms}` |
| `matchQueue/{uid}` | server; owner reads | `uid, info, battleId, createdAt` |
| `invites/{code}` | server only | `battleId, host, createdAt` |
| `pushTargets/{uid}` | owner | `tokens[≤10] (FIDs), tzOffsetMinutes, reminderHourUtc, workoutHourUtc, prefs{streak,workout,friends,battle}, updatedAt` |
| `users/{uid}` (server) | | `trophies, battleStats{played,wins,losses,draws}` |

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
npm run test:emulators   # end-to-end on Auth/Firestore/Functions/Pub/Sub emulators: scores, friends, AI (mock Groq), battles, push, purchases (mock Play API), rewarded ads (signed SSV), deletion
npm run smoke:groq       # live AI prompts against Groq (needs GROQ_API_KEY)
```
