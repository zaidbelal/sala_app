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
import 'package:sala/core/constants/app_colors.dart';
import 'package:sala/core/constants/app_theme.dart';
import 'package:sala/app_router.dart';
import 'package:sala/core/services/image_precache_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sala/core/services/wal_service.dart';
import 'package:sala/core/services/delta_sync_service.dart';

String _clean(String val) => val.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();

// إعدادات الويب
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

// ✅ إعدادات الآيفون مأخوذة مباشرة من ملفك لحل مشكلة عدم الربط في Xcode
const iosFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyC_O1Uu7f5sCrg5Xy2uP1JNeb_qgBPMqjo',
  appId: '1:846679653389:ios:362d95f5793128e5902944',
  messagingSenderId: '846679653389',
  projectId: 'app-sala-b42dd',
  storageBucket: 'app-sala-b42dd.firebasestorage.app',
  iosBundleId: 'com.example.sala',
);

// تحديد الإعداد المناسب لكل منصة
FirebaseOptions? get platformFirebaseOptions {
  if (kIsWeb) return webFirebaseOptions;
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return iosFirebaseOptions;
  }
  return null; // نظام أندرويد يقرأ من google-services.json تلقائياً
}

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: platformFirebaseOptions);
    }
    // تهيئة القنوات وعرض الإشعار فوراً في النظام حتى لو كان التطبيق مغلقاً تماماً
    await NotificationService.instance
        .initLocalNotifications(isBackground: true);
    await NotificationService.instance.showNotification(message);
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  GoogleFonts.config.allowRuntimeFetching = false;

  String? initError;
  bool isFirebaseReady = false;

  // 1. تهيئة فايربيز بالخيارات البرمجية المباشرة (حل الشاشة البيضاء)
  try {
    await Firebase.initializeApp(
      options: platformFirebaseOptions,
    );
    isFirebaseReady = true;
  } catch (e, st) {
    initError = 'خطأ تهيئة فايربيز: $e';
    debugPrint('❌ Firebase Init Error: $e\n$st');
  }

  // 2. إعداد رصد الأخطاء
  if (isFirebaseReady && !kIsWeb) {
    FlutterError.onError = (details) {
      final errorStr = details.exception.toString();
      if (errorStr.contains('fonts.gstatic.com') ||
          errorStr.contains('Failed to load font')) {
        return;
      }
      if (errorStr.contains('MultiImageStreamCompleter')) {
        FlutterError.presentError(details);
        try {
          unawaited(
            FirebaseCrashlytics.instance
                .recordError(
              details.exception,
              details.stack,
              reason: 'Image stream error',
              fatal: false,
            )
                .catchError((Object error) {
              debugPrint('Failed to report image stream error: $error');
            }),
          );
        } catch (error) {
          debugPrint('Failed to report image stream error: $error');
        }
        return;
      }
      FlutterError.presentError(details);
      try {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      } catch (_) {}
    };

    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    } catch (_) {}
  }

  // 3. فحص المستخدم مع مهلة أمان
  if (isFirebaseReady) {
    try {
      await FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  // 4. تهيئة التخزين المحلي
  try {
    await AppStorage.initialize();
  } catch (e) {
    debugPrint('❌ AppStorage Error: $e');
  }

// 5. تهيئة الكاش وسجل العمليات ومطابقة السلة قبل بدء الـ ProviderContainer
  try {
    await AppCache.instance.init();
    await WalService.instance.init();
    // 🔒 تشغيل تسوية القيود المالية في الخلفية بشكل آمن بدون مهلة قصيرة تعطل فتح التطبيق
    unawaited(WalService.instance.reconcilePendingEntries());
  } catch (e) {
    debugPrint('❌ Cache/WAL Initialization Warning: $e');
  }
  if (isFirebaseReady) {
    FirebaseService.initialize();
    unawaited(DeltaSyncService.instance.syncProductsDelta());
    unawaited(DeltaSyncService.instance.syncCategoriesDelta());
  }

  final container = ProviderContainer();

  // 6. تشغيل واجهة التطبيق فوراً لمنع الشاشة البيضاء
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: initError != null
          ? _CriticalErrorApp(error: initError)
          : const SalaApp(),
    ),
  );

  if (isFirebaseReady) {
    RealtimeHub().init(container);
    _warmUpCache(container);
    unawaited(_initializeRemoteConfig());

    if (!kIsWeb) {
      unawaited(_initializeNotifications());
    }
  }
}

class _CriticalErrorApp extends StatelessWidget {
  final String error;
  const _CriticalErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'تنبيه في إعدادات التطبيق',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _initializeRemoteConfig() async {
  try {
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval: const Duration(hours: 1),
      ),
    );
    await remoteConfig.setDefaults({'min_order_value': 4250.0});
    await remoteConfig.fetchAndActivate();
    final double fetchedMinOrder = remoteConfig.getDouble('min_order_value');
    if (fetchedMinOrder > 0) {
      AppConfig.minOrderValue = fetchedMinOrder;
    }
  } catch (_) {}
}

Future<void> _initializeNotifications() async {
  try {
    await NotificationService.instance.init();
    final userId = AppStorage.userId;
    if (userId != null && userId.trim().isNotEmpty) {
      await NotificationService.instance.saveTokenToFirestore(userId);
    }
  } catch (_) {}
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
      final firstLogin = AppStorage.getString('first_login_at');
      final started = firstLogin == null ? null : DateTime.tryParse(firstLogin);
      if (started != null && DateTime.now().difference(started).inDays > 90) {
        return;
      }
      AppStorage.setString('last_login_at', DateTime.now().toIso8601String());
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
