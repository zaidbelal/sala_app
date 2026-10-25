import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sala/core/services/local_storage.dart';
import 'package:sala/core/services/realtime_hub.dart';
import 'dart:async';
import 'package:sala/core/services/notification_service.dart';

enum SessionResult {
  merchant,
  admin,
  driver,
  pending,
  unauthenticated,
}

final sessionCheckerProvider = FutureProvider<SessionResult>((ref) async {
  return SessionChecker.check();
});

class SessionChecker {
  SessionChecker._();
  static SessionResult localSessionResult() {
    // في وضع الأوفلاين نعتمد الجلسة المحلية المحفوظة طالما لم تنتهِ صلاحيتها
    if (!AppStorage.isLoggedIn || AppStorage.isSessionExpired) {
      return SessionResult.unauthenticated;
    }

    final authUser = FirebaseAuth.instance.currentUser;
    // إذا كان كائن فايربيز موجوداً وتعارض مع المعرّف المحلي، نعتبر الجلسة ملغاة
    if (authUser != null && authUser.uid != AppStorage.userId) {
      return SessionResult.unauthenticated;
    }

    if (AppStorage.isBanned) {
      return SessionResult.unauthenticated;
    }

    if (!AppStorage.isActive) {
      return SessionResult.pending;
    }

    switch (AppStorage.normalizedUserRole) {
      case 'admin':
      case 'super_admin':
      case 'accountant':
      case 'warehouse_manager':
        return SessionResult.admin;

      case 'driver':
        return SessionResult.driver;

      case 'merchant':
        return SessionResult.merchant;

      default:
        return SessionResult.unauthenticated;
    }
  }

  static Future<SessionResult> check() async {
    final sessionFuture = _checkSession();

    final minimumSplashDuration = Future<void>.delayed(
      const Duration(milliseconds: 800),
    );

    final result = await sessionFuture;
    await minimumSplashDuration;

    return result;
  }

