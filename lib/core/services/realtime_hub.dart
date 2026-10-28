// ==================================================
// FILE: lib/core/services/realtime_hub.dart
// ==================================================

import 'dart:async';
import 'dart:collection';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'local_storage.dart';
import 'notification_service.dart';
import 'connectivity_service.dart';
import 'package:sala/core/services/app_cache.dart';
import 'package:sala/features/merchant/cart/providers/cart_provider.dart';

// ══════════════════════════════════════════════════════════
//  RealtimeHub — Production-Grade
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
  StreamSubscription<bool>? _connectivitySub;
  ProviderContainer? _container;
  ProviderContainer? get container => _container;
  bool _initialized = false;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int reconnectAttempts = 0;
  bool _lastKnownNetworkState = true;

  static const int _productsPageSize = 100;

  StreamSubscription? _profileSub;
  StreamSubscription? _notificationsSub;
  StreamSubscription? _categoriesSub;
  StreamSubscription? _brandsSub;

  Future<void> _startForUserLock = Future.value();
  String? _activeUserId;
  String? _activeUserRole;
  bool _isRestarting = false;

  // ── التهيئة ──────────────────────────────────────────────
  void init(ProviderContainer container) {
    if (_initialized) return;
    _initialized = true;
    _container = container;

    _container?.read(realtimeStatusProvider.notifier).state =
        RealtimeStatus.connected;

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

    _connectivitySub ??=
        ConnectivityHelper.onConnectivityChanged.listen((hasNet) {
      final wasOffline = !_lastKnownNetworkState;
      _lastKnownNetworkState = hasNet;
      if (hasNet && wasOffline && _initialized) {
        reconnectAttempts = 0;
        restart();
      }
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
  }

  // ── قنوات المستخدم مع قفل الحماية ────────────────────────
  Future<void> startForUser(
    String userId, {
    String role = 'merchant',
  }) async {
    if (userId.isEmpty) return;

    final normalizedRole = role.toLowerCase().trim();
    if (_activeUserId == userId &&
        _activeUserRole == normalizedRole &&
        _userSubs.isNotEmpty) {
      return;
    }

    final prevLock = _startForUserLock;
    final completer = Completer<void>();
    _startForUserLock = completer.future;

    try {
      await prevLock;
    } catch (_) {}

    try {
      if (_activeUserId == userId &&
          _activeUserRole == normalizedRole &&
          _userSubs.isNotEmpty) {
        return;
      }

      if (_container != null) {
        _initialized = true;
        _setConnected();
        _startHeartbeat();
      }

      _connectivitySub ??=
          ConnectivityHelper.onConnectivityChanged.listen((hasNet) {
        final wasOffline = !_lastKnownNetworkState;
        _lastKnownNetworkState = hasNet;
        if (hasNet && wasOffline && _initialized) {
          reconnectAttempts = 0;
          restart();
        }
      });

      await _stopUserChannels();

      _activeUserId = userId;
      _activeUserRole = normalizedRole;

      _startUserChannels(
        userId,
        role: normalizedRole,
      );
    } finally {
      completer.complete();
    }
  }

  void _startUserChannels(String userId, {required String role}) {
    if (_categoriesSub == null) _watchCategories();
    if (_brandsSub == null) _watchBrands();

    _profileSub?.cancel();
    if (_profileSub != null) {
      _userSubs.remove(_profileSub);
      _profileSub = null;
    }

    _profileSub =
        _db.collection('profiles').doc(userId).snapshots().listen((doc) async {
      if (!_initialized || AppStorage.userId != userId) return;
      if (!doc.exists || doc.data() == null) return;
      final data = doc.data()!;
      final isBanned = data['is_banned'] == true;
      final isActive = data['is_active'] as bool? ?? false;
      final newRole = (data['role'] as String?)?.trim().toLowerCase() ?? role;
      final bool wasInactive = !AppStorage.isActive;

      await AppStorage.setIsBanned(isBanned);
      await AppStorage.setIsActive(isActive);

      if (isBanned || (!isActive && data['account_status'] != 'pending')) {
        final navContext = NotificationService.navigatorKey.currentContext;
        final container = _container;
        dispose();
        if (container != null) {
          try {
            container.read(cartProvider.notifier).clear();
            container.invalidate(cartProvider);
            container.invalidate(realtimeNotifsProvider);
            container.invalidate(merchantOrdersProvider);
            container.invalidate(realtimeConfirmedOrdersProvider);
            container.invalidate(realtimeMyShippedOrdersProvider);
            container.invalidate(realtimeAllOrdersProvider);
            container.invalidate(driverNewOrderCallbackProvider);
          } catch (_) {}
        }
        try {
          await NotificationService.instance
              .detachTokenFromFirestore(userId)
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
        try {
          await AppCache.instance.clearAll();
        } catch (_) {}
        await FirebaseAuth.instance.signOut();
        await AppStorage.clearUserData();
        if (navContext != null && navContext.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (navContext.mounted) {
              navContext.go('/login');
            }
          });
        }
        return;
      }

      if (wasInactive && isActive) {
        await AppStorage.setIsActive(true);
        await AppStorage.saveUserData(
          userId: userId,
          role: newRole,
          name: data['full_name'] as String?,
          phone: data['phone_number'] as String?,
        );
        final targetRoute = switch (newRole) {
          'admin' ||
          'super_admin' ||
          'accountant' ||
          'warehouse_manager' =>
            '/admin',
          'driver' => '/driver',
          _ => '/merchant',
        };
        final navContext = NotificationService.navigatorKey.currentContext;
        if (navContext != null && navContext.mounted && AppStorage.isLoggedIn) {
          navContext.go(targetRoute);
        }
        return;
      }

      if (newRole != AppStorage.userRole) {
        await AppStorage.saveUserData(
          userId: userId,
          role: newRole,
          name: data['full_name'] as String?,
          phone: data['phone_number'] as String?,
        );
        unawaited(NotificationService.instance.saveTokenToFirestore(userId));
        Future.microtask(() async {
          if (AppStorage.userId == userId && _initialized) {
            await startForUser(userId, role: newRole);
          }
        });
        final targetRoute = switch (newRole) {
          'admin' ||
          'super_admin' ||
          'accountant' ||
          'warehouse_manager' =>
            '/admin',
          'driver' => '/driver',
          _ => '/merchant',
        };
        final navContext = NotificationService.navigatorKey.currentContext;
        if (navContext != null && navContext.mounted && AppStorage.isLoggedIn) {
          navContext.go(targetRoute);
        }
        return;
      }
    }, onError: (_) {});

    if (_profileSub != null) {
      _userSubs.add(_profileSub!);
    }

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
    await _notificationsSub?.cancel();
    _notificationsSub = null;

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

    if (_categoriesSub == null) _watchCategories();
    if (_brandsSub == null) _watchBrands();
  }

  void _watchOrders(String merchantId) {
    if (merchantId.isEmpty) return;
    final sub = _db
        .collection('orders')
        .where('merchant_id', isEqualTo: merchantId)
        .orderBy('created_at', descending: true)
        .limit(50)
        .snapshots()
        .listen((snap) {
      final data = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      _container?.read(merchantOrdersProvider.notifier).update(data);
    }, onError: (_) {});
    _userSubs.add(sub);
  }

  void _watchNotifications(String userId) {
    if (userId.isEmpty) return;

    unawaited(_container?.read(realtimeNotifsProvider.notifier).reload(userId));

    bool isFirstLoad = true;
    final Set<String> knownNotifIds = {};

    _notificationsSub?.cancel();
    if (_notificationsSub != null) {
      _userSubs.remove(_notificationsSub);
      _notificationsSub = null;
    }

    final sub = _db
        .collection('user_notifications')
        .where('user_id', isEqualTo: userId)
        .limit(50)
        .snapshots()
        .listen(
      (snap) {
        final data = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList()
          ..sort((a, b) {
            DateTime parse(dynamic v) {
              if (v is Timestamp) return v.toDate();
              if (v is DateTime) return v;
              if (v is String) return DateTime.tryParse(v) ?? DateTime(2000);
              return DateTime(2000);
            }

            return parse(b['created_at']).compareTo(parse(a['created_at']));
          });
        _container?.read(realtimeNotifsProvider.notifier).update(data);
        _setConnected();
        if (knownNotifIds.length > 500) {
          knownNotifIds.clear();
          for (final d in snap.docs) {
            knownNotifIds.add(d.id);
          }
        } else if (!isFirstLoad) {
          for (final change in snap.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final id = change.doc.id;
              if (!knownNotifIds.contains(id)) {
                knownNotifIds.add(id);
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
        if (_initialized && AppStorage.isLoggedIn) {
          _scheduleReconnect();
        }
      },
    );
    _notificationsSub = sub;
    _userSubs.add(sub);
  }

  void watchProducts() {
    if ((_container?.read(realtimeProductsProvider).length ?? 0) == 0) {
      unawaited(_container?.read(realtimeProductsProvider.notifier).reload());
    }
  }

  void _watchCategories() {
    _categoriesSub?.cancel();
    _categoriesSub = _db
        .collection('categories')
        .snapshots(includeMetadataChanges: false)
        .listen(
      (snap) {
        final data = snap.docs
            .where((d) =>
                d.data()['is_active'] != false &&
                d.data()['is_deleted'] != true)
            .map((d) => {'id': d.id, ...d.data()})
            .toList()
          ..sort((a, b) => ((a['sort_order'] as num?)?.toInt() ?? 999)
              .compareTo((b['sort_order'] as num?)?.toInt() ?? 999));

        _container?.read(realtimeCategoriesProvider.notifier).update(data);
        AppCache.instance.setCategories(data);
      },
      onError: (e) {
        if (kDebugMode) debugPrint('❌ _watchCategories error: $e');
      },
    );
  }

  void _watchBrands() {
    _brandsSub?.cancel();
    _brandsSub = _db
        .collection('brands')
        .snapshots(includeMetadataChanges: false)
        .listen(
      (snap) {
        final data = snap.docs
            .where((d) =>
                d.data()['is_active'] != false &&
                d.data()['is_deleted'] != true)
            .map((d) => {'id': d.id, ...d.data()})
            .toList()
          ..sort((a, b) => (a['name']?.toString() ?? '')
              .compareTo(b['name']?.toString() ?? ''));

        _container?.read(realtimeBrandsProvider.notifier).update(data);
        AppCache.instance.setBrands(data);
      },
      onError: (e) {
        if (kDebugMode) debugPrint('❌ _watchBrands error: $e');
      },
    );
  }

  void _watchAllOrders() {
    final sub = _db
        .collection('orders')
        .orderBy('created_at', descending: true)
        .limit(50)
        .snapshots()
        .listen((snap) {
      final data = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      _container?.read(realtimeAllOrdersProvider.notifier).update(data);
    }, onError: (_) {});
    _userSubs.add(sub);
  }

  void _watchConfirmedOrders() {
    bool firstLoad = true;
    final seenIds = LinkedHashSet<String>();

    final sub = _db
        .collection('orders')
        .where('status', isEqualTo: 'confirmed')
        .orderBy('created_at', descending: true)
        .limit(25)
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

        final currentIds = LinkedHashSet<String>.from(
          snap.docs.map((doc) => doc.id),
        );
        if (!firstLoad) {
          final newIds = currentIds.difference(seenIds);
          for (final id in newIds) {
            final doc = snap.docs.firstWhere((d) => d.id == id);
            final order = {'id': doc.id, ...doc.data()};
            final assignedDriver = order['driver_id'] as String?;
            if (assignedDriver != null && assignedDriver.isNotEmpty) continue;

            NotificationService.instance.showLocalNotification(
              title: '🚨 طلب جديد وصلك!',
              body:
                  'طلب جديد جاهز للتوصيل بقيمة ${(order['total'] ?? order['total_amount'] ?? 0)} ر.ي',
              payload: '/driver',
            );
          }
        }
        firstLoad = false;
        for (final id in currentIds) {
          seenIds
            ..remove(id)
            ..add(id);
        }
        while (seenIds.length > 500) {
          seenIds.remove(seenIds.first);
        }
      },
      onError: (e) {
        if (kDebugMode) debugPrint('❌ _watchConfirmedOrders error: $e');
        _scheduleReconnect();
      },
    );
    _userSubs.add(sub);
  }

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

  void _setConnected() {
    _reconnectTimer?.cancel();
    reconnectAttempts = 0;
    _container?.read(realtimeStatusProvider.notifier).state =
        RealtimeStatus.connected;
  }

  void _scheduleReconnect() {
    _container?.read(realtimeStatusProvider.notifier).state =
        RealtimeStatus.disconnected;

    reconnectAttempts++;
    if (reconnectAttempts < 6) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(seconds: 3 * reconnectAttempts), () {
        if (_initialized) restart();
      });
    }
  }

  void restart() {
    if (_isRestarting) return;
    _isRestarting = true;
    unawaited(_restartAsync().whenComplete(() => _isRestarting = false));
  }

  Future<void> _restartAsync() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    await _categoriesSub?.cancel();
    _categoriesSub = null;
    await _brandsSub?.cancel();
    _brandsSub = null;
    await _notificationsSub?.cancel();
    _notificationsSub = null;
    await _profileSub?.cancel();
    _profileSub = null; // 🔒 منع تسريب مؤشر الملف الشخصي في الذاكرة

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

