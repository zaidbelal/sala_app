import 'dart:async';
import 'package:flutter/material.dart';
import '../controllers/session_checker.dart';

class SplashAnimator extends StatefulWidget {
  final Widget logo;
  final String appName;
  final Color textColor;
  final Future<SessionResult> sessionFuture;
  final void Function(SessionResult result) onAnimationComplete;

  const SplashAnimator({
    super.key,
    required this.logo,
    required this.appName,
    required this.sessionFuture,
    required this.onAnimationComplete,
    this.textColor = Colors.white,
  });

  @override
  State<SplashAnimator> createState() => _SplashAnimatorState();
}

class _SplashAnimatorState extends State<SplashAnimator>
    with TickerProviderStateMixin {
  // ── Controllers ──
  late AnimationController _logoController;
  late AnimationController _nameController;
  late AnimationController _nameFallController;

  // ── Logo Animations ──
  late Animation<double> _logoSlideY; // يصعد من الأسفل
  late Animation<double> _logoOpacity; // يظهر تدريجياً
  late Animation<double> _logoScale; // يكبر قليلاً

  // ── Name Animations (الصعود السريع) ──
  late Animation<double> _nameSlideY; // يصعد بسرعة
  late Animation<double> _nameOpacity; // يظهر

  // ── Name Fall (السقوط) ──
  late Animation<double> _nameFallY; // يسقط للأسفل
  late Animation<double> _nameBounce; // ارتداد خفيف

  SessionResult? _sessionResult;
  bool _animationDone = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _setupControllers();
    _setupAnimations();
    _startSequence();
    _listenToSession();

// صمام أمان لنظام iOS للتنقل الفوري
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted && !_animationDone) {
        _animationDone = true;
        _sessionResult ??= SessionChecker.localSessionResult();
        widget.onAnimationComplete(_sessionResult!);
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _logoController.stop();
    _nameController.stop();
    _nameFallController.stop();
    _logoController.dispose();
    _nameController.dispose();
    _nameFallController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════
  // إعداد الـ Controllers
  // ══════════════════════════════════════════
  void _setupControllers() {
    // 🚀 تسريع الأنيميشنات نفسها مع الحفاظ على الإحساس البصري
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _nameController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _nameFallController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  // ══════════════════════════════════════════
  // إعداد الأنيميشنات
  // ══════════════════════════════════════════
  void _setupAnimations() {
    // ── اللوجو يصعد ──
    _logoSlideY = Tween<double>(begin: 120, end: 0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutCubic),
    );

    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );

    // ── الاسم يصعد بسرعة ──
    _nameSlideY = Tween<double>(begin: 180, end: 0).animate(
      CurvedAnimation(parent: _nameController, curve: Curves.easeOutExpo),
    );

    _nameOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _nameController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    // ── الاسم يسقط ──
    _nameFallY = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _nameFallController, curve: Curves.easeInCubic),
    );

    _nameBounce = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: -8).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -8, end: 3).chain(
          CurveTween(curve: Curves.easeIn),
        ),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 3, end: 0).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 40,
      ),
    ]).animate(
      CurvedAnimation(parent: _nameController, curve: Curves.easeOut),
    );
  }

  Future<void> _startSequence() async {
    try {
      if (_disposed || !mounted) return;
      await Future.delayed(const Duration(milliseconds: 80));
      if (_disposed || !mounted) return;
      if (_logoController.isAnimating || _logoController.isCompleted) return;
      await _logoController.forward();

      if (_disposed || !mounted) return;
      await Future.delayed(const Duration(milliseconds: 80));
      if (_disposed || !mounted) return;
      if (_nameController.isAnimating || _nameController.isCompleted) return;
      await _nameController.forward();

      if (_disposed || !mounted) return;
      await Future.delayed(const Duration(milliseconds: 180));
      if (_disposed || !mounted) return;
      if (_nameFallController.isAnimating || _nameFallController.isCompleted)
        return;
      await _nameFallController.forward();

      if (_disposed || !mounted) return;
      await Future.delayed(const Duration(milliseconds: 350));
      if (_disposed || !mounted) return;

      _animationDone = true;
      _tryNavigate();
    } catch (_) {}
  }

  // ══════════════════════════════════════════
  // انتظار نتيجة الجلسة
  // ══════════════════════════════════════════
  Future<void> _listenToSession() async {
    try {
      _sessionResult = await widget.sessionFuture.timeout(
        const Duration(milliseconds: 2200),
      );
    } catch (_) {
      _sessionResult = SessionChecker.localSessionResult();
    }
    if (mounted) {
      _tryNavigate();
    }
  }

  void _tryNavigate() {
    if (_animationDone && _sessionResult != null && mounted) {
      widget.onAnimationComplete(_sessionResult!);
    }
  }

  // ══════════════════════════════════════════
  // الـ Build
  // ══════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _logoController,
        _nameController,
        _nameFallController,
      ]),
      builder: (context, child) {
        // حساب موضع السقوط النهائي للاسم
        // يبدأ فوق اللوجو (offset سالب) وينتهي تحته (offset موجب)
        const nameAboveLogo = -70.0; // فوق اللوجو
        const nameBelowLogo = 74.0; // تحت اللوجو
        final currentNameY = nameAboveLogo +
            (_nameFallY.value * (nameBelowLogo - nameAboveLogo));

        return Stack(
          alignment: Alignment.center,
          children: [
            // ── اللوجو ──
            Transform.translate(
              offset: Offset(0, _logoSlideY.value),
              child: Opacity(
                opacity: _logoOpacity.value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: _logoScale.value,
                  child: widget.logo,
                ),
              ),
            ),

            // ── الاسم ──
            Transform.translate(
              offset: Offset(
                0,
                _nameController.isAnimating || _nameController.isCompleted
                    ? currentNameY + _nameBounce.value
                    : _nameSlideY.value + nameAboveLogo,
              ),
              child: Opacity(
                opacity: _nameOpacity.value.clamp(0.0, 1.0),
                child: _AppNameText(
                  name: widget.appName,
                  color: widget.textColor,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ══════════════════════════════════════════
// ويدجت اسم التطبيق
// ══════════════════════════════════════════
class _AppNameText extends StatelessWidget {
  final String name;
  final Color color;

  const _AppNameText({required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [
          color,
          color.withValues(alpha: 0.85),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(bounds),
      child: Text(
        name,
        style: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 2.0,
          height: 1.0,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
      ),
    );
  }
}
