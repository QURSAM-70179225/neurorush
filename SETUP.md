# Setup guide (Phase 1: Firebase Authentication)

Later phases extend this guide with Firestore, Functions, Groq, AdMob, Billing and release signing.

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
