# packages/core (`varanasi_core`)

**Owner:** Frontend platform group (`@varanasi/frontend-core`).

Shared app core used by every Varanasi app:

| API | Purpose |
|-----|---------|
| `ApiClient` | Calls the backend with `Authorization`, a fresh `X-Correlation-ID`, an `Idempotency-Key` on every POST, and `If-Match` for PATCH. Errors become `ApiException` (Problem Details, ADR-0007). A `401` signs the user out |
| `TokenStore` | Keeps the short-lived access token **in memory only** (refresh token is an HttpOnly cookie) |
| `buildAppRouter` | go_router with a sign-in guard and safe `?from=` redirects |
| `setupLogging` / `appLogger` | One JSON log line per record, same shape as the backend |
| `AppConfig.fromEnvironment` | `API_BASE_URL` from `--dart-define` |

Tests: `flutter test`.