// ✅ التطهير التام للجلسة مع الحفاظ على القنوات الحية للتطبيق بعد تسجيل الخروج
  Future<void> resetOnSignOut() async {
    final container = _container;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final subsToCancel = <StreamSubscription?>[
      _profileSub,
      _notificationsSub,
      _categoriesSub,
      _brandsSub,
      ..._userSubs,
    ];

    _profileSub = null;
    _notificationsSub = null;
    _categoriesSub = null;
    _brandsSub = null;
    _userSubs.clear();

    await Future.wait(
      subsToCancel
          .whereType<StreamSubscription>()
          .map((s) => s.cancel().catchError((_) {})),
    );

    if (container != null) {
      try {
        container.read(merchantOrdersProvider.notifier).clear();
        container.read(realtimeNotifsProvider.notifier).clear();
        container.read(realtimeAllOrdersProvider.notifier).clear();
        container.read(realtimeConfirmedOrdersProvider.notifier).clear();
        container.read(realtimeMyShippedOrdersProvider.notifier).clear();
        container.read(driverNewOrderCallbackProvider.notifier).state = null;
        container.read(realtimeStatusProvider.notifier).state =
            RealtimeStatus.disconnected;
      } catch (_) {}
    }

    _activeUserId = null;
    _activeUserRole = null;
    reconnectAttempts = 0;
    _initialized = false;
  }

  Future<void> dispose() async {
    await resetOnSignOut();
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    await _categoriesSub?.cancel();
    _categoriesSub = null;
    await _brandsSub?.cancel();
    _brandsSub = null;
    _initialized = false;
    _container = null;
  }
}

