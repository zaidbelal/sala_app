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
    try {
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
    } catch (_) {
      return SessionResult.unauthenticated;
    }
  }

  static Future<SessionResult> check() async {
    try {
      final result = await _checkSession().timeout(
        const Duration(milliseconds: 2500),
        onTimeout: () => localSessionResult(),
      );
      return result;
    } catch (_) {
      return localSessionResult();
    }
  }

  static Future<SessionResult> _checkSession() async {
    try {
      final userId = AppStorage.userId;
      if (!AppStorage.isLoggedIn || userId == null || userId.trim().isEmpty) {
        return SessionResult.unauthenticated;
      }

      if (AppStorage.isSessionExpired) {
        await AppStorage.clearUserData();
        return SessionResult.unauthenticated;
      }

      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null && authUser.uid != userId.trim()) {
        return localSessionResult();
      }

      final profileSnapshot = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(userId)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 2));

      if (profileSnapshot.exists && profileSnapshot.data() != null) {
        final data = profileSnapshot.data()!;
        final isActive = data['is_active'] as bool? ?? false;
        final isBanned = data['is_banned'] == true;
        final serverRole =
            data['role']?.toString().trim().toLowerCase() ?? 'merchant';

        if (isBanned) {
          await AppStorage.clearUserData();
          return SessionResult.unauthenticated;
        }

        if (!isActive) {
          await AppStorage.setIsActive(false);
          return SessionResult.pending;
        }

        await AppStorage.setIsActive(true);
        await AppStorage.saveUserData(
          userId: userId,
          role: serverRole,
          name: data['full_name']?.toString(),
          phone: data['phone_number']?.toString(),
        );

        RealtimeHub().startForUser(userId, role: serverRole);

        switch (serverRole) {
          case 'admin':
          case 'super_admin':
          case 'accountant':
          case 'warehouse_manager':
            return SessionResult.admin;
          case 'driver':
            return SessionResult.driver;
          default:
            return SessionResult.merchant;
        }
      }

      return localSessionResult();
    } catch (_) {
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
