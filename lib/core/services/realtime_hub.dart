import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'local_storage.dart';
import 'notification_service.dart';

// ══════════════════════════════════════════════════════════
//  RealtimeHub — Production-Grade
//
//  ① لا .timeout() — Firestore SDK يدير timeout داخلياً
//  ② لا for-loop retries — retry واحد فقط مع backoff
//  ③ _silently() يمسك كل exception بصمت — لا debugger pause
//  ④ StateNotifier.mounted محفوظ — StateNotifier يدعمه
//  ⑤ Heartbeat خفيف بدون .timeout() لتجنب freeze
// ══════════════════════════════════════════════════════════

enum RealtimeStatus { connecting, connected, disconnected }

final realtimeStatusProvider = StateProvider<RealtimeStatus>(
  (ref) => RealtimeStatus.connecting,
);

// ══════════════════════════════════════════════════════════
//  Providers
// ══════════════════════════════════════════════════════════

final merchantOrdersProvider =
    StateNotifierProvider<_OrdersNotifier, List<Map<String, dynamic>>>(
  (ref) => _OrdersNotifier(),
);

final realtimeNotifsProvider =
    StateNotifierProvider<_NotificationsNotifier, List<Map<String, dynamic>>>(
  (ref) => _NotificationsNotifier(),
);

final unreadCountProvider = Provider<int>((ref) {
  return ref
      .watch(realtimeNotifsProvider)
      .where((n) => n['is_read'] == false)
      .length;
});

final realtimeProductsProvider =
    StateNotifierProvider<_ProductsNotifier, List<Map<String, dynamic>>>(
  (ref) => _ProductsNotifier(),
);

final realtimeCategoriesProvider =
    StateNotifierProvider<_CategoriesNotifier, List<Map<String, dynamic>>>(
  (ref) => _CategoriesNotifier(),
);

final realtimeBrandsProvider =
    StateNotifierProvider<_BrandsNotifier, List<Map<String, dynamic>>>(
  (ref) => _BrandsNotifier(),
);

// ══ Admin — كل الطلبات لحظياً ══
final realtimeAllOrdersProvider =
    StateNotifierProvider<_AllOrdersNotifier, List<Map<String, dynamic>>>(
  (ref) => _AllOrdersNotifier(),
);

// ══ Driver — الطلبات المؤكدة غير المسندة ══
final realtimeConfirmedOrdersProvider =
    StateNotifierProvider<_ConfirmedOrdersNotifier, List<Map<String, dynamic>>>(
  (ref) => _ConfirmedOrdersNotifier(),
);

// ══ Driver — طلباته هو (shipped) ══
final realtimeMyShippedOrdersProvider =
    StateNotifierProvider<_MyShippedOrdersNotifier, List<Map<String, dynamic>>>(
  (ref) => _MyShippedOrdersNotifier(),
);

// ══ Driver — callback عند وصول طلب جديد ══
final driverNewOrderCallbackProvider =
    StateProvider<void Function(String, Map<String, dynamic>)?>((_) => null);

Future<T?> _silently<T>(
  Future<T> Function() task, {
  String tag = 'hub',
}) async {
  try {
    return await task();
  } on FirebaseException catch (e, st) {
    if (e.code == 'permission-denied') {
      debugPrint(
          '🚨 [$tag] PERMISSION DENIED — راجع Firestore Rules: ${e.message}');
    } else {
      if (kDebugMode) {
        debugPrint('⚠️ [$tag] Firebase error (${e.code}): ${e.message}');
      }
    }
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'Firebase error in RealtimeHub [$tag] (${e.code})',
        fatal: false,
      );
    }
    return null;
  } catch (e, st) {
    if (kDebugMode) debugPrint('⚠️ [$tag] silent error: $e');
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'Silent error in RealtimeHub [$tag]',
        fatal: false,
      );
    }
    return null;
  }
}

