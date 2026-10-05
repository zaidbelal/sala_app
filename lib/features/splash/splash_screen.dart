import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/notification_service.dart';
import 'animations/splash_animator.dart';
import 'controllers/session_checker.dart';
import 'widgets/sala_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // تم حذف SystemUiMode.immersiveSticky لمنع تجميد الأنيميشن في iOS
  }

  void _onAnimationComplete(SessionResult result) {
    if (!mounted) return;

    final pending = NotificationService.pendingRoute;
    if (pending != null && pending.isNotEmpty && result.isAuthenticated) {
      NotificationService.pendingRoute = null;
      context.go(pending);
      return;
    }

    context.go(result.route);
  }

  @override
  Widget build(BuildContext context) {
    final sessionFuture = ref.watch(sessionCheckerProvider.future);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppColors.splashGradient,
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -60,
              child: _CircleDecor(
                size: 220,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -80,
              child: _CircleDecor(
                size: 280,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.12,
              left: -40,
              child: _CircleDecor(
                size: 130,
                color: Colors.white.withValues(alpha: 0.03),
              ),
            ),
            Center(
              child: SplashAnimator(
                logo: const SalaLogo(
                  size: 110,
                  color: Colors.white,
                ),
                appName: 'سَلة',
                textColor: Colors.white,
                sessionFuture: sessionFuture,
                onAnimationComplete: _onAnimationComplete,
              ),
            ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    'توصيل خلال 24 ساعة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.65),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'v1.0.0',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════
// ويدجت الدوائر الزخرفية
// ══════════════════════════════════════════
class _CircleDecor extends StatelessWidget {
  final double size;
  final Color color;

  const _CircleDecor({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
