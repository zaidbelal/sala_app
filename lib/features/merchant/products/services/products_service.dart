import 'package:sala/core/models/product_unit.dart';
// ✅ إعادة تصدير ProductModel حتى لا تتأثر الملفات الأخرى
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProductModel {
  final String id;
  final String name;
  final double price;
  final String? imageUrl;
  final String brandId;
  final String? description;
  final double? sizeMl;
  final String? sizeText;
  final int? itemsPerCarton;
  final String? productionDate;
  final String? expiryDate;
  final double costPrice;
  final double stock;
  final List<ProductUnit> units;

  const ProductModel({
    required this.id,
    required this.name,
    required this.price,
    this.imageUrl,
    required this.brandId,
    this.description,
    this.sizeMl,
    this.sizeText,
    this.itemsPerCarton,
    this.productionDate,
    this.expiryDate,
    this.costPrice = 0,
    this.stock = 0.0,
    this.units = const [],
  });

  factory ProductModel.fromMap(Map<String, dynamic> m) {
    final rawUnits = m['units'];

    final units = rawUnits is List
        ? rawUnits
            .whereType<Map>()
            .map(
              (e) => ProductUnit.fromMap(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList()
        : <ProductUnit>[];

    String? readDate(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) {
        return value.toDate().toIso8601String();
      }
      if (value is DateTime) {
        return value.toIso8601String();
      }
      return value.toString();
    }

    final basePrice = (m['price'] as num?)?.toDouble() ?? 0.0;
    final cartonItems = (m['items_per_carton'] as num?)?.toInt() ?? 1;
    final sizeMl = (m['size_ml'] as num?)?.toDouble();
    final prodDate = readDate(m['production_date']);
    final expDate = readDate(m['expiry_date']);
    final imageUrl = m['image_url'] as String?;
    final costPrice = (m['cost_price'] as num?)?.toDouble() ?? 0;

// ✅ إبقاء الكرتون دائماً كوحدة أساسية أولى ومزامنة سعره وتكلفته تلقائياً مع السعر الأساسي للمنتج
    final cartonIndex = units.indexWhere((u) => u.label.trim() == 'كرتون');
    if (cartonIndex == -1) {
      units.insert(
        0,
        ProductUnit(
          label: 'كرتون',
          qty: cartonItems > 0 ? cartonItems : 1,
          price: basePrice,
          costPrice: costPrice > 0 ? costPrice : null,
          imageUrl: imageUrl,
          sizeMl: sizeMl,
          productionDate: prodDate != null ? DateTime.tryParse(prodDate) : null,
          expiryDate: expDate != null ? DateTime.tryParse(expDate) : null,
        ),
      );
    } else {
      final existingCarton = units[cartonIndex];
      units[cartonIndex] = ProductUnit(
        label: 'كرتون',
        qty: existingCarton.qty > 0
            ? existingCarton.qty
            : (cartonItems > 0 ? cartonItems : 1),
        price: basePrice,
        costPrice: costPrice > 0 ? costPrice : existingCarton.costPrice,
        imageUrl: existingCarton.imageUrl ?? imageUrl,
        sizeMl: existingCarton.sizeMl ?? sizeMl,
        productionDate: existingCarton.productionDate ??
            (prodDate != null ? DateTime.tryParse(prodDate) : null),
        expiryDate: existingCarton.expiryDate ??
            (expDate != null ? DateTime.tryParse(expDate) : null),
      );
    }
    return ProductModel(
      id: m['id']?.toString() ?? '',
      name: (m['name'] as String?)?.trim() ?? '',
      price: basePrice,
      imageUrl: imageUrl,
      brandId: m['brand_id']?.toString() ?? '',
      description: m['description'] as String?,
      sizeMl: sizeMl,
      sizeText: m['size_text']?.toString() ?? m['size_label']?.toString(),
      itemsPerCarton: (m['items_per_carton'] as num?)?.toInt(),
      productionDate: prodDate,
      expiryDate: expDate,
      costPrice: (m['cost_price'] as num?)?.toDouble() ?? 0,
      stock: (m['stock'] as num?)?.toDouble() ?? 0.0,
      units: units,
    );
  }
  factory ProductModel.fromJson(Map<String, dynamic> m) {
    return ProductModel.fromMap(m);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'image_url': imageUrl,
      'brand_id': brandId,
      'description': description,
      'size_ml': sizeMl,
      'items_per_carton': itemsPerCarton,
      'production_date': productionDate,
      'expiry_date': expiryDate,
      'cost_price': costPrice,
      'stock': stock,
      'units': units.map((unit) => unit.toMap()).toList(),
    };
  }
}

final productsStreamProvider =
    StreamProvider.autoDispose.family<List<ProductModel>, String>(
  (ref, brandId) {
    return FirebaseFirestore.instance
        .collection('products')
        .where('brand_id', isEqualTo: brandId)
        .limit(250)
        .snapshots(includeMetadataChanges: false)
        .map(
      (snapshot) {
        final list = snapshot.docs
            .where((doc) =>
                doc.data()['is_deleted'] != true &&
                doc.data()['is_active'] != false)
            .map(
              (doc) => ProductModel.fromMap({
                'id': doc.id,
                ...doc.data(),
              }),
            )
            .where((product) => product.name.trim().isNotEmpty)
            .toList();
        list.sort((a, b) => a.name.compareTo(
            b.name)); // ✅ فرز في الذاكرة دون استثناء FAILED_PRECONDITION
        return list;
      },
    );
  },
);
