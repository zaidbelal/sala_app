import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OtpVerificationRejected implements Exception {
  final String message;
  const OtpVerificationRejected(this.message);

  @override
  String toString() => message;
}

class QuickConnectOtpService {
  QuickConnectOtpService._();

  static final FirebaseFunctions functions = FirebaseFunctions.instance;

  // ════════════════════════════════════════════════════════════
  // 🛠️ قائمة أرقام الاختبار لـ Firebase (يمكنك إضافة أي رقم هنا)
  // ════════════════════════════════════════════════════════════
  static const Set<String> _firebaseTestNumbers = {
    '+967777700002',
    '+967777700001',
    '+967777700000',
    '+967777700003',
    '+967777700004',
    '+967777700005',
    '+967777700006',
    '+967777700007',
    '+967777700008',
    '+967777700009',
    '+967777700010',
    '+967777700011',
    '+967777700012',
    '+967777700013',
    '+967777700014',
    '+967777700015',
    '+967777700016',
    '+967777700017',
    '+967777700018',
    '+967777700019',
    '+967777700020',
    '+967777700021',
    '+967777700022',
  };

  /// هل الرقم تجريبي خاص بـ Firebase؟
  //static bool isFirebaseTestPhone(String phone) {
  //  final clean = normalizeCode(phone);
  //  if (_firebaseTestNumbers.contains(phone) ||
  //     _firebaseTestNumbers.contains(clean)) {
  //    return true;
  //  }
  // الأرقام التجريبية الشائعة
//    return clean.contains('77770000') || clean.contains('70000000');
//  }
  /// هل الرقم تجريبي خاص بـ Firebase؟
  /// ⚠️ إصلاح أمني حرج: مطابقة تامة فقط (Exact Match).
  /// كان الكود السابق يستخدم contains() مما يسمح لأي رقم حقيقي يحتوي على
  /// سلسلة مشابهة (مثل +96777770000XX) بتجاوز تحقق WhatsApp والدخول عبر
  /// نظام Firebase Test OTP المكشوف.
  static bool isFirebaseTestPhone(String phone) {
    // حظر أرقام الاختبار في بيئة الإنتاج Release تماماً لمنع تجاوز التحقق الأمني
    if (kReleaseMode) return false;
    final clean = normalizeCode(phone);
    return _firebaseTestNumbers.contains(phone) ||
        _firebaseTestNumbers.contains(clean);
  }

  static const _arabicDigits = <String, String>{
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
  };

  static String normalizeCode(String value) {
    final cleanValue = value.trim().replaceAll(RegExp(r'\s+'), '');
    return cleanValue.split('').map((c) => _arabicDigits[c] ?? c).join();
  }

  static Map<String, dynamic> readResult(HttpsCallableResult raw) {
    final decoded = raw.data;
    if (decoded is! Map) {
      throw StateError('استجابة الخادم غير صحيحة');
    }
    return Map<String, dynamic>.from(decoded);
  }

