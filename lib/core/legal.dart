/// Contact and policy links. Release builds pass these with --dart-define
/// (see SETUP.md); they are shown in Settings and the privacy policy.
class Legal {
  const Legal._();
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');
  static const privacyUrl = String.fromEnvironment('PRIVACY_URL');
  static const deleteAccountUrl = String.fromEnvironment('DELETE_ACCOUNT_URL');
  static const packageName = 'com.neurorush.app';

  static Uri manageSubscription(String productId) =>
      Uri.parse('https://play.google.com/store/account/subscriptions?sku=$productId&package=$packageName');
}