// ══════════════════════════════════════════════════════════
//  الخدمة الرئيسية — Singleton
// ══════════════════════════════════════════════════════════
class RealtimeHub {
  static final RealtimeHub _instance = RealtimeHub._();
  factory RealtimeHub() => _instance;
  RealtimeHub._();

  final _db = FirebaseFirestore.instance;
  final List<StreamSubscription> _userSubs = [];
  ProviderContainer? _container;
  bool _initialized = false;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int reconnectAttempts = 0;

  static const int _productsPageSize = 100;

  // ── التهيئة (تحسين التكلفة لآلاف المستخدمين) ───────────────
  void init(ProviderContainer container) {
    if (_initialized) return;
    _initialized = true;
    _container = container;

    _container?.read(realtimeStatusProvider.notifier).state =
        RealtimeStatus.connected;

    // 🚀 جلب أولي خفيف عند تشغيل التطبيق
    _watchCategories();
    _watchBrands();

    final userId = AppStorage.userId ?? '';
    if (userId.isNotEmpty) {
      unawaited(
        startForUser(
          userId,
          role: AppStorage.userRole ?? 'merchant',
        ),
      );
    }

    _startHeartbeat();
  }

  // ── Heartbeat ──────────────────────────────────────────
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
  }

  // ── قنوات تعتمد على userId ────────────────────────────────
  Future<void> startForUser(
    String userId, {
    String role = 'merchant',
  }) async {
    if (userId.isEmpty) return;

    // ✅ إعادة تعيين حالة التشغيل تلقائياً إذا تم تسجيل الدخول بعد تسجيل خروج مسبق
    if (!_initialized && _container != null) {
      _initialized = true;
      _setConnected();
      _startHeartbeat();
    }

    await _stopUserChannels();

    _startUserChannels(
      userId,
      role: role.toLowerCase().trim(),
    );
  }

  void _startUserChannels(String userId, {required String role}) {
    _watchCategories();
    _watchBrands();

    final profileSub =
        _db.collection('profiles').doc(userId).snapshots().listen((doc) async {
      if (!doc.exists || doc.data() == null) return;
      final data = doc.data()!;
      final isBanned = data['is_banned'] == true;
      final isActive = data['is_active'] as bool? ?? true;
      final newRole = (data['role'] as String?)?.trim().toLowerCase() ?? role;
// ✅ التقاط الحالة السابقة من التخزين المحلي قبل استبدالها بالقيمة الجديدة من السيرفر
      final bool wasInactive = !AppStorage.isActive;

      await AppStorage.setIsBanned(isBanned);
      await AppStorage.setIsActive(isActive);

      if (isBanned || (!isActive && data['account_status'] != 'pending')) {
        dispose();
        try {
          await NotificationService.instance
              .detachTokenFromFirestore(userId)
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
        await FirebaseAuth.instance.signOut();
        await AppStorage.clearUserData();
        NotificationService.navigatorKey.currentContext?.go('/login');
        return;
      }
// ✅ التوجيه التلقائي المباشر فور موافقة الإدارة وتفعيل الحساب بحسب دور المستخدم
      if (wasInactive && isActive) {
        await AppStorage.setIsActive(true);
        final targetRoute = switch (newRole) {
          'admin' ||
          'super_admin' ||
          'accountant' ||
          'warehouse_manager' =>
            '/admin',
          'driver' => '/driver',
          _ => '/merchant',
        };
        NotificationService.navigatorKey.currentContext?.go(targetRoute);
        return;
      }

      if (newRole != AppStorage.userRole) {
        await AppStorage.saveUserData(
          userId: userId,
          role: newRole,
          name: data['full_name'] as String?,
          phone: data['phone_number'] as String?,
        );
        unawaited(startForUser(userId, role: newRole));
        final targetRoute = switch (newRole) {
          'admin' ||
          'super_admin' ||
          'accountant' ||
          'warehouse_manager' =>
            '/admin',
          'driver' => '/driver',
          _ => '/merchant',
        };
        NotificationService.navigatorKey.currentContext?.go(targetRoute);
      }
    }, onError: (_) {});
    _userSubs.add(profileSub);

    _watchNotifications(userId);
    if (role == 'admin' ||
        role == 'super_admin' ||
        role == 'accountant' ||
        role == 'warehouse_manager') {
      _watchAllOrders();
    } else if (role == 'driver') {
      _watchConfirmedOrders();
      _watchMyShippedOrders(userId);
    } else {
      _watchOrders(userId);
    }
  }

  Future<void> _stopUserChannels() async {
    final subscriptions = List<StreamSubscription>.from(_userSubs);
    _userSubs.clear();

    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );

    _container?.read(merchantOrdersProvider.notifier).clear();
    _container?.read(realtimeNotifsProvider.notifier).clear();
    _container?.read(realtimeAllOrdersProvider.notifier).clear();
    _container?.read(realtimeConfirmedOrdersProvider.notifier).clear();
    _container?.read(realtimeMyShippedOrdersProvider.notifier).clear();
  }

  // ── مراقبة طلبات التاجر ──────────────────────────────────
  void _watchOrders(String merchantId) {
    // تم إلغاء الاستماع الخلفي المزدوج لتوفير فواتير Firebase؛ شاشات التاجر تفتح طلباتها عند الحاجة
  }
