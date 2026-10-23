import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sala/core/services/app_cache.dart';

class BrandModel {
  final String id;
  final String name;
  final String? logoUrl;
  final String? description;
  final String categoryId;

  const BrandModel({
    required this.id,
    required this.name,
    this.logoUrl,
    this.description,
    required this.categoryId,
  });

  factory BrandModel.fromMap(Map<String, dynamic> map) => BrandModel(
        id: map['id'].toString(),
        name: map['name'] ?? '',
        logoUrl: map['logo_url'],
        description: map['description'],
        categoryId: map['category_id'].toString(),
      );
}

final brandsStreamProvider =
    StreamProvider.autoDispose.family<List<BrandModel>, String>((
  ref,
  categoryId,
) {
  return FirebaseFirestore.instance
      .collection('brands')
      .where('category_id', isEqualTo: categoryId)
      .limit(150)
      .snapshots(includeMetadataChanges: false)
      .map(
    (snap) {
      final rawDocs = snap.docs
          .where((d) =>
              d.data()['is_deleted'] != true && d.data()['is_active'] != false)
          .map((d) => {'id': d.id, ...d.data()})
          .toList();

      // حفظ الشركات في كاش الهاتف لتغذية البحث الفوري بدون إنترنت مع دمج الأصناف
      if (rawDocs.isNotEmpty) {
        AppCache.instance.setBrands(rawDocs, categoryId: categoryId);
      }
      final list = rawDocs.map((d) => BrandModel.fromMap(d)).toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    },
  );
});
