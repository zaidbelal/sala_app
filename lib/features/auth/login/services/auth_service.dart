import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/app_cache.dart';
import '../../../../core/services/local_storage.dart';
import '../../../../core/services/firebase_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/realtime_hub.dart';
import 'quickconnect_otp_service.dart';
import 'package:cloud_functions/cloud_functions.dart';

enum PhoneCheckResult {
  registered,
  notRegistered,
  inactive,
  error,
}

class PhoneCheckResponse {
  final PhoneCheckResult result;
  final String? userId;
  final String? role;
  final String? message;

  const PhoneCheckResponse({
    required this.result,
    this.userId,
    this.role,
    this.message,
  });
}

class OtpVerifyResponse {
  final bool success;
  final bool isDisabled;
  final String message;
  final String? customToken;

  const OtpVerifyResponse({
    required this.success,
    this.isDisabled = false,
    required this.message,
    this.customToken,
  });
}

class PhoneVerificationSession {
  final String verificationId;
  final int? resendToken;

  const PhoneVerificationSession({
    required this.verificationId,
    this.resendToken,
  });
}

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(),
);

class AuthService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // كانت static من قبل، وهذا خطأ معماري خطير:
  // أي Instance جديد من AuthService (مثلاً في الاختبارات، أو لو تم بناؤه
  // يدويًا في مكان آخر) كان سيشارك نفس القفل مع الـ Provider الرئيسي،
  // مما قد يسبب "يوجد طلب قيد التنفيذ" بشكل خاطئ لمستخدم مختلف تمامًا.
  bool _otpRequestRunning = false;

  /// توحيد صيغة رقم الهاتف اليمني.
  ///
  /// الصيغ المدعومة:
  /// 7XXXXXXXX
  /// 07XXXXXXXX
  /// 9677XXXXXXXX
  /// +9677XXXXXXXX
  // رقم الدولة مُدمج داخل الدالة (+967) بشكل صريح، وهذا يمنع التوسع
  // مستقبلاً لأي دولة أخرى دون تعديل منطق التحقق بالكامل.
  // يُفضّل استخراجه كـ constant قابل للتهيئة (AppConfig.countryCode)
  // ليصبح formatPhone دالة عامة لا مرتبطة بدولة واحدة مباشرة.
  static const defaultCountryCode = '+967';
  static const localPrefix = '0';
  static const requiredLength = 9;
  static const validStartDigit = '7';
  static String formatPhone(String phone) {
    // ✅ تحويل الأرقام العربية المشرقية تلقائياً إلى أرقام لاتينية قياسية
    final normalized = QuickConnectOtpService.normalizeCode(phone);
    final raw = normalized.trim().replaceAll(RegExp(r'[\s()-]'), '');

    if (raw.isEmpty) {
      throw const FormatException('أدخل رقم الهاتف');
    }
    final value = raw.startsWith('00') ? '+${raw.substring(2)}' : raw;
    final countryCodeDigits = defaultCountryCode.replaceAll('+', '');

    if (value.startsWith(defaultCountryCode) &&
        value.length == defaultCountryCode.length + requiredLength) {
      return value;
    }

    if (value.startsWith(countryCodeDigits) &&
        value.length == countryCodeDigits.length + requiredLength) {
      return '+$value';
    }

    if (value.startsWith('$localPrefix$validStartDigit') &&
        value.length == requiredLength + localPrefix.length) {
      return '$defaultCountryCode${value.substring(localPrefix.length)}';
    }

    if (value.startsWith(validStartDigit) && value.length == requiredLength) {
      return '$defaultCountryCode$value';
    }

    throw FormatException(
        'رقم الهاتف يجب أن يكون $requiredLength أرقام ويبدأ بالرقم $validStartDigit');
  }

  Future<PhoneCheckResponse> checkPhoneNumber(String phone) async {
    try {
      final formattedPhone = formatPhone(phone);

      final callable = FirebaseFunctions.instance.httpsCallable(
        'checkPhoneNumber',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      );

      final res = await callable.call({'phone': formattedPhone});
      final data = Map<String, dynamic>.from(res.data as Map);

      if (data['exists'] != true) {
        return const PhoneCheckResponse(
          result: PhoneCheckResult.notRegistered,
          message: 'يرجى المتابعة لإتمام إنشاء الحساب',
        );
      }

      if (data['is_banned'] == true ||
          (data['is_active'] == false && data['account_status'] != 'pending')) {
        return const PhoneCheckResponse(
          result: PhoneCheckResult.inactive,
          message: 'تعذر الدخول، يرجى التواصل مع الدعم الفني',
        );
      }

      return PhoneCheckResponse(
        result: PhoneCheckResult.registered,
        userId: data['userId']?.toString(),
        role: data['role']?.toString() ?? 'merchant',
        message: 'يرجى المتابعة لإتمام التحقق',
      );
    } on FirebaseFunctionsException catch (e) {
      return PhoneCheckResponse(
        result: PhoneCheckResult.error,
        message: 'تعذر الاتصال بالخادم (${e.message})',
      );
    } on FormatException catch (error) {
      return PhoneCheckResponse(
        result: PhoneCheckResult.error,
        message: error.message,
      );
    } on TimeoutException {
      return const PhoneCheckResponse(
        result: PhoneCheckResult.error,
        message: 'انتهت مهلة الاتصال، تحقق من جودة الإنترنت',
      );
    } catch (error) {
      return const PhoneCheckResponse(
        result: PhoneCheckResult.error,
        message: 'خطأ أثناء الاتصال بالخادم',
      );
    }
  }

  Future<PhoneVerificationSession> sendOtp(
    String phone, {
    int? forceResendingToken,
    String purpose = 'login',
  }) async {
    if (_otpRequestRunning) {
      throw StateError(
        'يوجد طلب تحقق قيد التنفيذ، انتظر قليلاً',
      );
    }
    _otpRequestRunning = true;

    try {
      final phoneNumber = formatPhone(phone);

      final verificationId = await QuickConnectOtpService.send(
        phone: phoneNumber,
        purpose: purpose,
      );

      return PhoneVerificationSession(
        verificationId: verificationId,
      );
    } on FormatException catch (error) {
      throw StateError(error.message);
    } catch (e) {
      rethrow;
    } finally {
      _otpRequestRunning = false;
    }
  }

  // ══════════════════════════════════════════
  // التحقق من رمز OTP
  // ══════════════════════════════════════════

  Future<OtpVerifyResponse> verifyOtp({
    required String verificationId,
    required String otp,
    required String phone,
    String purpose = 'login',
  }) async {
    final cleanVerificationId = verificationId.trim();
    final cleanOtp = QuickConnectOtpService.normalizeCode(otp);
    if (cleanVerificationId.isEmpty) {
      return const OtpVerifyResponse(
        success: false,
        message: 'انتهت جلسة التحقق، أعد إرسال الرمز',
      );
    }

    if (!RegExp(r'^\d{6}$').hasMatch(cleanOtp)) {
      return const OtpVerifyResponse(
        success: false,
        message: 'أدخل رمز التحقق المكوّن من 6 أرقام',
      );
    }

    try {
      final customToken = await QuickConnectOtpService.verify(
        verificationId: cleanVerificationId,
        phone: formatPhone(phone),
        code: cleanOtp,
        purpose: purpose,
      );

      return OtpVerifyResponse(
        success: customToken != null,
        customToken: customToken,
        message: customToken != null
            ? 'تم التحقق بنجاح'
            : 'رمز التحقق غير صحيح أو انتهت صلاحيته',
      );
    } on OtpVerificationRejected catch (error) {
      return OtpVerifyResponse(
        success: false,
        message: error.message,
      );
    } on FormatException catch (error) {
      return OtpVerifyResponse(
        success: false,
        message: error.message,
      );
    } on FirebaseFunctionsException catch (error) {
      return OtpVerifyResponse(
        success: false,
        message: error.message ?? 'تعذر التحقق من الرمز',
      );
    } catch (error) {
      return const OtpVerifyResponse(
        success: false,
        message: 'تعذر الاتصال بخدمة التحقق',
      );
    }
  }
  // ══════════════════════════════════════════
  // حفظ بيانات المستخدم محلياً
  // ══════════════════════════════════════════

  Future<void> saveUserLocally(
    String userId,
  ) async {
    try {
      final document =
          await _db.collection('profiles').doc(userId).get().timeout(
                const Duration(seconds: 10),
              );

      if (!document.exists) {
        throw StateError(
          'User profile was not found',
        );
      }

      final data = document.data();

      if (data == null) {
        throw StateError(
          'User profile data is empty',
        );
      }
      IdTokenResult? idTokenResult;
      try {
        idTokenResult = await FirebaseAuth.instance.currentUser
            ?.getIdTokenResult(true)
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        idTokenResult = null;
      }

      final role = (data['role'] as String?)?.trim().toLowerCase() ??
          (idTokenResult?.claims?['role'] as String?)?.trim().toLowerCase();
      if (role == null || role.isEmpty) {
        throw StateError(
          'User role is missing',
        );
      }
      final isActive = data['is_active'] as bool? ?? true;
      final isBanned = data['is_banned'] == true;
      final accountStatus =
          data['account_status']?.toString().trim().toLowerCase() ?? '';

      if (isBanned || (!isActive && accountStatus != 'pending')) {
        throw StateError(
          'User account is inactive or banned',
        );
      }

      await AppStorage.setIsActive(
        isActive,
      );

      await AppStorage.setIsBanned(
        isBanned,
      );

      await AppStorage.saveUserData(
        userId: document.id,
        role: role,
        name: data['full_name'] as String?,
        phone: data['phone_number'] as String?,
      );

      await NotificationService.instance.saveTokenToFirestore(
        document.id,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[AuthService] saveUserLocally failed '
          'for $userId: $error',
        );

        debugPrintStack(
          stackTrace: stackTrace,
        );
      }

      rethrow;
    }
  }

  // ══════════════════════════════════════════
  // التحقق من حالة الحساب من Firestore
  // ══════════════════════════════════════════

  Future<bool> checkIsActiveFromServer(
    String userId,
  ) async {
    try {
      final document =
          await _db.collection('profiles').doc(userId).get().timeout(
                const Duration(seconds: 8),
              );

      if (!document.exists) {
        return false;
      }

      final data = document.data();

      if (data == null) {
        return false;
      }

      final isBanned = data['is_banned'] == true;
      final isActive = data['is_active'] as bool? ?? true;

      await AppStorage.setIsBanned(
        isBanned,
      );

      await AppStorage.setIsActive(
        isActive,
      );

      return !isBanned && isActive;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[AuthService] checkIsActiveFromServer failed: $error',
        );

        debugPrintStack(
          stackTrace: stackTrace,
        );
      }

      // لا نعتمد على الكاش عند فشل فحص أمني.
      return false;
    }
  }

