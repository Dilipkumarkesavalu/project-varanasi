# apps/

**Owner:** each app is owned by its product team. See [`.github/CODEOWNERS`](../.github/CODEOWNERS).

| Folder | App | Owner |
|--------|-----|-------|
| [`platform/`](platform/) | Varanasi Platform (tenant admin) | Platform team |
| [`billing/`](billing/) | Varanasi Billing | Billing team |
| [`hrms/`](hrms/) | Varanasi HRMS | HRMS team |

All three are Flutter **web** apps in one Melos/pub workspace (root `pubspec.yaml`), sharing
[`packages/core`](../packages/core/) and [`packages/ui`](../packages/ui/).
