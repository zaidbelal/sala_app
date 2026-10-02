import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_spacing.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgPage,
      appBar: AppBar(
        backgroundColor: context.bgHeader,
        elevation: 0,
        title: Text('سياسة الخصوصية',
            style:
                AppTextStyles.titleLarge.copyWith(color: context.textPrimary)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.primary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('سياسة الخصوصية',
                style: AppTextStyles.headlineMedium.copyWith(
                    fontWeight: FontWeight.w800, color: context.textPrimary)),
            const SizedBox(height: 8),
            Text(
                'آخر تحديث: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                style: AppTextStyles.bodySmall
                    .copyWith(color: context.textSecondary)),
            const SizedBox(height: AppSpacing.lg),
            const _Section(
              title: 'المعلومات التي نجمعها',
              body:
                  'نجمع رقم الهاتف، الاسم، وعنوان المتجر لأغراض تسجيل الدخول وتنفيذ الطلبات. لا نشارك بياناتك مع أطراف ثالثة.',
            ),
            const _Section(
              title: 'استخدام الموقع الجغرافي',
              body:
                  'نستخدم موقعك الجغرافي فقط عند تحديد عنوان التوصيل. لا يتم تتبع موقعك في الخلفية.',
            ),
            const _Section(
              title: 'الإشعارات',
              body:
                  'نرسل إشعارات متعلقة بحالة طلباتك فقط. يمكنك إيقاف الإشعارات من إعدادات جهازك.',
            ),
            const _Section(
              title: 'حذف الحساب والبيانات',
              body:
                  'للحذف الكامل لحسابك وبياناتك، يمكنك تقديم الطلب مباشرة من داخل التطبيق عبر صفحة (حذف الحساب)، أو عبر الرابط الرسمي أدناه، أو بالتواصل مع خدمة العملاء.',
            ),
            const SizedBox(height: 6),
            // ── بطاقة رابط سياسة الخصوصية الخارجي الرسمي ──
            GestureDetector(
              onTap: () async {
                const urlString =
                    'https://sites.google.com/d/1FlF7VMxCBxBMQKezoMNtryfLt41TaanD/p/1mqw5-Z7T1w5Q7qtBbps_It0E3QtUc4sw/edit';
                final uri = Uri.parse(urlString);
                try {
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                } catch (_) {}
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.language_rounded,
                          color: Colors.blue, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'عرض سياسة الخصوصية الكاملة عبر الويب',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.blue,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'اضغط لفتح الصفحة الرسمية وحذف الحساب أونلاين',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.open_in_new_rounded,
                        size: 18, color: Colors.blue),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _Section(
              title: 'التواصل معنا وخدمة العملاء',
              body:
                  'لأي استفسار حول خصوصيتك أو طلب المساعدة، يسعدنا تواصلكم المباشر مع فريق خدمة العملاء عبر الرقم الموضح أدناه:',
            ),
            const SizedBox(height: 10),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.headset_mic_rounded,
                          color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'خدمة العملاء والدعم الفني (اضغط للنسخ)',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11.5,
                              color: Colors.grey,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '777 692 369',
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.copy_rounded,
                        size: 18, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700, color: context.textPrimary)),
          const SizedBox(height: 6),
          Text(body,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: context.textSecondary, height: 1.6)),
        ],
      ),
    );
  }
}
