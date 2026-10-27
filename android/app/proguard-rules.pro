# Flutter Engine & Framework
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# Google Maps & Play Services
-keep class com.google.android.gms.maps.** { *; }
-keep interface com.google.android.gms.maps.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.libraries.maps.** { *; }
-keep class com.google.maps.android.** { *; }
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.google.android.gms.**

# Firebase & Crashlytics
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes SourceFile,LineNumberTable
-keepclassmembers class * {
@com.google.firebase.database.PropertyName <fields>;
@com.google.firebase.database.PropertyName <methods>;
}
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.protobuf.**
-keep class com.google.protobuf.** { *; }

# Firebase Storage
-keep class com.google.firebase.storage.** { *; }

# Desugaring Java 8+ APIs
-keep class j$.** { *; }

# Security, EncryptedSharedPreferences & Flutter Secure Storage
-keep class androidx.security.crypto.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Local Notifications & WorkManager
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# Network & Connectivity
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# Media, Gallery & Sharing
-keep class com.google.zxing.** { *; }
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class com.fluttercandies.gal.** { *; }
-keep class dev.fluttercommunity.plus.share.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }

# 📷 Mobile Scanner & Google ML Kit (حماية ماسح الباركود من الانهيار في Release)
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class com.google.mlkit.vision.barcode.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
-dontwarn com.google.mlkit.**

# حماية كائنات ونماذج بيانات تطبيق سلة
-keep class com.zaidsalaapp.sala.** { *; }
-keepclassmembers class * {
*** fromMap(...);
*** toMap(...);
*** fromJson(...);
*** toJson(...);
}
# ==========================================
# 🚀 إضافات الحماية القصوى لـ Google Play
# ==========================================

# منع حذف دوال وخصائص Cloud Firestore
-keep class com.google.firebase.firestore.** { *; }
-dontwarn com.google.firebase.firestore.**

# حماية مكتبات طباعة وتوليد الـ PDF و الخطوط
-keep class net.sf.andpdf.** { *; }
-keep class com.sun.pdfview.** { *; }
-dontwarn com.sun.pdfview.**

# حماية مشغلات الكوروتين والـ Isolates
-keepclassmembers class kotlinx.coroutines.** { *; }

# منع إزالة دوال Gson والتحويل المالي
-keepattributes Signature
-keepattributes *Annotation*
-keepclassmembers class * {
@com.google.gson.annotations.SerializedName <fields>;
}

# كتم تحذيرات التوافق الثانوية للمكتبات الخارجية
-dontwarn okio.**
-dontwarn javax.annotation.**