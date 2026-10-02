import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// خدمة اتصال موحدة وخفيفة لفحص حالة الشبكة
class ConnectivityHelper {
  ConnectivityHelper._();

  static Future<bool> hasConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  static Stream<bool> get onConnectivityChanged {
    return Connectivity().onConnectivityChanged.map(
          (results) => results.any((r) => r != ConnectivityResult.none),
        );
  }
}
