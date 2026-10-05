import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'features/splash/splash_screen.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import 'features/auth/login/login_screen.dart';
import 'features/auth/login/otp_screen.dart';
import 'features/auth/signup/signup_details_screen.dart';
import 'package:sala/core/services/local_storage.dart';
import 'package:sala/core/services/notification_service.dart';
import 'package:sala/core/services/realtime_hub.dart';
import 'features/merchant/home/screens/merchant_home_screen.dart';
import 'features/admin/screens/admin_home_screen.dart';
import 'features/merchant/notifications/notifications_screen.dart';
import 'features/merchant/home/screens/delete_account_screen.dart';
import 'features/legal/privacy_policy_screen.dart';
import 'features/driver/screens/driver_home_screen.dart';
import 'features/auth/signup/services/signup_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const signup = '/signup';
  static const otp = '/otp';
  static const signupDetails = '/signup-details';
  static const merchantHome = '/merchant';
  static const driverHome = '/driver';
  static const adminHome = '/admin';
  static const pending = '/pending';
  static const notifications = '/notifications';
  static const privacy = '/privacy';
  static const deleteAccount = '/delete-account';
}

/// المسارات المحمية حسب الدور
const _protectedMerchantRoutes = [
  AppRoutes.merchantHome,
];
const _protectedAdminRoutes = [AppRoutes.adminHome];
const _protectedDriverRoutes = [AppRoutes.driverHome];

