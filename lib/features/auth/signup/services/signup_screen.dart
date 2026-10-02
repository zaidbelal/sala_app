import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radius.dart';
import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_adaptive_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../splash/widgets/sala_logo.dart';
import '../../login/widgets/phone_input_field.dart';
import '../services/signup_service.dart';
import 'package:go_router/go_router.dart';
import 'package:sala/app_router.dart';
import '../../login/services/auth_service.dart';

class SignupScreen extends ConsumerStatefulWidget {
  final String? prefilledPhone;

  const SignupScreen({super.key, this.prefilledPhone});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  bool _isPhoneValid = false;
  bool _isLoading = false;
  String _errorMsg = '';
  String? _lastAutoCheckedPhone;
  @override
  void initState() {
    super.initState();

    // إذا جاء برقم مُدخل مسبقاً
    if (widget.prefilledPhone != null) {
      _phoneController.text = widget.prefilledPhone!;
      _lastAutoCheckedPhone = widget.prefilledPhone!;
    }
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.forward();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _animController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════
  // التحقق والانتقال
  // ══════════════════════════════════════════
  Future<void> _onNext() async {
    if (_isLoading) return;
    final phone = _phoneController.text.trim();

    if (phone.isEmpty || phone[0] != AuthService.validStartDigit) {
      setState(() =>
          _errorMsg = 'يجب أن يبدأ الرقم بـ ${AuthService.validStartDigit}');
      return;
    }
    if (!_isPhoneValid) return;

    setState(() {
      _isLoading = true;
      _errorMsg = '';
    });

    try {
      final signupService = ref.read(signupServiceProvider);
      final alreadyCheckedFromLogin = widget.prefilledPhone != null &&
          widget.prefilledPhone!.trim() == phone;

      final response = alreadyCheckedFromLogin
          ? const SignupPhoneResponse(
              result: SignupPhoneCheck.available,
            )
          : await signupService.checkPhoneAvailability(phone);
      if (!mounted) return;

      switch (response.result) {
        case SignupPhoneCheck.available:
          try {
            final session = await signupService.sendOtp(phone);
            if (!mounted) return;
            setState(() => _isLoading = false);
            context.push(
              AppRoutes.otp,
              extra: {
                'phone': phone,
                'verificationId': session.verificationId,
                'resendToken': session.resendToken,
                'isNewUser': true,
              },
            );
          } catch (error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMsg = error.toString().replaceFirst('Bad state: ', '');
              });
            }
          }
          break;

        case SignupPhoneCheck.alreadyExists:
          setState(() {
            _isLoading = false;
            _errorMsg = '';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'هذا الرقم مسجل مسبقاً، تم نقلك لتسجيل الدخول مباشرة ✅',
                  style: TextStyle(fontFamily: 'Cairo'),
                  textAlign: TextAlign.center,
                ),
                backgroundColor: AppColors.primary,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ),
            );
            context.go(AppRoutes.login, extra: phone);
          }
          break;
        case SignupPhoneCheck.error:
          setState(() {
            _isLoading = false;
            _errorMsg = response.message ?? 'حدث خطأ، حاول مجدداً';
          });
          break;
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 56),
                  // ── اللوجو ──
                  const SalaLogo(size: 90, color: AppColors.primary),
                  const SizedBox(height: 14),

                  // ── اسم التطبيق ──
                  ShaderMask(
                    shaderCallback: (bounds) =>
                        AppColors.primaryGradient.createShader(bounds),
                    child: Text(
                      'سَلة',
                      style: AppTextStyles.displaySmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),

                  // ── البطاقة الرئيسية ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: context.bgCard,
                      borderRadius: AppRadius.xxlAll,
                      boxShadow: AppShadows.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── العنوان ──
                        Text(
                          'مرحباً بك في سَلة 🎉',
                          style: AppTextStyles.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'أنشئ حسابك وابدأ الطلب الآن',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.grey700,
                          ),
                        ),

                        const SizedBox(height: 28),

                        // ── تسمية الحقل ──
                        Text(
                          'أدخل رقم الهاتف',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.grey700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // ── خانة الهاتف ──
                        PhoneInputField(
                          controller: _phoneController,
                          onChanged: (valid) {
                            setState(() {
                              _isPhoneValid = valid;
                              _errorMsg = '';
                            });

                            final currentPhone = _phoneController.text.trim();
                            if (currentPhone.length < 9) {
                              _lastAutoCheckedPhone = null;
                            }

                            // فحص تلقائي فوري بمجرد اكتمال الرقم التاسع
                            if (valid &&
                                !_isLoading &&
                                _lastAutoCheckedPhone != currentPhone) {
                              _lastAutoCheckedPhone = currentPhone;
                              _onNext();
                            }
                          },
                        ),

                        // ── رسالة خطأ ──
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          child: _errorMsg.isNotEmpty
                              ? Container(
                                  margin: const EdgeInsets.only(top: 14),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.errorSurface,
                                    borderRadius: AppRadius.mdAll,
                                    border: Border.all(
                                      color: AppColors.error
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: AppColors.error,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorMsg,
                                          style:
                                              AppTextStyles.bodySmall.copyWith(
                                            color: AppColors.error,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),

                        const SizedBox(height: 28),

                        // ── زر التالي ──
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: double.infinity,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: _isPhoneValid
                                ? AppColors.primaryGradient
                                : const LinearGradient(colors: [
                                    Color(0xFFE0E0E0),
                                    Color(0xFFE0E0E0),
                                  ]),
                            borderRadius: AppRadius.lgAll,
                            boxShadow: _isPhoneValid ? AppShadows.button : [],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: AppRadius.lgAll,
                              onTap:
                                  _isPhoneValid && !_isLoading ? _onNext : null,
                              child: Center(
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Text(
                                        'التالي',
                                        style:
                                            AppTextStyles.labelLarge.copyWith(
                                          color: _isPhoneValid
                                              ? AppColors.white
                                              : AppColors.grey500,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── لديك حساب؟ ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'لديك حساب؟  ',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: context.textSecondary,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.go(AppRoutes.login),
                        child: Text(
                          'تسجيل الدخول',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(const ClipboardData(text: '777692369'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'تم نسخ رقم خدمة العملاء: 777692369 ✅',
                            style: TextStyle(fontFamily: 'Cairo'),
                            textAlign: TextAlign.center,
                          ),
                          backgroundColor: AppColors.primary,
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.headset_mic_rounded,
                            size: 15,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'خدمة العملاء: ',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: context.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '777 692 369',
                            textDirection: TextDirection.ltr,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
