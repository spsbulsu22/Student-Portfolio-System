import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Fonts are bundled locally (assets/fonts) and declared in pubspec.yaml:
///   Inter  (400, 500, 700)  and  Lexend (600)
class AppTheme {
  AppTheme._();

  static const _inter = 'Inter';
  static const _lexend = 'Lexend';

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
      scaffoldBackgroundColor: Colors.white,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: _inter),
    );
  }

  // Text styles used across screens
  static TextStyle get appTitle => const TextStyle(
      fontFamily: _lexend,
      fontSize: 26,
      fontWeight: FontWeight.w600,
      color: AppColors.brandText);

  static TextStyle get screenHeading => const TextStyle(
      fontFamily: _inter,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: AppColors.textDark);

  static TextStyle get fieldLabel => const TextStyle(
      fontFamily: _inter,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: AppColors.brandText);

  static TextStyle get fieldHint => TextStyle(
      fontFamily: _inter,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AppColors.textDark.withOpacity(0.5));

  static TextStyle get fieldText => const TextStyle(
      fontFamily: _inter,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AppColors.textDark);

  static TextStyle get body14 => const TextStyle(
      fontFamily: _inter,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: AppColors.textDark);

  static TextStyle get linkText => const TextStyle(
      fontFamily: _inter,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: AppColors.link);

  static TextStyle get buttonText => const TextStyle(
      fontFamily: _inter,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: Colors.white);
}
