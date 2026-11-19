import 'package:flutter/material.dart';

/// Names and version shown in the app (same as the desktop AppInfo).
class AppInfo {
  static const productName = 'Hostel Management System';
  static const businessName = 'Shri Balaji Hostel';
  static const version = '1.0.0';
}

/// Colours carried over from the desktop application (LoginForm and UiTheme).
class AppColors {
  // Login screen: night sky, lit sign board and the terracotta facade.
  static const loginBackground = Color(0xFF181B21);
  static const panel = Color(0xCD181B21); // alpha 205
  static const gold = Color(0xFFE8BA62);
  static const terracotta = Color(0xFFC0652B);
  static const terracottaDark = Color(0xFFA05020);
  static const lightText = Color(0xFFECE6DA);
  static const mutedText = Color(0xFFAAA59B);
  static const errorText = Color(0xFFFF8C78);

  // Main screens.
  static const contentBackground = Color(0xFFF5ECDC); // beige, like the hostel walls
  static const textPrimary = Color(0xFF212529);
  static const textMuted = Color(0xFF6C757D);
}

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.terracotta,
          primary: AppColors.terracotta,
        ),
        scaffoldBackgroundColor: AppColors.contentBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.terracotta,
          foregroundColor: Colors.white,
        ),
      );
}