// ── مراقبة الإشعارات وإطلاق الصوت والتنبيه فوراً ────────────
  void _watchNotifications(String userId) {
    if (userId.isEmpty) return;

    unawaited(_container?.read(realtimeNotifsProvider.notifier).reload(userId));

    bool isFirstLoad = true;
    final Set<String> knownNotifIds = {};

    // 🚀 إزالة الترتيب السحابي لتجاوز خطأ الفهرس، والفرز يتم في الذاكرة
    final sub = _db
        .collection('user_notifications')
        .where('user_id', isEqualTo: userId)
        .limit(50)
        .snapshots()
        .listen(
      (snap) {
        final data = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        data.sort((a, b) {
          final aDate = a['created_at'] is Timestamp
              ? (a['created_at'] as Timestamp).toDate()
              : DateTime(2000);
          final bDate = b['created_at'] is Timestamp
              ? (b['created_at'] as Timestamp).toDate()
              : DateTime(2000);
          return bDate.compareTo(aDate);
        });
        _container?.read(realtimeNotifsProvider.notifier).update(data);
        _setConnected();

        // ✅ تحديث قائمة الإشعارات في الخلفية وتحديث العداد، مع ترك عرض الإشعار المنبثق لخوادم Firebase (FCM) لمنع التكرار
        if (!isFirstLoad) {
          for (final change in snap.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final id = change.doc.id;
              if (!knownNotifIds.contains(id)) {
                knownNotifIds.add(id);
                // تم إزالة NotificationService.instance.showLocalNotification
                // لأن Firebase Functions ترسل الإشعار الفعلي للجهاز مسبقاً.
              }
            }
          }
        } else {
          isFirstLoad = false;
          for (final d in snap.docs) {
            knownNotifIds.add(d.id);
          }
        }
      },
      onError: (e) {
        if (kDebugMode) debugPrint('❌ _watchNotifications error: $e');
        _scheduleReconnect();
      },
    );
    _userSubs.add(sub);
  }

  // ── تحميل المنتجات ────────────────────────────────────────
  void watchProducts() {
    if ((_container?.read(realtimeProductsProvider).length ?? 0) == 0) {
      unawaited(_container?.read(realtimeProductsProvider.notifier).reload());
    }
  }

  // ── جلب الأصناف مرة واحدة ─────────────────────────────────
  void _watchCategories() {
    unawaited(_container?.read(realtimeCategoriesProvider.notifier).reload());
  }

  // ── جلب الماركات مرة واحدة ────────────────────────────────
  void _watchBrands() {
    unawaited(_container?.read(realtimeBrandsProvider.notifier).reload());
  }

  // ── Admin: كل الطلبات ────────────────────────────────────
  void _watchAllOrders() {
    // تم إلغاء الاستماع الخلفي المزدوج لأن شاشات الإدارة تفتح استعلاماتها عند الطلب
  }