// ══════════════════════════════════════════════════════════
//  Notifiers
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
    state = data;
  }

  void clear() {
    if (mounted) state = [];
  }
}

class _NotificationsNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  _NotificationsNotifier() : super([]);
  final _db = FirebaseFirestore.instance;
  static const int _pageSize = 50;
  DocumentSnapshot<Map<String, dynamic>>? _lastLoadedDoc;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  String? loadMoreError;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;

  Future<void> reload(String userId) async {
    if (userId.isEmpty) return;
    final snapshot = await _silently(
      () => _db
          .collection('user_notifications')
          .where('user_id', isEqualTo: userId)
          .orderBy('created_at', descending: true)
          .limit(_pageSize)
          .get(),
      tag: 'notifs-reload',
    );
    if (snapshot != null && mounted) {
      _lastLoadedDoc = snapshot.docs.isEmpty ? null : snapshot.docs.last;
      _hasMore = snapshot.docs.length == _pageSize;
      update(snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList());
    }
  }

  void update(List<Map<String, dynamic>> data) {
    if (!mounted) return;
    final merged = <String, Map<String, dynamic>>{
      for (final notification in state)
        notification['id'].toString(): notification,
      for (final notification in data)
        notification['id'].toString(): notification,
    };
    final notifications = merged.values.toList()
      ..sort((a, b) => _notificationDate(b).compareTo(_notificationDate(a)));
    state = notifications;
  }

  DateTime _notificationDate(Map<String, dynamic> notification) {
    final value = notification['created_at'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime(2000);
    return DateTime(2000);
  }

  Future<void> loadMore(String userId) async {
    final cursor = _lastLoadedDoc;
    if (userId.isEmpty || !_hasMore || _isLoadingMore || cursor == null) {
      return;
    }
    _isLoadingMore = true;
    loadMoreError = null;
    state = List<Map<String, dynamic>>.from(state);
    try {
      final snapshot = await _db
          .collection('user_notifications')
          .where('user_id', isEqualTo: userId)
          .orderBy('created_at', descending: true)
          .startAfterDocument(cursor)
          .limit(_pageSize)
          .get(const GetOptions(source: Source.serverAndCache));
      if (!mounted) return;

      if (snapshot.docs.isNotEmpty) _lastLoadedDoc = snapshot.docs.last;
      _hasMore = snapshot.docs.length == _pageSize;
      update(snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList());
    } catch (error, stackTrace) {
      loadMoreError = 'تعذر تحميل الإشعارات الأقدم. أعد المحاولة.';
      if (kDebugMode) {
        debugPrint('Notification pagination failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    } finally {
      _isLoadingMore = false;
      if (mounted) state = List<Map<String, dynamic>>.from(state);
    }
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
        final query = _db
            .collection('user_notifications')
            .where('user_id', isEqualTo: userId)
            .where('is_read', isEqualTo: false)
            .orderBy(FieldPath.documentId);
        const chunkSize = 400;
        DocumentSnapshot<Map<String, dynamic>>? cursor;
        bool hasMore;
        do {
          Query<Map<String, dynamic>> pageQuery = query.limit(chunkSize);
          if (cursor != null) {
            pageQuery = pageQuery.startAfterDocument(cursor);
          }
          final page = await pageQuery.get();
          if (page.docs.isEmpty) break;

          final batch = _db.batch();
          for (final doc in page.docs) {
            batch.update(doc.reference, {'is_read': true});
          }
          await batch.commit();
          cursor = page.docs.last;
          hasMore = page.docs.length == chunkSize;
        } while (hasMore);
        if (mounted) {
          state = state.map((n) => {...n, 'is_read': true}).toList();
        }
      },
      tag: 'notifs-markAllRead',
    );
  }

  void clear() {
    if (!mounted) return;
    state = [];
    _lastLoadedDoc = null;
    _hasMore = true;
    _isLoadingMore = false;
    loadMoreError = null;
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
        final snap = await query.limit(RealtimeHub._productsPageSize).get();
        final list = snap.docs
            .where((d) =>
                d.data()['is_active'] != false &&
                d.data()['is_deleted'] != true)
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
        list.sort((a, b) => (a['name']?.toString() ?? '')
            .compareTo(b['name']?.toString() ?? ''));
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
//  مؤشر الاتصال
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
