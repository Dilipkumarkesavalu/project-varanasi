import 'package:flutter/material.dart';

import 'tokens.dart';

/// Type scale and font stack; tabular figures for numbers in tables.
///
/// Inter is the brand font. Until its files are bundled as an app asset, text falls back
/// to the platform font (Roboto on Flutter web), so no font is fetched from a third party.
abstract final class VTypography {
  static const String fontFamily = 'Inter';
  static const List<String> fontFamilyFallback = [
    'Roboto',
    'Noto Sans',
    'Arial',
  ];

  static TextTheme textTheme() {
    const base = TextTheme(
      displaySmall: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
    );
    final themed = base.apply(
      bodyColor: VColors.textPrimary,
      displayColor: VColors.textPrimary,
    );
    return themed.apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
  }

  /// Aligned digits for amounts and dates in tables.
  static const tabularFigures = [FontFeature.tabularFigures()];
}
