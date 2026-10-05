import 'package:cloud_firestore/cloud_firestore.dart';

// ══════════════════════════════════════════════════════════
// ProductUnit — وحدة البيع مع بيانات كاملة وسعر التكلفة
// ══════════════════════════════════════════════════════════

class ProductUnit {
  final String label; // اسم الوحدة: كرتون، نصف كرتون، حبة...
  final int qty; // عدد الحبات في هذه الوحدة
  final double price; // سعر بيع هذه الوحدة
  final double? costPrice; // سعر شراء / تكلفة هذه الوحدة (لحساب الربح)
  final String? imageUrl; // صورة خاصة بهذه الوحدة (اختياري)
  final double? sizeMl; // الحجم بالمل (اختياري)
  final DateTime? productionDate; // تاريخ الإنتاج (اختياري)
  final DateTime? expiryDate; // تاريخ الانتهاء (اختياري)
  final String? barcode; // باركود الوحدة (اختياري)

  const ProductUnit({
    required this.label,
    required this.qty,
    required this.price,
    this.costPrice,
    this.imageUrl,
    this.sizeMl,
    this.productionDate,
    this.expiryDate,
    this.barcode,
  });

  factory ProductUnit.fromMap(Map<String, dynamic> m) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String && val.trim().isNotEmpty) {
        return DateTime.tryParse(val.trim());
      }
      return null;
    }

    return ProductUnit(
      label: m['label']?.toString() ?? '',
      qty: (m['qty'] as num?)?.toInt() ?? 1,
      price: (m['price'] as num?)?.toDouble() ?? 0.0,
      costPrice: (m['cost_price'] as num?)?.toDouble() ??
          (m['costPrice'] as num?)?.toDouble(),
      imageUrl: m['image_url'] as String?,
      sizeMl: (m['size_ml'] as num?)?.toDouble(),
      productionDate: parseDate(m['production_date']),
      expiryDate: parseDate(m['expiry_date']),
      barcode: m['barcode']?.toString()?.trim(),
    );
  }

  Map<String, dynamic> toMap() => {
        'label': label,
        'qty': qty,
        'price': price,
        if (costPrice != null) 'cost_price': costPrice,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'image_url': imageUrl,
        if (sizeMl != null) 'size_ml': sizeMl,
        if (productionDate != null)
          'production_date': Timestamp.fromDate(productionDate!),
        if (expiryDate != null) 'expiry_date': Timestamp.fromDate(expiryDate!),
        if (barcode != null && barcode!.isNotEmpty) 'barcode': barcode,
      };
}