// ── Driver: الطلبات المؤكدة غير المسندة ──────────────────
  void _watchConfirmedOrders() {
    bool firstLoad = true;
    Set<String> seenIds = {};

    final sub = _db
        .collection('orders')
        .where('status', isEqualTo: 'confirmed')
        .limit(100)
        .snapshots()
        .listen(
      (snap) {
        final data = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        data.sort((a, b) {
          final aDate = a['created_at'] is Timestamp
              ? (a['created_at'] as Timestamp).toDate()
              : DateTime(2000);
          final bDate = b['created_at'] is Timestamp
              ? (b['created_at'] as Timestamp).toDate()
              : DateTime(2000);
          return bDate.compareTo(aDate);
        });

        _container?.read(realtimeConfirmedOrdersProvider.notifier).update(data);
        _setConnected();

        // إشعار السائق بالطلب الجديد مع إطلاق صوت الرنين
        final currentIds = {for (final d in snap.docs) d.id};
        if (!firstLoad) {
          final newIds = currentIds.difference(seenIds);
          for (final id in newIds) {
            final doc = snap.docs.firstWhere((d) => d.id == id);
            final order = {'id': doc.id, ...doc.data()};
            final assignedDriver = order['driver_id'] as String?;
            if (assignedDriver != null && assignedDriver.isNotEmpty) continue;

            // 🚀 تشغيل نغمة الإشعار مع الصوت والتنبيه للسائق
            NotificationService.instance.showLocalNotification(
              title: '🚨 طلب جديد وصلك!',
              body:
                  'طلب جديد جاهز للتوصيل بقيمة ${(order['total'] ?? order['total_amount'] ?? 0)} ر.ي',
              payload: '/driver',
            );

            _container?.read(driverNewOrderCallbackProvider)?.call(id, order);
          }
        }
        firstLoad = false;
        seenIds.addAll(currentIds);
        if (seenIds.length > 500) {
          seenIds = currentIds;
        }
      },
      onError: (e) {
        if (kDebugMode) debugPrint('❌ _watchConfirmedOrders error: $e');
        _scheduleReconnect();
      },
    );
    _userSubs.add(sub);
  }

  // ── Driver: طلباته هو المُسنَدة (shipped) ─────────────────
  void _watchMyShippedOrders(String driverId) {
    if (driverId.isEmpty) return;
    final sub = _db
        .collection('orders')
        .where('status', isEqualTo: 'shipped')
        .where('driver_id', isEqualTo: driverId)
        .snapshots()
        .listen(
      (snap) {
        final data = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        data.sort((a, b) {
          final aDate = a['created_at'] is Timestamp
              ? (a['created_at'] as Timestamp).toDate()
              : DateTime(2000);
          final bDate = b['created_at'] is Timestamp
              ? (b['created_at'] as Timestamp).toDate()
              : DateTime(2000);
          return bDate.compareTo(aDate);
        });
        _container?.read(realtimeMyShippedOrdersProvider.notifier).update(data);
        _setConnected();
      },
      onError: (e) {
        if (kDebugMode) debugPrint('❌ _watchMyShippedOrders error: $e');
        _scheduleReconnect();
      },
    );
    _userSubs.add(sub);
  }

  // ── إدارة الحالة ──────────────────────────────────────────
  void _setConnected() {
    _reconnectTimer?.cancel();
    reconnectAttempts = 0;
    _container?.read(realtimeStatusProvider.notifier).state =
        RealtimeStatus.connected;
  }

  void _scheduleReconnect() {
    _container?.read(realtimeStatusProvider.notifier).state =
        RealtimeStatus.disconnected;

    // 🚀 إعادة الاتصال التصاعدي (Exponential Backoff) لإنعاش الـ Streams في حال توقفت نهائياً.
    reconnectAttempts++;
    if (reconnectAttempts < 6) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(seconds: 3 * reconnectAttempts), () {
        if (_initialized) restart();
      });
    }
  }

  // ── إعادة التشغيل ─────────────────────────────────────────
  void restart() {
    unawaited(_restartAsync());
  }

  Future<void> _restartAsync() async {
    _reconnectTimer?.cancel();
    final subscriptions = List<StreamSubscription>.from(_userSubs);
    _userSubs.clear();

    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );

    _initialized = false;

    final container = _container;
    if (container != null) {
      init(container);
    }
  }

