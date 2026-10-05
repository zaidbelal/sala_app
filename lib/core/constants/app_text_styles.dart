import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  // ── الخط الأساسي للتطبيق (Cairo محلي ومستقر أوفلاين) ──
  static const String _fontFamily = 'Cairo';

  // ── العناوين الكبيرة ──
  static TextStyle get displayLarge => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: AppColors.black,
        height: 1.3,
      );

  static TextStyle get displayMedium => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.black,
        height: 1.3,
      );

  static TextStyle get displaySmall => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.black,
        height: 1.3,
      );

  // ── العناوين ──
  static TextStyle get headlineLarge => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.black,
        height: 1.4,
      );

  static TextStyle get headlineMedium => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.black,
        height: 1.4,
      );

  static TextStyle get headlineSmall => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.black,
        height: 1.4,
      );

  // ── العناوين الفرعية ──
  static TextStyle get titleLarge => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.black,
        height: 1.5,
      );

  static TextStyle get titleMedium => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.black,
        height: 1.5,
      );

  static TextStyle get titleSmall => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.grey900,
        height: 1.5,
      );

  // ── النصوص العادية ──
  static TextStyle get bodyLarge => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.grey900,
        height: 1.6,
      );

  static TextStyle get bodyMedium => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.grey900,
        height: 1.6,
      );

  static TextStyle get bodySmall => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.grey700,
        height: 1.6,
      );

  // ── التسميات والأزرار ──
  static TextStyle get labelLarge => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.white,
        height: 1.4,
        letterSpacing: 0.3,
      );

  static TextStyle get labelMedium => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.grey700,
        height: 1.4,
      );

  static TextStyle get labelSmall => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.grey500,
        height: 1.4,
        letterSpacing: 0.2,
      );

  // ── خاصة بالتطبيق ──
  static TextStyle get price => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
        height: 1.3,
      );

  static TextStyle get priceLarge => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
        height: 1.3,
      );

  static TextStyle get badge => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.white,
        height: 1.2,
      );

  static TextStyle get hint => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.grey500,
        height: 1.5,
      );

  static TextStyle get link => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.secondary,
        height: 1.5,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.secondary,
      );

  static TextStyle get error => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.error,
        height: 1.4,
      );

  // ── دالة مساعدة للتخصيص السريع ──
  static TextStyle custom({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
  }) =>
      TextStyle(
        fontFamily: _fontFamily,
        fontSize: fontSize ?? 14,
        fontWeight: fontWeight ?? FontWeight.w400,
        color: color ?? AppColors.black,
        height: height ?? 1.5,
        letterSpacing: letterSpacing,
        decoration: decoration,
      );
}
