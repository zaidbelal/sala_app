// ==================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../auth/login/services/auth_service.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

/// شاشة مستقلة لحذف الحساب — مطلوبة من سياسة Google Play لأي تطبيق
/// يسمح بإنشاء حساب داخل التطبيق نفسه (وليس فقط عبر الدعم/البريد).
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  static const _confirmWord = 'حذف';

  final _confirmCtrl = TextEditingController();
  bool _isDeleting = false;
  String? _error;

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _canDelete =>
      !_isDeleting && _confirmCtrl.text.trim() == _confirmWord;

  Future<void> _deleteAccount() async {
    if (!_canDelete) return;

    setState(() {
      _isDeleting = true;
      _error = null;
    });

    try {
      await ref.read(authServiceProvider).deleteAccount();
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
        _error = e is StateError
            ? e.message
            : 'تعذّر حذف الحساب. تحقق من اتصال الإنترنت وحاول مجددًا.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgPage,
      appBar: AppBar(
        backgroundColor: context.bgHeader,
        elevation: 0,
        iconTheme: IconThemeData(color: context.textPrimary),
        title: Text(
          'حذف الحساب',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.25),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: AppColors.error, size: 26),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'هذا الإجراء نهائي ولا يمكن التراجع عنه',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 14),
                    Text(
                      'عند حذف حسابك:',
                      style: TextStyle(
                          fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    _BulletLine(
                      'سيتم تعطيل حسابك فورًا ولن تستطيع تسجيل الدخول به مجددًا.',
                    ),
                    _BulletLine(
                      'ستُفقد بياناتك الشخصية المحفوظة على هذا الجهاز.',
                    ),
                    _BulletLine(
                      'سجلات الطلبات السابقة تُحتفظ للأغراض المحاسبية والقانونية، '
                      'ولن تكون مرتبطة بحساب فعّال يمكنك الوصول إليه.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'للتأكيد، اكتب كلمة "$_confirmWord" في الحقل أدناه:',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirmCtrl,
                onChanged: (_) => setState(() {}),
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontFamily: 'Cairo', color: context.textPrimary),
                decoration: InputDecoration(
                  hintText: _confirmWord,
                  hintStyle: TextStyle(color: context.textHint),
                  filled: true,
                  fillColor: context.bgInput,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: context.borderColor,
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: AppColors.error,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: _canDelete ? _deleteAccount : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  icon: _isDeleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.delete_forever_rounded),
                  label: const Text(
                    'حذف الحساب نهائيًا',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 54,
                child: OutlinedButton(
                  onPressed:
                      _isDeleting ? null : () => Navigator.of(context).pop(),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  final String text;
  const _BulletLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontFamily: 'Cairo')),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}


// ==================================================