final appRouterProvider = Provider<GoRouter>((ref) {
  final goRouter = GoRouter(
    navigatorKey: NotificationService.navigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,

    // ══ حماية المسارات ══
    redirect: (context, state) {
      final path = state.matchedLocation;

// المسارات العامة — لا حماية (تم حماية pending خلف تسجيل الدخول)
      const publicRoutes = [
        AppRoutes.splash,
        AppRoutes.login,
        AppRoutes.signup,
        AppRoutes.otp,
        AppRoutes.signupDetails,
        AppRoutes.privacy,
      ];
      final pendingPush = NotificationService.pendingRoute;

      // أثناء وجود المستخدم في شاشة البداية، دعه يكمل فحص الجلسة والتأكد من عدم حظره أولاً
      if (path == AppRoutes.splash) {
        return null;
      }
      final firebaseUser = FirebaseAuth.instance.currentUser;

      // حماية من التوجيه الخاطئ أثناء تهيئة المستخدم لأول مرة
      if (AppStorage.userId == null || AppStorage.userId!.isEmpty) {
        if (!publicRoutes.contains(path)) {
          return AppRoutes.login;
        }
        return null;
      }

      final bool sessionExpired =
          AppStorage.isLoggedIn && AppStorage.isSessionExpired;

      if (sessionExpired) {
        if (!publicRoutes.contains(path)) {
          return AppRoutes.login;
        }
        return null;
      }
      // حماية صفحة إكمال البيانات من الدخول دون تسجيل دخول مسبق
      if (path == AppRoutes.signupDetails && firebaseUser == null) {
        return AppRoutes.login;
      }

      if (pendingPush != null && pendingPush.isNotEmpty) {
        NotificationService.pendingRoute = null;
        return pendingPush;
      }

      // حساب محظور نهائياً — طرد فوري ما لم يكن في صفحة تسجيل الدخول أو السياسة
      if (AppStorage.isBanned &&
          path != AppRoutes.login &&
          path != AppRoutes.privacy) {
        return AppRoutes.login;
      }

      if (publicRoutes.contains(path)) return null;

      // الحساب بانتظار المراجعة والتفعيل من الإدارة
      if (!AppStorage.isActive) {
        if (AppStorage.isBanned) return AppRoutes.login;
        return path == AppRoutes.pending ? null : AppRoutes.pending;
      }

      // إذا كان الحساب مفعّلاً وتواجد في صفحة الانتظار، يتم توجيهه حسب دوره الصحيح
      if (path == AppRoutes.pending && AppStorage.isActive) {
        if (AppStorage.hasAdminAccess) return AppRoutes.adminHome;
        if (AppStorage.isDriver) return AppRoutes.driverHome;
        return AppRoutes.merchantHome;
      }
      // حماية حسب الدور
      if (_protectedAdminRoutes.contains(path) && !AppStorage.hasAdminAccess) {
        return AppRoutes.login;
      }
      if (_protectedMerchantRoutes.contains(path) && !AppStorage.isMerchant) {
        return AppRoutes.login;
      }
      if (_protectedDriverRoutes.contains(path) && !AppStorage.isDriver) {
        return AppRoutes.login;
      }

      return null;
    },
    // ══ المسارات ══
    routes: [
      GoRoute(
        path: AppRoutes.privacy,
        builder: (_, __) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) {
          final prefilledPhone = state.extra as String?;
          return LoginScreen(prefilledPhone: prefilledPhone);
        },
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) {
          final prefilledPhone = state.extra as String?;
          return SignupScreen(prefilledPhone: prefilledPhone);
        },
      ),
      GoRoute(
        path: AppRoutes.otp,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is Map &&
              extra['phone'] is String &&
              extra['verificationId'] is String) {
            final dynamic rawResendToken = extra['resendToken'];
            final dynamic rawUserId = extra['userId'];
            final dynamic rawRole = extra['role'];
            return OtpScreen(
              phone: extra['phone'] as String,
              verificationId: extra['verificationId'] as String,
              resendToken: rawResendToken is int ? rawResendToken : null,
              userId: rawUserId is String ? rawUserId : null,
              role: rawRole is String ? rawRole : null,
              isNewUser: extra['isNewUser'] == true,
            );
          }
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_off_rounded,
                        size: 54, color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text(
                      'انتهت جلسة التحقق',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'يرجى العودة والتحقق من رقم هاتفك مجدداً',
                      style: TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => context.go(AppRoutes.login),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B8E3D),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('العودة لتسجيل الدخول',
                          style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.signupDetails,
        builder: (context, state) {
          final phone = state.extra as String? ?? '';
          return SignupDetailsScreen(phone: phone);
        },
      ),
      GoRoute(
        path: AppRoutes.pending,
        builder: (_, __) => const _PendingActivationScreen(),
      ),
      GoRoute(
        path: AppRoutes.merchantHome,
        builder: (_, __) => const MerchantHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.driverHome,
        builder: (_, __) => const DriverHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminHome,
        builder: (_, __) => const AdminHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.deleteAccount,
        builder: (_, __) => const DeleteAccountScreen(),
      ),
    ],

    // ══ صفحة الخطأ ══
    errorBuilder: (context, state) => _ErrorScreen(error: state.error),
  );

  return goRouter;
});

// ══════════════════════════════════════════
// شاشة انتظار التفعيل (بدون زر تسجيل الخروج)
// ══════════════════════════════════════════
class _PendingActivationScreen extends StatefulWidget {
  const _PendingActivationScreen();

  @override
  State<_PendingActivationScreen> createState() =>
      _PendingActivationScreenState();
}

