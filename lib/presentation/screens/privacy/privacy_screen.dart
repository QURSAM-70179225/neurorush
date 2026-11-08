import 'package:flutter/material.dart';

import '../../../core/legal.dart';

/// The privacy policy, also published on the web (public/privacy.html).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const effectiveDate = '8 November 2026';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget h(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Semantics(header: true, child: Text(t, style: theme.textTheme.titleMedium)),
        );
    Widget p(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: theme.textTheme.bodyMedium));
    Widget li(String t) => Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(t))]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text('Effective $effectiveDate', style: theme.textTheme.bodySmall),
          p('NeuroRush is a brain-training game. This policy explains what data the app collects, why, and the choices you have.'),
          h('Data we collect'),
          li('Account: an anonymous ID for guests; for Google or email sign-in, your email address, display name and (Google only) profile photo.'),
          li('Profile you choose: username, display name and country.'),
          li('Gameplay: scores, accuracy, reaction times, difficulty reached, streaks, XP, achievements, battle results and Endless Mode progress.'),
          li('Social: your friends list and friend requests.'),
          li('Device: a push-notification installation ID, your time zone (to send reminders at the right local time), and your notification preferences.'),
          li('Purchases: product, order ID and Google Play purchase token. Payments are handled by Google Play; we never see your card details.'),
          li('Ads: if you allow it, Google AdMob may use your device advertising ID to show ads. You can change this choice in Settings → Ad privacy choices.'),
          h('How we use it'),
          li('To run the game, save and sync your progress, and show leaderboards, friends and battles.'),
          li('To detect cheating: every round is checked on our servers before it counts.'),
          li('To personalise your Daily Workout and Brain Coach tips.'),
          li('To send the notifications you switched on.'),
          li('To verify purchases and rewarded ads.'),
          h('AI features'),
          p('The Brain Coach and Endless Mode use Groq to generate tips and puzzles. We send only game numbers (scores, accuracy, skill levels) and puzzle text — never your name, email or other identifiers.'),
          h('Who we share data with'),
          li('Google Firebase (hosting, sign-in, database, cloud functions, notifications, remote configuration, App Check).'),
          li('Google AdMob (ads) and Google Play (payments).'),
          li('Groq (AI text generation, as described above).'),
          li('Other players see your username, display name, country, level, streak, Brain Score and battle results.'),
          p('We do not sell your personal data.'),
          h('Keeping and deleting your data'),
          p('We keep your data while your account exists. You can delete your account at any time in Profile → Delete account, which permanently removes your profile, scores, friends and other data. '
              'Purchase records are kept, unlinked from your account, where the law requires it (for example tax and refunds).'),
          if (Legal.deleteAccountUrl.isNotEmpty) p('You can also request deletion on the web: ${Legal.deleteAccountUrl}'),
          h('Children'),
          p('NeuroRush is not directed at children under 13, and we do not knowingly collect their personal data.'),
          h('Security'),
          p('Data is encrypted in transit. Competitive data can only be changed by our servers after validation, and access rules restrict who can read what.'),
          h('Changes'),
          p('We will update this page and the effective date when the policy changes.'),
          if (Legal.supportEmail.isNotEmpty) ...[h('Contact'), p('Questions or requests: ${Legal.supportEmail}')],
        ],
      ),
    );
  }
}
