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

      // فحص سريع ومباشر على IP عالمي (Cloudflare DNS) بمهلة 1200ms
      // تجاوز فحص أسماء النطاق (DNS) الذي يعلق طويلاً على شبكات الواي فاي المفصولة
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
}
