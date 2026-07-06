import 'package:flutter/material.dart';

/// Visual language matching the approved web draft: warm neutral surfaces,
/// blue accent, green for sentences, high contrast, large touch targets.
///
/// AAC design rules (SPEC.md): minimum 64dp touch targets, WCAG-AAA-leaning
/// contrast, nothing times out, buttons never move.
abstract final class AppTheme {
  static const blue = Color(0xFF1A6FC4);
  static const blueDark = Color(0xFF0C4A8A);
  static const green = Color(0xFF1A8C5B);
  static const red = Color(0xFFC42B2B);
  static const amber = Color(0xFFB86A00);
  static const gold = Color(0xFFC99700);
  static const purple = Color(0xFF6B4FA3);

  /// Minimum touch target for word tiles and action buttons.
  static const double minTarget = 64;

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: brightness,
      surface: isDark ? const Color(0xFF242228) : Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF18171A) : const Color(0xFFF6F5F3),
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  /// Parses "#RRGGBB" from the backend's Fitzgerald Key colors.
  static Color hex(String value, {Color fallback = blue}) {
    final cleaned = value.replaceFirst('#', '');
    if (cleaned.length != 6) return fallback;
    final parsed = int.tryParse(cleaned, radix: 16);
    return parsed == null ? fallback : Color(0xFF000000 | parsed);
  }
}
