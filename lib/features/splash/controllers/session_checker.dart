import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sala/core/services/local_storage.dart';
import 'package:sala/core/services/realtime_hub.dart';

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
    final authUser = FirebaseAuth.instance.currentUser;
    if (!AppStorage.isLoggedIn ||
        authUser == null ||
        authUser.uid != AppStorage.userId) {
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
      await AppStorage.clearUserData();
      return SessionResult.unauthenticated;
    }

    // انتهت مدة الجلسة (30 يوماً)
    if (AppStorage.isSessionExpired) {
      await AppStorage.clearUserData();
      return SessionResult.unauthenticated;
    }

    // ✅ اعتماد الجلسة المحلية عند انقطاع الإنترنت أو تعذر استجابة فايربيز أوفلاين
    if (authUser == null) {
      return localSessionResult();
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
      final serverRole = data['role']?.toString().trim().toLowerCase();

      // الحساب محظور
      if (isBanned) {
        await AppStorage.clearUserData();
        return SessionResult.unauthenticated;
      }

      // الحساب بانتظار موافقة الإدارة (طالما لم يُحظر، لا يتم طرده أبداً)
      if (!isActive) {
        await AppStorage.setIsActive(false);
        await AppStorage.setIsBanned(false);
        return SessionResult.pending;
      }

      // التحقق من وجود دور معتمد للمستخدم في قاعدة البيانات
      if (serverRole == null || serverRole.isEmpty) {
        await AppStorage.clearUserData();
        return SessionResult.unauthenticated;
      }
      // حفظ البيانات القادمة من الخادم فقط
      await AppStorage.setIsActive(true);
      await AppStorage.setIsBanned(false);

      await AppStorage.saveUserData(
        userId: userId,
        role: serverRole,
        name: data['full_name']?.toString(),
        phone: data['phone_number']?.toString(),
      );

      // تفعيل القنوات اللحظية للمستخدم فور التحقق من هويته وصلاحية حسابه
      RealtimeHub().startForUser(userId, role: serverRole);

      switch (serverRole) {
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