  static Future<SessionResult> _checkSession() async {
    var authUser = FirebaseAuth.instance.currentUser;

    if (authUser == null &&
        AppStorage.isLoggedIn &&
        !AppStorage.isSessionExpired) {
      try {
        authUser = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((user) => user != null)
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
    }

    final userId = AppStorage.userId;

    if (!AppStorage.isLoggedIn || userId == null || userId.trim().isEmpty) {
      try {
        RealtimeHub().dispose();
      } catch (_) {}
      await AppStorage.clearUserData();
      return SessionResult.unauthenticated;
    }

    // انتهت مدة الجلسة (30 يوماً) - إيقاف الاشتراكات فوراً وتفريغ الذاكرة
    if (AppStorage.isSessionExpired) {
      try {
        RealtimeHub().dispose();
        await NotificationService.instance.detachTokenFromFirestore(userId);
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      await AppStorage.clearUserData();
      return SessionResult.unauthenticated;
    }

    // ✅ اعتماد الجلسة المحلية عند انقطاع الإنترنت أو تعذر استجابة فايربيز أوفلاين
    if (authUser == null) {
      return localSessionResult();
    } else {
      try {
        // فحص التوكن المحفوظ محلياً (لا يحتاج إنترنت) لضمان عدم تزييف الصلاحية
        final idToken = await authUser.getIdTokenResult(false);
        final secureRole = idToken.claims?['role']?.toString();
        if (secureRole != null && secureRole != AppStorage.userRole) {
          await AppStorage.saveUserData(userId: authUser.uid, role: secureRole);
        }
      } catch (_) {}
    }
    // في حال تعارض معرف المستخدم الحالي مع المعرف المحلي
    if (authUser.uid != userId.trim()) {
      await AppStorage.clearUserData();
      return SessionResult.unauthenticated;
    }
    try {
      // 🚀 إقلاع فوري: استخدام serverAndCache يزيل فترة الانتظار في الـ Splash Screen بالكامل.
      // التطبيق سيفتح فوراً من الكاش المحلي (0ms) وسيُحدّث البيانات في الخلفية بدون حجز المستخدم.
      final profileSnapshot = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(userId)
          .get(
            const GetOptions(
              source: Source.serverAndCache,
            ),
          )
          .timeout(const Duration(seconds: 5));

      // ✅ فحص دقيق: لا نحكم بعدم وجود الحساب إلا إذا كان الرد قادماً حتماً من السيرفر الحي
      if (!profileSnapshot.exists || profileSnapshot.data() == null) {
        final isFromCache = profileSnapshot.metadata.isFromCache;
        if (isFromCache) {
          // الهاتف أوفلاين ولم يجد الوثيقة بالكاش — لا تحذف المستخدم مطلقاً واعتمد الجلسة المحلية
          return localSessionResult();
        }

        // ⚠️ إصلاح حرج: لا نحذف حساب Firebase Auth تلقائياً — قد يكون:
        // - المستخدم في منتصف التسجيل (أنشأ OTP ولم يُكمل البيانات)
        // - فشل شبكي جزئي أعاد رداً فارغاً من السيرفر
        // الحذف التلقائي يعني فقدان حساب مستخدم شرعي بشكل نهائي لا يمكن التراجع عنه.
        try {
          await FirebaseAuth.instance
              .signOut()
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
        await AppStorage.clearUserData();
        return SessionResult.unauthenticated;
      }
      final data = profileSnapshot.data()!;

      final isActive = data['is_active'] as bool? ?? false;
      final isBanned = data['is_banned'] == true;
      final accountStatus =
          data['account_status']?.toString().trim().toLowerCase() ?? '';

      // الحساب محظور نهائياً أو موقوف من الإدارة
      if (isBanned || (!isActive && accountStatus != 'pending')) {
        try {
          await FirebaseAuth.instance
              .signOut()
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
        await AppStorage.clearUserData();
        return SessionResult.unauthenticated;
      }

      // الحساب بانتظار المراجعة لأول مرة فقط
      if (!isActive) {
        await AppStorage.setIsActive(false);
        await AppStorage.setIsBanned(false);
        return SessionResult.pending;
      }

      // 🔒 الأولوية للدور الموقّع مشفراً في Custom Claims لمنع تصعيد الصلاحيات
      final idTokenResult = await authUser.getIdTokenResult(false);
      final claimsRole =
          idTokenResult.claims?['role']?.toString().trim().toLowerCase();
      final docRole = data['role']?.toString().trim().toLowerCase();

      final effectiveRole = (claimsRole != null && claimsRole.isNotEmpty)
          ? claimsRole
          : (docRole ?? 'merchant');

      if (effectiveRole.isEmpty) {
        await AppStorage.clearUserData();
        return SessionResult.unauthenticated;
      }

      await AppStorage.setIsActive(true);
      await AppStorage.setIsBanned(false);

      await AppStorage.saveUserData(
        userId: userId,
        role: effectiveRole,
        name: data['full_name']?.toString(),
        phone: data['phone_number']?.toString(),
      );

      RealtimeHub().startForUser(userId, role: effectiveRole);

      switch (effectiveRole) {
        case 'admin':
        case 'super_admin':
        case 'accountant':
        case 'warehouse_manager':
          return SessionResult.admin;

        case 'driver':
          return SessionResult.driver;

        case 'merchant':
          return SessionResult.merchant;

        default:
          await AppStorage.clearUserData();
          return SessionResult.unauthenticated;
      }
    } on FirebaseException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Session Firebase error: ${error.code} ${error.message}',
        );
        debugPrintStack(stackTrace: stackTrace);
      }

      // الاعتماد على الجلسة المحلية عند انقطاع الإنترنت أو وجود أخطاء شبكية لمنع تسجيل الخروج العشوائي
      return localSessionResult();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Session check failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }

      return localSessionResult();
    }
  }

  static bool get isLoggedIn => AppStorage.isLoggedIn;

  static String? get currentUserId => AppStorage.userId;
}

extension SessionResultNavigation on SessionResult {
  String get route {
    switch (this) {
      case SessionResult.merchant:
        return '/merchant';

      case SessionResult.admin:
        return '/admin';

      case SessionResult.driver:
        return '/driver';

      case SessionResult.pending:
        return '/pending';

      case SessionResult.unauthenticated:
        return '/login';
    }
  }

  bool get isAuthenticated {
    return this != SessionResult.unauthenticated;
  }
}
