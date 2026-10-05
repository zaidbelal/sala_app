import 'package:flutter/material.dart';

class AppConfig {
  AppConfig._();
  static const double minOrderValue = 8250.0;
  static const int maxOrderItems = 50;
}

class AppColors {
  AppColors._();
  // ── الأساسي (أخضر) ──
  static const Color primary = Color(0xFF1B8E3D);
  static const Color primaryLight = Color(0xFF2DB85B);
  static const Color primaryDark = Color(0xFF146B2E);
  static const Color primarySurface = Color(0xFFE8F5ED);

  // ── الثانوي (سماوي) ──
  static const Color secondary = Color(0xFF00B4D8);
  static const Color secondaryLight = Color(0xFF48CAE4);
  static const Color secondaryDark = Color(0xFF0077B6);
  static const Color secondarySurface = Color(0xFFE0F7FA);

  // ── الأخطاء (أحمر) ──
  static const Color error = Color(0xFFD32F2F);
  static const Color errorLight = Color(0xFFEF5350);
  static const Color errorSurface = Color(0xFFFFEBEE);

  // ── النجاح (أزرق) ──
  static const Color success = Color(0xFF1565C0);
  static const Color successLight = Color(0xFF1E88E5);
  static const Color successSurface = Color(0xFFE3F2FD);

  // ── التحذير (برتقالي) ──
  static const Color warning = Color(0xFFF57C00);
  static const Color warningSurface = Color(0xFFFFF3E0);

  // ── المحايدة ──
  static const Color black = Color(0xFF0D0D0D);
  static const Color textPrimary = Color(0xFF212121);
  static const Color grey900 = Color(0xFF212121);
  static const Color grey800 = Color(0xFF424242); // مضاف
  static const Color grey700 = Color(0xFF616161);
  static const Color grey600 = Color(0xFF757575); // مضاف
  static const Color grey500 = Color(0xFF9E9E9E);
  static const Color grey400 = Color(0xFFBDBDBD); // مضاف لحل الخطأ
  static const Color grey300 = Color(0xFFE0E0E0);
  static const Color grey200 = Color(0xFFEEEEEE); // مضاف
  static const Color grey100 = Color(0xFFF5F5F5);

  static const Color white = Color(0xFFFFFFFF);

  // ── الخلفية ──
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFEEEEEE);

  // ── ألوان كل دور في التطبيق ──
  static const Color merchantColor = Color(0xFF1B8E3D);
  static const Color driverColor = Color(0xFF00B4D8);
  static const Color warehouseColor = Color(0xFFF57C00);
  static const Color adminColor = Color(0xFF6C3483);
  static const Color accountantColor = Color(0xFF1565C0);

  // ── تدرجات لونية ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1B8E3D), Color(0xFF2DB85B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [Color(0xFF0077B6), Color(0xFF00B4D8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient splashGradient = LinearGradient(
    colors: [
      Color(0xFF146B2E),
      Color(0xFF1B8E3D),
      Color(0xFF2DB85B),
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
