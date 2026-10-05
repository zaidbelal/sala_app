import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/services/local_storage.dart';
import '../../../../auth/login/services/auth_service.dart';
import '../../../cart/providers/cart_provider.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import 'package:sala/core/constants/app_theme.dart';

class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  bool _isSigningOut = false;

  /// دالة تنظيف الرقم من مفتاح الدولة (+967)
  String _cleanPhone(String raw) {
    var p = raw.replaceAll(RegExp(r'[\s()-]'), '').trim();
    if (p.startsWith('+967')) p = p.substring(4);
    if (p.startsWith('00967')) p = p.substring(5);
    if (p.startsWith('967')) p = p.substring(3);
    return p;
  }

  Future<void> _signOut() async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          backgroundColor: context.bgCard,
          title: Text(
            'تسجيل الخروج',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          content: Text(
            'هل تريد تسجيل الخروج من حسابك والعودة لشاشة الدخول؟',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              color: context.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'إلغاء',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'تسجيل الخروج',
                style:
                    TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSigningOut = true);

    try {
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(cartProvider);
      await ref.read(authServiceProvider).signOut();

      if (!mounted) return;
      context.go('/login');
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = AppStorage.userName ?? '';
    final rawPhone = AppStorage.userPhone ?? '';
    final phone = _cleanPhone(rawPhone);
    final role = AppStorage.userRole ?? 'merchant';

    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            // ── ترويسة الشاشة ──
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الملف الشخصي',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        'إدارة بيانات حسابك وتفضيلات التطبيق',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── بطاقة الحساب الرئيسية الفاخرة (Hero Card) ──
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF0F5A27),
                    Color(0xFF1B8E3D),
                    Color(0xFF2DB85B),
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1B8E3D).withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // ── شخصية التاجر اليمني ثلاثية الأبعاد (3D) ──
                  const _YemeniMerchantAvatar(size: 72),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'التاجر' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                role == 'merchant' ? 'حساب تاجر 🏪' : role,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              '•  مفعّل ✓',
                              style: TextStyle(
                                color: Color(0xFFB9F6CA),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── بطاقات المعلومات الشخصية ──
            Text(
              'البيانات الأساسية',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 10),

            _buildTile(
              context: context,
              icon: Icons.person_outline_rounded,
              title: 'الاسم الكامل',
              value: name,
            ),
            _buildTile(
              context: context,
              icon: Icons.phone_android_rounded,
              title: 'رقم الهاتف',
              value: phone,
              trailing: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Clipboard.setData(ClipboardData(text: phone));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'تم نسخ الرقم بنجاح ✅',
                        style: TextStyle(fontFamily: 'Cairo'),
                        textAlign: TextAlign.center,
                      ),
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_rounded,
                          size: 13, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text(
                        'نسخ',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildTile(
              context: context,
              icon: Icons.verified_user_outlined,
              title: 'نوع الحساب والصلاحية',
              value: role == 'merchant' ? 'تاجر تجزئة معتمد' : role,
            ),

            const SizedBox(height: 20),

            // ── إعدادات وتفضيلات التطبيق ──
            Text(
              'التفضيلات والخصوصية',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 10),

            // تبديل المظهر (داكن / فاتح)
            _buildTile(
              context: context,
              icon: context.isDark
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              title: 'مظهر التطبيق',
              value: context.isDark ? 'الوضع الداكن' : 'الوضع الفاتح',
              trailing: Switch.adaptive(
                value: context.isDark,
                activeTrackColor: AppColors.primary,
                onChanged: (isDark) {
                  HapticFeedback.lightImpact();
                  final newMode = isDark ? 'dark' : 'light';
                  AppStorage.saveThemeMode(newMode);
                  ref.read(themeProvider.notifier).state =
                      isDark ? ThemeMode.dark : ThemeMode.light;
                },
              ),
            ),

            // زر سياسة الخصوصية
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                context.push('/privacy');
              },
              child: _buildTile(
                context: context,
                icon: Icons.shield_outlined,
                title: 'سياسة الخصوصية',
                value: 'الشروط والأحكام وحماية البيانات',
                trailing: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 14,
                  color: Colors.grey,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── زر تسجيل الخروج ──
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _isSigningOut ? null : _signOut,
                icon: _isSigningOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_rounded, size: 18),
                label: const Text(
                  'تسجيل الخروج',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.35),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── زر حذف الحساب ──
            Center(
              child: TextButton(
                onPressed: _isSigningOut
                    ? null
                    : () => context.push('/delete-account'),
                child: const Text(
                  'حذف الحساب نهائياً',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.borderColor,
        ),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? 'غير متوفر' : value,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// مجسم الشخصية اليمنية ثلاثية الأبعاد (3D) داخل متجره بدون ملامح
// ══════════════════════════════════════════════════════════════
class _YemeniMerchantAvatar extends StatelessWidget {
  final double size;
  const _YemeniMerchantAvatar({this.size = 72});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD54F), Color(0xFF1B8E3D), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: const Color(0xFFFFD54F).withValues(alpha: 0.35),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.all(2.5),
      child: ClipOval(
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E2A38),
          ),
          child: CustomPaint(
            size: Size(size, size),
            painter: _Yemeni3DAvatarPainter(),
          ),
        ),
      ),
    );
  }
}

