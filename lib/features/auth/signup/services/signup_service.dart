import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../login/services/auth_service.dart';

final signupServiceProvider = Provider<SignupService>(
  (ref) => SignupService(ref.watch(authServiceProvider)),
);

class SignupService {
  // كان الكود يستخدم AuthService() مباشرة (إنشاء يدوي) في مكانين أدناه،
  // متجاهلاً authServiceProvider الذي عرّفه المشروع نفسه لنفس الغرض.
  // هذا يكسر مبدأ الحقن (DI) في Riverpod، ويجعل استبدال AuthService
  // بنسخة وهمية (mock) في الاختبارات مستحيلاً، ويكسر أي حالة داخلية
  // يحتفظ بها AuthService الحقيقي (مثل قفل _otpRequestRunning) لأنه
  // يصبح بلا فائدة إذا أُنشئ Instance جديد في كل استدعاء.
  final AuthService _authService;

  SignupService(this._authService);

  // ══════════════════════════════════════════
  // إرسال رمز التحقق للمستخدم الجديد
  // ══════════════════════════════════════════

  Future<PhoneVerificationSession> sendOtp(
    String phone, {
    int? forceResendingToken,
  }) {
    return _authService.sendOtp(
      phone,
      forceResendingToken: forceResendingToken,
      purpose: 'signup',
    );
  }
  // ══════════════════════════════════════════
  // التحقق من رمز المستخدم الجديد
  // ══════════════════════════════════════════

  Future<OtpVerifyResponse> verifyOtp(
    String verificationId,
    String otp, {
    required String phone,
  }) async {
    return _authService.verifyOtp(
      verificationId: verificationId,
      otp: otp,
      phone: phone,
      purpose: 'signup',
    );
  }
}
