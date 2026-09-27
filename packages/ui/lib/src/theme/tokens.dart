import 'package:flutter/painting.dart';

/// Brand and semantic colours. Widgets use these names, never raw hex values.
abstract final class VColors {
  // Brand
  static const primary = Color(0xFF1F4E8C); // deep river blue
  static const primaryContainer = Color(0xFFD6E3F7);
  static const secondary = Color(0xFFC8702A); // ghat saffron
  static const secondaryContainer = Color(0xFFF8E1CC);

  // Neutrals
  static const background = Color(0xFFF7F8FA);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFD9DDE3);
  static const textPrimary = Color(0xFF1B1F24);
  static const textSecondary = Color(0xFF5B6470);
  static const textDisabled = Color(0xFF9AA3AE);

  // Status
  static const success = Color(0xFF1E7B4C);
  static const warning = Color(0xFFB7791F);
  static const danger = Color(0xFFB42318);
  static const info = Color(0xFF2563A6);
}

/// 4-point spacing scale.
abstract final class VSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

abstract final class VRadius {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
}
