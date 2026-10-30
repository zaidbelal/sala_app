import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:sala/core/services/background_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // لـ compute()
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ══════════════════════════════════════════════════════════
// AppCache — نظام كاش ثلاثي الطبقات بسرعة الضوء
//
// الطبقة 1: RAM   → 0ms   (خلال الجلسة)
// الطبقة 2: Disk  → ~10ms (يبقى بعد إغلاق التطبيق)
// الطبقة 3: Net   → يُحدَّث في الخلفية بصمت
// ══════════════════════════════════════════════════════════

class AppCache {
  AppCache._();
  static final AppCache instance = AppCache._();

  // ── الطبقة الأولى: ذاكرة RAM المحمية من التضخم ──
  final Map<String, _CacheEntry> _ram = {};
  static const int _maxRamEntries =
      120; // سقف أمان يمنع تجاوز الذاكرة العشوائية

  SharedPreferences? _prefs;

  void _pruneRamIfNeeded() {
    if (_ram.length <= _maxRamEntries) return;
    // حذف المدخلات الأقدم لحماية ذاكرة الهاتف (LRU Cache Pruning)
    final sortedKeys = _ram.keys.toList()
      ..sort((a, b) => _ram[a]!.savedAt.compareTo(_ram[b]!.savedAt));
    final keysToRemove = sortedKeys.take(_ram.length - _maxRamEntries);
    for (final k in keysToRemove) {
      // لا نحذف المفاتيح الحيوية الأساسية
      if (k != _keyCategories && k != _keyBrands && k != _keyProducts) {
        _ram.remove(k);
      }
    }
  }

  // 🚀 مدة صلاحية متوازنة تمنع تعارض الأسعار عند الشراء وتدعم العمل المؤقت دون إنترنت
  static const Duration _categoryTtl = Duration(minutes: 30);
  static const Duration _productTtl = Duration(minutes: 20);
  static const Duration orderTtl = Duration(hours: 1);

  static const String _keyCategories = 'cache_categories';
  static const String _keyBrands = 'cache_brands';
  static const String _keyProducts = 'cache_products';

  List<Map<String, dynamic>>? getBrands() => _getList(_keyBrands);

  Future<void> _brandsWriteLock = Future.value();

  Future<void> setBrands(
    List<Map<String, dynamic>> data, {
    String? categoryId,
  }) async {
    final previousLock = _brandsWriteLock;
    final completer = Completer<void>();
    _brandsWriteLock = completer.future;

    try {
      await previousLock;
    } catch (_) {}

    try {
      final existing = getBrands() ?? [];
      if (categoryId != null && existing.isNotEmpty) {
        final ids = data.map((e) => e['id']).toSet();
        final merged = [
          ...existing.where((e) =>
              e['category_id']?.toString() != categoryId &&
              !ids.contains(e['id'])),
          ...data,
        ];
        await _set(_keyBrands, merged);
      } else {
        await _set(_keyBrands, data);
      }
    } finally {
      completer.complete();
    }
  }

