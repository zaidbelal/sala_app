import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum OrderStatus {
  pending,
  accepted,
  preparing,
  onTheWay,
  delivered,
  cancelled,
  rejected,
  returned,
  returnRequested,
}

extension OrderStatusX on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.pending:
        return 'قيد الانتظار';
      case OrderStatus.accepted:
        return 'تم القبول';
      case OrderStatus.preparing:
        return 'قيد التحضير';
      case OrderStatus.onTheWay:
        return 'في الطريق إليك';
      case OrderStatus.delivered:
        return 'تم التسليم';
      case OrderStatus.cancelled:
        return 'ملغي';
      case OrderStatus.rejected:
        return 'مرفوض';
      case OrderStatus.returned:
        return 'مرتجع';
      case OrderStatus.returnRequested:
        return 'طلب إرجاع';
    }
  }

  Color get color {
    switch (this) {
      case OrderStatus.pending:
        return const Color(0xFFF59E0B);
      case OrderStatus.accepted:
      case OrderStatus.preparing:
        return const Color(0xFF3B82F6);
      case OrderStatus.onTheWay:
        return const Color(0xFF8B5CF6);
      case OrderStatus.delivered:
        return const Color(0xFF10B981);
      case OrderStatus.cancelled:
      case OrderStatus.rejected:
        return const Color(0xFFEF4444);
      case OrderStatus.returned:
      case OrderStatus.returnRequested:
        return const Color(0xFFEA580C);
    }
  }

  String get description {
    switch (this) {
      case OrderStatus.pending:
        return 'طلبك في انتظار مراجعة المدير';
      case OrderStatus.accepted:
        return 'جاري تحضير طلبك الآن';
      case OrderStatus.preparing:
        return 'فريقنا يحضّر طلبك';
      case OrderStatus.onTheWay:
        return 'المندوب في طريقه لتوصيل طلبك';
      case OrderStatus.delivered:
        return 'تم توصيل طلبك بنجاح';
      case OrderStatus.cancelled:
        return 'تم إلغاء هذا الطلب';
      case OrderStatus.rejected:
        return 'تم رفض هذا الطلب';
      case OrderStatus.returned:
        return 'تم إرجاع هذا الطلب';
      case OrderStatus.returnRequested:
        return 'طلب الإرجاع قيد المراجعة';
    }
  }

  int get step {
    switch (this) {
      case OrderStatus.pending:
        return 0;
      case OrderStatus.accepted:
        return 1;
      case OrderStatus.preparing:
        return 2;
      case OrderStatus.onTheWay:
        return 3;
      case OrderStatus.delivered:
        return 4;
      case OrderStatus.cancelled:
      case OrderStatus.rejected:
        return -1;
      case OrderStatus.returned:
      case OrderStatus.returnRequested:
        return -2;
    }
  }

  static OrderStatus parse(String s) {
    switch (s) {
      case 'accepted':
        return OrderStatus.accepted;
      case 'confirmed':
        return OrderStatus.accepted;
      case 'preparing':
        return OrderStatus.preparing;
      case 'shipped':
        return OrderStatus.onTheWay;
      case 'on_the_way':
        return OrderStatus.onTheWay;
      case 'delivered':
        return OrderStatus.delivered;
      case 'cancelled':
        return OrderStatus.cancelled;
      case 'rejected':
        return OrderStatus.rejected;
      case 'returned':
        return OrderStatus.returned;
      case 'return_requested':
        return OrderStatus.returnRequested;
      default:
        return OrderStatus.pending;
    }
  }
}

class OrderModel {
  final String id;
  final String merchantId;
  final double total;
  final double returnedAmount; // 👈 مضاف: إجمالي المبلغ المرتجع
  final double originalTotal; // 👈 مضاف: إجمالي الفاتورة الأصلية قبل الإرجاع
  final OrderStatus status;
  final String? notes;
  final String? invoiceNumber;
  final String? orderNumber;
  final String? storeName;
  final String? customerName;
  final String? contact;
  final double? latitude;
  final double? longitude;
  final String? paymentMethod;
  final String? signatureUrl;
  final DateTime createdAt;

  const OrderModel({
    required this.id,
    required this.merchantId,
    required this.total,
    this.returnedAmount = 0.0,
    this.originalTotal = 0.0,
    required this.status,
    this.notes,
    this.invoiceNumber,
    this.orderNumber,
    this.storeName,
    this.customerName,
    this.contact,
    this.latitude,
    this.longitude,
    this.paymentMethod,
    this.signatureUrl,
    required this.createdAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> j) {
    final rawCreatedAt = j['created_at'];

    final createdAt = rawCreatedAt is Timestamp
        ? rawCreatedAt.toDate()
        : DateTime.tryParse(
              rawCreatedAt?.toString() ?? '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);

    final rawTotal = (j['total'] as num?)?.toDouble() ??
        (j['total_amount'] as num?)?.toDouble() ??
        0.0;
    final retAmt = (j['returned_amount'] as num?)?.toDouble() ??
        (j['refund_amount'] as num?)?.toDouble() ??
        0.0;
    final origTotal = (j['original_total'] as num?)?.toDouble() ??
        (rawTotal > 0 ? (rawTotal + retAmt) : retAmt);

    return OrderModel(
      id: j['id']?.toString() ?? '',
      merchantId: j['merchant_id']?.toString() ?? '',
      total: rawTotal,
      returnedAmount: retAmt,
      originalTotal: origTotal,
      status: OrderStatusX.parse(
        j['status']?.toString() ?? 'pending',
      ),
      notes: j['notes']?.toString(),
      invoiceNumber: j['invoice_number']?.toString(),
      orderNumber: j['order_number']?.toString(),
      storeName: j['store_name']?.toString(),
      customerName: j['customer_name']?.toString(),
      contact: j['contact']?.toString(),
      latitude: (j['latitude'] as num?)?.toDouble(),
      longitude: (j['longitude'] as num?)?.toDouble(),
      paymentMethod: j['payment_method']?.toString(),
      signatureUrl: j['signature_url']?.toString(),
      createdAt: createdAt,
    );
  }
}
