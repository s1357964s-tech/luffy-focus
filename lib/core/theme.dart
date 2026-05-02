import 'package:flutter/material.dart';
import 'constants.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: AppConstants.primaryButtonColor,
      scaffoldBackgroundColor: AppConstants.backgroundColor,
      fontFamily: 'Roboto', // 這裡可以根據後續需求替換為其他字型
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: AppConstants.primaryTextColor,
          fontSize: 48,
          fontWeight: FontWeight.bold,
        ),
        bodyLarge: TextStyle(
          color: AppConstants.primaryTextColor,
          fontSize: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryButtonColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        ),
      ),
    );
  }
}
