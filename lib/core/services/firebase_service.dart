import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'local_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ══ العملاء المركزيون ══
final db = FirebaseFirestore.instance;
final storage = FirebaseStorage.instance;

// ══ كاش خفيف في الذاكرة (RAM) ══
class _CacheEntry {
  final dynamic data;
  final DateTime expiresAt;
  _CacheEntry(this.data, int ttlSeconds)
      : expiresAt = DateTime.now().add(Duration(seconds: ttlSeconds));
  bool get isValid => DateTime.now().isBefore(expiresAt);
}

final _cache = <String, _CacheEntry>{};

class FirebaseService {
  FirebaseService._();

  // ══ تهيئة ══
  static void initialize() {
    // Firestore offline persistence مفعّلة افتراضياً على الموبايل
  }

  // ══ معلومات المستخدم (من التخزين المحلي — Auth مخصص) ══
  static String? get currentUserId => AppStorage.userId;
  static String? get currentUserRole => AppStorage.userRole;
  static bool get isLoggedIn => AppStorage.userId != null;

  // ══════════════════════════════════════════════════
  // استعلام مع كاش — سرعة خيالية للبيانات الثابتة
  // ══════════════════════════════════════════════════
  static Future<List<Map<String, dynamic>>> cachedQuery(
    String cacheKey,
    Future<List<Map<String, dynamic>>> Function() query, {
    int ttlSeconds = 30,
    int retries = 2,
  }) async {
    final cached = _cache[cacheKey];
    if (cached != null && cached.isValid) {
      return List<Map<String, dynamic>>.from(cached.data);
    }

    for (int attempt = 1; attempt <= retries + 1; attempt++) {
      try {
        final result = await query();
        if (ttlSeconds > 0) _cache[cacheKey] = _CacheEntry(result, ttlSeconds);
        return result;
      } catch (e) {
        if (attempt > retries) return [];
        await Future.delayed(Duration(milliseconds: 150 * attempt));
      }
    }
    return [];
  }

  static void invalidateCache(String prefix) {
    _cache.removeWhere((key, _) => key.startsWith(prefix));
  }

  static void clearCache() => _cache.clear();

  // ══════════════════════════════════════════════════
  // استعلامات متوازية
  // ══════════════════════════════════════════════════
  static Future<List<List<Map<String, dynamic>>>> parallelQueries(
    List<Future<List<Map<String, dynamic>>>> queries,
  ) async {
    return Future.wait(queries);
  }

  // ══════════════════════════════════════════════════
  // رفع صورة لـ Firebase Storage
  // ══════════════════════════════════════════════════
  static Future<String?> uploadImage({
    required String bucket,
    required String path,
    required List<int> bytes,
    String contentType = 'image/jpeg',
  }) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final ref = storage.ref('$bucket/$path');
        await ref.putData(
          Uint8List.fromList(bytes),
          SettableMetadata(contentType: contentType),
        );
        return await ref.getDownloadURL();
      } catch (e) {
        if (attempt == 3) return null;
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
    return null;
  }

  // ══ حذف صورة ══
  static Future<bool> deleteImage({
    required String bucket,
    required String path,
  }) async {
    try {
      await storage.ref('$bucket/$path').delete();
      return true;
    } catch (_) {
      return false;
    }
  }

// ══ تسجيل الخروج ══
  static Future<void> signOut() async {
    clearCache();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    await AppStorage.clearUserData();
  }
}

// ══ مساعد تحويل Firestore Document ══
extension DocToMap on DocumentSnapshot {
  Map<String, dynamic> toMap() {
    final data = this.data() as Map<String, dynamic>? ?? {};
    return {'id': id, ...data};
  }
}

extension QueryToList on QuerySnapshot {
  List<Map<String, dynamic>> toList() {
    return docs.map((d) {
      final data = d.data() as Map<String, dynamic>? ?? {};
      return {'id': d.id, ...data};
    }).toList();
  }
}