// ── الإيقاف الكامل ────────────────────────────────────────
  void dispose() {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    for (final s in _userSubs) {
      s.cancel();
    }
    _userSubs.clear();

    // تنظيف الحالات المحفوظة
    _container?.read(merchantOrdersProvider.notifier).clear();
    _container?.read(realtimeNotifsProvider.notifier).clear();
    _container?.read(realtimeAllOrdersProvider.notifier).clear();
    _container?.read(realtimeConfirmedOrdersProvider.notifier).clear();
    _container?.read(realtimeMyShippedOrdersProvider.notifier).clear();

    // لا نقوم بتصفير _container = null لأن الـ App Container حي ومستمر
    _initialized = false;
    reconnectAttempts = 0;
  }
}

// ══════════════════════════════════════════════════════════
//  Notifiers — StateNotifier يدعم .mounted بشكل طبيعي
// ══════════════════════════════════════════════════════════

class _OrdersNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  _OrdersNotifier() : super([]);
  final _db = FirebaseFirestore.instance;
  Future<void> reload(String merchantId) async {
    if (merchantId.isEmpty) return;
    final docs = await _silently(
      () async {
        final snap = await _db
            .collection('orders')
            .where('merchant_id', isEqualTo: merchantId)
            .limit(200)
            .get();
        final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList()
          ..sort((a, b) {
            DateTime parse(dynamic v) {
              if (v is Timestamp) return v.toDate();
              if (v is DateTime) return v;
              if (v is String) return DateTime.tryParse(v) ?? DateTime(2000);
              return DateTime(2000);
            }

            return parse(b['created_at']).compareTo(parse(a['created_at']));
          });
        return list;
      },
      tag: 'orders-reload',
    );
    if (docs != null && mounted) state = docs;
  }

  void update(List<Map<String, dynamic>> data) {
    if (!mounted) return;
    // ✅ إزالة الفحص `identical` الذي لم يكن فعّالاً أبداً (القائمة data دائماً كائن جديد)
    state = data;
  }

  void clear() {
    if (mounted) state = [];
  }
}

