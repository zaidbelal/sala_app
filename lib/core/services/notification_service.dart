import 'dart:async'; // ✅ مطلوب لـ StreamSubscription
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart'; // ✅ جديد
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'local_storage.dart';

// ══ معالج الإشعارات في الخلفية (خارج الكلاس) ══

class NotificationService {
  Future<void> detachTokenFromFirestore(String? userId) async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    await _onMessageSub?.cancel();
    _onMessageSub = null;
    await _onMessageOpenedSub?.cancel();
    _onMessageOpenedSub = null;

    // 🚀 فك الاشتراك من قنوات البث الجماعي عند تسجيل الخروج مع حماية المهلة
    try {
      await Future.wait([
        _messaging.unsubscribeFromTopic('all'),
        _messaging.unsubscribeFromTopic('merchants'),
        _messaging.unsubscribeFromTopic('drivers'),
      ]).timeout(const Duration(seconds: 2));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NotificationService] topic unsubscribe failed: $e');
      }
    }

    if (userId == null || userId.trim().isEmpty) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(userId)
          .update({
        'fcm_token': FieldValue.delete(),
        'token_updated_at': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 2));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Failed to detach FCM token: $error');
      }
    }
  }

  NotificationService._();
  static final instance = NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotif = FlutterLocalNotificationsPlugin();

  // ✅ نمنع تسرّب الذاكرة — نحفظ الـ subscription ونلغيه عند إعادة التهيئة
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedSub;
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static String? pendingRoute;
// ── تهيئة المكتبة المحلية مع فرض تشغيل صوت الإشعار الرسمي لأندرويد و iOS ──
  Future<void> initLocalNotifications({bool isBackground = false}) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        const ordersChannel = AndroidNotificationChannel(
          'sala_orders_channel_v3',
          'طلبات سلة',
          description: 'إشعارات الطلبات وتحديثات الحالة والمرتجعات',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
        );

        const driverChannel = AndroidNotificationChannel(
          'sala_orders_channel',
          'طلبات السائقين',
          description: 'إشعارات الطلبات الجديدة للسائق مع الرنين',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          sound: RawResourceAndroidNotificationSound('sala_notification'),
        );

        final androidPlugin = _localNotif.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.createNotificationChannel(ordersChannel);
        await androidPlugin?.createNotificationChannel(driverChannel);

        if (!isBackground) {
          await androidPlugin?.requestNotificationsPermission();
        }
      }

      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );

      await _localNotif.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onTap,
      );
    } catch (_) {}
  }

  Future<void> init() async {
    try {
      await _messaging
          .requestPermission(
            alert: true,
            badge: true,
            sound: true,
          )
          .timeout(const Duration(seconds: 2));

      await _messaging
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          )
          .timeout(const Duration(seconds: 1));
    } catch (_) {}

    await initLocalNotifications();

    try {
      await _onMessageSub?.cancel();
      await _onMessageOpenedSub?.cancel();
      _onMessageSub = FirebaseMessaging.onMessage.listen(showNotification);
      _onMessageOpenedSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmTap);

      final initial = await _messaging
          .getInitialMessage()
          .timeout(const Duration(seconds: 1), onTimeout: () => null);
      if (initial != null) {
        _handleFcmTap(initial);
      }
    } catch (_) {}
  }

// ══ عرض إشعار من Firebase FCM مع الصوت والاهتزاز الافتراضي ══
  Future<void> showNotification(RemoteMessage message) async {
    final title =
        message.notification?.title ?? message.data['title']?.toString();
    final body = message.notification?.body ?? message.data['body']?.toString();

    if (title == null && body == null) return;

    final androidDetails = AndroidNotificationDetails(
      'sala_orders_channel_v3', // تم تغيير القناة لتتطابق مع التهيئة وتعمل في الخلفية
      'طلبات سلة',
      channelDescription: 'إشعارات الطلبات وتحديثات الحالة والمرتجعات',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      styleInformation: BigTextStyleInformation(body ?? ''),
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotif.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload:
          message.data['route']?.toString() ?? _routeFromData(message.data),
    );
  }

// ══ عرض إشعار محلي مع الصوت والاهتزاز الفوري ══
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'sala_orders_channel_v3',
      'طلبات سلة',
      channelDescription: 'إشعارات الطلبات وتحديثات الحالة والمرتجعات',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      styleInformation: BigTextStyleInformation(body),
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotif.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  // ✅ إصلاح: تنقل حقيقي عند الضغط على الإشعار المحلي
  void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    _navigateTo(payload);
  }

  // ✅ إصلاح: تنقل حقيقي عند الضغط على إشعار FCM
  void _handleFcmTap(RemoteMessage message) {
    final route =
        message.data['route'] as String? ?? _routeFromData(message.data);
    if (route.isEmpty) return;
    _navigateTo(route);
  }

  void _navigateTo(String route) {
    if (route.isEmpty) return;

    final context = navigatorKey.currentContext;

    if (context == null) {
      pendingRoute = route;
      return;
    }

    try {
      context.go(route);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Notification navigation failed: $error');
      }
    }
  }

  String _routeFromData(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    final bool isDriver =
        AppStorage.isInitialized ? AppStorage.isDriver : false;
    return switch (type) {
      'new_order' => isDriver ? '/driver' : '/admin',
      'order_status' => '/merchant',
      'return_request' => '/admin',
      'notification' => '/notifications',
      _ => '',
    };
  }

  // ══ إشعار محلي مباشر (للسائق عند وصول طلب جديد) ══
  Future<void> showOrderNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'sala_orders_channel',
      'طلبات سلة',
      channelDescription: 'إشعارات الطلبات الجديدة',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('sala_notification'),
      enableVibration: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'sala_notification.wav',
    );
    await _localNotif.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  // ══ الحصول على FCM Token وحفظه في Firestore ══
  Future<String?> getToken() => _messaging.getToken();

  Future<void> saveTokenToFirestore(String userId) async {
    try {
      final token = await _messaging
          .getToken()
          .timeout(const Duration(seconds: 4), onTimeout: () => null);

      if (token == null || userId.isEmpty) return;

      try {
        await _messaging
            .subscribeToTopic('all')
            .timeout(const Duration(seconds: 2));
        final role = AppStorage.normalizedUserRole;
        if (role == 'merchant') {
          await _messaging
              .subscribeToTopic('merchants')
              .timeout(const Duration(seconds: 2));
        } else if (role == 'driver') {
          await _messaging
              .subscribeToTopic('drivers')
              .timeout(const Duration(seconds: 2));
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[NotificationService] topic subscribe failed: $e');
        }
      }

      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(userId)
          .update({
        'fcm_token': token,
        'token_updated_at': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 3));
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) async {
        try {
          await FirebaseFirestore.instance
              .collection('profiles')
              .doc(userId)
              .update({
            'fcm_token': newToken,
            'token_updated_at': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          if (kDebugMode) debugPrint('❌ onTokenRefresh update: $e');
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('❌ saveTokenToFirestore: $e');
    }
  }
}
