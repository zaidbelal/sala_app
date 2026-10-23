import 'dart:async';
import 'package:flutter/foundation.dart';
import 'app_cache.dart';
import 'image_precache_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// محرك التحميل الاستباقي لتحميل بيانات المنتجات والصور في الذاكرة قبل أن ينقر عليها التاجر
class PrefetchService {
  PrefetchService._();
  static final PrefetchService instance = PrefetchService._();
  final Set<String> _warmedCategories = {};

  void clear() => _warmedCategories.clear();

  void onCategoryHoverOrViewed(String categoryId) {
    if (_warmedCategories.contains(categoryId) || kIsWeb) return;
    _warmedCategories.add(categoryId);

    unawaited(_warmUpCategoryAssets(categoryId));
  }

  Future<void> _warmUpCategoryAssets(String categoryId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('brands')
          .where('category_id', isEqualTo: categoryId)
          .limit(10)
          .get(const GetOptions(source: Source.serverAndCache));

      final brandsData = snap.docs
          .where((d) => d.data()['is_deleted'] != true)
          .map((d) => {'id': d.id, ...d.data()})
          .toList();

      if (brandsData.isNotEmpty) {
        await AppCache.instance.setBrands(brandsData, categoryId: categoryId);
        ImagePrecacheService.instance.prewarmBrands(brandsData);
      }
    } catch (_) {}
  }
}
