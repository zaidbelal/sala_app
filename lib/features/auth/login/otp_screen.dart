import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radius.dart';
import '../../../core/constants/app_shadows.dart';
import '../../../core/constants/app_adaptive_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/local_storage.dart';
import '../../splash/widgets/sala_logo.dart';
import 'services/auth_service.dart';
import 'package:sala/core/services/realtime_hub.dart';
import '../signup/services/signup_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../merchant/cart/providers/cart_provider.dart';
import 'package:sala/app_router.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  final String? userId;
  final String? role;
  final bool isNewUser;
  final String verificationId;
  final int? resendToken;

  const OtpScreen({
    super.key,
    required this.phone,
    this.userId,
    this.role,
    this.isNewUser = false,
    this.verificationId = '',
    this.resendToken,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen>
    with TickerProviderStateMixin {
  static const int _length = 6;

  final List<TextEditingController> _controllers =
      List.generate(_length, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_length, (_) => FocusNode());

  bool _isVerifying = false;
  bool _isError = false;
  bool _isSuccess = false;
  String _errorMsg = '';

  Timer? _resendTimer;
  int _resendSeconds = 60;
  int _resendAttempts = 0;
  bool _canResend = false;
  bool _isResending = false; // ← أضف هذا
  StreamSubscription<User?>? _authStateSub;
  late String _verificationId;
  int? _resendToken;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;
  late AnimationController _entryController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _shakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut));
    _entryController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _entryController, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _entryController, curve: Curves.easeOutCubic));
    _entryController.forward();
    _startResendTimer(60);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _authStateSub?.cancel();
    _authStateSub = null;
    _resendTimer?.cancel();
    _shakeController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  void _onChanged(int index, String value) {
    setState(() => _errorMsg = '');

    if (value.isEmpty) {
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
      return;
    }

    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');

      for (int i = 0; i < _length && i < digits.length; i++) {
        if (index + i < _length) {
          _controllers[index + i].text = digits[i];
        }
      }

      final next = (index + digits.length - 1).clamp(0, _length - 1);
      _focusNodes[next].requestFocus();
      setState(() {});
      if (_isComplete) {
        autoVerify();
      }
      return;
    }

    if (index < _length - 1) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
      if (_isComplete) {
        autoVerify();
      }
    }
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData('text/plain');
    final raw = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (raw.isEmpty) return;
    final digits = raw.substring(0, raw.length.clamp(0, _length));
    for (int i = 0; i < _length; i++) {
      _controllers[i].text = i < digits.length ? digits[i] : '';
    }
    final next = (digits.length - 1).clamp(0, _length - 1);
    _focusNodes[next].requestFocus();
    setState(() {});
    if (_isComplete) {
      autoVerify();
    }
  }

  String get _otpValue => _controllers.map((c) => c.text).join();
  bool get _isComplete => _controllers.every((c) => c.text.isNotEmpty);

  Future<void> autoVerify() async {
    if (!_isComplete) return;
    await _verify(_otpValue);
  }

  Future<void> _verify(String otp) async {
    if (_isVerifying) return;
    if (_verificationId.isEmpty) {
      setState(() {
        _isError = true;
        _errorMsg = 'انتهت جلسة التحقق، أعد إرسال الرمز';
      });
      return;
    }
    setState(() {
      _isVerifying = true;
      _isError = false;
      _errorMsg = '';
    });

    if (widget.isNewUser) {
      final signupService = ref.read(signupServiceProvider);
      final response = await signupService.verifyOtp(
        _verificationId,
        otp,
        phone: widget.phone,
      );
      if (!response.success) {
        HapticFeedback.vibrate();
        setState(() {
          _isVerifying = false;
          _isError = true;
          _errorMsg = response.message.isNotEmpty
              ? response.message
              : 'كود التحقق غير صحيح أو انتهت صلاحيته';
        });
        _shakeController.forward(from: 0);
        return;
      }
      try {
        final customToken = response.customToken;
        if (FirebaseAuth.instance.currentUser == null &&
            customToken != null &&
            customToken != 'firebase_phone_verified') {
          await FirebaseAuth.instance
              .signInWithCustomToken(customToken)
              .timeout(const Duration(seconds: 10));
        }
      } catch (e) {
        setState(() {
          _isVerifying = false;
          _isError = true;
          _errorMsg = 'فشل التحقق، يرجى التأكد من اتصالك بالإنترنت';
        });
        _shakeController.forward(from: 0);
        return;
      }
      setState(() {
        _isSuccess = true;
        _isVerifying = false;
      });
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        context.go(AppRoutes.signupDetails, extra: widget.phone);
      }
      return;
    }

    final authService = ref.read(authServiceProvider);
    final result = await authService.verifyOtp(
      verificationId: _verificationId,
      otp: otp,
      phone: widget.phone,
    );

    if (!mounted) return;

    if (!result.success) {
      HapticFeedback.vibrate();
      setState(() {
        _isVerifying = false;
        _isError = true;
        _errorMsg = result.isDisabled
            ? 'خدمة OTP غير مفعّلة — تواصل مع المدير'
            : result.message;
      });

      _shakeController.forward(from: 0);
      return;
    }
    try {
      final customToken = result.customToken;
      if (customToken != null &&
          customToken.isNotEmpty &&
          customToken != 'firebase_phone_verified') {
        await FirebaseAuth.instance
            .signInWithCustomToken(customToken)
            .timeout(const Duration(seconds: 10));
      }
    } catch (e) {
      setState(() {
        _isVerifying = false;
        _isError = true;
        _errorMsg = 'فشل تسجيل الدخول لدى خادم الأمان، يرجى التحقق من اتصالك';
      });
      _shakeController.forward(from: 0);
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      setState(() {
        _isVerifying = false;
        _isError = true;
        _errorMsg = 'تعذر تأكيد جلسة المستخدم لدى خادم الأمان';
      });
      _shakeController.forward(from: 0);
      return;
    }

    final authenticatedUserId = firebaseUser.uid.trim();
    try {
      await authService.saveUserLocally(
        authenticatedUserId,
      );
    } on StateError catch (e) {
      // الحساب غير موجود فعلياً في قاعدة البيانات
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      setState(() {
        _isVerifying = false;
        _isError = true;
        _errorMsg = e.message.contains('inactive or banned')
            ? 'حسابك معطل أو محظور، يرجى مراجعة الإدارة'
            : 'تم التحقق من الرقم، لكن الحساب غير موجود. أنشئ حساباً جديداً';
      });

      return;
    } catch (e) {
      if (!mounted) return;
      final fallbackRole = widget.role ?? 'merchant';
      try {
        await AppStorage.saveUserData(
          userId: authenticatedUserId,
          role: fallbackRole.trim().toLowerCase(),
        );
        await AppStorage.setIsActive(false);
        await AppStorage.setIsBanned(false);
      } catch (_) {}

      setState(() {
        _isVerifying = false;
        _isError = true;
        _errorMsg =
            'تعذر التحقق من حالة الحساب من الخادم. يرجى التأكد من اتصالك وإعادة المحاولة.';
      });
      _shakeController.forward(from: 0);
      return;
    }
    setState(() {
      _isSuccess = true;
      _isVerifying = false;
    });
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    ref.invalidate(cartProvider);
    final role = AppStorage.userRole ?? widget.role ?? 'merchant';
    unawaited(
      RealtimeHub().startForUser(
        AppStorage.userId ?? '',
        role: role,
      ),
    );
    _navigateByRole();
  }

  void _navigateByRole() {
    if (!AppStorage.isActive) {
      context.go('/pending');
      return;
    }

    final raw = AppStorage.userRole ?? widget.role ?? 'merchant';
    final role = raw.toLowerCase().trim();

    if (role == 'admin' ||
        role == 'super_admin' ||
        role == 'accountant' ||
        role == 'warehouse_manager') {
      context.go('/admin');
    } else if (role == 'driver') {
      context.go('/driver');
    } else if (role == 'merchant') {
      context.go('/merchant');
    } else {
      context.go('/login');
    }
  }

  void _startResendTimer(int seconds) {
    setState(() {
      _resendSeconds = seconds;
      _canResend = false;
    });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds <= 1) {
        t.cancel();
        if (mounted) setState(() => _canResend = true);
      } else {
        if (mounted) setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _onResend() async {
    if (!_canResend || _isResending) return;

    setState(() {
      _isResending = true;
      _errorMsg = '';
      _isError = false;
    });

    try {
      final session = widget.isNewUser
          ? await ref.read(signupServiceProvider).sendOtp(
                widget.phone,
                forceResendingToken: _resendToken,
              )
          : await ref.read(authServiceProvider).sendOtp(
                widget.phone,
                forceResendingToken: _resendToken,
              );

      _verificationId = session.verificationId;
      _resendToken = session.resendToken;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'تم إرسال رمز جديد ✅',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

      _resendAttempts++;
      _startResendTimer(_resendAttempts == 1 ? 60 : 120 * _resendAttempts);
    } catch (error) {
      if (mounted) {
        setState(() {
          _isError = true;
          _errorMsg = error.toString().replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  String get _timerText {
    final m = _resendSeconds ~/ 60;
    final s = _resendSeconds % 60;
    return m > 0 ? '$mد ${s.toString().padLeft(2, '0')}ث' : '$sث';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(AppRoutes.login);
                          }
                        },
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        color: context.textPrimary,
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: AppRadius.circleAll,
                        ),
                        child: Text(
                          widget.isNewUser ? 'إنشاء حساب' : 'تسجيل دخول',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        const SalaLogo(size: 64, color: AppColors.primary),
                        const SizedBox(height: 10),
                        ShaderMask(
                          shaderCallback: (bounds) =>
                              AppColors.primaryGradient.createShader(bounds),
                          child: Text('سَلة',
                              style: AppTextStyles.headlineMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              )),
                        ),
                        const SizedBox(height: 36),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: context.bgCard,
                            borderRadius: AppRadius.xxlAll,
                            boxShadow: AppShadows.md,
                          ),
                          child: Column(
                            children: [
                              Text('أدخل رمز التحقق',
                                  style: AppTextStyles.headlineSmall),
                              const SizedBox(height: 8),
                              RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  style: AppTextStyles.bodyMedium
                                      .copyWith(color: context.textSecondary),
                                  children: [
                                    const TextSpan(text: 'الرمز مرسل إلى '),
                                    TextSpan(
                                      text:
                                          AuthService.formatPhone(widget.phone),
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 28),
                              AnimatedBuilder(
                                animation: _shakeAnim,
                                builder: (_, child) => Transform.translate(
                                  offset: Offset(
                                      _isError
                                          ? 8 * (0.5 - _shakeAnim.value).abs()
                                          : 0,
                                      0),
                                  child: child,
                                ),
                                child: Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(_length, (i) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        child: _OtpBox(
                                          controller: _controllers[i],
                                          focusNode: _focusNodes[i],
                                          isError: _isError,
                                          isSuccess: _isSuccess,
                                          onChanged: (v) => _onChanged(i, v),
                                          onBackspace: () {
                                            if (i > 0) {
                                              _focusNodes[i - 1].requestFocus();
                                              _controllers[i - 1].clear();
                                            }
                                          },
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 200),
                                child: _isError && _errorMsg.isNotEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.red
                                                .withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                  Icons.error_outline_rounded,
                                                  color: Colors.red,
                                                  size: 16),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Text(_errorMsg,
                                                    style: const TextStyle(
                                                        fontFamily: 'Cairo',
                                                        color: Colors.red,
                                                        fontSize: 13)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: (_isComplete && !_isVerifying)
                                      ? () => _verify(_otpValue)
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isSuccess
                                        ? Colors.green
                                        : AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    elevation: 0,
                                  ),
                                  child: _isVerifying
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2))
                                      : _isSuccess
                                          ? const Icon(
                                              Icons.check_circle_rounded,
                                              color: Colors.white,
                                              size: 24)
                                          : Text('تحقق',
                                              style: AppTextStyles.bodyLarge
                                                  .copyWith(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              GestureDetector(
                                onTap: (_canResend && !_isResending)
                                    ? _onResend
                                    : null,
                                child: _isResending
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      )
                                    : Text(
                                        _canResend
                                            ? 'إعادة إرسال الرمز'
                                            : 'إعادة الإرسال بعد $_timerText',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: _canResend
                                              ? AppColors.primary
                                              : AppColors.grey700,
                                          fontWeight: _canResend
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                          decoration: _canResend
                                              ? TextDecoration.underline
                                              : TextDecoration.none,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: _handlePaste,
                                icon: const Icon(Icons.content_paste_rounded,
                                    size: 16),
                                label: const Text('لصق الرمز',
                                    style: TextStyle(fontFamily: 'Cairo')),
                                style: TextButton.styleFrom(
                                    foregroundColor: AppColors.grey700),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
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

class _OtpBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isError;
  final bool isSuccess;
  final ValueChanged<String> onChanged;
  final VoidCallback? onBackspace;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.isError,
    required this.isSuccess,
    required this.onChanged,
    this.onBackspace,
  });

  @override
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> {
  @override
  Widget build(BuildContext context) {
    final borderColor = widget.isSuccess
        ? Colors.green
        : widget.isError
            ? Colors.red
            : AppColors.primary;

    final screenWidth = MediaQuery.of(context).size.width;
    const totalPadding = 96 + (6 * 8);
    final boxWidth = ((screenWidth - totalPadding) / 6).clamp(32.0, 44.0);

    return SizedBox(
      width: boxWidth,
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.backspace &&
                  widget.controller.text.isEmpty) {
                widget.onBackspace?.call();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextFormField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              showCursor: false,
              textDirection: TextDirection.ltr,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: widget.onChanged,
              style: const TextStyle(
                color: Colors.transparent,
                fontSize: 22,
                fontFamily: 'Cairo',
              ),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                contentPadding: EdgeInsets.zero,
                fillColor: widget.isSuccess
                    ? Colors.green.withValues(alpha: 0.05)
                    : widget.isError
                        ? Colors.red.withValues(alpha: 0.05)
                        : AppColors.primary.withValues(alpha: 0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF3A3A3A)
                        : Colors.grey[300]!,
                    width: 1.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: borderColor, width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: widget.controller.text.isNotEmpty
                        ? borderColor
                        : (Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF3A3A3A)
                            : Colors.grey[300]!),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (_, value, __) => Text(
                value.text,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: widget.isSuccess
                      ? Colors.green
                      : widget.isError
                          ? Colors.red
                          : (Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFFE8E8E8)
                              : AppColors.black),
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