class _NotificationsNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  _NotificationsNotifier() : super([]);
  final _db = FirebaseFirestore.instance;

  Future<void> reload(String userId) async {
    if (userId.isEmpty) return;
    final docs = await _silently(
      () async {
        // ✅ إزالة الترتيب السحابي لمنع تعطل الاستعلام، والفرز الزمني يتم في الذاكرة
        final snap = await _db
            .collection('user_notifications')
            .where('user_id', isEqualTo: userId)
            .limit(50)
            .get();
        final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList()
          ..sort((a, b) {
            DateTime parse(dynamic v) {
              if (v is Timestamp) return v.toDate();
              if (v is DateTime) return v;
              if (v is String) return DateTime.tryParse(v) ?? DateTime(2000);
              return DateTime(2000);
            }

            return parse(b['created_at']).compareTo(parse(a['created_at']));
          });
        return list;
      },
      tag: 'notifs-reload',
    );
    if (docs != null && mounted) state = docs;
  }

  void update(List<Map<String, dynamic>> data) {
    if (mounted) state = data;
  }

  Future<void> markRead(String id) async {
    await _silently(
      () async {
        await _db
            .collection('user_notifications')
            .doc(id)
            .update({'is_read': true});
        if (mounted) {
          state = state
              .map((n) => n['id'] == id ? {...n, 'is_read': true} : n)
              .toList();
        }
      },
      tag: 'notifs-markRead',
    );
  }

  Future<void> markAllRead(String userId) async {
    await _silently(
      () async {
        final snap = await _db
            .collection('user_notifications')
            .where('user_id', isEqualTo: userId)
            .where('is_read', isEqualTo: false)
            .get();
        final docs = snap.docs;
        const chunkSize = 400;
        for (int i = 0; i < docs.length; i += chunkSize) {
          final chunk = docs.sublist(
              i, (i + chunkSize > docs.length) ? docs.length : i + chunkSize);
          final batch = _db.batch();
          for (final doc in chunk) {
            batch.update(doc.reference, {'is_read': true});
          }
          await batch.commit();
        }
        if (mounted) {
          state = state.map((n) => {...n, 'is_read': true}).toList();
        }
      },
      tag: 'notifs-markAllRead',
    );
  }

  void clear() {
    if (mounted) state = [];
  }
}

class _ProductsNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  _ProductsNotifier() : super([]);

  final _db = FirebaseFirestore.instance;

  bool _isLoadingMore = false;
  String? _lastLoadedCursor;
  String? _activeBrandId;

  Future<void> reload({String? brandId}) async {
    _activeBrandId = brandId;
    _lastLoadedCursor = null;
    final docs = await _silently(
      () async {
        Query<Map<String, dynamic>> query = _db.collection('products');
        if (brandId != null) {
          query = query.where('brand_id', isEqualTo: brandId);
        }
        final snap = await query
            .orderBy('name')
            .limit(RealtimeHub._productsPageSize)
            .get();
        final list = snap.docs
            .where((d) =>
                d.data()['is_active'] != false &&
                d.data()['is_deleted'] != true)
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
        return list;
      },
      tag: 'products-reload',
    );
    if (docs != null && mounted) state = docs;
  }

  Future<void> loadMore(DocumentSnapshot lastDoc) async {
    if (!mounted || _isLoadingMore || _lastLoadedCursor == lastDoc.id) return;

    _isLoadingMore = true;
    _lastLoadedCursor = lastDoc.id;

    try {
      Query<Map<String, dynamic>> query = _db.collection('products');
      if (_activeBrandId != null) {
        query = query.where('brand_id', isEqualTo: _activeBrandId);
      }
      final snap = await query
          .orderBy('name')
          .startAfterDocument(lastDoc)
          .limit(RealtimeHub._productsPageSize)
          .get();
      if (!mounted || snap.docs.isEmpty) {
        return;
      }

      final more = snap.docs
          .where((d) =>
              d.data()['is_active'] != false && d.data()['is_deleted'] != true)
          .map((d) {
        return {
          'id': d.id,
          ...d.data(),
        };
      }).toList();

      final productsById = <String, Map<String, dynamic>>{
        for (final product in state) product['id'].toString(): product,
      };

      for (final product in more) {
        productsById[product['id'].toString()] = product;
      }

      state = productsById.values.toList();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('products-loadMore failed: $error');
      }
      _lastLoadedCursor = null;
    } finally {
      _isLoadingMore = false;
    }
  }

  void update(List<Map<String, dynamic>> data) {
    if (!mounted) return;
    if (state.length <= RealtimeHub._productsPageSize) {
      state = data;
    } else {
      final activeIncomingIds = data.map((e) => e['id'].toString()).toSet();
      final mergedMap = <String, Map<String, dynamic>>{
        for (final item in state)
          if (!activeIncomingIds.contains(item['id'].toString()))
            item['id'].toString(): item,
      };
      for (final item in data) {
        mergedMap[item['id'].toString()] = item;
      }
      state = mergedMap.values.toList();
    }
  }
}

