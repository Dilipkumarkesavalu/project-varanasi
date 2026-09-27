/// Shared design system for the Varanasi apps (M1-FOU-005).
///
/// Tokens ([VColors], [VSpacing], [VRadius], [VTypography]), the app theme
/// ([buildVaranasiTheme]) and common widgets. Apps use these instead of raw
/// Material widgets so all three products look and behave the same.
library;

export 'src/theme/tokens.dart';
export 'src/theme/typography.dart';
export 'src/theme/theme.dart';
export 'src/widgets/v_button.dart';
export 'src/widgets/v_text_field.dart';
export 'src/widgets/v_data_table.dart';
export 'src/widgets/v_dialog.dart';
export 'src/widgets/state_views.dart';
