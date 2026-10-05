import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ═══════════════════════════════════════════════════════════
/// LocalStorage — خدمة التخزين المحلي لتطبيق سَلة
/// نمط Singleton مع تهيئة مسبقة في main.dart
/// ═══════════════════════════════════════════════════════════
class AppStorage {
  AppStorage._();

  static SharedPreferences? _prefs;
  static bool _initialized = false;
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );
  // ══════════════════════════════════════════
  // المفاتيح — private constants
  // ══════════════════════════════════════════
  static const _kUserId = 'user_id';
  static const _kUserRole = 'user_role';
  static const _kUserName = 'user_name';
  static const _kUserPhone = 'user_phone';
  static const _kWarehouseId = 'warehouse_id';
  static const _kFcmToken = 'fcm_token';
  static const _kFirstLaunch = 'first_launch';
  static const _kAppVersion = 'app_version';
  static const _kThemeMode = 'theme_mode'; // 'light' | 'dark' | 'system'
  static const _kLanguage = 'language'; // 'ar' | 'en'
  static const _kLastLoginAt = 'last_login_at';
  static const _kSessionToken = 'session_token';
  static const _kNotifEnabled = 'notif_enabled';
  static const _kOnboardingDone = 'onboarding_done';
  static const _kPendingOrder = 'pending_order_json';
  static const _kIsActive = 'is_active';
  static const _kIsBanned = 'is_banned'; // ✅ مفتاح الحظر
  static const _kPendingReturns = 'pending_returns_json'; // طابور المرتجعات
  static const _kPendingDeliveries =
      'pending_driver_deliveries_json'; // طابور تسليمات السائق أوفلاين

  // ══════════════════════════════════════════
  // التهيئة — يُستدعى مرة واحدة في main.dart
  // ══════════════════════════════════════════
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
      if (kDebugMode) debugPrint('✅ LocalStorage: initialized');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ LocalStorage: failed to initialize — $e');
      rethrow;
    }
  }

  static SharedPreferences get _db {
    if (!_initialized || _prefs == null) {
      throw StateError(
        '❌ LocalStorage لم يتم تهيئته — استدعِ AppStorage.initialize() في main.dart أولاً',
      );
    }
    return _prefs!;
  }

  // ══════════════════════════════════════════
  // حالة التهيئة
  // ══════════════════════════════════════════
  static bool get isInitialized => _initialized;

  // ╔══════════════════════════════════════════╗
  // ║           بيانات المستخدم               ║
  // ╚══════════════════════════════════════════╝
  static Future<void> clearUserData() async {
    final uid = userId;
    final clearSecureStorage = _secureStorage
        .delete(key: _kSessionToken)
        .timeout(const Duration(seconds: 2), onTimeout: () => null)
        .catchError((_) => null);

    await Future.wait([
      clearSecureStorage,
      _db.remove(_kLastLoginAt),
      _db.remove(_kFcmToken),
      _db.remove(_kIsActive),
      _db.remove(_kIsBanned),
      _db.remove(_kUserId),
      _db.remove(_kUserRole),
      _db.remove(_kUserName),
      _db.remove(_kUserPhone),
      _db.remove(_kWarehouseId),
      if (uid != null) _db.remove('sala_cart_v2_$uid'),
    ]);
    if (kDebugMode) {
      debugPrint(
          '🗑️ LocalStorage: user data cleared safely (offline pending queue preserved)');
    }
  }

  // ── Getters ──
  static String? get userId => _db.getString(_kUserId);
  static String? get userRole => _db.getString(_kUserRole);
  static String? get userName => _db.getString(_kUserName);
  static String? get userPhone => _db.getString(_kUserPhone);
  static String? get warehouseId => _db.getString(_kWarehouseId);
  static String? get fcmToken => _db.getString(_kFcmToken);
  static Future<String?> getSessionToken() async {
    try {
      return await _secureStorage
          .read(key: _kSessionToken)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  static String? get lastLoginAt => _db.getString(_kLastLoginAt);

  // ── فحص تسجيل الدخول ──
  static bool get isLoggedIn => userId != null && userId!.isNotEmpty;
  static bool get isActive => _db.getBool(_kIsActive) ?? false;
  static Future<void> setIsActive(bool value) => _db.setBool(_kIsActive, value);

  static bool get isBanned => _db.getBool(_kIsBanned) ?? false;
  static Future<void> setIsBanned(bool value) => _db.setBool(_kIsBanned, value);
  // ── آخر وقت دخول كـ DateTime ──
  static DateTime? get lastLoginDateTime {
    final raw = lastLoginAt;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  // ── فحص انتهاء الجلسة (30 يوم) ──
  static const int sessionDurationDays = 30; // ✅ غيّره من مكان واحد

  // تبقى الجلسة حتى يسجل المستخدم الخروج أو يحذف بيانات التطبيق
  static bool get isSessionExpired {
    final lastLogin = lastLoginDateTime;
    if (lastLogin == null) return true;

    return DateTime.now().toUtc().difference(
              lastLogin.toUtc(),
            ) >
        const Duration(days: 30);
  }

  // ╔══════════════════════════════════════════╗
  // ║            أدوار المستخدمين             ║
  // ╚══════════════════════════════════════════╝
  static String get normalizedUserRole => (userRole ?? '').trim().toLowerCase();

  static bool get isMerchant => normalizedUserRole == 'merchant';

  static bool get isDriver => normalizedUserRole == 'driver';

  static bool get isAdmin =>
      normalizedUserRole == 'admin' || normalizedUserRole == 'super_admin';

  static bool get isAccountant => normalizedUserRole == 'accountant';

  static bool get isWarehouseManager =>
      normalizedUserRole == 'warehouse_manager';
  static bool get hasAdminAccess =>
      isAdmin || isAccountant || isWarehouseManager;

  // ╔══════════════════════════════════════════╗
  // ║             إعدادات التطبيق             ║
  // ╚══════════════════════════════════════════╝

  // ── الفتح الأول ──
  static bool get isFirstLaunch => _db.getBool(_kFirstLaunch) ?? true;
  static Future<void> markLaunched() => _db.setBool(_kFirstLaunch, false);

  // ── الإعداد الأولي (Onboarding) ──
  static bool get isOnboardingDone => _db.getBool(_kOnboardingDone) ?? false;
  static Future<void> markOnboardingDone() =>
      _db.setBool(_kOnboardingDone, true);

  // ── الثيم ──
  static String get themeMode => _db.getString(_kThemeMode) ?? 'system';
  static Future<void> saveThemeMode(String mode) =>
      _db.setString(_kThemeMode, mode);

  // ── اللغة ──
  static String get language => _db.getString(_kLanguage) ?? 'ar';
  static Future<void> saveLanguage(String lang) =>
      _db.setString(_kLanguage, lang);

  // ── الإشعارات ──
  static bool get notificationsEnabled => _db.getBool(_kNotifEnabled) ?? true;
  static Future<void> setNotifications(bool enabled) =>
      _db.setBool(_kNotifEnabled, enabled);

  // ── إصدار التطبيق ──
  static String? get appVersion => _db.getString(_kAppVersion);
  static Future<void> saveAppVersion(String version) =>
      _db.setString(_kAppVersion, version);

  // ╔══════════════════════════════════════════╗
  // ║              FCM Token                  ║
  // ╚══════════════════════════════════════════╝
  static Future<void> saveFcmToken(String token) async {
    if (fcmToken == token) return; // لا تحديث إذا لم يتغير
    await _db.setString(_kFcmToken, token);
    if (kDebugMode) debugPrint('🔔 LocalStorage: FCM token updated');
  }

// ╔══════════════════════════════════════════╗
  // ║      طلبات معلقة (Offline Queue)        ║
  // ╚══════════════════════════════════════════╝
  static String _userPendingOrderKey([String? uid]) =>
      '${_kPendingOrder}_${uid ?? userId ?? "anonymous"}';

  static Future<void> _queueLock = Future.value();

  /// يضيف الطلب إلى الطابور المحلي الخاص بالمستخدم الحالي (Thread-Safe)
  static Future<void> savePendingOrder(Map<String, dynamic> order) {
    final previousLock = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;

    return previousLock.whenComplete(() async {
      try {
        final targetUid = order['merchantId']?.toString();
        final targetOrderId = order['orderId']?.toString() ?? '';
        final key = _userPendingOrderKey(targetUid);
        final currentQueue = getPendingOrders(targetUid);

        if (targetOrderId.isNotEmpty &&
            currentQueue.any((o) => o['orderId'] == targetOrderId)) {
          return;
        }

        currentQueue.add(order);
        final json = jsonEncode(currentQueue);
        await _db.setString(key, json);
      } finally {
        completer.complete();
      }
    });
  }

  /// يرجع جميع الطلبات المعلقة في الطابور للمستخدم الحالي فقط
  static List<Map<String, dynamic>> getPendingOrders([String? uid]) {
    final targetUid = uid ?? userId;
    if (targetUid == null || targetUid.isEmpty) return [];
    final key = _userPendingOrderKey(targetUid);
    final raw = _db.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return List<Map<String, dynamic>>.from(
            decoded.map((e) => Map<String, dynamic>.from(e as Map)));
      } else if (decoded is Map) {
        return [Map<String, dynamic>.from(decoded)];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// يحذف طلباً محدداً من الطابور بناءً على المعرّف (Thread-Safe)
  static Future<void> removePendingOrder(String orderId, [String? uid]) {
    final previousLock = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;

    return previousLock.whenComplete(() async {
      try {
        final targetUid = uid ?? userId;
        final key = _userPendingOrderKey(targetUid);
        final currentQueue = getPendingOrders(targetUid);
        currentQueue.removeWhere((order) => order['orderId'] == orderId);

        if (currentQueue.isEmpty) {
          await _db.remove(key);
          await _db.remove(_kPendingOrder);
        } else {
          await _db.setString(key, jsonEncode(currentQueue));
        }
      } finally {
        completer.complete();
      }
    });
  }

  static Future<void> clearPendingOrder([String? uid]) async {
    final targetUid = uid ?? userId;
    if (targetUid != null && targetUid.isNotEmpty) {
      await _db.remove(_userPendingOrderKey(targetUid));
    }
    await _db.remove(_kPendingOrder);
  }

  // ── طلبات الإرجاع المعلقة (أوفلاين) ──
  static String _userPendingReturnKey([String? uid]) =>
      '${_kPendingReturns}_${uid ?? userId ?? "anonymous"}';
  static Future<void> savePendingReturn(Map<String, dynamic> returnData) {
    final previousLock = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;

    return previousLock.whenComplete(() async {
      try {
        final targetUid = returnData['merchantId']?.toString() ?? userId;
        final key = _userPendingReturnKey(targetUid);
        final currentQueue = getPendingReturns(targetUid);
        final targetOrderId = returnData['orderId']?.toString() ?? '';
        if (targetOrderId.isNotEmpty &&
            currentQueue.any((r) => r['orderId'] == targetOrderId)) {
          return;
        }
        currentQueue.add(returnData);
        await _db.setString(key, jsonEncode(currentQueue));
      } finally {
        completer.complete();
      }
    });
  }

  static List<Map<String, dynamic>> getPendingReturns([String? uid]) {
    final targetUid = uid ?? userId;
    if (targetUid == null || targetUid.isEmpty) return [];
    final key = _userPendingReturnKey(targetUid);
    final raw = _db.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return List<Map<String, dynamic>>.from(
            decoded.map((e) => Map<String, dynamic>.from(e as Map)));
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> removePendingReturn(String orderId, [String? uid]) {
    final previousLock = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;

    return previousLock.whenComplete(() async {
      try {
        final targetUid = uid ?? userId;
        final key = _userPendingReturnKey(targetUid);
        final currentQueue = getPendingReturns(targetUid);
        currentQueue.removeWhere((r) => r['orderId'] == orderId);

        if (currentQueue.isEmpty) {
          await _db.remove(key);
        } else {
          await _db.setString(key, jsonEncode(currentQueue));
        }
      } finally {
        completer.complete();
      }
    });
  }

  // ╔══════════════════════════════════════════╗
  // ║          قيم عامة (Generic API)         ║
  // ╚══════════════════════════════════════════╝
  static Future<void> setString(String key, String value) =>
      _db.setString(key, value);
  static Future<void> setBool(String key, bool value) =>
      _db.setBool(key, value);
  static Future<void> setInt(String key, int value) => _db.setInt(key, value);
  static Future<void> remove(String key) => _db.remove(key);

  static String? getString(String key) => _db.getString(key);
  static bool? getBool(String key) => _db.getBool(key);
  static int? getInt(String key) => _db.getInt(key);
  static bool hasKey(String key) => _db.containsKey(key);

  // ╔══════════════════════════════════════════╗
  // ║                  المسح                  ║
  // ╚══════════════════════════════════════════╝
  /// مسح بيانات المستخدم فقط مع الاحتفاظ بالإعدادات والطلبات المعلقة أوفلاين
  static Future<void> saveUserData({
    required String userId,
    required String role,
    String? name,
    String? phone,
    String? warehouseId,
    String? sessionToken,
  }) async {
    final batch = <Future>[
      _db.setString(_kUserId, userId),
      _db.setString(_kUserRole, role),
      _db.setString(_kLastLoginAt, DateTime.now().toIso8601String()),
    ];
    if (name != null) batch.add(_db.setString(_kUserName, name));
    if (phone != null) batch.add(_db.setString(_kUserPhone, phone));
    if (warehouseId != null) {
      batch.add(_db.setString(_kWarehouseId, warehouseId));
    }
    if (sessionToken != null) {
      try {
        await _secureStorage
            .write(key: _kSessionToken, value: sessionToken)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    await Future.wait(batch.cast<Future<void>>());
    if (kDebugMode) debugPrint('💾 LocalStorage: user saved — role=$role');
  }

  /// مسح كل شيء مع الاحتفاظ بحالة الفتح الأول والإعدادات
  static Future<void> clearAll() async {
    final isFirst = isFirstLaunch;
    final theme = themeMode;
    final lang = language;
    final onboard = isOnboardingDone;

    await _db.clear();

    await Future.wait([
      _db.setBool(_kFirstLaunch, isFirst),
      _db.setString(_kThemeMode, theme),
      _db.setString(_kLanguage, lang),
      _db.setBool(_kOnboardingDone, onboard),
    ]);
    if (kDebugMode) {
      debugPrint('🗑️ LocalStorage: cleared all (settings preserved)');
    }
  }

  /// مسح شامل كامل — عند حذف الحساب فقط
  static Future<void> nukeAll() async {
    await _db.clear();
    if (kDebugMode) debugPrint('💥 LocalStorage: full wipe');
  }

  // ╔══════════════════════════════════════════╗
  // ║            Debug / DevTools             ║
  // ╚══════════════════════════════════════════╝
  @visibleForTesting
  static void debugPrintAll() {
    assert(kDebugMode, 'debugPrintAll يجب ألا يُستدعى في production');
    if (!kDebugMode) return;
    final keys = _db.getKeys().where((k) => k != _kSessionToken).toList();
    debugPrint('━━━━━━ LocalStorage Debug ━━━━━━');
    for (final key in keys) {
      debugPrint('  $key = ${_db.get(key)}');
    }
    debugPrint('  session_token = [REDACTED]');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

// ── تسليمات السائق المعلقة (أوفلاين) ──
  static String _driverDeliveriesKey([String? uid]) =>
      '${_kPendingDeliveries}_${uid ?? userId ?? "driver"}';

  static Future<void> savePendingDriverDelivery(String orderId, [String? uid]) {
    final previousLock = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;

    return previousLock.whenComplete(() async {
      try {
        final targetUid = uid ?? userId;
        final key = _driverDeliveriesKey(targetUid);
        final queue = getPendingDriverDeliveries(targetUid);
        if (!queue.contains(orderId)) {
          queue.add(orderId);
          await _db.setString(key, jsonEncode(queue));
        }
      } finally {
        completer.complete();
      }
    });
  }

  static List<String> getPendingDriverDeliveries([String? uid]) {
    final targetUid = uid ?? userId;
    if (targetUid == null || targetUid.isEmpty) return [];
    final key = _driverDeliveriesKey(targetUid);
    final raw = _db.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return List<String>.from(decoded.map((e) => e.toString()));
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> removePendingDriverDelivery(String orderId,
      [String? uid]) {
    final previousLock = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;

    return previousLock.whenComplete(() async {
      try {
        final targetUid = uid ?? userId;
        final key = _driverDeliveriesKey(targetUid);
        final queue = getPendingDriverDeliveries(targetUid);
        queue.remove(orderId);
        if (queue.isEmpty) {
          await _db.remove(key);
        } else {
          await _db.setString(key, jsonEncode(queue));
        }
      } finally {
        completer.complete();
      }
    });
  }
}
