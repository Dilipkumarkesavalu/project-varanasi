import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// The one theme all three apps use.
ThemeData buildVaranasiTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: VColors.primary,
    primary: VColors.primary,
    primaryContainer: VColors.primaryContainer,
    secondary: VColors.secondary,
    secondaryContainer: VColors.secondaryContainer,
    error: VColors.danger,
    surface: VColors.surface,
  );
  const inputBorder = OutlineInputBorder(
    borderRadius: VRadius.mdAll,
    borderSide: BorderSide(color: VColors.border),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: VColors.background,
    textTheme: VTypography.textTheme(),
    appBarTheme: const AppBarTheme(
      backgroundColor: VColors.surface,
      foregroundColor: VColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: const CardThemeData(
      color: VColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: VRadius.lgAll,
        side: BorderSide(color: VColors.border),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: VRadius.mdAll,
        borderSide: BorderSide(color: VColors.primary, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: VSpacing.md,
        vertical: VSpacing.md,
      ),
      isDense: true,
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: VRadius.lgAll),
    ),
    dividerTheme: const DividerThemeData(color: VColors.border, space: 1),
  );
}
