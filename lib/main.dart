// ==================================================
// FILE: lib/main.dart
// ==================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:sala/core/services/firebase_service.dart';
import 'package:sala/core/services/local_storage.dart';
import 'package:sala/core/services/realtime_hub.dart';
import 'package:sala/core/services/notification_service.dart';
import 'package:sala/core/services/app_cache.dart';
import 'package:sala/core/services/catalog_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sala/core/constants/app_theme.dart';
import 'package:sala/app_router.dart';
import 'package:sala/core/services/image_precache_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ✅ تنظيف النصوص من أي محارف مخفية أو رموز اتجاه تسبب خطأ ISO-8859-1
String _clean(String val) => val.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();

// ✅ قراءة المتغيرات وتطهيرها برمجياً قبل تمريرها لـ Firebase
FirebaseOptions get webFirebaseOptions {
  final apiKey = _clean(const String.fromEnvironment('FIREBASE_API_KEY'));
  final authDomain =
      _clean(const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'));
  final projectId = _clean(const String.fromEnvironment('FIREBASE_PROJECT_ID'));
  final storageBucket =
      _clean(const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'));
  final messagingSenderId =
      _clean(const String.fromEnvironment('FIREBASE_SENDER_ID'));
  final appId = _clean(const String.fromEnvironment('FIREBASE_APP_ID'));
  final measurementId =
      _clean(const String.fromEnvironment('FIREBASE_MEASUREMENT_ID'));

  return FirebaseOptions(
    apiKey: apiKey,
    authDomain: authDomain,
    projectId: projectId,
    storageBucket: storageBucket,
    messagingSenderId: messagingSenderId,
    appId: appId,
    measurementId: measurementId.isEmpty ? null : measurementId,
  );
}

// ✅ يجب أن يكون top-level — Flutter يشغّله في isolate منفصل عند الإغلاق
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: kIsWeb ? webFirebaseOptions : null,
      );
    }
  } catch (_) {}

  try {
    await AppStorage.initialize();
  } catch (_) {}

  if (message.notification == null) {
    try {
      await NotificationService.instance
          .initLocalNotifications(isBackground: true);
      await NotificationService.instance.showNotification(message);
    } catch (_) {}
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  GoogleFonts.config.allowRuntimeFetching = true;
  FlutterError.onError = (details) {
    final errorStr = details.exception.toString();
    if (errorStr.contains('fonts.gstatic.com') ||
        errorStr.contains('Failed to load font') ||
        errorStr.contains('MultiImageStreamCompleter')) {
      return;
    }
    FlutterError.presentError(details);
  };

  try {
    await Firebase.initializeApp(
      options: kIsWeb ? webFirebaseOptions : null,
    ).timeout(const Duration(seconds: 3));

    if (!kIsWeb && Firebase.apps.isNotEmpty) {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    }
  } catch (e) {
    debugPrint("⚠️ تعذر تهيئة Firebase عند بدء التشغيل: $e");
  }

  try {
    await AppStorage.initialize();
  } catch (e) {
    debugPrint("خطأ في AppStorage: $e");
  }

  try {
    await AppCache.instance.init();
  } catch (e) {
    debugPrint("خطأ في AppCache: $e");
  }

  try {
    FirebaseService.initialize();
  } catch (_) {}

  final container = ProviderContainer();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SalaApp(),
    ),
  );

  try {
    RealtimeHub().init(container);
  } catch (_) {}

  _warmUpCache(container);

  if (Firebase.apps.isNotEmpty) {
    unawaited(_initializeRemoteConfig());

    if (!kIsWeb) {
      unawaited(_initializeNotifications());
    }
  }
}

/// تهيئة Remote Config في الخلفية
Future<void> _initializeRemoteConfig() async {
  try {
    final remoteConfig = FirebaseRemoteConfig.instance;

    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval: const Duration(hours: 1),
      ),
    );

    await remoteConfig.fetchAndActivate();
  } catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('Remote Config unavailable: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

Future<void> _initializeNotifications() async {
  try {
    await NotificationService.instance.init();

    final userId = AppStorage.userId;

    if (userId != null && userId.trim().isNotEmpty) {
      await NotificationService.instance.saveTokenToFirestore(userId);
    }
  } catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('Notification initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!kIsWeb) {
      try {
        await FirebaseCrashlytics.instance.recordError(
          error,
          stackTrace,
          reason: 'Notification initialization failed at startup',
          fatal: false,
        );
      } catch (_) {}
    }
  }
}

void _warmUpCache(ProviderContainer container) {
  final categoriesFuture = container
      .read(categoriesProvider.future)
      .catchError((_) => <Map<String, dynamic>>[]);

  categoriesFuture.then((categories) async {
    if (categories.isEmpty) return;
    ImagePrecacheService.instance.prewarmCategories(categories);
  });
}

class SalaApp extends ConsumerStatefulWidget {
  const SalaApp({super.key});

  @override
  ConsumerState<SalaApp> createState() => _SalaAppState();
}

class _SalaAppState extends ConsumerState<SalaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && AppStorage.isLoggedIn) {
      AppStorage.setString(
        'last_login_at',
        DateTime.now().toIso8601String(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final currentTheme = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'سلة',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: currentTheme,
      routerConfig: router,
      locale: const Locale('ar'),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
    );
  }
}
