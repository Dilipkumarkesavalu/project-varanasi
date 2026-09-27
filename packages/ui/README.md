# packages/ui (`varanasi_ui`)

**Owner:** Frontend platform group (`@varanasi/frontend-core`), with design review.

The shared design system: `VColors`, `VSpacing`, `VRadius`, `VTypography`, `buildVaranasiTheme()`,
and widgets `VButton`, `VTextField`, `VDataTable`, `showVDialog` / `showVConfirmDialog`,
`LoadingView`, `EmptyView`, `ErrorView`.

Apps use these instead of raw Material widgets so all three products look and behave the same.
The brand font (Inter) is declared in `VTypography`; until its files are bundled as an asset,
text falls back to Roboto. No fonts are fetched from third parties at runtime.

Tests: `flutter test`.
