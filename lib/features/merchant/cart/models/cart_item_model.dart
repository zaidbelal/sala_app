// ==================================================
// FILE: lib/features/merchant/cart/models/cart_item_model.dart
// ==================================================

import '../../products/services/products_service.dart';
import 'package:sala/core/models/product_unit.dart';

class CartItem {
  final ProductModel product;
  final int quantity;
  final ProductUnit? selectedUnit;

  const CartItem({
    required this.product,
    required this.quantity,
    this.selectedUnit,
  });

  String get cartKey {
    if (selectedUnit == null || selectedUnit!.label.trim() == 'كرتون') {
      return product.id;
    }
    return '${product.id}__${selectedUnit!.label.trim()}';
  }

  double get unitPrice => selectedUnit?.price ?? product.price;

  String get unitLabel => selectedUnit?.label ?? 'كرتون';

  double get total => unitPrice * quantity;

  CartItem copyWith({int? quantity, ProductUnit? selectedUnit}) => CartItem(
        product: product,
        quantity: quantity ?? this.quantity,
        selectedUnit: selectedUnit ?? this.selectedUnit,
      );

  Map<String, dynamic> toJson() {
    final unitMap = selectedUnit?.toMap();

    if (unitMap != null) {
      if (selectedUnit!.productionDate != null) {
        unitMap['production_date'] =
            selectedUnit!.productionDate!.toIso8601String();
      }
      if (selectedUnit!.expiryDate != null) {
        unitMap['expiry_date'] = selectedUnit!.expiryDate!.toIso8601String();
      }
    }

    return {
      'product': {
        'id': product.id,
        'name': product.name,
        'price': product.price,
        'image_url': product.imageUrl,
        'imageUrl': product.imageUrl,
        'brandId': product.brandId,
        'size_ml': product.sizeMl,
        'items_per_carton': product.itemsPerCarton,
      },
      'quantity': quantity,
      'snapshot_at': DateTime.now().millisecondsSinceEpoch,
      if (unitMap != null) 'selectedUnit': unitMap,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> j) {
    final p = j['product'] as Map<String, dynamic>;
    final unitMap = j['selectedUnit'] as Map<String, dynamic>?;
    final img = (p['image_url'] ?? p['imageUrl']) as String?;

    return CartItem(
      product: ProductModel.fromMap({
        'id': p['id'],
        'name': p['name'],
        'price': p['price'],
        'image_url': img,
        'brand_id': p['brandId'] ?? p['brand_id'] ?? '',
        'size_ml': p['size_ml'],
        'items_per_carton': p['items_per_carton'],
        'category_id': '',
        'cost_price': 0,
        'stock': 0,
        'is_active': true,
      }),
      quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      selectedUnit: unitMap != null ? ProductUnit.fromMap(unitMap) : null,
    );
  }
}
