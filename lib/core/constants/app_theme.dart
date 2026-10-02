import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sala/core/services/local_storage.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_text_styles.dart';

// مزود إدارة مظهر التطبيق (داكن/فاتح)
final themeProvider = StateProvider<ThemeMode>((ref) {
  final savedTheme = AppStorage.themeMode;
  if (savedTheme == 'dark') return ThemeMode.dark;
  if (savedTheme == 'light') return ThemeMode.light;
  return ThemeMode.system;
});

class AppTheme {
  AppTheme._();

  static const String _fontFamily = 'Cairo';

  // ══════════════════════════════════════════
  // الثيم الفاتح
  // ══════════════════════════════════════════
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        fontFamily: _fontFamily,
        brightness: Brightness.light,

        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          primaryContainer: AppColors.primarySurface,
          secondary: AppColors.secondary,
          secondaryContainer: AppColors.secondarySurface,
          error: AppColors.error,
          errorContainer: AppColors.errorSurface,
          surface: AppColors.surface,
          onPrimary: AppColors.white,
          onSecondary: AppColors.white,
          onError: AppColors.white,
          onSurface: AppColors.black,
          outline: AppColors.grey300,
          outlineVariant: AppColors.divider,
        ),

        scaffoldBackgroundColor: AppColors.background,

        // 🚀 تفعيل حركة الانتقال والسحب للرجوع (Swipe to Back) الخاصة بالآيفون لجميع الأجهزة
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),

        // ── AppBar ──
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.black,
          elevation: 0,
          scrolledUnderElevation: 1,
          shadowColor: AppColors.black.withValues(alpha: 0.06),
          centerTitle: true,
          titleTextStyle: AppTextStyles.headlineSmall,
          iconTheme: const IconThemeData(
            color: AppColors.black,
            size: 24,
          ),
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
        ),

        // ── ElevatedButton ──
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.white,
            disabledBackgroundColor: AppColors.grey300,
            disabledForegroundColor: AppColors.grey500,
            elevation: 0,
            shadowColor: Colors.transparent,
            minimumSize: const Size(64, 48),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.button,
            ),
            textStyle: AppTextStyles.labelLarge,
          ),
        ),

        // ── OutlinedButton ──
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            disabledForegroundColor: AppColors.grey500,
            minimumSize: const Size(64, 48),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.button,
            ),
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            textStyle: AppTextStyles.labelLarge,
          ),
        ),

        // ── TextButton ──
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.smAll,
            ),
            textStyle: AppTextStyles.labelLarge,
          ),
        ),

        // ── InputDecoration ──
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.grey100,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.grey300,
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.primary,
              width: 1.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.error,
              width: 1.5,
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.error,
              width: 1.5,
            ),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          hintStyle: AppTextStyles.hint,
          labelStyle: AppTextStyles.bodyMedium,
          errorStyle: AppTextStyles.error,
          prefixIconColor: WidgetStateColor.resolveWith(
            (states) => AppColors.grey500,
          ),
          suffixIconColor: WidgetStateColor.resolveWith(
            (states) => AppColors.grey500,
          ),
        ),

        // ── Card ──
        cardTheme: const CardThemeData(
          color: AppColors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.card,
            side: BorderSide(
              color: AppColors.divider,
              width: 1,
            ),
          ),
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
        ),

        // ── BottomNavigationBar ──
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.white,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.grey500,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
        ),

        // ── Chip ──
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.grey100,
          selectedColor: AppColors.primarySurface,
          labelStyle: AppTextStyles.labelMedium,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.chip,
          ),
          side: BorderSide.none,
        ),

        // ── Divider ──
        dividerTheme: const DividerThemeData(
          color: AppColors.divider,
          thickness: 1,
          space: 1,
        ),

        // ── BottomSheet ──
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.bottomSheet,
          ),
          elevation: 0,
          modalElevation: 0,
          showDragHandle: true,
          dragHandleColor: AppColors.grey300,
          dragHandleSize: Size(40, 4),
          clipBehavior: Clip.antiAlias,
        ),

        // ── Dialog ──
        dialogTheme: const DialogThemeData(
          backgroundColor: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.lgAll,
          ),
          titleTextStyle: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
        ),

        // ── SnackBar ──
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.grey900,
          contentTextStyle: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.white,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.snackbar,
          ),
          behavior: SnackBarBehavior.floating,
          elevation: 0,
        ),

        // ── ListTile ──
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16),
          minVerticalPadding: 12,
          iconColor: AppColors.grey700,
          textColor: AppColors.black,
        ),

        // ── Switch ──
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.white;
            return AppColors.grey500;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.primary;
            return AppColors.grey300;
          }),
        ),

        // ── Checkbox ──
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.primary;
            return Colors.transparent;
          }),
          checkColor: const WidgetStatePropertyAll(AppColors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          side: const BorderSide(color: AppColors.grey300, width: 1.5),
        ),

        // ── TabBar ──
        tabBarTheme: TabBarThemeData(
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.grey500,
          labelStyle: AppTextStyles.titleSmall.copyWith(
            color: AppColors.primary,
          ),
          unselectedLabelStyle: AppTextStyles.titleSmall.copyWith(
            color: AppColors.grey500,
          ),
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(
              color: AppColors.primary,
              width: 2,
            ),
          ),
          dividerColor: AppColors.divider,
        ),

        // ── TextTheme ──
        textTheme: TextTheme(
          displayLarge: AppTextStyles.displayLarge,
          displayMedium: AppTextStyles.displayMedium,
          displaySmall: AppTextStyles.displaySmall,
          headlineLarge: AppTextStyles.headlineLarge,
          headlineMedium: AppTextStyles.headlineMedium,
          headlineSmall: AppTextStyles.headlineSmall,
          titleLarge: AppTextStyles.titleLarge,
          titleMedium: AppTextStyles.titleMedium,
          titleSmall: AppTextStyles.titleSmall,
          bodyLarge: AppTextStyles.bodyLarge,
          bodyMedium: AppTextStyles.bodyMedium,
          bodySmall: AppTextStyles.bodySmall,
          labelLarge: AppTextStyles.labelLarge,
          labelMedium: AppTextStyles.labelMedium,
          labelSmall: AppTextStyles.labelSmall,
        ),
      );

  // ══════════════════════════════════════════
  // الثيم الداكن
  // ══════════════════════════════════════════
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        fontFamily: _fontFamily,
        brightness: Brightness.dark,

        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4CAF7D),
          primaryContainer: Color(0xFF1A3A25),
          secondary: Color(0xFF26C6DA),
          secondaryContainer: Color(0xFF00363D),
          error: Color(0xFFEF5350),
          errorContainer: Color(0xFF3A1515),
          surface: Color(0xFF1E1E1E),
          onPrimary: Color(0xFFFFFFFF),
          onSecondary: Color(0xFFFFFFFF),
          onError: Color(0xFFFFFFFF),
          onSurface: Color(0xFFE8E8E8),
          outline: Color(0xFF3A3A3A),
          outlineVariant: Color(0xFF2A2A2A),
        ),

        scaffoldBackgroundColor: const Color(0xFF121212),

        // 🚀 تفعيل حركة الانتقال والسحب للرجوع (Swipe to Back) الخاصة بالآيفون لجميع الأجهزة
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),

        // ── AppBar ──
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF1A1A1A),
          foregroundColor: const Color(0xFFE8E8E8),
          elevation: 0,
          scrolledUnderElevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          centerTitle: true,
          titleTextStyle: AppTextStyles.headlineSmall.copyWith(
            color: const Color(0xFFE8E8E8),
          ),
          iconTheme: const IconThemeData(
            color: Color(0xFFE8E8E8),
            size: 24,
          ),
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
        ),

        // ── ElevatedButton ──
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF7D),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF2A2A2A),
            disabledForegroundColor: const Color(0xFF666666),
            elevation: 0,
            shadowColor: Colors.transparent,
            minimumSize: const Size(64, 48),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.button,
            ),
            textStyle: AppTextStyles.labelLarge,
          ),
        ),

        // ── OutlinedButton ──
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF4CAF7D),
            disabledForegroundColor: const Color(0xFF666666),
            minimumSize: const Size(64, 48),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.button,
            ),
            side: const BorderSide(color: Color(0xFF4CAF7D), width: 1.5),
            textStyle: AppTextStyles.labelLarge,
          ),
        ),

        // ── TextButton ──
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF4CAF7D),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.smAll,
            ),
            textStyle: AppTextStyles.labelLarge,
          ),
        ),

        // ── InputDecoration ──
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF242424),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFF3A3A3A),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFF4CAF7D),
              width: 1.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFFEF5350),
              width: 1.5,
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFFEF5350),
              width: 1.5,
            ),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          hintStyle: AppTextStyles.hint.copyWith(
            color: const Color(0xFF555555),
          ),
          labelStyle: AppTextStyles.bodyMedium.copyWith(
            color: const Color(0xFFAAAAAA),
          ),
          errorStyle: AppTextStyles.error,
          prefixIconColor: WidgetStateColor.resolveWith(
            (states) => const Color(0xFF666666),
          ),
          suffixIconColor: WidgetStateColor.resolveWith(
            (states) => const Color(0xFF666666),
          ),
        ),

        // ── Card ──
        cardTheme: const CardThemeData(
          color: Color(0xFF1E1E1E),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.card,
            side: BorderSide(
              color: Color(0xFF2A2A2A),
              width: 1,
            ),
          ),
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
        ),

        // ── BottomNavigationBar ──
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1A1A1A),
          selectedItemColor: Color(0xFF4CAF7D),
          unselectedItemColor: Color(0xFF555555),
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
        ),

        // ── Chip ──
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF242424),
          selectedColor: const Color(0xFF1A3A25),
          labelStyle: AppTextStyles.labelMedium.copyWith(
            color: const Color(0xFFE8E8E8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.chip,
          ),
          side: BorderSide.none,
        ),

        // ── Divider ──
        dividerTheme: const DividerThemeData(
          color: Color(0xFF2A2A2A),
          thickness: 1,
          space: 1,
        ),

        // ── BottomSheet ──
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.bottomSheet,
          ),
          elevation: 0,
          modalElevation: 0,
          showDragHandle: true,
          dragHandleColor: Color(0xFF3A3A3A),
          dragHandleSize: Size(40, 4),
          clipBehavior: Clip.antiAlias,
        ),

        // ── Dialog ──
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.lgAll,
          ),
          titleTextStyle: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFFE8E8E8),
          ),
        ),

        // ── SnackBar ──
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF2A2A2A),
          contentTextStyle: AppTextStyles.bodyMedium.copyWith(
            color: const Color(0xFFE8E8E8),
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.snackbar,
          ),
          behavior: SnackBarBehavior.floating,
          elevation: 0,
        ),

        // ── ListTile ──
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16),
          minVerticalPadding: 12,
          iconColor: Color(0xFF888888),
          textColor: Color(0xFFE8E8E8),
        ),

        // ── Switch ──
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return const Color(0xFF555555);
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF4CAF7D);
            }
            return const Color(0xFF3A3A3A);
          }),
        ),

        // ── Checkbox ──
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF4CAF7D);
            }
            return Colors.transparent;
          }),
          checkColor: const WidgetStatePropertyAll(Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          side: const BorderSide(color: Color(0xFF3A3A3A), width: 1.5),
        ),

        // ── TabBar ──
        tabBarTheme: TabBarThemeData(
          labelColor: const Color(0xFF4CAF7D),
          unselectedLabelColor: const Color(0xFF666666),
          labelStyle: AppTextStyles.titleSmall.copyWith(
            color: const Color(0xFF4CAF7D),
          ),
          unselectedLabelStyle: AppTextStyles.titleSmall.copyWith(
            color: const Color(0xFF666666),
          ),
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(
              color: Color(0xFF4CAF7D),
              width: 2,
            ),
          ),
          dividerColor: const Color(0xFF2A2A2A),
        ),

        // ── TextTheme ──
        textTheme: TextTheme(
          displayLarge: AppTextStyles.displayLarge
              .copyWith(color: const Color(0xFFE8E8E8)),
          displayMedium: AppTextStyles.displayMedium
              .copyWith(color: const Color(0xFFE8E8E8)),
          displaySmall: AppTextStyles.displaySmall
              .copyWith(color: const Color(0xFFE8E8E8)),
          headlineLarge: AppTextStyles.headlineLarge
              .copyWith(color: const Color(0xFFE8E8E8)),
          headlineMedium: AppTextStyles.headlineMedium
              .copyWith(color: const Color(0xFFE8E8E8)),
          headlineSmall: AppTextStyles.headlineSmall
              .copyWith(color: const Color(0xFFE8E8E8)),
          titleLarge:
              AppTextStyles.titleLarge.copyWith(color: const Color(0xFFE8E8E8)),
          titleMedium: AppTextStyles.titleMedium
              .copyWith(color: const Color(0xFFDDDDDD)),
          titleSmall:
              AppTextStyles.titleSmall.copyWith(color: const Color(0xFFDDDDDD)),
          bodyLarge:
              AppTextStyles.bodyLarge.copyWith(color: const Color(0xFFCCCCCC)),
          bodyMedium:
              AppTextStyles.bodyMedium.copyWith(color: const Color(0xFFCCCCCC)),
          bodySmall:
              AppTextStyles.bodySmall.copyWith(color: const Color(0xFFAAAAAA)),
          labelLarge:
              AppTextStyles.labelLarge.copyWith(color: const Color(0xFFE8E8E8)),
          labelMedium: AppTextStyles.labelMedium
              .copyWith(color: const Color(0xFFDDDDDD)),
          labelSmall:
              AppTextStyles.labelSmall.copyWith(color: const Color(0xFFAAAAAA)),
        ),
      );
}