  // ════════════════════════════════════════════════════════════
  // 🚀 SEND OTP: ذكي (Firebase للأرقام التجريبية + واتساب للباقي)
  // ════════════════════════════════════════════════════════════
  static Future<String> send({
    required String phone,
    required String purpose,
  }) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty) {
      throw StateError('رقم الهاتف غير صحيح');
    }

    // ── 1. إذا كان رقم اختبار تجريبي: استخدم Firebase مباشرة بكوده الثابت ──
    if (isFirebaseTestPhone(cleanPhone)) {
      final completer = Completer<String>();
      try {
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: cleanPhone,
          timeout: const Duration(seconds: 30),
          verificationCompleted: (PhoneAuthCredential credential) async {
            await FirebaseAuth.instance.signInWithCredential(credential);
          },
          verificationFailed: (FirebaseAuthException e) {
            if (!completer.isCompleted) {
              completer.completeError(
                  StateError(e.message ?? 'فشل التحقق من فايربيز'));
            }
          },
          codeSent: (String verificationId, int? resendToken) {
            if (!completer.isCompleted) {
              completer.complete('fb_test_$verificationId');
            }
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            if (!completer.isCompleted) {
              completer.complete('fb_test_$verificationId');
            }
          },
        );
        return await completer.future;
      } catch (e) {
        if (e is StateError) rethrow;
        throw StateError('تعذر إرسال رمز الاختبار: $e');
      }
    }

    // ── 2. للأرقام الحقيقية لجميع التجار: إرسال فوري إلى الواتساب عبر Green-API ──
    try {
      final callable = functions.httpsCallable(
        'requestOtp',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
      );

      final result = await callable.call({
        'phone': cleanPhone,
        'purpose': purpose,
      });

      final data = readResult(result);
      if (data['success'] != true) {
        throw StateError(
            data['message']?.toString() ?? 'تعذر إرسال رمز التحقق عبر واتساب');
      }

      return 'wa_${data['verificationId']?.toString() ?? cleanPhone}';
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'فشل إرسال كود الواتساب');
    } catch (e) {
      if (e is StateError) rethrow;
      throw StateError('تعذر الاتصال بخدمة التحقق: $e');
    }
  }

  // ════════════════════════════════════════════════════════════
  // 🔐 VERIFY OTP: يتحقق إما من Firebase أو من كود الواتساب
  // ════════════════════════════════════════════════════════════
  static Future<String?> verify({
    required String verificationId,
    required String phone,
    required String code,
    required String purpose,
  }) async {
    final cleanCode = normalizeCode(code);
    if (!RegExp(r'^\d{6}$').hasMatch(cleanCode)) {
      throw const OtpVerificationRejected('أدخل رمز التحقق المكوّن من 6 أرقام');
    }

    // ── 1. إذا كان التوثيق عبر رقم تجريبي لفايربيز ──
    if (verificationId.startsWith('fb_test_')) {
      final actualVerificationId = verificationId.replaceFirst('fb_test_', '');
      try {
        final credential = PhoneAuthProvider.credential(
          verificationId: actualVerificationId,
          smsCode: cleanCode,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
        return 'firebase_phone_verified';
      } on FirebaseAuthException catch (e) {
        if (e.code == 'invalid-verification-code') {
          throw const OtpVerificationRejected('رمز التحقق التجريبي غير صحيح');
        }
        throw OtpVerificationRejected(e.message ?? 'فشل التحقق التجريبي');
      } catch (e) {
        if (e is OtpVerificationRejected) rethrow;
        throw OtpVerificationRejected('خطأ في التحقق التجريبي: $e');
      }
    }

    // ── 2. للتحقق من كود الواتساب (Green-API) للأرقام الحقيقية ──
    final actualWaVerificationId = verificationId.startsWith('wa_')
        ? verificationId.replaceFirst('wa_', '')
        : verificationId;

    try {
      final callable = functions.httpsCallable(
        'verifyOtp',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
      );

      final result = await callable.call({
        'verificationId': actualWaVerificationId,
        'phone': phone.trim(),
        'code': cleanCode,
        'purpose': purpose,
      });

      final data = readResult(result);
      if (data['verified'] != true && data['success'] != true) {
        throw OtpVerificationRejected(
          data['message']?.toString() ?? 'رمز التحقق غير صحيح أو انتهت صلاحيته',
        );
      }

      final customToken = data['customToken']?.toString();
      if (customToken == null || customToken.isEmpty) {
        throw const OtpVerificationRejected(
          'فشل إنشاء جلسة أمان صالحة للمستخدم من الخادم، يرجى المحاولة لاحقاً',
        );
      }
      return customToken;
    } on OtpVerificationRejected {
      rethrow;
    } on FirebaseFunctionsException catch (e) {
      throw OtpVerificationRejected(e.message ?? 'فشل التحقق من الرمز');
    } catch (e) {
      throw OtpVerificationRejected('خطأ في التحقق: $e');
    }
  }
}
