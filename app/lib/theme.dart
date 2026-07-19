import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the current ThemeMode and persists it. Exposed as a ValueNotifier so
/// MaterialApp can rebuild when the user toggles light/dark.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController(super.value);

  static const _key = 'theme_mode';

  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key);
    final mode = switch (s) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return ThemeController(mode);
  }

  Future<void> toggle(Brightness current) async {
    // Flip relative to what's on screen now.
    value = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, value == ThemeMode.dark ? 'dark' : 'light');
  }
}

// High-contrast palettes.
const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF0033CC),
  onPrimary: Colors.white,
  secondary: Color(0xFF0033CC),
  onSecondary: Colors.white,
  error: Color(0xFFB00020),
  onError: Colors.white,
  surface: Colors.white,
  onSurface: Colors.black,
);

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFCFD8DC), // light grey on black
  onPrimary: Colors.black,
  secondary: Color(0xFFCFD8DC),
  onSecondary: Colors.black,
  error: Color(0xFFFF6E6E),
  onError: Colors.black,
  surface: Colors.black,
  onSurface: Colors.white,
);

// Bundled serif face (SIL OFL, assets/fonts/Lora.ttf) — serifs make the large
// body text easier to read.
const _fontFamily = 'Lora';

// Shared large, accessible button sizing.
ButtonStyle _bigButton() => ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(60)),
      textStyle: const WidgetStatePropertyAll(TextStyle(
          fontFamily: _fontFamily, fontSize: 20, fontWeight: FontWeight.w700)),
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );

ThemeData buildTheme(Brightness brightness) {
  final scheme = brightness == Brightness.dark ? _darkScheme : _lightScheme;
  final base = ThemeData(
      useMaterial3: true, colorScheme: scheme, fontFamily: _fontFamily);

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    // Large, bold, high-contrast text throughout.
    textTheme: base.textTheme
        .apply(
            fontFamily: _fontFamily,
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface)
        .copyWith(
          headlineMedium: TextStyle(
              fontFamily: _fontFamily,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface),
          titleLarge: TextStyle(
              fontFamily: _fontFamily,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface),
          bodyLarge: TextStyle(
              fontFamily: _fontFamily,
              fontSize: 22,
              height: 1.35,
              color: scheme.onSurface),
          bodyMedium: TextStyle(
              fontFamily: _fontFamily,
              fontSize: 20,
              height: 1.35,
              color: scheme.onSurface),
        ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: _bigButton()),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _bigButton().copyWith(
        side: WidgetStatePropertyAll(
            BorderSide(color: scheme.primary, width: 2)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: _bigButton()),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface),
      elevation: 0,
    ),
  );
}

/// Semantic colors for answer feedback (kept vivid in both themes).
const answerCorrect = Color(0xFF2E7D32);
const answerWrong = Color(0xFFC62828);

/// Pastel accents for the quiz navigation buttons. Light fills, so they use
/// dark text/icons for contrast in both themes.
const navPrevious = Color(0xFFEF9A9A); // pastel red
const navNext = Color(0xFF81C784); // brighter pastel green
const navMark = Color(0xFFFFCC80); // pastel orange
const navShowAnswer = Color(0xFFCE93D8); // pastel purple
