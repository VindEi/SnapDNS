import 'package:flutter/material.dart';

class SnapDnsTheme {
  static ThemeData createTheme(Brightness brightness, Color accent) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF5F5F7),
      primaryColor: accent,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
        primary: accent,
        surface: isDark ? const Color(0xFF151515) : const Color(0xFFFAFAFA),
        onSurface: isDark ? const Color(0xFFE5E5E7) : const Color(0xFF1A1A1A),
        outline: isDark ? Colors.white10 : Colors.black12,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return true;
          }
          return false;
        }),
        thickness: WidgetStateProperty.all(4),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.all(accent.withValues(alpha: 0.4)),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        interactive: true,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
