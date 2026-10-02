import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
// ══════════════════════════════════════════════════════════
//  ImagePrecacheService
//  يحفظ الصور على القرص — تبقى حتى بعد إغلاق التطبيق
//
//  الفرق عن CachedNetworkImageProvider.resolve():
//  ┌─────────────────────────────────────────────────────┐
//  │ .resolve()          → RAM فقط — تُحذف عند الإغلاق  │
//  │ DefaultCacheManager → Disk  — تبقى بين الجلسات      │
//  └─────────────────────────────────────────────────────┘
// ══════════════════════════════════════════════════════════

class ImagePrecacheService {
  ImagePrecacheService._();
  static final ImagePrecacheService instance = ImagePrecacheService._();

  // تخصيص مدير الكاش للاحتفاظ بصور المنتجات لمدة 30 يوماً وزيادة السعة الاستيعابية
  // هذا يمنع إعادة تحميل الصور في حالة الإنترنت البطيء ويوفر تجربة تصفح فورية
  final _cacheManager = CacheManager(
    Config(
      'sala_images_cache',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 2000,
    ),
  );
  CacheManager get cacheManager => _cacheManager;
  bool _isRunning = false;
  bool _isCancelled = false;

  void cancel() {
    _isCancelled = true;
  }

  // ══ الواجهة الرئيسية — استدعِها من _warmUpCache ══
  Future<void> prewarmAll({
    required List<Map<String, dynamic>> categories,
    required List<Map<String, dynamic>> brands,
    required List<Map<String, dynamic>> products,
  }) async {
    if (kIsWeb || _isRunning) return;
    _isRunning = true;
    _isCancelled = false;

    try {
      // المرحلة 1: الأصناف أولاً
      final categoryUrls = _extractUrls(categories, 'image_url');
      await _downloadBatch(categoryUrls, concurrency: 3, label: 'categories');

      if (_isCancelled) return;

      // المرحلة 2: الماركات ثانياً
      final brandUrls = _extractUrls(brands, 'logo_url');
      await _downloadBatch(brandUrls, concurrency: 2, label: 'brands');

      if (_isCancelled) return;

      // المرحلة 3: أول 30 منتج فقط
      final productUrls = _extractUrls(products, 'image_url').take(30).toList();
      await _downloadBatch(productUrls, concurrency: 2, label: 'products');
    } finally {
      _isRunning = false;
    }
  }

  // ══ تحميل صور الأصناف فقط (استدعِها عند تحديث الأصناف) ══
  void prewarmCategories(List<Map<String, dynamic>> categories) {
    if (kIsWeb) return;
    _isCancelled = false;
    final urls = _extractUrls(categories, 'image_url');
    _downloadBatch(urls, concurrency: 5, label: 'categories');
  }

  // ══ تحميل صور الماركات فقط (استدعِها عند فتح صفحة صنف) ══
  void prewarmBrands(List<Map<String, dynamic>> brands) {
    if (kIsWeb) return;
    _isCancelled = false;
    final urls = _extractUrls(brands, 'logo_url');
    _downloadBatch(urls, concurrency: 6, label: 'brands');
  }

// ══ تحميل وتخزين صور المنتجات وصور جميع الكميات في ذاكرة الهاتف للأوفلاين ══
  Future<void> prewarmProducts(List<Map<String, dynamic>> products) async {
    if (kIsWeb) return;
    _isCancelled = false;
    // فحص ذكي للشبكة: إذا كان الاتصال عبر بيانات الجوال (Mobile Data)، نقلل الصور للحفاظ على باقة التاجر.
    final connectivity = await Connectivity().checkConnectivity();
    final isMobileData = connectivity.contains(ConnectivityResult.mobile);
    final limit = isMobileData ? 15 : 60;

    final urls = <String>{};
    // 🚀 تقييد التحميل المسبق
    final targetProducts = products.take(limit);
    for (final p in targetProducts) {
      final pUrl = p['image_url'] as String?;
      if (pUrl != null && pUrl.trim().isNotEmpty) urls.add(pUrl.trim());

      final rawUnits = p['units'];
      if (rawUnits is List) {
        for (final u in rawUnits) {
          if (u is Map) {
            final uUrl = u['image_url'] as String?;
            if (uUrl != null && uUrl.trim().isNotEmpty) urls.add(uUrl.trim());
          }
        }
      }
    }
    _downloadBatch(urls.toList(), concurrency: 3, label: 'products_and_units');
  }

  // ══ هل الصورة موجودة في الـ Disk Cache؟ ══
  Future<bool> isCached(String url) async {
    try {
      final info = await _cacheManager.getFileFromCache(url);
      return info != null;
    } catch (_) {
      return false;
    }
  }

  // ══════ دوال داخلية ══════

  List<String> _extractUrls(
    List<Map<String, dynamic>> items,
    String key,
  ) {
    return items
        .map((e) => e[key] as String?)
        .where((url) => url != null && url.isNotEmpty)
        .cast<String>()
        .toList();
  }

  /// يُحمّل دفعات متوازية — concurrency يتحكم في عدد التحميلات المتزامنة
  Future<void> _downloadBatch(
    List<String> urls, {
    required int concurrency,
    required String label,
  }) async {
    if (urls.isEmpty) return;

    for (int i = 0; i < urls.length; i += concurrency) {
      if (_isCancelled) return;
      final chunk = urls.skip(i).take(concurrency).toList();
      await Future.wait(
        chunk.map((url) => _downloadOne(url)
            .timeout(const Duration(seconds: 8), onTimeout: () => null)),
        eagerError: false,
      );
      await Future.delayed(const Duration(milliseconds: 200));
      chunk.clear();
    }
  }

  Future<void> _downloadOne(String url) async {
    try {
      // getSingleFile: يتحقق من الـ Disk Cache أولاً — إذا موجود لا يُنزّله مجدداً
      await _cacheManager.getSingleFile(url);
    } catch (e) {
      // تجاهل أخطاء الشبكة — الصورة ستُحمَّل لاحقاً عند الحاجة
      if (kDebugMode) debugPrint('⚠️ prewarm failed: $url — $e');
    }
  }
}
