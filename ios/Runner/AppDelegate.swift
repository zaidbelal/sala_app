import Flutter
import UIKit
import UserNotifications
import GoogleMaps // 👈 1. استيراد مكتبة خرائط قوقل

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 🗺️ 2. تفعيل مفتاح خرائط قوقل للآيفون قبل تسجيل الـ Plugins لمنع الانهيار
    GMSServices.provideAPIKey("AIzaSyC_O1Uu7f5sCrg5Xy2uP1JNeb_qgBPMqjo")

    // تسجيل الإشعارات الفورية الأصلية لنظام iOS
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }

    GeneratedPluginRegistrant.register(with: self)
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}