  Future<void> _removeKeyFamily(String baseKey) async {
    final prefs = _prefs;
    if (prefs == null) return;

    final keys = prefs.getKeys().where((key) {
      return key == baseKey || key.startsWith('${baseKey}_');
    }).toList();

    _ram.removeWhere((key, _) {
      return key == baseKey || key.startsWith('${baseKey}_');
    });

    if (!kIsWeb) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        for (final k in keys) {
          final cleanKey = k.endsWith('_ts') ? k.substring(0, k.length - 3) : k;
          final file = File('${dir.path}/$cleanKey.json');
          if (await file.exists()) await file.delete();
        }
      } catch (_) {}
    }

    await Future.wait(
      keys.map(prefs.remove),
    );
  }

  // ══════════════════════════════
  // تهيئة — استدعِها في main()
  // ══════════════════════════════
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    // ✅ مسح أي ملفات مؤقتة متبقية لمنع تراكم الملفات التالفة على قرص الهاتف
    if (!kIsWeb) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final files = dir.listSync();
        for (final f in files) {
          if (f is File &&
              (f.path.endsWith('.tmp.json') || f.path.endsWith('.tmp'))) {
            await f.delete().catchError((_) => f);
          }
        }
      } catch (_) {}
    }

    final keys = <String>{
      _keyCategories,
      _keyBrands,
      _keyProducts,
      ..._prefs!
          .getKeys()
          .where((key) =>
              key.startsWith('${_keyProducts}_') && key.endsWith('_ts'))
          .map((key) => key.substring(0, key.length - 3)),
    };
    await Future.wait(
      keys.map(_loadFromDisk),
    );
  }

  // ══════════════════════════════
  // قراءة — فورية من RAM
  // ══════════════════════════════
  List<Map<String, dynamic>>? getCategories() => _getList(_keyCategories);

  List<Map<String, dynamic>>? getProducts({String? categoryId}) {
    final key =
        categoryId == null ? _keyProducts : '${_keyProducts}_$categoryId';
    return _getList(key);
  }

  bool isCategoriesFresh() => _isFresh(_keyCategories, _categoryTtl);
  bool isProductsFresh({String? categoryId}) {
    final key =
        categoryId == null ? _keyProducts : '${_keyProducts}_$categoryId';
    return _isFresh(key, _productTtl);
  }

  // ══════════════════════════════
  // كتابة — RAM + Disk معاً
  // ══════════════════════════════
  Future<void> _categoriesWriteLock = Future.value();

  Future<void> setCategories(List<Map<String, dynamic>> data) async {
    final previousLock = _categoriesWriteLock;
    final completer = Completer<void>();
    _categoriesWriteLock = completer.future;

    try {
      await previousLock;
    } catch (_) {}

    try {
      await _set(_keyCategories, data);
    } finally {
      completer.complete();
    }
  }

  Future<void> _productsWriteLock = Future.value();

  Future<void> setProducts(
    List<Map<String, dynamic>> data, {
    String? categoryId,
  }) async {
    final previousLock = _productsWriteLock;
    final completer = Completer<void>();
    _productsWriteLock = completer.future;

    try {
      await previousLock;
    } catch (_) {}

    try {
      final key =
          categoryId == null ? _keyProducts : '${_keyProducts}_$categoryId';

      // ✅ تحديث الـ RAM أولاً قبل القرص لمنع أي Race Condition
      _ram[key] = _CacheEntry(
        data: data,
        savedAt: DateTime.now(),
      );

      await _saveToDisk(key, data);

      if (categoryId != null) {
        List<Map<String, dynamic>> all = [];
        final existingRam = _ram[_keyProducts];

        if (existingRam != null &&
            existingRam.data is List &&
            (existingRam.data as List).isNotEmpty) {
          all = List<Map<String, dynamic>>.from(
            (existingRam.data as List)
                .map((e) => Map<String, dynamic>.from(e as Map)),
          );
        } else if (!kIsWeb) {
          try {
            final dir = await getApplicationDocumentsDirectory();
            final file = File('${dir.path}/$_keyProducts.json');
            if (await file.exists()) {
              final raw = await file.readAsString();
              final decoded = _decodeJson(raw);
              if (decoded != null && decoded.isNotEmpty) all = decoded;
            }
          } catch (_) {}
        }

        // لا نقوم بتحديث الكاش الشامل إلا إذا كان محملاً مسبقاً لمنع مسح باقي المنتجات
        if (all.isNotEmpty) {
          final ids = data.map((e) => e['id']).toSet();
          final merged = [
            ...all.where((e) =>
                e['category_id']?.toString() != categoryId &&
                !ids.contains(e['id'])),
            ...data,
          ];
          _ram[_keyProducts] = _CacheEntry(
            data: merged,
            savedAt: DateTime.now(),
          );
          await _saveToDisk(_keyProducts, merged);
        }
      }
    } finally {
      completer.complete();
    }
  }

  // ══════════════════════════════
  // مسح
  // ══════════════════════════════
  Future<void> invalidateCategories() async {
    await _removeKeyFamily(_keyCategories);
  }

  Future<void> invalidateBrands() async {
    await _removeKeyFamily(_keyBrands);
  }

  Future<void> invalidateProducts() async {
    final previousLock = _productsWriteLock;
    final completer = Completer<void>();
    _productsWriteLock = completer.future;

    try {
      await previousLock;
    } catch (_) {}

    try {
      final expiredDate = DateTime(2000);
      final productCacheKeys = <String>{
        _keyProducts,
        ..._ram.keys.where((key) => key.startsWith('${_keyProducts}_')),
      };
      final prefs = _prefs;
      if (prefs != null) {
        productCacheKeys.addAll(prefs.getKeys().where((key) =>
            key == _keyProducts || key.startsWith('${_keyProducts}_')));
      }

      // 🛡️ وسم البيانات بأنها منتهية الصلاحية (Stale) لتحديثها لاحقاً دون حذف ملفات القرص لتأمين الأوفلاين
      for (final key in productCacheKeys) {
        final current = _ram[key];
        if (current != null) {
          _ram[key] = _CacheEntry(
            data: current.data,
            savedAt: expiredDate,
          );
        }
        if (prefs != null) {
          await prefs.setString('${key}_ts', expiredDate.toIso8601String());
        }
      }
      // 🔒 ملفات القرص تبقى محفوظة بالكامل لتشغيل الطلبات في وضع عدم الاتصال (Offline-First)
    } finally {
      completer.complete();
    }
  }

  /// جلب كافة المنتجات المخزنة محلياً من ذاكرة RAM فائقة السرعة دون تعليق الـ UI Thread
  List<Map<String, dynamic>> getAllCachedProducts() {
    final Map<String, Map<String, dynamic>> byId = {};

    for (final entry in _ram.entries) {
      if (entry.key == _keyProducts ||
          entry.key.startsWith('${_keyProducts}_')) {
        if (entry.value.data is List) {
          for (final p in (entry.value.data as List)) {
            if (p is Map<String, dynamic>) {
              final id = p['id']?.toString();
              if (id != null && id.isNotEmpty) {
                byId[id] = p;
              }
            }
          }
        }
      }
    }

    // 🔒 إذا كانت الذاكرة غير محملة بعد، يتم جدولتها بالخلفية بدلاً من قراءة ملفات ضخمة متزامنة على شاشة المستخدم
    if (byId.isEmpty && !kIsWeb) {
      Future.microtask(() => _loadFromDisk(_keyProducts));
    }

    return byId.values.toList();
  }

  Future<void> clearAll() async {
    await Future.wait([
      _removeKeyFamily(_keyCategories),
      _removeKeyFamily(_keyBrands),
      _removeKeyFamily(_keyProducts),
    ]);
  }

  // ══════════════════════════════
  // دوال مساعدة داخلية
  // ══════════════════════════════
  List<Map<String, dynamic>>? _getList(String key) {
    final entry = _ram[key];
    if (entry == null) return null;
    return entry.data as List<Map<String, dynamic>>?;
  }

  bool _isFresh(String key, Duration ttl) {
    final entry = _ram[key];
    if (entry == null) return false;
    return DateTime.now().difference(entry.savedAt) < ttl;
  }

  Future<void> _set(String key, List<Map<String, dynamic>> data) async {
    await _saveToDisk(key, data);
    _pruneRamIfNeeded();
    _ram[key] = _CacheEntry(
      data: data,
      savedAt: DateTime.now(),
    );
  }

  Future<void> _invalidate(String key) async {
    _ram.remove(key);
    if (!kIsWeb) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$key.json');
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await _prefs?.remove('${key}_ts');
  }

  Future<void> _loadFromDisk(String key) async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$key.json');
      final raw = await file.exists() ? await file.readAsString() : null;
      if (raw == null || raw.isEmpty) return;

      final ts = _prefs?.getString('${key}_ts');
      final savedAt = ts != null
          ? (DateTime.tryParse(ts) ?? DateTime(2000))
          : DateTime(2000);
      final decoded = raw.length > 10000
          ? await BackgroundWorker.decodeJsonList(raw)
          : _decodeJson(raw);

      if (decoded == null) {
        await _invalidate(key);
        return;
      }

      _ram[key] = _CacheEntry(
        data: decoded,
        savedAt: savedAt,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AppCache load failed for $key: $e');
        debugPrintStack(stackTrace: st);
      }
      await _invalidate(key);
    }
  }

  static List<Map<String, dynamic>>? _decodeJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return List<Map<String, dynamic>>.from(
          decoded.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static dynamic _sanitizeForJson(dynamic item) {
    if (item is Map) {
      return item.map((k, v) => MapEntry(k.toString(), _sanitizeForJson(v)));
    } else if (item is List) {
      return item.map(_sanitizeForJson).toList();
    } else if (item is num || item is bool || item is String) {
      return item;
    } else if (item is DateTime) {
      return item.toIso8601String();
    } else if (item is Timestamp) {
      return item.toDate().toIso8601String();
    } else if (item != null) {
      return item.toString();
    }
    return item;
  }

  static String _isolateEncodeJson(List<dynamic> sanitizedData) {
    return jsonEncode(sanitizedData);
  }

  Future<void> _saveToDisk(
    String key,
    List<Map<String, dynamic>> data,
  ) async {
    if (kIsWeb) return;
    try {
      final sanitizedData = data.map((e) => _sanitizeForJson(e)).toList();
      final encoded = await compute(_isolateEncodeJson, sanitizedData);
      final dir = await getApplicationDocumentsDirectory();
      final nonce = DateTime.now().microsecondsSinceEpoch;
      final tempFile = File('${dir.path}/${key}_$nonce.tmp.json');
      final finalFile = File('${dir.path}/$key.json');
      await tempFile.writeAsString(encoded, flush: true);

      final backupFile = File('${dir.path}/$key.bak.json');
      try {
        if (await finalFile.exists()) {
          await finalFile.copy(backupFile.path);
        }
        await tempFile.rename(finalFile.path);
      } catch (_) {
        try {
          await tempFile.copy(finalFile.path);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {
          if (await backupFile.exists()) {
            await backupFile.copy(finalFile.path);
          }
        }
      } finally {
        if (await backupFile.exists()) {
          await backupFile.delete().catchError((_) => backupFile);
        }
      }
      await _prefs?.setString(
        '${key}_ts',
        DateTime.now().toIso8601String(),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AppCache save failed for $key: $e');
        debugPrintStack(stackTrace: st);
      }
      await _prefs?.remove('${key}_ts');
    }
  }
}

class _CacheEntry {
  final dynamic data;
  final DateTime savedAt;
  const _CacheEntry({required this.data, required this.savedAt});
}
