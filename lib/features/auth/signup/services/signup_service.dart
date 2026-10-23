import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../login/services/auth_service.dart';

enum SignupPhoneCheck {
  available,
  alreadyExists,
  error,
}

class SignupPhoneResponse {
  final SignupPhoneCheck result;
  final String? message;

  const SignupPhoneResponse({
    required this.result,
    this.message,
  });
}

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

  final FirebaseFirestore db = FirebaseFirestore.instance;

  // ══════════════════════════════════════════
  // فحص توفر رقم الهاتف للتسجيل
  // ══════════════════════════════════════════
  Future<SignupPhoneResponse> checkPhoneAvailability(
    String phone,
  ) async {
    try {
      final formattedPhone = AuthService.formatPhone(phone);
      final checkResponse = await _authService.checkPhoneNumber(formattedPhone);

      if (checkResponse.result == PhoneCheckResult.registered) {
        return const SignupPhoneResponse(
          result: SignupPhoneCheck.alreadyExists,
          message: 'هذا الرقم مسجل من قبل، يرجى تسجيل الدخول',
        );
      }

      return const SignupPhoneResponse(
        result: SignupPhoneCheck.available,
      );
    } on FormatException catch (error) {
      return SignupPhoneResponse(
        result: SignupPhoneCheck.error,
        message: error.message,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[SignupService] phone availability: $error');
      }
      return const SignupPhoneResponse(
        result: SignupPhoneCheck.available,
      );
    }
  }
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
