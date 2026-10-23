import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_spacing.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _privacyPolicyWebUrl =
      'https://sites.google.com/view/salla-yemen-privacy';
  Future<void> _launchUrl(BuildContext context, String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر فتح الرابط الخارجي، يرجى المحاولة لاحقاً',
                  style: TextStyle(fontFamily: 'Cairo')),
            ),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('حدث خطأ أثناء فتح الرابط',
                style: TextStyle(fontFamily: 'Cairo')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgPage,
      appBar: AppBar(
        backgroundColor: context.bgHeader,
        elevation: 0,
        title: Text(
          'سياسة الخصوصية وأمان البيانات',
          style: AppTextStyles.titleLarge.copyWith(color: context.textPrimary),
        ),
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
            Text(
              'سياسة الخصوصية وحماية البيانات لمنصة سَلة',
              style: AppTextStyles.headlineMedium.copyWith(
                fontWeight: FontWeight.w800,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'تاريخ السريان: متوافق مع لوائح حماية البيانات وسياسات متجر Google Play',
              style: AppTextStyles.bodySmall
                  .copyWith(color: context.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),

            const _Section(
              title: '1. البيانات التي نجمعها والأغراض التشغيلية',
              body:
                  'نقوم بجمع بيانات الحساب الأساسية وتتضمن: رقم الهاتف للتحقق والمصادقة، الاسم الرباعي، واسم المتجر التجاري لغرض إنشاء الحساب وتوثيقه. هذه البيانات ضرورية لتقديم خدمات التوزيع وإتمام دورة البيع والشحن.',
            ),

            const _Section(
              title: '2. استخدام الكاميرا ومسح الباركود (Camera Permission)',
              body:
                  'يطلب التطبيق الإذن للوصول إلى الكاميرا حصراً لتمكين التجار من مسح الباركود الدولي الخاص بالمنتجات والكراتين لإضافتها إلى السلة أو دفتر الديون بسرعة ودقة. لا يقوم التطبيق بتسجيل أو رفع مقاطع فيديو أو صور شخصية للمستخدم عبر الكاميرا إلى أي خوادم خارجية دون إذن صريح.',
            ),

            const _Section(
              title: '3. استخدام الموقع الجغرافي الدقيق (Precise Location GPS)',
              body:
                  'يستخدم التطبيق الموقع الجغرافي فقط أثناء استخدام الواجهة (Foreground) لتحديد موقع البقالة أو المتجر على الخريطة لتوجيه مندوبي الشحن وسائقي التوزيع إليها بدقة. نؤكد أن التطبيق لا يقوم بتتبع الموقع في الخلفية عند إغلاق التطبيق نهائياً.',
            ),

            const _Section(
              title:
                  '4. بيانات المعاملات المالية ودفتر الديون (Financial Records)',
              body:
                  'البيانات المسجلة في دفتر الديون (مثل أسماء الزبائن، أرقام هواتفهم، ومبالغ الديون والسداد) هي سجلات تجارية خاصة بالتاجر وحده، وتخضع لبروتوكولات تشفير آمنة ولا يتم بيعها أو مشاركتها مع أي جهات تسويقية خارجية.',
            ),

            const _Section(
              title: '5. التوقيع الرقمي وإثبات التسليم (Proof of Delivery)',
              body:
                  'قد يطلب التطبيق توقيع المستلم على الشاشة كإجراء إثبات تسليم رسمي للفاتورة لحماية حقوق التاجر والمندوب ومنع النزاعات القانونية، وتُحفظ صورة التوقيع ضمن الفاتورة الإلكترونية الخاصة بالطلب فقط.',
            ),

            const _Section(
              title: '6. حزم الخدمات الخارجية والتشخيص (Third-Party Services)',
              body:
                  'يعتمد التطبيق على بنية تحتية سحابية موثوقة تشمل: Firebase Authentication للمصادقة الآمنة، Cloud Firestore لقاعدة البيانات المشفرة، Firebase Cloud Messaging لإرسال إشعارات التحديثات، و Firebase Crashlytics لرصد الأعطال البرمجية ومعالجتها لتحسين استقرار التطبيق دون جمع بيانات تعريفية شخصية غير مصرح بها.',
            ),
            const _Section(
              title: '7. سياسة حذف الحساب والبيانات (Account & Data Deletion)',
              body:
                  'يحق لك طلب حذف حسابك وكافة بياناتك نهائياً في أي وقت مباشرةً وبكل سهولة من داخل التطبيق عبر تبويب (حسابي > حذف الحساب نهائياً).',
            ),

            const SizedBox(height: 14),
            // زر استعراض السياسة الكاملة على الويب
            GestureDetector(
              onTap: () => _launchUrl(context, _privacyPolicyWebUrl),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.language_rounded, color: Colors.blue, size: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'استعراض سياسة الخصوصية المعتمدة عبر الويب',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.blue,
                            ),
                          ),
                          Text(
                            'اضغط للاطلاع على الوثيقة الموثقة والمقدمة لمتجر Google Play',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.open_in_new_rounded,
                        size: 18, color: Colors.blue),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            const _Section(
              title: '8. التواصل والدعم الفني',
              body:
                  'للاستفسار عن سياسة الخصوصية، أو لطلب تصحيح أي بيانات، يمكنك التواصل مباشرةً مع مسؤولي أمان البيانات وخدمة العملاء عبر الرقم الموضح أدناه:',
            ),
            const SizedBox(height: 8),

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
          Text(
            title,
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.textSecondary,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}
