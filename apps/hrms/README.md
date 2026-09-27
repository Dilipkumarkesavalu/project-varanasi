# apps/hrms/

**Owner:** HRMS team (`@varanasi/hrms-team`). See [`.github/CODEOWNERS`](../../.github/CODEOWNERS).

The **Varanasi HRMS** web app (Flutter, web target): employees, attendance, leave, payroll (ADR-0002).
It talks to the backend only through `package:varanasi_core` (`ApiClient`) and builds its UI from
`package:varanasi_ui`. It never calls another product's screens or data directly (ADR-0001).

## Run locally

```bash
# from the repo root, once: melos bootstrap
cd apps/hrms
flutter run -d chrome --web-port 8083 --dart-define=API_BASE_URL=http://localhost:8000
```

## Check

```bash
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter build web --release
```
