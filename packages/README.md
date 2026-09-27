# packages/

**Owner:** Frontend platform group (`@varanasi/frontend-core`). Changes here affect all three apps,
so they need a review from this group. See [`.github/CODEOWNERS`](../.github/CODEOWNERS).

| Package | What it holds |
|---------|---------------|
| [`core/`](core/) (`varanasi_core`) | HTTP client (ADR-0007 headers + Problem Details), auth-token holder, routing helpers, logging |
| [`ui/`](ui/) (`varanasi_ui`) | Colours, fonts, spacing, theme, buttons, form fields, table, dialog, loading/empty/error views |

Rule: **no business logic** in shared packages (same rule as `backend/src/varanasi/shared`, ADR-0008).
