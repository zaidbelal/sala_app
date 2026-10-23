import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/services/app_cache.dart';
import '../../../../core/services/image_precache_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // ✅ إضافة استيراد Crashlytics

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
    if (q.isEmpty) {
      return const SearchResult(products: [], brands: [], categories: []);
    }

    if (_cache.containsKey(q)) return _cache[q]!;

    // 1. البحث الفوري المحلي في الذاكرة (0ms)
    final localResult = _searchLocally(q);
    if (localResult != null && !localResult.isEmpty) {
      _cache[q] = localResult;
      unawaited(_fetchAndUpdateCache(q));
      return localResult;
    }

    final serverResult = await _fetchAndUpdateCache(q);
    _cache[q] = serverResult;
    return serverResult;
  }

  static String normalizeArabic(String text) {
    return text
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '') // الحركات
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ـ', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase()
        .trim();
  }

  static bool _matchesTokens(String target, List<String> tokens) {
    final normTarget = normalizeArabic(target);
    return tokens.every((token) => normTarget.contains(token));
  }

  SearchResult? _searchLocally(String q) {
    final cache = AppCache.instance;
    final allProducts = cache.getProducts() ?? [];
    final allCategories = cache.getCategories() ?? [];
    final allBrands = cache.getBrands() ?? [];

    if (allProducts.isEmpty && allCategories.isEmpty && allBrands.isEmpty) {
      return null;
    }

    final tokens =
        normalizeArabic(q).split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return null;

    final products = allProducts
        .where((p) {
          if (p['is_deleted'] == true || p['is_active'] == false) return false;
          final name = p['name']?.toString() ?? '';
          if (_matchesTokens(name, tokens)) return true;

          final barcode = p['barcode']?.toString().trim() ?? '';
          if (barcode.isNotEmpty && barcode.contains(q)) return true;

          final units = p['units'];
          if (units is List) {
            for (final u in units) {
              if (u is Map &&
                  (u['barcode']?.toString().trim() ?? '').contains(q)) {
                return true;
              }
            }
          }
          return false;
        })
        .take(30)
        .toList();

    final brands = allBrands
        .where((b) {
          if (b['is_deleted'] == true || b['is_active'] == false) return false;
          return _matchesTokens(b['name']?.toString() ?? '', tokens);
        })
        .take(15)
        .toList();

    final categories = allCategories
        .where((c) {
          if (c['is_deleted'] == true || c['is_active'] == false) return false;
          return _matchesTokens(c['name']?.toString() ?? '', tokens);
        })
        .take(10)
        .toList();

    return SearchResult(
      products: products,
      brands: brands,
      categories: categories,
    );
  }

  Future<SearchResult> _fetchAndUpdateCache(String q) async {
    final tokens =
        normalizeArabic(q).split(' ').where((t) => t.isNotEmpty).toList();
    final firstToken = tokens.isNotEmpty ? tokens.first : q;

    final results = await Future.wait([
      _safeQuery('products', () async {
        final barcodeQuery = await _db
            .collection('products')
            .where('all_barcodes', arrayContains: q)
            .limit(15)
            .get(const GetOptions(source: Source.serverAndCache));

        // استعلام السيرفر الموسّع
        final nameQuery = await _db
            .collection('products')
            .where('name', isGreaterThanOrEqualTo: firstToken)
            .where('name', isLessThanOrEqualTo: '$firstToken\uf8ff')
            .limit(60)
            .get(const GetOptions(source: Source.serverAndCache));

        final combinedDocs = <String, Map<String, dynamic>>{};
        for (final d in [...barcodeQuery.docs, ...nameQuery.docs]) {
          if (d.data()['is_deleted'] != true &&
              d.data()['is_active'] != false) {
            combinedDocs[d.id] = {'id': d.id, ...d.data()};
          }
        }

        // تصفية متعددة الكلمات في الذاكرة
        final filteredList = combinedDocs.values.where((p) {
          final name = p['name']?.toString() ?? '';
          return _matchesTokens(name, tokens);
        }).toList();

        ImagePrecacheService.instance.prewarmProducts(filteredList);
        return filteredList.take(30).toList();
      }),
      _safeQuery('brands', () async {
        final snap = await _db
            .collection('brands')
            .where('name', isGreaterThanOrEqualTo: firstToken)
            .where('name', isLessThanOrEqualTo: '$firstToken\uf8ff')
            .limit(25)
            .get(const GetOptions(source: Source.serverAndCache));

        final list = snap.docs
            .where((d) =>
                d.data()['is_deleted'] != true &&
                d.data()['is_active'] != false)
            .map((d) => {'id': d.id, ...d.data()})
            .where((b) => _matchesTokens(b['name']?.toString() ?? '', tokens))
            .toList();

        ImagePrecacheService.instance.prewarmBrands(list);
        return list.take(15).toList();
      }),
      _safeQuery('categories', () async {
        final snap = await _db
            .collection('categories')
            .where('name', isGreaterThanOrEqualTo: firstToken)
            .where('name', isLessThanOrEqualTo: '$firstToken\uf8ff')
            .limit(20)
            .get(const GetOptions(source: Source.serverAndCache));

        final list = snap.docs
            .where((d) =>
                d.data()['is_deleted'] != true &&
                d.data()['is_active'] != false)
            .map((d) => {'id': d.id, ...d.data()})
            .where((c) => _matchesTokens(c['name']?.toString() ?? '', tokens))
            .toList();

        ImagePrecacheService.instance.prewarmCategories(list);
        return list.take(10).toList();
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
    } catch (e, st) {
      if (kDebugMode) debugPrint('SEARCH ERROR [$tableName]: $e');
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'Search query error in $tableName');
      }
      return [];
    }
  }

  static void clearCache() => _cache.clear();
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
