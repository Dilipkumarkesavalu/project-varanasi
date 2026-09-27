/// Build-time configuration, passed with `--dart-define` (never secrets: web builds are public).
///
/// ```sh
/// flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
/// ```
class AppConfig {
  const AppConfig({required this.appName, required this.apiBaseUrl});

  /// Reads `API_BASE_URL` from `--dart-define`, defaulting to the local backend.
  ///
  /// `API_BASE_URL=/` means "the site this app was loaded from" (staging/production,
  /// where nginx serves the app and proxies the API on the same origin).
  factory AppConfig.fromEnvironment({required String appName}) {
    const apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8000',
    );
    return AppConfig(
      appName: appName,
      apiBaseUrl: resolveApiBaseUrl(apiBaseUrl),
    );
  }

  /// Base URL of the backend, e.g. `https://staging.example.com`.
  static Uri resolveApiBaseUrl(String value, {Uri? pageUrl}) {
    if (value == '/') {
      final page = pageUrl ?? Uri.base;
      return Uri(scheme: page.scheme, host: page.host, port: page.port);
    }
    return Uri.parse(value);
  }

  /// Short app identifier used in logs, e.g. `billing`.
  final String appName;

  /// Base URL of the backend, e.g. `https://staging.example.com`.
  final Uri apiBaseUrl;
}
