import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../login/services/auth_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radius.dart';
import '../../../core/constants/app_shadows.dart';
import '../../../core/constants/app_adaptive_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/local_storage.dart';
import '../../../core/services/realtime_hub.dart';
import '../../splash/widgets/sala_logo.dart';
import 'widgets/map_location_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../../../core/services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignupDetailsScreen extends ConsumerStatefulWidget {
  final String phone;

  const SignupDetailsScreen({super.key, required this.phone});

  @override
  ConsumerState<SignupDetailsScreen> createState() =>
      _SignupDetailsScreenState();
}

class _SignupDetailsScreenState extends ConsumerState<SignupDetailsScreen>
    with SingleTickerProviderStateMixin {
  final _fullNameController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _fullNameFocus = FocusNode();
  final _shopNameFocus = FocusNode();

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  LatLng? _selectedLocation;
  bool _isLoading = false;

  String _fullNameError = '';
  String _locationError = '';
  String _shopNameError = '';

  @override
  void initState() {
    super.initState();
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
    _fullNameController.addListener(_validateAll);
    _shopNameController.addListener(_validateAll);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _shopNameController.dispose();
    _fullNameFocus.dispose();
    _shopNameFocus.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _validateAll() => setState(() {});

  bool _validateFullName({bool showError = false}) {
    final name = _fullNameController.text.trim();
    if (name.isEmpty) {
      if (showError) setState(() => _fullNameError = 'الاسم الرباعي مطلوب');
      return false;
    }
    final parts =
        name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length < 4) {
      if (showError) {
        setState(() => _fullNameError =
            'يجب إدخال الاسم الرباعي كاملاً (${parts.length}/4)');
      }
      return false;
    }
    if (showError) setState(() => _fullNameError = '');
    return true;
  }

  bool _validateLocation({bool showError = false}) {
    if (_selectedLocation == null) {
      if (showError) {
        setState(() => _locationError = 'يجب تحديد موقع البقالة على الخريطة');
      }
      return false;
    }
    if (showError) setState(() => _locationError = '');
    return true;
  }

  bool _validateShopName({bool showError = false}) {
    final name = _shopNameController.text.trim();
    if (name.isEmpty) {
      if (showError) setState(() => _shopNameError = 'اسم البقالة مطلوب');
      return false;
    }
    if (name.length < 2) {
      if (showError) setState(() => _shopNameError = 'اسم البقالة قصير جداً');
      return false;
    }
    if (showError) setState(() => _shopNameError = '');
    return true;
  }

  bool get _allValid =>
      _validateFullName() && _validateLocation() && _validateShopName();

  Future<void> _openMap() async {
    final result = await showModalBottomSheet<LatLng>(
      context: context,
      isScrollControlled: true,
      enableDrag: false, // 👈 منع النافذة من سرقة سحب ولمسات الخريطة
      backgroundColor: Colors.transparent,
      builder: (_) =>
          MapLocationPickerSheet(initialLocation: _selectedLocation),
    );
    if (result != null) {
      setState(() {
        _selectedLocation = result;
        _locationError = '';
      });
    }
  }

  Future<bool> _onWillPop() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.xlAll,
        ),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: AppColors.warning, size: 24),
            SizedBox(width: 10),
            Text('تنبيه أمني'),
          ],
        ),
        content: Text(
          'إذا رجعت الآن، ستحتاج إلى إعادة إرسال رمز التحقق مجدداً للتأكد من هويتك.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.grey700,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'إكمال التسجيل',
              style:
                  AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'رجوع',
              style: AppTextStyles.labelMedium.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        context.go('/login');
      }
    }
    return false;
  }

  Future<void> _onSubmit() async {
    final nameOk = _validateFullName(showError: true);
    final locationOk = _validateLocation(showError: true);
    final shopOk = _validateShopName(showError: true);
    if (!nameOk || !locationOk || !shopOk) {
      HapticFeedback.vibrate();
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      final formattedPhone = AuthService.formatPhone(widget.phone);
      final firebaseUser = FirebaseAuth.instance.currentUser;

      if (firebaseUser == null) {
        throw StateError('انتهت جلسة التحقق، يرجى إعادة المحاولة');
      }

      final userId = firebaseUser.uid;
      final fullName = _fullNameController.text.trim();
      final storeName = _shopNameController.text.trim();
      final lat = _selectedLocation!.latitude;
      final lng = _selectedLocation!.longitude;

      // ── إنشاء وتوثيق البروفايل مباشرة في Firestore ──
      await FirebaseFirestore.instance.collection('profiles').doc(userId).set({
        'full_name': fullName,
        'store_name': storeName,
        'phone_number': formattedPhone,
        'latitude': lat,
        'longitude': lng,
        'role': 'merchant',
        'is_active': false, // بانتظار موافقة الإدارة
        'is_banned': false,
        'account_status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // ── حفظ البيانات محلياً في ذاكرة الهاتف ──
      await AppStorage.saveUserData(
        userId: userId,
        role: 'merchant',
        name: fullName,
        phone: formattedPhone,
      );
      await AppStorage.setIsActive(false);
      await AppStorage.setIsBanned(false);

      // ── ربط رمز الإشعارات FCM ──
      try {
        await NotificationService.instance.saveTokenToFirestore(userId);
      } catch (_) {}

      // ── بدء الاستماع اللحظي لتوجيه التاجر تلقائياً فور موافقة الإدارة ──
      await RealtimeHub().startForUser(userId, role: 'merchant');

      if (!mounted) return;
      setState(() => _isLoading = false);

      // التوجيه إلى شاشة انتظار التفعيل
      context.go('/pending');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _shopNameError = e.message ?? 'حدث خطأ في قاعدة البيانات، حاول مجدداً';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _shopNameError = 'خطأ: ${e.toString().replaceAll("Exception: ", "")}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _onWillPop();
      },
      child: Scaffold(
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
                          onPressed: () async => await _onWillPop(),
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          color: context.textPrimary,
                        ),
                        Expanded(
                          child: Text('إنشاء حساب',
                              style: AppTextStyles.titleLarge.copyWith(
                                color: context.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                              textAlign: TextAlign.center),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SalaLogo(
                                  size: 36, color: AppColors.primary),
                              const SizedBox(width: 10),
                              ShaderMask(
                                shaderCallback: (b) =>
                                    AppColors.primaryGradient.createShader(b),
                                child: Text(
                                  'سَلة',
                                  style: AppTextStyles.headlineMedium.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: List.generate(3, (i) {
                              return Expanded(
                                child: Container(
                                  margin: EdgeInsets.only(left: i < 2 ? 6 : 0),
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: i == 1
                                        ? AppColors.primary
                                        : AppColors.grey200,
                                    borderRadius: AppRadius.circleAll,
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text('الخطوة 2 من 3',
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: AppColors.grey500)),
                          ),
                          const SizedBox(height: 20),
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
                                Text('بيانات حسابك',
                                    style: AppTextStyles.headlineSmall.copyWith(
                                      color: context.textPrimary,
                                      fontWeight: FontWeight.w900,
                                    )),
                                const SizedBox(height: 4),
                                Text(
                                  'أدخل بياناتك بدقة لمراجعة حسابك',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: context.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const _FieldLabel(
                                    label: 'الاسم الرباعي', isRequired: true),
                                const SizedBox(height: 8),
                                _buildTextField(
                                  controller: _fullNameController,
                                  focusNode: _fullNameFocus,
                                  hint: 'أحمد محمد علي سالم',
                                  icon: Icons.person_rounded,
                                  errorText: _fullNameError,
                                  onChanged: (_) => _validateAll(),
                                  onFieldSubmitted: (_) =>
                                      _shopNameFocus.requestFocus(),
                                  textInputAction: TextInputAction.next,
                                ),
                                _buildNameCounter(),
                                const SizedBox(height: 20),
                                const _FieldLabel(
                                    label: 'موقع البقالة', isRequired: true),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: _openMap,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: _selectedLocation != null
                                          ? AppColors.primarySurface
                                          : context.bgInput,
                                      borderRadius: AppRadius.mdAll,
                                      border: Border.all(
                                        // ✅ إصلاح: withValues بدلاً من withOpacity
                                        color: _locationError.isNotEmpty
                                            ? AppColors.error
                                            : _selectedLocation != null
                                                ? AppColors.primary
                                                    .withValues(alpha: 0.5)
                                                : AppColors.grey300,
                                        width:
                                            _selectedLocation != null ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          _selectedLocation != null
                                              ? Icons.location_on_rounded
                                              : Icons.add_location_alt_rounded,
                                          color: _selectedLocation != null
                                              ? AppColors.primary
                                              : AppColors.grey500,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _selectedLocation != null
                                              ? Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'تم تحديد الموقع ✅',
                                                      style: AppTextStyles
                                                          .bodyMedium
                                                          .copyWith(
                                                        color:
                                                            AppColors.primary,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    Text(
                                                      '${_selectedLocation!.latitude.toStringAsFixed(4)}, '
                                                      '${_selectedLocation!.longitude.toStringAsFixed(4)}',
                                                      style: AppTextStyles
                                                          .bodySmall
                                                          .copyWith(
                                                              color: AppColors
                                                                  .grey500),
                                                    ),
                                                  ],
                                                )
                                              : Text(
                                                  'اضغط لتحديد موقعك على الخريطة',
                                                  style: AppTextStyles
                                                      .bodyMedium
                                                      .copyWith(
                                                          color: AppColors
                                                              .grey500),
                                                ),
                                        ),
                                        Icon(
                                          Icons.map_rounded,
                                          color: _selectedLocation != null
                                              ? AppColors.primary
                                              : AppColors.grey500,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                _buildErrorText(_locationError),
                                const SizedBox(height: 20),
                                const _FieldLabel(
                                    label: 'اسم البقالة', isRequired: true),
                                const SizedBox(height: 8),
                                _buildTextField(
                                  controller: _shopNameController,
                                  focusNode: _shopNameFocus,
                                  hint: 'بقالة الأمين',
                                  icon: Icons.storefront_rounded,
                                  errorText: _shopNameError,
                                  onChanged: (_) => _validateAll(),
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) =>
                                      _shopNameFocus.unfocus(),
                                ),
                                const SizedBox(height: 28),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: double.infinity,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    gradient: _allValid
                                        ? AppColors.primaryGradient
                                        : const LinearGradient(colors: [
                                            Color(0xFFE0E0E0),
                                            Color(0xFFE0E0E0),
                                          ]),
                                    borderRadius: AppRadius.lgAll,
                                    boxShadow:
                                        _allValid ? AppShadows.button : [],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: AppRadius.lgAll,
                                      onTap: _allValid && !_isLoading
                                          ? _onSubmit
                                          : null,
                                      child: Center(
                                        child: _isLoading
                                            ? const SizedBox(
                                                width: 24,
                                                height: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                  color: Colors.white,
                                                  strokeWidth: 2.5,
                                                ),
                                              )
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'إكمال التسجيل',
                                                    style: AppTextStyles
                                                        .labelLarge
                                                        .copyWith(
                                                      color: _allValid
                                                          ? AppColors.white
                                                          : AppColors.grey500,
                                                    ),
                                                  ),
                                                  if (_allValid) ...[
                                                    const SizedBox(width: 8),
                                                    const Icon(
                                                      Icons
                                                          .arrow_forward_rounded,
                                                      color: Colors.white,
                                                      size: 20,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
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
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    required String errorText,
    required void Function(String) onChanged,
    required void Function(String) onFieldSubmitted,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    final hasError = errorText.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            color: hasError ? AppColors.errorSurface : AppColors.grey100,
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              // ✅ إصلاح: withValues بدلاً من withOpacity
              color: hasError
                  ? AppColors.error
                  : controller.text.isNotEmpty
                      ? AppColors.primary.withValues(alpha: 0.5)
                      : AppColors.grey300,
              width: controller.text.isNotEmpty ? 1.5 : 1,
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: textInputAction,
            textDirection:
                TextDirection.rtl, // 👈 ضبط اتجاه النص العربي دائماً من اليمين
            cursorColor: AppColors.primary,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              color: context.textPrimary,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: context.textHint,
              ),
              prefixIcon: Icon(
                icon,
                color: hasError
                    ? AppColors.error
                    : controller.text.isNotEmpty
                        ? AppColors.primary
                        : AppColors.grey500,
                size: 20,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: onChanged,
            onSubmitted: onFieldSubmitted,
          ),
        ),
        _buildErrorText(errorText),
      ],
    );
  }

  Widget _buildNameCounter() {
    final text = _fullNameController.text.trim();
    final parts = text.isEmpty
        ? 0
        : text.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).length;

    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 4, left: 4),
      child: Row(
        children: [
          // ── الخطوط الأربعة التفاعلية ──
          ...List.generate(4, (i) {
            final filled = i < parts;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 5,
                decoration: BoxDecoration(
                  color: filled
                      ? AppColors.primary
                      : (context.isDark
                          ? const Color(0xFF2C2C2C)
                          : const Color(0xFFE0E0E0)),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: filled
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : [],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildErrorText(String error) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: error.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 6, right: 4),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 14),
                  const SizedBox(width: 4),
                  Text(error,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w500,
                      )),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool isRequired;

  const _FieldLabel({required this.label, this.isRequired = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: AppTextStyles.labelMedium.copyWith(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF9E9E9E)
                  : AppColors.grey700,
              fontWeight: FontWeight.w600,
            )),
        if (isRequired) ...[
          const SizedBox(width: 4),
          const Text('*',
              style: TextStyle(
                color: AppColors.error,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              )),
        ],
      ],
    );
  }
}
