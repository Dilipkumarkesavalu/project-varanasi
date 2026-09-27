# apps/platform/

**Owner:** Platform team (`@varanasi/platform-team`). See [`.github/CODEOWNERS`](../../.github/CODEOWNERS).

The **Varanasi Platform** web app (Flutter, web target): tenant admin, users, roles, entitlements, audit log (ADR-0002).
It talks to the backend only through `package:varanasi_core` (`ApiClient`) and builds its UI from
`package:varanasi_ui`. It never calls another product's screens or data directly (ADR-0001).

## Run locally

```bash
# from the repo root, once: melos bootstrap
cd apps/platform
flutter run -d chrome --web-port 8081 --dart-define=API_BASE_URL=http://localhost:8000
```

## Check

```bash
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter build web --release
```