class _Yemeni3DAvatarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── 1. خلفية المتجر الدافئة (رفوف وإضاءة دافئة) ──
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.3),
        radius: 0.85,
        colors: [
          const Color(0xFF8D5B28).withValues(alpha: 0.9), // إضاءة رفوف خشبية
          const Color(0xFF2B1D0E),
          const Color(0xFF0F141C),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    // خطوط رفوف المتجر في الخلفية
    final shelfPaint = Paint()
      ..color = const Color(0xFFD7A15C).withValues(alpha: 0.25)
      ..strokeWidth = w * 0.035
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, h * 0.38), Offset(w, h * 0.38), shelfPaint);
    canvas.drawLine(Offset(0, h * 0.52), Offset(w, h * 0.52), shelfPaint);

    // ── 2. الجسم (الثوب الأبيض والكوت/الصديري اليمني) ──
    // الثوب الأساسي
    final thobePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFFFFFFFF), Color(0xFFD6DCE5)],
      ).createShader(Rect.fromLTWH(w * 0.25, h * 0.65, w * 0.5, h * 0.35));

    final thobePath = Path()
      ..moveTo(w * 0.32, h * 0.68)
      ..lineTo(w * 0.68, h * 0.68)
      ..lineTo(w * 0.85, h)
      ..lineTo(w * 0.15, h)
      ..close();
    canvas.drawPath(thobePath, thobePaint);

    // الكوت / الصديري التقليدي الداكن الفخم مع تظليل 3D
    final vestPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2C3E50), Color(0xFF1A252F), Color(0xFF0E171E)],
      ).createShader(Rect.fromLTWH(0, h * 0.65, w, h * 0.35));

    // الجانب الأيمن للصديري
    final vestRight = Path()
      ..moveTo(w * 0.2, h * 0.72)
      ..quadraticBezierTo(w * 0.35, h * 0.73, w * 0.38, h * 0.95)
      ..lineTo(w * 0.12, h)
      ..lineTo(w * 0.05, h * 0.8)
      ..close();
    canvas.drawPath(vestRight, vestPaint);

    // الجانب الأيسر للصديري
    final vestLeft = Path()
      ..moveTo(w * 0.8, h * 0.72)
      ..quadraticBezierTo(w * 0.65, h * 0.73, w * 0.62, h * 0.95)
      ..lineTo(w * 0.88, h)
      ..lineTo(w * 0.95, h * 0.8)
      ..close();
    canvas.drawPath(vestLeft, vestPaint);

    // خط حواف ذهبية تقليدية للصديري (تطريز)
    final goldTrim = Paint()
      ..color = const Color(0xFFFFD54F).withValues(alpha: 0.8)
      ..strokeWidth = w * 0.018
      ..style = PaintingStyle.stroke;
    canvas.drawPath(vestRight, goldTrim);
    canvas.drawPath(vestLeft, goldTrim);

    // ── 3. الرقبة ──
    final neckPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFDCA172), Color(0xFFB87848)],
      ).createShader(Rect.fromLTWH(w * 0.42, h * 0.54, w * 0.16, h * 0.16));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.61),
            width: w * 0.18,
            height: h * 0.16),
        Radius.circular(w * 0.08),
      ),
      neckPaint,
    );

    // ── 4. الرأس والوجه المودرن بدون ملامح مع إضاءة 3D ──
    final headRect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.45),
      width: w * 0.38,
      height: h * 0.42,
    );

    final facePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.3),
        radius: 0.75,
        colors: const [
          Color(0xFFF7C8A0), // ضوء علوي
          Color(0xFFE4AA7D),
          Color(0xFFC88554), // تظليل سفلي ثلاثي الأبعاد
        ],
      ).createShader(headRect);

    canvas.drawOval(headRect, facePaint);

    // ── 5. الشال / العمامة اليمنية الملتفة (اللفة اليمنية التقليدية الأصيلة 3D) ──
    // تظليل العمامة السفلي
    final turbanShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.32), width: w * 0.52, height: h * 0.32),
      turbanShadow,
    );

    // الطبقة الأساسية للعمامة اليمنية
    final turbanBasePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFAF7F2),
          Color(0xFFE0D5C1),
          Color(0xFFBFAF95),
        ],
      ).createShader(Rect.fromLTWH(w * 0.2, h * 0.15, w * 0.6, h * 0.35));

    final turbanPath = Path()
      ..moveTo(w * 0.22, h * 0.36)
      ..quadraticBezierTo(w * 0.18, h * 0.22, w * 0.38, h * 0.16)
      ..quadraticBezierTo(w * 0.52, h * 0.13, w * 0.72, h * 0.18)
      ..quadraticBezierTo(w * 0.84, h * 0.25, w * 0.78, h * 0.38)
      ..quadraticBezierTo(w * 0.5, h * 0.44, w * 0.22, h * 0.36)
      ..close();
    canvas.drawPath(turbanPath, turbanBasePaint);

    // طيات ولفات الشال اليمني (نقشات وطيات ثلاثية الأبعاد)
    final foldPaint1 = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFC0392B),
          Color(0xFF8E1B1B)
        ], // نقشة الشال اليمني الماروني
      ).createShader(Rect.fromLTWH(w * 0.24, h * 0.24, w * 0.52, h * 0.08))
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.04
      ..strokeCap = StrokeCap.round;

    final foldPath1 = Path()
      ..moveTo(w * 0.25, h * 0.34)
      ..quadraticBezierTo(w * 0.5, h * 0.40, w * 0.75, h * 0.34);
    canvas.drawPath(foldPath1, foldPaint1);

    final foldPaint2 = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFAF0E6), Color(0xFFD2B48C)],
      ).createShader(Rect.fromLTWH(w * 0.25, h * 0.18, w * 0.5, h * 0.08))
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;

    final foldPath2 = Path()
      ..moveTo(w * 0.26, h * 0.27)
      ..quadraticBezierTo(w * 0.52, h * 0.31, w * 0.74, h * 0.25);
    canvas.drawPath(foldPath2, foldPaint2);

    // زاوية العقدة والتاج العلوي للعمامة
    final turbanCrown = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFFFFFFFF), Color(0xFFD7CCC8)],
      ).createShader(Rect.fromLTWH(w * 0.4, h * 0.12, w * 0.25, h * 0.12));
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.18), width: w * 0.36, height: h * 0.12),
      turbanCrown,
    );

    // خط ذهبي زخرفي في العمامة
    final goldBand = Paint()
      ..color = const Color(0xFFFFD54F)
      ..strokeWidth = w * 0.015
      ..style = PaintingStyle.stroke;
    canvas.drawPath(foldPath1, goldBand);

    // ── 6. طبقة لمعان زجاجية علوية ناعمة (3D Gloss Highlight) ──
    final glossPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.28),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w * 0.7, h * 0.7));

    canvas.drawOval(
      Rect.fromLTWH(w * 0.1, h * 0.05, w * 0.5, h * 0.35),
      glossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
