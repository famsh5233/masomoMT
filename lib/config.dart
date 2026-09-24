/// Build-time settings. Override with --dart-define, for example:
/// flutter build appbundle --dart-define=API_BASE_URL=https://api.masomo.co.tz
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://api.masomo.co.tz');
  static const privacyUrl = String.fromEnvironment('PRIVACY_URL', defaultValue: 'https://masomo.co.tz/privacy');

  /// Google Play subscription product IDs. They must match plan codes on the server.
  static const playProductIds = {'pro_monthly', 'pro_yearly'};
}
