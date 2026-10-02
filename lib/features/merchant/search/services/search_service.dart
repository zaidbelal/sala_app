// ==================================================
// FILE: lib/features/merchant/search/services/search_service.dart
// ==================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/services/app_cache.dart';
import '../../../../core/services/image_precache_service.dart';
import 'package:flutter/foundation.dart';

final _db = FirebaseFirestore.instance;
final _cache = <String, SearchResult>{};

class SearchResult {
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> brands;
  final List<Map<String, dynamic>> categories;

  const SearchResult({
    required this.products,
    required this.brands,
    required this.categories,
  });

  bool get isEmpty => products.isEmpty && brands.isEmpty && categories.isEmpty;
}

class SearchService {
  Future<SearchResult> search(String query) async {
    final q = query.trim().toLowerCase();
    // ✅ السماح بالبحث من أول حرف مباشرة
    if (q.isEmpty) {
      return const SearchResult(products: [], brands: [], categories: []);
    }

    // فحص كاش الذاكرة السريع
    if (_cache.containsKey(q)) return _cache[q]!;

    // 1. البحث المحلي الفوري في الهاتف (Offline 0ms)
    final localResult = _searchLocally(q);
    if (localResult != null && !localResult.isEmpty) {
      _cache[q] = localResult;
      // جلب تحديث في الخلفية لضمان تطابق البيانات
      _fetchAndUpdateCache(q);
      return localResult;
    }

    // 2. إذا لم توجد نتائج كافية محلياً، نجلب من السيرفر والكاش
    final serverResult = await _fetchAndUpdateCache(q);
    _cache[q] = serverResult;
    return serverResult;
  }

  static String _normalizeArabic(String text) {
    return text
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ـ', '')
        .toLowerCase()
        .trim();
  }

  SearchResult? _searchLocally(String q) {
    final cache = AppCache.instance;
    final allProducts = cache.getProducts() ?? [];
    final allCategories = cache.getCategories() ?? [];
    final allBrands = cache.getBrands() ?? [];

    if (allProducts.isEmpty && allCategories.isEmpty && allBrands.isEmpty) {
      return null;
    }

    final normalizedQ = _normalizeArabic(q);

    // البحث في المنتجات أولاً
    final products = allProducts
        .where((p) =>
            _normalizeArabic(p['name'] as String? ?? '').contains(normalizedQ))
        .take(30)
        .toList();

    // البحث في الشركات ثانياً
    final brands = allBrands
        .where((b) =>
            _normalizeArabic(b['name'] as String? ?? '').contains(normalizedQ))
        .take(15)
        .toList();

    // البحث في الأصناف ثالثاً
    final categories = allCategories
        .where((c) =>
            _normalizeArabic(c['name'] as String? ?? '').contains(normalizedQ))
        .take(10)
        .toList();

    return SearchResult(
      products: products,
      brands: brands,
      categories: categories,
    );
  }

  Future<SearchResult> _fetchAndUpdateCache(String q) async {
    final results = await Future.wait([
      // 1. المنتجات
      _safeQuery('products', () async {
        final snap = await _db
            .collection('products')
            .where('is_active', isEqualTo: true)
            .limit(300)
            .get(const GetOptions(source: Source.serverAndCache));

        final list = snap.docs
            .where((d) => d.data()['is_deleted'] != true)
            .map((d) => {'id': d.id, ...d.data()})
            .toList();

        // حفظ المنتجات وصورها محلياً للأوفلاين
        AppCache.instance.setProducts(list);
        ImagePrecacheService.instance.prewarmProducts(list);

        return list
            .where((p) => _normalizeArabic(p['name']?.toString() ?? '')
                .contains(_normalizeArabic(q)))
            .take(30)
            .toList();
      }),
      // 2. الشركات
      _safeQuery('brands', () async {
        final snap = await _db
            .collection('brands')
            .limit(200)
            .get(const GetOptions(source: Source.serverAndCache));

        final list = snap.docs
            .where((d) =>
                d.data()['is_deleted'] != true &&
                d.data()['is_active'] != false)
            .map((d) => {'id': d.id, ...d.data()})
            .toList();

        AppCache.instance.setBrands(list);
        ImagePrecacheService.instance.prewarmBrands(list);

        return list
            .where((b) => _normalizeArabic(b['name']?.toString() ?? '')
                .contains(_normalizeArabic(q)))
            .take(15)
            .toList();
      }),
      // 3. الأصناف
      _safeQuery('categories', () async {
        final snap = await _db
            .collection('categories')
            .limit(100)
            .get(const GetOptions(source: Source.serverAndCache));

        final list = snap.docs
            .where((d) =>
                d.data()['is_deleted'] != true &&
                d.data()['is_active'] != false)
            .map((d) => {'id': d.id, ...d.data()})
            .toList();

        AppCache.instance.setCategories(list);
        ImagePrecacheService.instance.prewarmCategories(list);

        return list
            .where((c) => _normalizeArabic(c['name']?.toString() ?? '')
                .contains(_normalizeArabic(q)))
            .take(10)
            .toList();
      }),
    ]);

    final result = SearchResult(
      products: results[0],
      brands: results[1],
      categories: results[2],
    );

    if (_cache.length >= 60) _cache.clear();
    _cache[q] = result;
    return result;
  }

  Future<List<Map<String, dynamic>>> _safeQuery(
    String tableName,
    Future<List<Map<String, dynamic>>> Function() query,
  ) async {
    try {
      return await query();
    } catch (e) {
      if (kDebugMode) debugPrint('SEARCH ERROR [$tableName]: $e');
      return [];
    }
  }

  void clearCache() => _cache.clear();
}

final searchServiceProvider = Provider<SearchService>((ref) => SearchService());
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider =
    FutureProvider.autoDispose.family<SearchResult, String>((ref, query) async {
  if (query.trim().isEmpty) {
    return const SearchResult(products: [], brands: [], categories: []);
  }
  return ref.read(searchServiceProvider).search(query);
});
