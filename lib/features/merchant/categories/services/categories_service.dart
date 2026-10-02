import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CategoryModel {
  final String id;
  final String name;
  final String? imageUrl;
  final int? sortOrder;

  const CategoryModel({
    required this.id,
    required this.name,
    this.imageUrl,
    this.sortOrder,
  });

  factory CategoryModel.fromMap(Map<String, dynamic> map) => CategoryModel(
        id: map['id'].toString(),
        name: (map['name'] as String?)?.trim() ?? '',
        imageUrl: map['image_url'] as String?,
        sortOrder: map['sort_order'] as int?,
      );
}

final categoriesStreamProvider =
    StreamProvider.autoDispose<List<CategoryModel>>((ref) {
  ref.keepAlive();

  return FirebaseFirestore.instance
      .collection('categories')
      // ❌ تم إزالة where('is_active') من هنا لتجنب مشاكل الحقول المفقودة
      .limit(100)
      .snapshots(includeMetadataChanges: false)
      .map((snap) {
    final list = snap.docs
        // ✅ الفلترة تتم هنا محلياً (نفس طريقة صفحة الأدمن)
        .where((d) =>
            d.data()['is_deleted'] != true && d.data()['is_active'] != false)
        .map((d) => CategoryModel.fromMap({'id': d.id, ...d.data()}))
        .where((c) => c.name.isNotEmpty)
        .toList()
      ..sort((a, b) => (a.sortOrder ?? 999).compareTo(b.sortOrder ?? 999));

    return list;
  });
});