class _PendingActivationScreenState extends State<_PendingActivationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ✅ فحص مباشر لحظي من السيرفر بدون طرد وبدون إعادة تشغيل
  Future<void> _checkStatusDirectly() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);
    try {
      final uid = AppStorage.userId ?? FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        context.go(AppRoutes.login);
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(uid)
          .get(const GetOptions(source: Source.server));

      if (!mounted) return;

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final isActive = data['is_active'] as bool? ?? false;
        final isBanned = data['is_banned'] == true;
        final role =
            (data['role'] as String?)?.trim().toLowerCase() ?? 'merchant';

        if (isBanned) {
          await AppStorage.clearUserData();
          if (mounted) context.go(AppRoutes.login);
          return;
        }

        // إذا وافقت الإدارة وتم التفعيل: توجيهه فوراً للرئيسية!
        if (isActive) {
          await AppStorage.setIsActive(true);
          await AppStorage.saveUserData(
            userId: uid,
            role: role,
            name: data['full_name'] as String?,
            phone: data['phone_number'] as String?,
          );
          if (mounted) {
            final target = switch (role) {
              'admin' ||
              'super_admin' ||
              'accountant' ||
              'warehouse_manager' =>
                AppRoutes.adminHome,
              'driver' => AppRoutes.driverHome,
              _ => AppRoutes.merchantHome,
            };
            context.go(target);
          }
          return;
        }
      }

      // إذا لم يتم التفعيل بعد: رسالة تنبيه لطيفة بدون أي طرد
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'طلبك ما زال قيد المراجعة من الإدارة ⏳ سنشُعرك فور اعتماده',
              style: TextStyle(fontFamily: 'Cairo'),
              textAlign: TextAlign.center,
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فحص الحالة، تأكد من الاتصال بالإنترنت',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── أيقونة نابضة ──
                ScaleTransition(
                  scale: _pulseAnim,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B8E3D).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1B8E3D).withValues(alpha: 0.2),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.hourglass_top_rounded,
                      size: 50,
                      color: Color(0xFF1B8E3D),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── العنوان ──
                Text(
                  'حسابك قيد المراجعة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'سيتم مراجعة طلبك من قِبل الإدارة\nوإشعارك فور تفعيل حسابك 🎉',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    color: context.textSecondary,
                    height: 1.7,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // ── مؤشر الخطوات ──
                _buildStepsIndicator(context),
                const SizedBox(height: 28),
// ── زر تحديث الحالة بكامل العرض ──
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isChecking ? null : _checkStatusDirectly,
                    icon: _isChecking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, size: 20),
                    label: Text(
                      _isChecking ? 'جاري التحقق...' : 'تحديث الحالة',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B8E3D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
// ── زر تسجيل الخروج / استخدام حساب آخر ──
                TextButton.icon(
                  onPressed: () async {
                    try {
                      final uid = AppStorage.userId;
                      // ✅ إيقاف المستمعات اللحظية لمنع تسرب الذاكرة بعد تسجيل الخروج
                      RealtimeHub().dispose();
                      await NotificationService.instance
                          .detachTokenFromFirestore(uid);
                      await FirebaseAuth.instance
                          .signOut()
                          .timeout(const Duration(seconds: 3));
                      await AppStorage.clearUserData();
                    } catch (_) {}
                    if (context.mounted) {
                      context.go(AppRoutes.login);
                    }
                  },
                  icon: const Icon(Icons.logout_rounded,
                      size: 18, color: Colors.grey),
                  label: const Text(
                    'تسجيل الخروج / استخدام حساب آخر',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepsIndicator(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Column(
        children: [
          _StepRow(
            icon: Icons.check_circle_rounded,
            color: Color(0xFF1B8E3D),
            label: 'تم استلام طلب التسجيل ✅',
            done: true,
          ),
          SizedBox(height: 12),
          _StepRow(
            icon: Icons.pending_rounded,
            color: Colors.orange,
            label: 'مراجعة البيانات من الإدارة ⏳',
            done: false,
          ),
          SizedBox(height: 12),
          _StepRow(
            icon: Icons.lock_open_rounded,
            color: Colors.grey,
            label: 'تفعيل الحساب والدخول للتطبيق',
            done: false,
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool done;

  const _StepRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: done ? FontWeight.w700 : FontWeight.w500,
              color: done ? context.textPrimary : context.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════
// صفحة الخطأ
// ══════════════════════════════════════════
class _ErrorScreen extends StatelessWidget {
  final Exception? error;
  const _ErrorScreen({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.error_outline_rounded,
                      size: 48, color: Colors.red),
                ),
                const SizedBox(height: 20),
                Text(
                  'الصفحة غير موجودة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'تحقق من الرابط أو عد للصفحة الرئيسية',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      color: context.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () => context.go(AppRoutes.login),
                    icon: const Icon(Icons.home_rounded, size: 18),
                    label: const Text('العودة للرئيسية',
                        style: TextStyle(
                            fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B8E3D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
