import 'package:flutter/material.dart';

/// استخدم هذه الـ getters بدلاً من الألوان الثابتة
/// مثال: context.bgPage بدلاً من const Color(0xFFF5F7FA)
extension AppAdaptiveColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  // ── خلفيات ──
  /// خلفية الصفحة الرئيسية (رمادي فاتح / رمادي داكن)
  Color get bgPage =>
      isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);

  /// خلفية البطاقات والـ Containers (أبيض / داكن قليلاً)
  Color get bgCard => isDark ? const Color(0xFF1E1E1E) : Colors.white;

  /// خلفية الـ AppBar والـ Header
  Color get bgHeader => isDark ? const Color(0xFF1A1A1A) : Colors.white;

  /// خلفية الـ input والـ chip
  Color get bgInput =>
      isDark ? const Color(0xFF242424) : const Color(0xFFF5F5F5);

  // ── نصوص ──
  /// النص الرئيسي (أسود / أبيض)
  Color get textPrimary =>
      isDark ? const Color(0xFFE8E8E8) : const Color(0xFF1A1A2E);

  /// النص الثانوي (رمادي)
  Color get textSecondary =>
      isDark ? const Color(0xFF9E9E9E) : Colors.grey.shade600;

  /// النص الخافت (placeholder)
  Color get textHint => isDark ? const Color(0xFF666666) : Colors.grey.shade400;

  // ── حدود وفواصل ──
  Color get borderColor =>
      isDark ? const Color(0xFF3A3A3A) : const Color(0xFFEEEEEE);

  // ── ظلال ──
  Color get shadowColor => isDark ? Colors.black54 : Colors.black12;

  // ── رموز وأيقونات ──
  Color get iconSecondary =>
      isDark ? const Color(0xFF9E9E9E) : Colors.grey.shade400;
}
