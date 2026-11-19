# Google Play Data safety form — answers for NeuroRush

These answers are based on what the code actually does (Phases 1–7). Update them if you add SDKs.

**Does your app collect or share any of the required user data types?** Yes
**Is all of the user data encrypted in transit?** Yes (HTTPS/TLS for Firebase, AdMob, Play)
**Do you provide a way for users to request that their data is deleted?** Yes — in the app (Profile → Delete account) and at `https://<project-id>.web.app/delete-account`

| Data type | Collected | Shared | Optional? | Purposes |
|---|---|---|---|---|
| Personal info → Email address | Yes (Google/email sign-in only) | No | Optional (guests have none) | Account management |
| Personal info → Name | Yes (display name) | No | Optional | App functionality, Account management |
| Personal info → User IDs | Yes (account ID, username) | No | Required | App functionality, Account management, Fraud prevention |
| Location → Approximate location | **No** (country is chosen by the user, not detected) | — | — | — |
| Financial info → Purchase history | Yes | No | Optional | App functionality (entitlements), Fraud prevention |
| App activity → App interactions | Yes (game results, events) | No | Required | App functionality, Analytics, Personalization |
| App activity → Other user-generated content | Yes (friends list) | No | Optional | App functionality |
| App info and performance → Crash logs | Yes (Crashlytics) | No | Required | Analytics |
| App info and performance → Diagnostics | Yes (Crashlytics) | No | Required | Analytics |
| Device or other IDs | Yes (FCM installation ID; advertising ID via AdMob with consent) | **Yes** — advertising ID with Google AdMob | Advertising ID optional (consent) | App functionality (notifications), Advertising or marketing, Fraud prevention (App Check) |

Notes:
- **Shared** means sent to a third party for its own use. Groq gets only anonymous game numbers and puzzle text, with no user data or identifiers, so it doesn't count as sharing. Firebase and Google Play are *service providers* and aren't declared as sharing either.
- **AdMob** collects the advertising ID and approximate location *derived from IP* for ads. Google's own guidance is to declare this under *Device or other IDs* (shared) and *Approximate location*, purpose Advertising. If you keep ads on, also tick **Location → Approximate location: Collected and Shared (Advertising)**.
- **Target audience:** 13+. Not designed for children, so the app is not in the Families program.

# Content rating questionnaire (IARC) — expected answers
- Violence, fear, sexuality, drugs, gambling, crude language: **No**
- Users can interact or exchange content: **Yes** — usernames, friends and battles. There is no free-text chat, only usernames and display names.
- Shares user location: **No** (country only, chosen by the user)
- Digital purchases: **Yes**
- Expected rating: **PEGI 3 / Everyone**, with “In-app purchases” and “Users interact”