class _CategoriesNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  _CategoriesNotifier() : super([]);
  final _db = FirebaseFirestore.instance;

  DateTime? _lastFetch;

  Future<void> reload() async {
    if (state.isNotEmpty &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 30)) {
      return;
    }
    final docs = await _silently(
      () async {
        final snap =
            await _db.collection('categories').orderBy('sort_order').get();
        return snap.docs
            .where((d) =>
                d.data()['is_active'] != false &&
                d.data()['is_deleted'] != true)
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
      },
      tag: 'categories-reload',
    );
    if (docs != null && mounted) {
      state = docs;
      _lastFetch = DateTime.now();
    }
  }

  void update(List<Map<String, dynamic>> data) {
    if (mounted) state = data;
  }
}

class _BrandsNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  _BrandsNotifier() : super([]);
  final _db = FirebaseFirestore.instance;
  DateTime? _lastFetch;
  Future<void> reload({String? categoryId}) async {
    if (state.isNotEmpty &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 30)) {
      return;
    }
    final docs = await _silently(
      () async {
        Query<Map<String, dynamic>> query = _db.collection('brands');
        if (categoryId != null) {
          query = query.where('category_id', isEqualTo: categoryId);
        }
        final snap =
            await query.get(const GetOptions(source: Source.serverAndCache));
        // ✅ الفرز في الذاكرة لتجنب اشتراط Composite Index في Firestore
        final list = snap.docs
            .where((d) =>
                d.data()['is_deleted'] != true &&
                d.data()['is_active'] != false)
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
        list.sort((a, b) => (a['name']?.toString() ?? '')
            .compareTo(b['name']?.toString() ?? ''));
        return list;
      },
      tag: 'brands-reload',
    );
    if (docs != null && mounted) {
      state = docs;
      _lastFetch = DateTime.now();
    }
  }

  void update(List<Map<String, dynamic>> data) {
    if (mounted) state = data;
  }
}

class _AllOrdersNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  _AllOrdersNotifier() : super([]);
  void update(List<Map<String, dynamic>> data) {
    if (mounted) state = data;
  }

  void clear() {
    if (mounted) state = [];
  }
}

class _ConfirmedOrdersNotifier
    extends StateNotifier<List<Map<String, dynamic>>> {
  _ConfirmedOrdersNotifier() : super([]);
  void update(List<Map<String, dynamic>> data) {
    if (mounted) state = data;
  }

  void clear() {
    if (mounted) state = [];
  }
}

class _MyShippedOrdersNotifier
    extends StateNotifier<List<Map<String, dynamic>>> {
  _MyShippedOrdersNotifier() : super([]);
  void update(List<Map<String, dynamic>> data) {
    if (mounted) state = data;
  }

  void clear() {
    if (mounted) state = [];
  }
}

// ══════════════════════════════════════════════════════════
//  مؤشر الاتصال — ضعه في أي شاشة
// ══════════════════════════════════════════════════════════
class RealtimeIndicator extends ConsumerWidget {
  const RealtimeIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(realtimeStatusProvider);
    if (status == RealtimeStatus.connected) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: status == RealtimeStatus.connecting
          ? const _StatusDot(
              key: ValueKey('c'),
              color: Color(0xFFF59E0B),
              label: 'جاري الاتصال...',
              pulse: true,
            )
          : const _StatusDot(
              key: ValueKey('d'),
              color: Color(0xFFEF4444),
              label: 'انقطع الاتصال',
              pulse: false,
            ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  final Color color;
  final String label;
  final bool pulse;
  const _StatusDot({
    super.key,
    required this.color,
    required this.label,
    required this.pulse,
  });

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _opacity = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.pulse) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: widget.pulse ? _opacity : const AlwaysStoppedAnimation(1),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            widget.label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: widget.color,
            ),
          ),
        ],
      ),
    );
  }
}
