# apps/billing/

**Owner:** Billing team (`@varanasi/billing-team`). See [`.github/CODEOWNERS`](../../.github/CODEOWNERS).

The **Varanasi Billing** web app (Flutter, web target): customers, invoices, payments (ADR-0002).
It talks to the backend only through `package:varanasi_core` (`ApiClient`) and builds its UI from
`package:varanasi_ui`. It never calls another product's screens or data directly (ADR-0001).

## Run locally

```bash
# from the repo root, once: melos bootstrap
cd apps/billing
flutter run -d chrome --web-port 8082 --dart-define=API_BASE_URL=http://localhost:8000
```

## Check

```bash
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter build web --release
```
