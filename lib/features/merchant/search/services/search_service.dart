import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/services/app_cache.dart';
import '../../../../core/services/image_precache_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // ✅ إضافة استيراد Crashlytics

final _db = FirebaseFirestore.instance;
final _cache = <String, _CachedSearchResult>{};

class _CachedSearchResult {
  final SearchResult result;
  final DateTime cachedAt;

  const _CachedSearchResult(this.result, this.cachedAt);
}

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
  static const _cacheTtl = Duration(seconds: 30);

  Future<SearchResult> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return const SearchResult(products: [], brands: [], categories: []);
    }

    final cached = _cache[q];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) < _cacheTtl) {
      return cached.result;
    }
    _cache.remove(q);

    // 1. البحث الفوري المحلي في الذاكرة (0ms)
    final localResult = _searchLocally(q);
    if (localResult != null && !localResult.isEmpty) {
      _putInCache(q, localResult);
      unawaited(_fetchAndUpdateCache(q));
      return localResult;
    }

    final serverResult = await _fetchAndUpdateCache(q);
    _putInCache(q, serverResult);
    return serverResult;
  }

  void _putInCache(String query, SearchResult result) {
    if (_cache.length >= 60) {
      final now = DateTime.now();
      _cache.removeWhere(
        (_, entry) => now.difference(entry.cachedAt) >= _cacheTtl,
      );
      if (_cache.length >= 60) _cache.clear();
    }
    _cache[query] = _CachedSearchResult(result, DateTime.now());
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
    // Firestore stores the original product names; normalize only after retrieval.
    final firstToken = q.split(RegExp(r'\s+')).first;

    final results = await Future.wait([
      _safeQuery('products', () async {
        final barcodeQuery = await _db
            .collection('products')
            .where('all_barcodes', arrayContains: q)
            .limit(15)
            .get(const GetOptions(source: Source.serverAndCache));

        final combinedDocs = <String, Map<String, dynamic>>{};
        for (final d in barcodeQuery.docs) {
          if (d.data()['is_deleted'] != true &&
              d.data()['is_active'] != false) {
            combinedDocs[d.id] = {'id': d.id, ...d.data()};
          }
        }
        for (final product in await _fetchNameMatches(
          collectionName: 'products',
          prefix: firstToken,
          tokens: tokens,
          resultLimit: 30,
        )) {
          combinedDocs[product['id'].toString()] = product;
        }

        // تصفية متعددة الكلمات في الذاكرة مع إبقاء نتائج الباركود المطابقة.
        final filteredList = combinedDocs.values.where((p) {
          final name = p['name']?.toString() ?? '';
          return _matchesTokens(name, tokens) || _matchesBarcode(p, q);
        }).toList();

        ImagePrecacheService.instance.prewarmProducts(filteredList);
        return filteredList.take(30).toList();
      }),
      _safeQuery('brands', () async {
        final list = await _fetchNameMatches(
          collectionName: 'brands',
          prefix: firstToken,
          tokens: tokens,
          resultLimit: 15,
        );
        ImagePrecacheService.instance.prewarmBrands(list);
        return list;
      }),
      _safeQuery('categories', () async {
        final list = await _fetchNameMatches(
          collectionName: 'categories',
          prefix: firstToken,
          tokens: tokens,
          resultLimit: 10,
        );
        ImagePrecacheService.instance.prewarmCategories(list);
        return list;
      }),
    ]);

    final result = SearchResult(
      products: results[0],
      brands: results[1],
      categories: results[2],
    );

    _putInCache(q, result);
    return result;
  }

  Future<List<Map<String, dynamic>>> _fetchNameMatches({
    required String collectionName,
    required String prefix,
    required List<String> tokens,
    required int resultLimit,
  }) async {
    const pageSize = 60;
    final collection = _db.collection(collectionName);
    final matches = <String, Map<String, dynamic>>{};
    DocumentSnapshot<Map<String, dynamic>>? cursor;

    while (matches.length < resultLimit) {
      Query<Map<String, dynamic>> query = collection
          .where('name', isGreaterThanOrEqualTo: prefix)
          .where('name', isLessThanOrEqualTo: '$prefix\uf8ff')
          .orderBy('name')
          .limit(pageSize);
      if (cursor != null) query = query.startAfterDocument(cursor);

      final page =
          await query.get(const GetOptions(source: Source.serverAndCache));
      if (page.docs.isEmpty) break;

      for (final doc in page.docs) {
        final data = doc.data();
        if (data['is_deleted'] == true || data['is_active'] == false) {
          continue;
        }
        final product = {'id': doc.id, ...data};
        if (_matchesTokens(data['name']?.toString() ?? '', tokens)) {
          matches[doc.id] = product;
          if (matches.length >= resultLimit) break;
        }
      }

      if (matches.length >= resultLimit || page.docs.length < pageSize) break;
      cursor = page.docs.last;
    }

    return matches.values.toList(growable: false);
  }

  bool _matchesBarcode(Map<String, dynamic> product, String query) {
    bool matches(Object? value) =>
        value?.toString().trim().toLowerCase().contains(query) ?? false;

    if (matches(product['barcode'])) return true;
    final barcodes = product['all_barcodes'];
    if (barcodes is List && barcodes.any(matches)) return true;
    final units = product['units'];
    return units is List &&
        units.any((unit) => unit is Map && matches(unit['barcode']));
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
