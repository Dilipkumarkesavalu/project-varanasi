/// Shared core for the Varanasi apps (M1-FOU-004).
///
/// - [ApiClient]: HTTP client following the API standards (ADR-0007):
///   bearer token, `X-Correlation-ID`, `Idempotency-Key`, Problem Details errors.
/// - [TokenStore]: holds the short-lived access token in memory.
/// - [buildAppRouter]: go_router setup with a sign-in guard.
/// - [setupLogging]/[appLogger]: consistent, structured client logging.
library;

export 'src/config/app_config.dart';
export 'src/auth/token_store.dart';
export 'src/http/api_client.dart';
export 'src/http/api_exception.dart';
export 'src/http/ids.dart';
export 'src/logging/logging.dart';
export 'src/routing/app_router.dart';
