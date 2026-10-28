import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sala/core/services/local_storage.dart';
import 'package:sala/core/services/realtime_hub.dart';
import 'dart:async';

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
    if (!AppStorage.isLoggedIn || AppStorage.userId == null) {
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
      default:
        return SessionResult.merchant;
    }
  }

  static Future<SessionResult> check() async {
    final sessionFuture = _checkSession();
    final minimumSplashDuration = Future<void>.delayed(
      const Duration(milliseconds: 600),
    );

    final result = await sessionFuture;
    await minimumSplashDuration;
    return result;
  }

  static Future<SessionResult> _checkSession() async {
    final userId = AppStorage.userId;

    // إذا لم يكن مسجلاً محلياً إطلاقاً
    if (!AppStorage.isLoggedIn || userId == null || userId.trim().isEmpty) {
      return SessionResult.unauthenticated;
    }

    // فحص محلي فوري لتسريع فتح التطبيق وعدم حجب المستخدم
    if (AppStorage.isBanned) {
      return SessionResult.unauthenticated;
    }

    try {
      // محاولة فحص حالة الحساب في الخلفية بهدوء دون مسح الحساب إذا تعثرت الشبكة
      final doc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(userId)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 3));

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final isActive = data['is_active'] as bool? ?? false;
        final isBanned = data['is_banned'] == true;
        final role = (data['role'] as String?)?.trim().toLowerCase() ??
            AppStorage.normalizedUserRole;

        if (isBanned) {
          await AppStorage.clearUserData();
          return SessionResult.unauthenticated;
        }

        await AppStorage.setIsActive(isActive);
        await AppStorage.setIsBanned(isBanned);
        await AppStorage.saveUserData(
          userId: userId,
          role: role,
          name: data['full_name'] as String?,
          phone: data['phone_number'] as String?,
        );

        unawaited(RealtimeHub().startForUser(userId, role: role));

        if (!isActive) return SessionResult.pending;

        return switch (role) {
          'admin' ||
          'super_admin' ||
          'accountant' ||
          'warehouse_manager' =>
            SessionResult.admin,
          'driver' => SessionResult.driver,
          _ => SessionResult.merchant,
        };
      }
    } catch (_) {
      // في حال وجود بطء في الاتصال أو عدم توفر إنترنت، نعتمد الجلسة المحلية فوراً
    }

    // تشغيل القنوات الحية والانتقال مباشرة
    unawaited(RealtimeHub()
        .startForUser(userId, role: AppStorage.normalizedUserRole));
    return localSessionResult();
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
