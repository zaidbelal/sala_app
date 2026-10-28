import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityHelper {
  ConnectivityHelper._();

  /// فحص ذكي وفوري: يتأكد من الاتصال بالراوتر أولاً، ثم يختبر مقبس اتصال حي
  static Future<bool> hasActiveInternet() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.every((r) => r == ConnectivityResult.none)) {
        return false;
      }

      final socket = await Socket.connect(
        '1.1.1.1',
        443,
        timeout: const Duration(milliseconds: 1200),
      );
      socket.destroy();
      return true;
    } catch (_) {
      try {
        final socket = await Socket.connect(
          '8.8.8.8',
          53,
          timeout: const Duration(milliseconds: 800),
        );
        socket.destroy();
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  static Stream<bool> get onConnectivityChanged {
    return Connectivity().onConnectivityChanged.map(
          (results) => results.any((r) => r != ConnectivityResult.none),
        );
  }

  /// 🔒 المصنف المركزي الشامل: يكشف كافة أشكال أخطاء الشبكة والمهلة (عربية، إنجليزية، ونظامية)
  static bool isNetworkException(Object? error) {
    if (error == null) return false;

    // 1. استثناءات الدفتر المؤمّنة أوفلاين
    if (error.runtimeType.toString().contains('LedgerQueuedException'))
      return true;

    // 2. استثناءات الإدخال/الإخراج والمهلة الصريحة
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return true;
    }

    final errStr = error.toString().toLowerCase();

    // 3. استثناءات Firebase Cloud Functions و Firestore
    if (errStr.contains('unavailable') &&
        !errStr.contains('product_unavailable')) return true;
    if (errStr.contains('deadline-exceeded') ||
        errStr.contains('network-request-failed') ||
        errStr.contains('network_error') ||
        errStr.contains('retry exhausted') ||
        errStr.contains('channel error') ||
        errStr.contains('connection closed') ||
        errStr.contains('connection reset') ||
        errStr.contains('host lookup')) {
      return true;
    }

    // 4. مطابقة النصوص العربية الناتجة عن تعثر الاتصال
    return errStr.contains('لا يوجد اتصال') ||
        errStr.contains('انقطع الاتصال') ||
        errStr.contains('تعذر الاتصال') ||
        errStr.contains('انتهت المهلة') ||
        errStr.contains('فشل الاتصال') ||
        errStr.contains('غير متصل') ||
        errStr.contains('تحقق من اتصال');
  }
}
