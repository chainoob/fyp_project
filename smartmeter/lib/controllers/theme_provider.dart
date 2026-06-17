import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartmeter/utils/logger.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = "theme_mode";
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeString = prefs.getString(_themeKey);
      if (modeString != null) {
        _themeMode = modeString == "light" ? ThemeMode.light : ThemeMode.dark;
        notifyListeners();
      }
    } catch (e, stack) {
      AppLog.error("Failed to load theme preference", e, stack);
    }
  }

  Future<void> toggleTheme(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, isDark ? "dark" : "light");
    } catch (e, stack) {
      AppLog.error("Failed to save theme preference", e, stack);
    }
  }
}