// ══════════════════════════════════════════
  // تسجيل الخروج الآمن
  // ══════════════════════════════════════════
  Future<void> signOut({VoidCallback? onClearCart}) async {
    final currentUserId = AppStorage.userId;

    try {
      RealtimeHub().dispose();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[AuthService] RealtimeHub dispose failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    // ✅ تصفير السلة بالكامل لمنع تسريب بيانات وأسعار التاجر للحساب التالي
    onClearCart?.call();

    // ✅ مسح التوكن من السيرفر أثناء بقاء المستخدم مسجل الدخول لضمان صلاحية الـ Security Rules
    if (currentUserId != null && currentUserId.isNotEmpty) {
      try {
        await NotificationService.instance
            .detachTokenFromFirestore(currentUserId)
            .timeout(const Duration(seconds: 4));
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint(
              '[AuthService] failed to detach notification token: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
    }

    try {
      await FirebaseMessaging.instance
          .deleteToken()
          .timeout(const Duration(seconds: 2));
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[AuthService] failed to delete FCM token: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
    try {
      await FirebaseAuth.instance.signOut().timeout(const Duration(seconds: 5));
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[AuthService] Firebase sign out failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
    await AppStorage.clearUserData();
    await AppCache.instance.clearAll();
    FirebaseService.clearCache();
  }

  Future<void> deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('لا يوجد مستخدم مسجل حالياً');
    final userId = AppStorage.userId ?? user.uid;

    try {
      // 🚀 استخدام Cloud Function لحذف الحساب ذرياً وبشكل آمن من الخادم
      // (يجب أن تتأكد من كتابة دالة 'deleteUserAccount' في ملف index.js في Firebase)
      final callable = FirebaseFunctions.instance.httpsCallable(
        'deleteUserAccount',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );

      await callable.call({'userId': userId});
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) debugPrint('[AuthService] Function Error: ${e.message}');
      throw StateError(e.message ?? 'تعذر حذف الحساب من الخادم');
    } catch (error) {
      if (kDebugMode) debugPrint('[AuthService] Delete error: $error');
      throw StateError(
          'تعذّر حذف الحساب. تحقق من اتصال الإنترنت وحاول مجددًا.');
    }

    // 3. مسح كافة البيانات المحلية من الهاتف بعد نجاح الحذف النهائي
    await signOut();
  }
}
