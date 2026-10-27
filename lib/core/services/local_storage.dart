import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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
  static String? _appDocsPath;
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  // ══════════════════════════════════════════
  // المفاتيح — private constants
  // ══════════════════════════════════════════
  static const _kUserId = 'user_id';
  static const _kUserRole = 'user_role';
  static const _kUserName = 'user_name';
  static const _kStoreName = 'store_name';
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
  static const _kPendingLedger =
      'pending_merchant_ledger_json'; // ✅ طابور حركات الدفتر أوفلاين

  // ══════════════════════════════════════════
  // التهيئة — يُستدعى مرة واحدة في main.dart
  // ══════════════════════════════════════════
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      if (!kIsWeb) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          _appDocsPath = dir.path;
        } catch (_) {}
      }
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

  /// 🔒 كتابة تزامنية مباشرة لقرص الهاتف (Crash-Safe) لمنع ضياع السلة عند الإغلاق الفجائي
  static void saveCartBackupSync(String uid, String jsonString,
      {String? revision}) {
    if (!kIsWeb && _appDocsPath != null) {
      try {
        if (revision != null) {
          final revisionFile = File('$_appDocsPath/sala_cart_v2_$uid.revision');
          revisionFile.writeAsStringSync(revision, flush: true);
        }
        final file = File('$_appDocsPath/sala_cart_v2_$uid.json');
        file.writeAsStringSync(jsonString, flush: true);
      } catch (_) {}
    }
  }

  // ╔══════════════════════════════════════════╗
  // ║           بيانات المستخدم               ║
  // ╚══════════════════════════════════════════╝
  static Future<void> clearUserData() async {
    final uid = userId;
    final clearSecureStorage = _secureStorage
        .delete(key: _kSessionToken)
        .timeout(const Duration(seconds: 2), onTimeout: () => null)
        .catchError((_) => null);

    final clearCartFile = Future<void>(() async {
      if (uid != null && !kIsWeb) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          final file = File('${dir.path}/sala_cart_v2_$uid.json');
          if (await file.exists()) await file.delete();
          final revisionFile = File('${dir.path}/sala_cart_v2_$uid.revision');
          if (await revisionFile.exists()) await revisionFile.delete();
        } catch (_) {}
      }
    });

    await Future.wait([
      clearSecureStorage,
      clearCartFile,
      _db.remove('first_login_at'),
      _db.remove(_kLastLoginAt),
      _db.remove(_kFcmToken),
      _db.remove(_kIsActive),
      _db.remove(_kIsBanned),
      _db.remove(_kUserId),
      _db.remove(_kUserRole),
      _db.remove(_kUserName),
      _db.remove(_kStoreName),
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
  static String? get storeName => _db.getString(_kStoreName);
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

  /// الجلسة تنتهي بعد [sessionDurationDays] يوماً من آخر نشاط.
  /// ملاحظة: last_login_at يُحدَّث تلقائياً من _SalaAppState.didChangeAppLifecycleState
  /// عند كل استئناف للتطبيق — لذا أجهزة POS النشطة لا تنتهي جلساتها.
  static bool get isSessionExpired {
    final lastLogin = lastLoginDateTime;
    if (lastLogin == null) return true;

    return DateTime.now().toUtc().difference(lastLogin.toUtc()) >
        const Duration(days: sessionDurationDays);
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
  static Future<void> savePendingOrder(Map<String, dynamic> order) async {
    final previousLock = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;

    try {
      await previousLock;
    } catch (_) {}

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
// 🔒 كتابة ذرية آمنة متوافقة مع أنظمة Android و iOS تضمن عدم تلف ملفات الطابور
      if (!kIsWeb && _appDocsPath != null) {
        try {
          final finalFile = File('$_appDocsPath/${key}_backup.json');
          final nonce = DateTime.now().microsecondsSinceEpoch;
          final tempFile = File('$_appDocsPath/${key}_tmp_$nonce.json');

          await tempFile.writeAsString(json, flush: true);

          // 🔒 استبدال ذري آمن بدون حذف مسبق: POSIX Atomic Rename
          try {
            await tempFile.rename(finalFile.path);
          } catch (_) {
            // حل بديل في حال قيود أنظمة الملفات بين الأقسام
            await tempFile.copy(finalFile.path);
            await tempFile.delete().catchError((_) => tempFile);
          }
        } catch (_) {
          try {
            final finalFile = File('$_appDocsPath/${key}_backup.json');
            await finalFile.writeAsString(json, flush: true);
          } catch (_) {}
        }
      }
    } finally {
      completer.complete();
    }
  }

  /// يرجع جميع الطلبات المعلقة في الطابور للمستخدم الحالي فقط
  static List<Map<String, dynamic>> getPendingOrders([String? uid]) {
    final targetUid = uid ?? userId;
    if (targetUid == null || targetUid.isEmpty) return [];
    final key = _userPendingOrderKey(targetUid);
    var raw = _db.getString(key);
    // 🔒 قراءة نظيفة موحدة: فحص الملف الاحتياطي الدائم ثم الملفات المؤقتة الأحدث عند وجود تعطل
    if ((raw == null || raw.isEmpty) && !kIsWeb && _appDocsPath != null) {
      try {
        final file = File('$_appDocsPath/${key}_backup.json');
        if (file.existsSync()) {
          raw = file.readAsStringSync();
        } else {
          final dir = Directory(_appDocsPath!);
          if (dir.existsSync()) {
            final candidates = dir
                .listSync()
                .whereType<File>()
                .where(
                  (f) =>
                      f.path.contains('${key}_tmp_') &&
                      f.path.endsWith('.json'),
                )
                .toList();
            if (candidates.isNotEmpty) {
              candidates.sort((a, b) =>
                  b.lastModifiedSync().compareTo(a.lastModifiedSync()));
              raw = candidates.first.readAsStringSync();
              try {
                candidates.first.copySync(file.path);
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    }
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

  /// يحذف طلباً محدداً من الطابور ويحدث ملف القرص الدائم وينظف كافة الملفات المؤقتة لمنع قيامة الطلبات القديمة نهائياً
  static Future<void> removePendingOrder(String orderId, [String? uid]) async {
    final previousLock = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;

    try {
      await previousLock;
    } catch (_) {}

    try {
      final targetUid = uid ?? userId;
      final key = _userPendingOrderKey(targetUid);
      final currentQueue = getPendingOrders(targetUid);
      currentQueue.removeWhere((order) => order['orderId'] == orderId);

      // تنظيف شامل وجذري لكافة الملفات المؤقتة التابعة لهذا المفتاح
      if (!kIsWeb && _appDocsPath != null) {
        try {
          final dir = Directory(_appDocsPath!);
          if (dir.existsSync()) {
            final leftovers = dir.listSync().whereType<File>().where(
                  (f) =>
                      f.path.contains('${key}_tmp_') &&
                      f.path.endsWith('.json'),
                );
            for (final f in leftovers) {
              try {
                f.deleteSync();
              } catch (_) {}
            }
          }
        } catch (_) {}
      }

      if (currentQueue.isEmpty) {
        await _db.remove(key);
        await _db.remove(_kPendingOrder);
        if (!kIsWeb && _appDocsPath != null) {
          try {
            final backupFile = File('$_appDocsPath/${key}_backup.json');
            final tmpFile = File('$_appDocsPath/${key}_backup.tmp');
            if (await backupFile.exists()) await backupFile.delete();
            if (await tmpFile.exists()) await tmpFile.delete();
          } catch (_) {}
        }
      } else {
        final json = jsonEncode(currentQueue);
        await _db.setString(key, json);
        if (!kIsWeb && _appDocsPath != null) {
          try {
            final backupFile = File('$_appDocsPath/${key}_backup.json');
            final nonce = DateTime.now().microsecondsSinceEpoch;
            final tmpFile = File('$_appDocsPath/${key}_backup_$nonce.tmp');
            await tmpFile.writeAsString(json, flush: true);
            await tmpFile.rename(backupFile.path);
          } catch (_) {}
        }
      }
    } finally {
      completer.complete();
    }
  }

  static Future<void> clearPendingOrder([String? uid]) async {
    final targetUid = uid ?? userId;
    if (targetUid != null && targetUid.isNotEmpty) {
      final key = _userPendingOrderKey(targetUid);
      await _db.remove(key);
      if (!kIsWeb && _appDocsPath != null) {
        try {
          final backupFile = File('$_appDocsPath/${key}_backup.json');
          final tmpFile = File('$_appDocsPath/${key}_backup.tmp');
          if (await backupFile.exists()) await backupFile.delete();
          if (await tmpFile.exists()) await tmpFile.delete();
        } catch (_) {}
      }
    }
    await _db.remove(_kPendingOrder);
  }

  // ── حركات الدفتر المعلقة (أوفلاين - حماية أموال التاجر) ──
  static String _userPendingLedgerKey([String? uid]) =>
      '${_kPendingLedger}_${uid ?? userId ?? "anonymous"}';
  static Future<void> savePendingLedgerTx(Map<String, dynamic> txData) async {
    final previousLock = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;

    try {
      await previousLock;
    } catch (_) {}

    try {
      final targetUid = txData['merchant_id']?.toString() ?? userId;
      final key = _userPendingLedgerKey(targetUid);
      final queue = getPendingLedgerTxs(targetUid);
      final txId = txData['id']?.toString() ?? '';
      if (txId.isNotEmpty && queue.any((t) => t['id'] == txId)) {
        return;
      }
      queue.add(txData);
      final json = jsonEncode(queue);
      await _db.setString(key, json);

      // 🔒 كتابة ذرية آمنة لحركات الدفتر على القرص لمنع فقدان ديون التجار عند انهيار التطبيق
      if (!kIsWeb && _appDocsPath != null) {
        try {
          final nonce = DateTime.now().microsecondsSinceEpoch;
          final tempFile = File('$_appDocsPath/${key}_tmp_$nonce.json');
          final finalFile = File('$_appDocsPath/${key}_backup.json');
          await tempFile.writeAsString(json, flush: true);
          await tempFile.rename(finalFile.path);
        } catch (_) {}
      }
    } finally {
      completer.complete();
    }
  }

  static List<Map<String, dynamic>> getPendingLedgerTxs([String? uid]) {
    final targetUid = uid ?? userId;
    if (targetUid == null || targetUid.isEmpty) return [];
    final key = _userPendingLedgerKey(targetUid);
    var raw = _db.getString(key);

    // 🔒 استعادة ذرية من القرص الصلب فوراً في حال فقدان بيانات SharedPreferences
    if ((raw == null || raw.isEmpty) && !kIsWeb && _appDocsPath != null) {
      try {
        final backupFile = File('$_appDocsPath/${key}_backup.json');
        if (backupFile.existsSync()) {
          raw = backupFile.readAsStringSync();
        }
      } catch (_) {}
    }

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

  static Future<void> removePendingLedgerTx(String txId, [String? uid]) async {
    final previousLock = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;

    try {
      await previousLock;
    } catch (_) {}

    try {
      final targetUid = uid ?? userId;
      final key = _userPendingLedgerKey(targetUid);
      final queue = getPendingLedgerTxs(targetUid);
      queue.removeWhere((t) => t['id'] == txId);

      if (queue.isEmpty) {
        await _db.remove(key);
        if (!kIsWeb && _appDocsPath != null) {
          try {
            final backupFile = File('$_appDocsPath/${key}_backup.json');
            if (await backupFile.exists()) await backupFile.delete();
          } catch (_) {}
        }
      } else {
        final json = jsonEncode(queue);
        await _db.setString(key, json);
        if (!kIsWeb && _appDocsPath != null) {
          try {
            final backupFile = File('$_appDocsPath/${key}_backup.json');
            final nonce = DateTime.now().microsecondsSinceEpoch;
            final tmpFile = File('$_appDocsPath/${key}_backup_$nonce.tmp');
            await tmpFile.writeAsString(json, flush: true);
            await tmpFile.rename(backupFile.path);
          } catch (_) {}
        }
      }
    } finally {
      completer.complete();
    }
  }

  // ── طلبات الإرجاع المعلقة (أوفلاين) ──
  static String _userPendingReturnKey([String? uid]) =>
      '${_kPendingReturns}_${uid ?? userId ?? "anonymous"}';
  static Future<void> savePendingReturn(Map<String, dynamic> returnData) async {
    final previousLock = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;

    try {
      await previousLock;
    } catch (_) {}

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
      final json = jsonEncode(currentQueue);
      await _db.setString(key, json);

      // 🔒 كتابة ذرية لطلبات الإرجاع أوفلاين على القرص
      if (!kIsWeb && _appDocsPath != null) {
        try {
          final nonce = DateTime.now().microsecondsSinceEpoch;
          final tempFile = File('$_appDocsPath/${key}_tmp_$nonce.json');
          final finalFile = File('$_appDocsPath/${key}_backup.json');
          await tempFile.writeAsString(json, flush: true);
          await tempFile.rename(finalFile.path);
        } catch (_) {}
      }
    } finally {
      completer.complete();
    }
  }

  static List<Map<String, dynamic>> getPendingReturns([String? uid]) {
    final targetUid = uid ?? userId;
    if (targetUid == null || targetUid.isEmpty) return [];
    final key = _userPendingReturnKey(targetUid);
    var raw = _db.getString(key);
    if ((raw == null || raw.isEmpty) && !kIsWeb && _appDocsPath != null) {
      try {
        final file = File('$_appDocsPath/${key}_backup.json');
        if (file.existsSync()) {
          raw = file.readAsStringSync();
        }
      } catch (_) {}
    }
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

  static Future<void> removePendingReturn(String orderId, [String? uid]) async {
    final previousLock = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;

    try {
      await previousLock;
    } catch (_) {}

    try {
      final targetUid = uid ?? userId;
      final key = _userPendingReturnKey(targetUid);
      final currentQueue = getPendingReturns(targetUid);
      currentQueue.removeWhere((r) => r['orderId'] == orderId);

      if (currentQueue.isEmpty) {
        await _db.remove(key);
        if (!kIsWeb && _appDocsPath != null) {
          try {
            final backupFile = File('$_appDocsPath/${key}_backup.json');
            if (await backupFile.exists()) await backupFile.delete();
          } catch (_) {}
        }
      } else {
        final json = jsonEncode(currentQueue);
        await _db.setString(key, json);
        if (!kIsWeb && _appDocsPath != null) {
          try {
            final backupFile = File('$_appDocsPath/${key}_backup.json');
            final nonce = DateTime.now().microsecondsSinceEpoch;
            final tmpFile = File('$_appDocsPath/${key}_backup_$nonce.tmp');
            await tmpFile.writeAsString(json, flush: true);
            await tmpFile.rename(backupFile.path);
          } catch (_) {}
        }
      }
    } finally {
      completer.complete();
    }
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
    String? storeName,
    String? phone,
    String? warehouseId,
    String? sessionToken,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    final batch = <Future>[
      _db.setString(_kUserId, userId),
      _db.setString(_kUserRole, role),
      _db.setString(_kLastLoginAt, nowIso),
    ];
    // ✅ كتابة تاريخ أول دخول إذا لم يكن مسجلاً لتفعيل سقف الـ 90 يوماً
    if (!hasKey('first_login_at')) {
      batch.add(_db.setString('first_login_at', nowIso));
    }
    if (name != null) batch.add(_db.setString(_kUserName, name));
    if (storeName != null) batch.add(_db.setString(_kStoreName, storeName));
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

// ── تسليمات السائق المعلقة (أوفلاين مع حفظ التوقيع الرقمي) ──
  static String _driverDeliveriesKey([String? uid]) =>
      '${_kPendingDeliveries}_${uid ?? userId ?? "driver"}';
  static Future<void> savePendingDriverDelivery(
    String orderId, {
    String? signatureUrl,
    String? uid,
  }) async {
    final previousLock = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;

    try {
      await previousLock;
    } catch (_) {}

    try {
      final targetUid = uid ?? userId;
      final key = _driverDeliveriesKey(targetUid);
      final queue = getPendingDriverDeliveriesPayload(targetUid);
      queue.removeWhere((item) => item['orderId'] == orderId);

      String? finalSignatureRef = signatureUrl;
      if (signatureUrl != null &&
          signatureUrl.startsWith('data:image') &&
          !kIsWeb) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          final sigFile = File('${dir.path}/sig_${orderId}.b64');
          await sigFile.writeAsString(signatureUrl, flush: true);
          finalSignatureRef = 'file://${sigFile.path}';
        } catch (_) {}
      }

      queue.add({
        'orderId': orderId,
        if (finalSignatureRef != null && finalSignatureRef.isNotEmpty)
          'signatureUrl': finalSignatureRef,
        'timestamp': DateTime.now().toIso8601String(),
      });
      await _db.setString(key, jsonEncode(queue));
    } finally {
      completer.complete();
    }
  }

  static List<Map<String, dynamic>> getPendingDriverDeliveriesPayload(
      [String? uid]) {
    final targetUid = uid ?? userId;
    if (targetUid == null || targetUid.isEmpty) return [];
    final key = _driverDeliveriesKey(targetUid);
    final raw = _db.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return List<Map<String, dynamic>>.from(decoded.map((e) {
          if (e is Map) return Map<String, dynamic>.from(e);
          return {'orderId': e.toString()};
        }));
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static List<String> getPendingDriverDeliveries([String? uid]) {
    return getPendingDriverDeliveriesPayload(uid)
        .map((e) => e['orderId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  static Future<void> removePendingDriverDelivery(String orderId,
      [String? uid]) async {
    final previousLock = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;

    try {
      await previousLock;
    } catch (_) {}

    try {
      final targetUid = uid ?? userId;
      final key = _driverDeliveriesKey(targetUid);
      final queue = getPendingDriverDeliveriesPayload(targetUid);
      queue.removeWhere((item) => item['orderId'] == orderId);
      if (queue.isEmpty) {
        await _db.remove(key);
      } else {
        await _db.setString(key, jsonEncode(queue));
      }

      // تنظيف ملف التوقيع المؤقت من القرص فور إزالة المهمة
      if (!kIsWeb && _appDocsPath != null) {
        try {
          final sigFile = File('$_appDocsPath/sig_${orderId}.b64');
          if (sigFile.existsSync()) sigFile.deleteSync();
        } catch (_) {}
      }
    } finally {
      completer.complete();
    }
  }
}
