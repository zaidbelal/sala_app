import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppShadows {
  AppShadows._();

  static List<BoxShadow> get xs => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get sm => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get md => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get lg => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.10),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get xl => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 40,
          offset: const Offset(0, 16),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get button => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.35),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.15),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get card => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get bottomSheet => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 32,
          offset: const Offset(0, -8),
        ),
      ];

  static List<BoxShadow> get fab => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.40),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];
}
