import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../../core/utils/inventory_math.dart';
import '../../../../core/services/app_cache.dart';
import '../../../../core/services/local_storage.dart';
import 'package:firebase_storage/firebase_storage.dart';

final adminServiceProvider = Provider((ref) => AdminService());

// ══ Models ══
class AdminStats {
  final int totalOrders;
  final int pendingOrders;
  final int deliveredOrders;
  final int cancelledOrders;
  final int totalMerchants;
  final double totalRevenue;
  final double totalProfit;
  final double returnedAmount;
  final bool hasCostData;
  const AdminStats({
    required this.totalOrders,
    required this.pendingOrders,
    this.deliveredOrders = 0,
    this.cancelledOrders = 0,
    required this.totalMerchants,
    required this.totalRevenue,
    required this.totalProfit,
    this.returnedAmount = 0,
    this.hasCostData = false,
  });
}

class AdminOrder {
  final String id;
  final String merchantId;
  final String merchantName;
  final String? storeName;
  final String? phoneNumber;
  final String status;
  final String paymentMethod;
  final double total;
  final double returnedAmount;
  final double originalTotal;
  final DateTime createdAt;
  final int itemsCount;
  final String? deliveryAddress;
  final String? notes;
  final String? orderNumber;
  final double? latitude;
  final double? longitude;
  final String? signatureUrl;

  const AdminOrder({
    required this.id,
    required this.merchantId,
    required this.merchantName,
    this.storeName,
    this.phoneNumber,
    required this.status,
    required this.paymentMethod,
    required this.total,
    this.returnedAmount = 0.0,
    this.originalTotal = 0.0,
    required this.createdAt,
    required this.itemsCount,
    this.deliveryAddress,
    this.notes,
    this.orderNumber,
    this.latitude,
    this.longitude,
    this.signatureUrl,
  });

  factory AdminOrder.fromMap(Map<String, dynamic> m) {
    final rawId = m['id'];
    final id =
        (rawId != null && rawId.toString().isNotEmpty) ? rawId.toString() : '';
    final rawMerchantId = m['merchant_id'];
    final merchantId =
        (rawMerchantId != null && rawMerchantId.toString().isNotEmpty)
            ? rawMerchantId.toString()
            : '';

    final rawTotal = (m['total_amount'] as num?)?.toDouble() ??
        (m['total'] as num?)?.toDouble() ??
        0;
    final retAmt = (m['returned_amount'] as num?)?.toDouble() ??
        (m['refund_amount'] as num?)?.toDouble() ??
        0.0;
    final origTotal = (m['original_total'] as num?)?.toDouble() ??
        (rawTotal > 0 ? (rawTotal + retAmt) : retAmt);

    return AdminOrder(
      id: id,
      merchantId: merchantId,
      merchantName: m['merchant_name'] ?? m['customer_name'] ?? 'غير معروف',
      storeName: m['store_name'],
      phoneNumber: m['phone_number'] ?? m['contact'],
      status: m['status'] ?? 'pending',
      paymentMethod: m['payment_method'] ?? 'cash',
      total: rawTotal,
      returnedAmount: retAmt,
      originalTotal: origTotal,
      createdAt: m['created_at'] is Timestamp
          ? (m['created_at'] as Timestamp).toDate()
          : DateTime.tryParse(m['created_at']?.toString() ?? '') ??
              DateTime.now(),
      itemsCount: (m['items_count'] as num?)?.toInt() ?? 0,
      deliveryAddress: m['delivery_address'],
      notes: m['notes'],
      orderNumber: m['order_number'] ?? m['invoice_number'],
      latitude: (m['latitude'] as num?)?.toDouble(),
      longitude: (m['longitude'] as num?)?.toDouble(),
      signatureUrl: m['signature_url']?.toString(),
    );
  }
}

// ══ Service ══
class AdminService {
  final _db = FirebaseFirestore.instance;

  static Future<T> _withFirestoreRetry<T>(
    Future<T> Function() operation,
  ) async {
    return operation();
  }

  // ── إحصائيات دقيقة وفورية مع حماية مطلقة واستهلاك كاش معدوم التكلفة ──
  Future<AdminStats> getStats() async {
    try {
      int totalOrders = 0;
      int pendingOrders = 0;
      int totalMerchants = 0;
      int cancelledOrders = 0;
      int deliveredOrders = 0;
      double grossRevenue = 0.0;
      double totalProfit = 0.0;
      double returnedRevenue = 0.0;

      // 1. عدد التجار المسجلين (استعلام عداد سحابي = تكلفة معدومة)
      try {
        final snap = await _db
            .collection('profiles')
            .where('role', isEqualTo: 'merchant')
            .count()
            .get();
        totalMerchants = snap.count ?? 0;
      } catch (_) {}
// 2. إحصائيات أعداد الطلبات وحساب الأرباح الدائمة الثابتة
      try {
        final totalSnap = await _db.collection('orders').count().get();
        totalOrders = totalSnap.count ?? 0;

        final pendingSnap = await _db
            .collection('orders')
            .where('status', isEqualTo: 'pending')
            .count()
            .get();
        pendingOrders = pendingSnap.count ?? 0;

        final cancelledSnap = await _db
            .collection('orders')
            .where('status', whereIn: ['cancelled', 'rejected'])
            .count()
            .get();
        cancelledOrders = cancelledSnap.count ?? 0;

        final deliveredSnap = await _db
            .collection('orders')
            .where('status', isEqualTo: 'delivered')
            .count()
            .get();
        deliveredOrders = deliveredSnap.count ?? 0;

        // ✅ قراءة الإحصائيات التراكمية في خطوة واحدة (O(1)) لمنع استنزاف باقات Firebase
        final summaryDoc = await _db
            .collection('stats')
            .doc('profit_summary')
            .get(const GetOptions(source: Source.serverAndCache));

        if (summaryDoc.exists && summaryDoc.data() != null) {
          final sData = summaryDoc.data()!;
          grossRevenue =
              (sData['accumulated_revenue'] as num?)?.toDouble() ?? 0.0;
          totalProfit =
              (sData['accumulated_profit'] as num?)?.toDouble() ?? 0.0;
          returnedRevenue =
              (sData['accumulated_returns'] as num?)?.toDouble() ?? 0.0;
        } else {
          try {
            final aggSnap = await _db
                .collection('orders')
                .where('status', isEqualTo: 'delivered')
                .aggregate(sum('total_amount'), sum('total_profit'))
                .get();
            grossRevenue = aggSnap.getSum('total_amount') ?? 0.0;
            totalProfit = aggSnap.getSum('total_profit') ?? 0.0;
          } catch (_) {}
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[AdminService] orders calculation error: $e');
        }
      }

      return AdminStats(
        totalOrders: totalOrders,
        pendingOrders: pendingOrders,
        deliveredOrders: deliveredOrders,
        cancelledOrders: cancelledOrders,
        totalMerchants: totalMerchants,
        totalRevenue: grossRevenue,
        totalProfit: totalProfit,
        returnedAmount: returnedRevenue,
        hasCostData:
            deliveredOrders > 0 || totalProfit != 0 || grossRevenue > 0,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Admin statistics failed: $error\n$stackTrace');
      }
      return const AdminStats(
        totalOrders: 0,
        pendingOrders: 0,
        totalMerchants: 0,
        totalRevenue: 0.0,
        totalProfit: 0.0,
      );
    }
  }

  Future<Map<String, dynamic>> getTodayStats() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    try {
      // جلب أحدث الطلبات المسلمة مرتبة تنازلياً بوقت التسليم
      final snap = await _db
          .collection('orders')
          .where('status', isEqualTo: 'delivered')
          .orderBy('delivered_at', descending: true)
          .limit(250)
          .get(const GetOptions(source: Source.serverAndCache));

      double revenue = 0.0;
      int deliveredCount = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        final rawDate =
            data['delivered_at'] ?? data['updated_at'] ?? data['created_at'];

        if (rawDate is Timestamp) {
          final date = rawDate.toDate();
          if (date.isAfter(startOfDay) || date.isAtSameMomentAs(startOfDay)) {
            final amount = (data['total_amount'] as num?)?.toDouble() ??
                (data['total'] as num?)?.toDouble() ??
                0.0;
            revenue += amount;
            deliveredCount++;
          } else {
            // توقف التكرار بمجرد الوصول لطلبات ما قبل اليوم لأنها مرتبة تنازلياً
            break;
          }
        }
      }

      return {
        'revenue': revenue,
        'orders': deliveredCount.toDouble(),
      };
    } catch (error) {
      if (kDebugMode) debugPrint('Today statistics error: $error');
      return {'revenue': 0.0, 'orders': 0.0};
    }
  }

  Stream<double> watchPermanentProfit() {
    return _db
        .collection('stats')
        .doc('profit_summary')
        .snapshots(includeMetadataChanges: false)
        .map((doc) {
      if (!doc.exists || doc.data() == null) return 0.0;
      final data = doc.data()!;
      return (data['cycle_profit'] as num?)?.toDouble() ??
          (data['accumulated_profit'] as num?)?.toDouble() ??
          0.0;
    });
  }

// تفريغ أرباح الدورة الحالية مع تسجيل قيد مالي تدقيقي غير قابل للتعديل
  Future<void> resetPermanentProfit() async {
    final docRef = _db.collection('stats').doc('profit_summary');
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final currentCycle =
          (snap.data()?['cycle_profit'] as num?)?.toDouble() ?? 0.0;

      // 1. تسجيل قيد محاسبي تدقيقي في الأرشيف
      final logRef = _db.collection('profit_resets_log').doc();
      tx.set(logRef, {
        'cleared_amount': currentCycle,
        'cleared_by': AppStorage.userId ?? 'admin',
        'cleared_at': FieldValue.serverTimestamp(),
      });

      // 2. تصفير العداد للدورة الجديدة
      tx.set(
        docRef,
        {
          'cycle_profit': 0.0,
          'last_reset_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  // Firestore whereIn يقبل 30 عنصراً كحد أقصى
  List<List<String>> chunked(List<String> ids, {int size = 30}) {
    final chunks = <List<String>>[];
    for (int i = 0; i < ids.length; i += size) {
      chunks.add(ids.sublist(i, i + size > ids.length ? ids.length : i + size));
    }
    return chunks;
  }

// ── الطلبات (مرة واحدة مرتبة زمنياً) ──
  Future<List<AdminOrder>> getOrders({String? status, int limit = 50}) async {
    final query = status != null
        ? _db
            .collection('orders')
            .where('status', isEqualTo: status)
            .orderBy('created_at', descending: true)
            .limit(limit)
        : _db
            .collection('orders')
            .orderBy('created_at', descending: true)
            .limit(limit);

    final snap = await query.get();

    return snap.docs
        .map((d) => AdminOrder.fromMap({'id': d.id, ...d.data()}))
        .toList();
  }

  Stream<List<AdminOrder>> watchOrders({List<String>? statuses}) {
    Query<Map<String, dynamic>> query = _db.collection('orders');

    if (statuses != null && statuses.isNotEmpty) {
      if (statuses.length == 1) {
        query = query.where('status', isEqualTo: statuses.first);
      } else {
        query = query.where('status', whereIn: statuses.take(10).toList());
      }
    }

    return query
        .orderBy('created_at', descending: true)
        .limit(100)
        .snapshots(includeMetadataChanges: false)
        .map((snap) {
      return snap.docs
          .map((d) => AdminOrder.fromMap({'id': d.id, ...d.data()}))
          .toList();
    });
  }

  // ── عناصر الطلب ──
  Future<List<Map<String, dynamic>>> getOrderItems(String orderId) async {
    final cleanOrderId = orderId.trim();

    if (cleanOrderId.isEmpty) {
      throw ArgumentError('معرّف الطلب غير صالح');
    }

    try {
      final snap = await _db
          .collection('order_items')
          .where('order_id', isEqualTo: cleanOrderId)
          .get();

      return snap.docs
          .map((d) => <String, dynamic>{
                'id': d.id,
                ...d.data(),
              })
          .toList();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to load order items: $error');
        debugPrintStack(stackTrace: stackTrace);
      }

      rethrow;
    }
  }

// ── تحديث الحالة مع دعم معلمات السائق ──
  Future<bool> updateOrderStatus(
    String orderId,
    String status, {
    String? driverId,
    String? driverName,
  }) async {
    final cleanOrderId = orderId.trim();
    final cleanStatus = status.trim().toLowerCase();

    if (cleanOrderId.isEmpty) {
      throw ArgumentError('معرّف الطلب غير صالح');
    }

    const allowedStatuses = <String>{
      'pending',
      'confirmed',
      'preparing',
      'shipped',
      'on_the_way',
      'delivered',
      'cancelled',
      'rejected',
      'return_requested',
      'returned',
    };

    if (!allowedStatuses.contains(cleanStatus)) {
      throw ArgumentError('حالة الطلب غير صالحة');
    }

    final orderRef = _db.collection('orders').doc(cleanOrderId);
    // جلب مراجع المنتجات فقط (References) خارج الـ Transaction لمنع كسر التسلسل
    final requiresStockRestore =
        cleanStatus == 'cancelled' || cleanStatus == 'rejected';
    List<DocumentReference<Map<String, dynamic>>> itemRefs = [];
    if (requiresStockRestore) {
      final itemsQuery = await _db
          .collection('order_items')
          .where('order_id', isEqualTo: cleanOrderId)
          .get();
      itemRefs = itemsQuery.docs.map((d) => d.reference).toList();
    }

    final didChange = await AdminService._withFirestoreRetry<bool>(() {
      return _db.runTransaction<bool>((tx) async {
        // 1. قراءة الطلب
        final snap = await tx.get(orderRef);

        if (!snap.exists || snap.data() == null) {
          throw StateError('الطلب غير موجود');
        }
        final currentStatus =
            snap.data()?['status']?.toString().trim().toLowerCase() ??
                'pending';

        final isProfitAlreadyRecorded = snap.data()?['profit_recorded'] == true;
        if (currentStatus == cleanStatus &&
            (cleanStatus != 'delivered' || isProfitAlreadyRecorded)) {
          return false;
        }
        // 2. قراءة العناصر والمنتجات بتسلسل صارم داخل الـ Transaction
        List<DocumentSnapshot<Map<String, dynamic>>> txItems = [];
        final Map<String, DocumentSnapshot<Map<String, dynamic>>>
            productSnapshots = {};
        if (requiresStockRestore && itemRefs.isNotEmpty) {
          for (final ref in itemRefs) {
            final itemDoc = await tx.get(ref);
            txItems.add(itemDoc);
            final pId = itemDoc.data()?['product_id']?.toString() ?? '';
            if (pId.isNotEmpty && !productSnapshots.containsKey(pId)) {
              productSnapshots[pId] =
                  await tx.get(_db.collection('products').doc(pId));
            }
          }
        }
        const allowedTransitions = <String, Set<String>>{
          'pending': {
            'confirmed',
            'shipped',
            'delivered',
            'rejected',
            'cancelled'
          },
          'confirmed': {'preparing', 'shipped', 'delivered', 'cancelled'},
          'preparing': {'shipped', 'delivered', 'cancelled'},
          'shipped': {'on_the_way', 'delivered', 'cancelled'},
          'on_the_way': {'delivered', 'cancelled'},
          'delivered': {'delivered', 'return_requested'},
          'return_requested': {'returned', 'delivered'},
        };
        const finalStatuses = <String>{'cancelled', 'rejected', 'returned'};

        if (finalStatuses.contains(currentStatus)) {
          throw StateError('لا يمكن تعديل طلب وصل إلى حالة نهائية');
        }

        final nextStatuses =
            allowedTransitions[currentStatus] ?? const <String>{};

        if (!nextStatuses.contains(cleanStatus)) {
          throw StateError(
              'لا يمكن نقل الطلب من "$currentStatus" إلى "$cleanStatus"');
        }
        // 3. تطبيق الكتابات مع تسجيل تاريخ التسليم وبيانات السائق
        final Map<String, dynamic> updatePayload = {
          'status': cleanStatus,
          if (cleanStatus == 'delivered')
            'delivered_at': FieldValue.serverTimestamp(),
          if (driverId != null && driverId.trim().isNotEmpty)
            'driver_id': driverId.trim(),
          if (driverName != null && driverName.trim().isNotEmpty)
            'driver_name': driverName.trim(),
          'updated_at': FieldValue.serverTimestamp(),
        };
        tx.update(orderRef, updatePayload);
        // ✅ إضافة الأرباح والإيرادات إلى الملخص المركزي عند التسليم لمرة واحدة فقط
        if (cleanStatus == 'delivered') {
          final isProfitRecorded = snap.data()?['profit_recorded'] == true;
          final profit =
              (snap.data()?['total_profit'] as num?)?.toDouble() ?? 0.0;
          final totalAmount =
              (snap.data()?['total_amount'] as num?)?.toDouble() ??
                  (snap.data()?['total'] as num?)?.toDouble() ??
                  0.0;
          if (!isProfitRecorded) {
            final summaryRef = _db.collection('stats').doc('profit_summary');
            tx.set(
              summaryRef,
              {
                if (profit != 0) ...{
                  'accumulated_profit': FieldValue.increment(profit),
                  'cycle_profit': FieldValue.increment(profit),
                },
                if (totalAmount > 0)
                  'accumulated_revenue': FieldValue.increment(totalAmount),
                'last_updated': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
            tx.update(orderRef, {'profit_recorded': true});
          }
        }

        // استعادة المخزون الصافي فقط (طرح الكميات المرتجعة مسبقاً لمنع ازدواجية المخزون)
        if (requiresStockRestore && txItems.isNotEmpty) {
          final Map<String, double> stockToRestoreMap = {};
          for (final doc in txItems) {
            if (!doc.exists || doc.data() == null) continue;
            final itemData = doc.data()!;
            final productId = itemData['product_id']?.toString() ?? '';
            final orderedQty = (itemData['quantity'] as num?)?.toInt() ?? 0;
            final alreadyReturned =
                (itemData['returned_quantity'] as num?)?.toInt() ?? 0;
            final netQty = (orderedQty - alreadyReturned).clamp(0, orderedQty);

            if (netQty <= 0) continue;

            final cartonCapacity =
                (itemData['carton_capacity'] as num?)?.toInt() ?? 1;
            final capacity = cartonCapacity > 0 ? cartonCapacity : 1;
            final unitQty = (itemData['unit_qty'] as num?)?.toInt() ?? capacity;
            final cartonsToRestore = InventoryMath.cartonsFor(
              qty: netQty,
              unitQty: unitQty,
              cartonCapacity: capacity,
            );

            if (productId.isNotEmpty && cartonsToRestore > 0) {
              stockToRestoreMap[productId] =
                  (stockToRestoreMap[productId] ?? 0.0) + cartonsToRestore;
            }
          }

          for (final entry in stockToRestoreMap.entries) {
            final pDoc = productSnapshots[entry.key];
            if (pDoc != null && pDoc.exists) {
              tx.update(pDoc.reference, {
                'stock': FieldValue.increment(entry.value),
                'updated_at': FieldValue.serverTimestamp(),
              });
            }
          }
        }
        return true;
      });
    });
    if (didChange) {
      if (requiresStockRestore) {
        await AppCache.instance.invalidateProducts();
      }
      try {
        await _sendStatusNotification(cleanOrderId, cleanStatus);
      } catch (e) {
        // يتم تجاهل خطأ الإشعار لعدم كسر عملية التحديث الرئيسية
      }
    }

    return didChange;
  }

  Future<void> _sendStatusNotification(
    String orderId,
    String status,
  ) async {
    try {
      final order = await _db.collection('orders').doc(orderId).get();

      final merchantId = order.data()?['merchant_id']?.toString().trim() ?? '';

      if (merchantId.isEmpty) {
        return;
      }

      final info = _statusNotification(status);
      await _db.collection('user_notifications').add({
        'user_id': merchantId,
        'title': info['title'],
        'body': info['body'],
        'order_id': orderId,
        'type':
            'order_status', // ✅ مضاف لتمكين GoRouter من توجيه التاجر لصفحة الطلبات
        'status': status,
        'is_read': false,
        'created_at': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Order status notification failed: '
          '${e.code} ${e.message}',
        );
        debugPrintStack(stackTrace: stackTrace);
      }

      // لا نعيد الخطأ حتى لا نعتبر تغيير الحالة فاشلاً
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Order status notification failed: $e');
        debugPrintStack(stackTrace: stackTrace);
      }

      // الإشعار اختياري، وتغيير حالة الطلب هو العملية الأساسية
    }
  }

// ── تسجيل إرجاع مضمون ومحمي ذرياً داخل Transaction ──
  Future<bool> processReturn(
    String orderId,
    String reason, {
    List<Map<String, dynamic>> returnItems = const [],
  }) async {
    final cleanOrderId = orderId.trim();
    final cleanReason = reason.trim();

    if (cleanOrderId.isEmpty) throw ArgumentError('معرّف الطلب غير صالح');
    if (cleanReason.isEmpty) throw ArgumentError('سبب الإرجاع مطلوب');
    if (returnItems.isEmpty) throw ArgumentError('يجب تحديد عناصر للإرجاع');

    final orderRef = _db.collection('orders').doc(cleanOrderId);
    final allItemsSnap = await _db
        .collection('order_items')
        .where('order_id', isEqualTo: cleanOrderId)
        .get();

    final itemRefs = allItemsSnap.docs.map((d) => d.reference).toList();
    final itemProductIds = allItemsSnap.docs
        .map((d) => d.data()['product_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final productRefs = {
      for (final pId in itemProductIds) pId: _db.collection('products').doc(pId)
    };

    String merchantId = '';

    await _db.runTransaction((tx) async {
      // 1. القراءات أولاً بالكامل
      final orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists || orderSnap.data() == null) {
        throw StateError('الطلب غير موجود');
      }

      final orderData = orderSnap.data()!;
      final currentStatus =
          orderData['status']?.toString().trim().toLowerCase() ?? '';
      if (currentStatus == 'returned') {
        throw StateError(
            'تم إرجاع هذا الطلب بالكامل مسبقاً ولا يمكن معالجة مرتجع إضافي له');
      }
      merchantId = orderData['merchant_id']?.toString().trim() ?? '';
      final currentTotal = (orderData['total_amount'] as num?)?.toDouble() ??
          (orderData['total'] as num?)?.toDouble() ??
          0.0;

      if (currentTotal <= 0.0) {
        throw StateError(
            'رصيد الفاتورة صفر مسبقاً، لا يمكن إرجاع أي مبالغ إضافية');
      }

      // ✅ حماية حاسمة تمنع ازدواجية الخصم واسترجاع المخزون في حال وجود طلب معلق
      final pendingReturnsCount =
          (orderData['pending_returns_count'] as num?)?.toInt() ?? 0;
      if (pendingReturnsCount > 0 || currentStatus == 'return_requested') {
        throw StateError(
            'توجد طلبات إرجاع معلقة لهذا الطلب، يرجى معالجتها من تبويب المرجوعات منعاً لتكرار الخصم');
      }
      final itemDocsMap = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final ref in itemRefs) {
        final doc = await tx.get(ref);
        itemDocsMap[doc.id] = doc;
      }

      final productDocsMap = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in productRefs.entries) {
        productDocsMap[entry.key] = await tx.get(entry.value);
      }

      // 2. التحقق من صحة الكميات وتجهيز الحسابات
      double totalRefundAmount = 0.0;
      double totalRefundProfit = 0.0;
      final stockRestoreMap = <String, double>{};
      final returnDocsToCreate = <Map<String, dynamic>>[];
      final itemQtyUpdates = <DocumentReference, int>{};

      for (final rItem in returnItems) {
        final itemId = rItem['item_id']?.toString() ?? '';
        final returnQty = (rItem['quantity'] as num?)?.toInt() ?? 0;
        if (itemId.isEmpty || returnQty <= 0) continue;

        final itemDoc = itemDocsMap[itemId];
        if (itemDoc == null || !itemDoc.exists || itemDoc.data() == null) {
          throw StateError(
              'عنصر الطلب غير موجود في قاعدة البيانات، يرجى تحديث الصفحة');
        }

        final itemData = itemDoc.data()!;
        final orderedQty = (itemData['quantity'] as num?)?.toInt() ?? 0;
        final alreadyReturned =
            (itemData['returned_quantity'] as num?)?.toInt() ?? 0;

        // 🛡️ حماية صارمة تمنع الإرجاع الزائد عن الكمية المباعة
        if (alreadyReturned + returnQty > orderedQty) {
          throw StateError(
            'الكمية المطلوب إرجاعها من "${itemData['product_name']}" تتجاوز المتبقي من الطلب',
          );
        }

        final productId = itemData['product_id']?.toString() ?? '';
        final price = (itemData['price'] as num?)?.toDouble() ?? 0.0;
        final cartonCapacity =
            (itemData['carton_capacity'] as num?)?.toInt() ?? 1;
        final capacity = cartonCapacity > 0 ? cartonCapacity : 1;
        final unitQty = (itemData['unit_qty'] as num?)?.toInt() ?? capacity;

        final cartonsToRestore = InventoryMath.cartonsFor(
          qty: returnQty,
          unitQty: unitQty,
          cartonCapacity: capacity,
        );

        final unitCost = (itemData['unit_cost'] as num?)?.toDouble() ??
            (((itemData['cost_price'] as num?)?.toDouble() ?? 0.0) /
                capacity *
                unitQty);

        totalRefundAmount += (price * returnQty);
        totalRefundProfit += ((price - unitCost) * returnQty);

        if (productId.isNotEmpty) {
          stockRestoreMap[productId] =
              (stockRestoreMap[productId] ?? 0.0) + cartonsToRestore;
        }

        itemQtyUpdates[itemDoc.reference] = returnQty;

        returnDocsToCreate.add({
          'order_id': cleanOrderId,
          'order_item_id': itemId,
          'merchant_id': merchantId,
          'refund_amount': price * returnQty,
          'product_name': itemData['product_name'] ?? '',
          'quantity': returnQty,
          'reason': cleanReason,
          'status': 'accepted',
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      final newTotal =
          (currentTotal - totalRefundAmount).clamp(0.0, double.infinity);

      bool isFullyReturned = newTotal <= 0.01;
      if (!isFullyReturned) {
        bool allZeroRemaining = true;
        for (final ref in itemRefs) {
          final doc = itemDocsMap[ref.id];
          if (doc == null || !doc.exists || doc.data() == null) continue;
          final ordered = (doc.data()!['quantity'] as num?)?.toInt() ?? 0;
          final alreadyRet =
              (doc.data()!['returned_quantity'] as num?)?.toInt() ?? 0;
          final addedRet = itemQtyUpdates[doc.reference] ?? 0;
          if ((alreadyRet + addedRet) < ordered) {
            allZeroRemaining = false;
            break;
          }
        }
        isFullyReturned = allZeroRemaining;
      }

      // 3. تنفيذ جميع الكتابات بعد القراءات
      for (final entry in itemQtyUpdates.entries) {
        tx.update(entry.key, {
          'returned_quantity': FieldValue.increment(entry.value),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      for (final rDoc in returnDocsToCreate) {
        tx.set(_db.collection('order_returns').doc(), rDoc);
      }
      tx.update(orderRef, {
        'status': isFullyReturned ? 'returned' : 'delivered',
        'total': newTotal,
        'total_amount': newTotal,
        'original_total': orderData['original_total'] ?? currentTotal,
        'returned_amount': FieldValue.increment(totalRefundAmount),
        'total_profit': FieldValue.increment(-totalRefundProfit),
        'return_reason': cleanReason,
        'updated_at': FieldValue.serverTimestamp(),
      });
// ✅ خصم الأرباح والإيرادات فقط إذا كانت قد سُجلت مسبقاً عند التسليم الفعلي
      final bool wasProfitRecorded = orderData['profit_recorded'] == true;
      final summaryRef = _db.collection('stats').doc('profit_summary');
      tx.set(
        summaryRef,
        {
          if (wasProfitRecorded && totalRefundProfit != 0) ...{
            'accumulated_profit': FieldValue.increment(-totalRefundProfit),
            'cycle_profit': FieldValue.increment(-totalRefundProfit),
          },
          if (wasProfitRecorded && totalRefundAmount != 0)
            'accumulated_revenue': FieldValue.increment(-totalRefundAmount),
          if (totalRefundAmount != 0)
            'accumulated_returns': FieldValue.increment(totalRefundAmount),
          'last_updated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      for (final entry in stockRestoreMap.entries) {
        final pDoc = productDocsMap[entry.key];
        if (pDoc != null && pDoc.exists) {
          tx.update(pDoc.reference, {
            'stock': FieldValue.increment(entry.value),
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      }
    });
    // ✅ إبطال كاش المنتجات لتحديث رصيد المخزون فوراً بعد الإرجاع
    await AppCache.instance.invalidateProducts();
    if (merchantId.isNotEmpty) {
      try {
        await _db.collection('user_notifications').add({
          'user_id': merchantId,
          'title': 'تم تسجيل المرتجع بنجاح ✅',
          'body':
              'تمت الموافقة على إرجاع الأصناف وخصم قيمتها من إجمالي الفاتورة.',
          'order_id': cleanOrderId,
          'type': 'order_status',
          'is_read': false,
          'created_at': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    return true;
  }

  Map<String, String> _statusNotification(String status) {
    return switch (status) {
      'confirmed' => {
          'title': '✅ طلبك عندنا وبالأمانة!',
          'body':
              'استلمنا طلبك وبدأنا تجهيزه بعناية. أنت في أيدٍ أمينة 💪 شكراً لثقتك بنا!',
        },
      'shipped' => {
          'title': '🚚 طلبك انطلق نحوك!',
          'body': 'المندوب في الطريق إليك الآن 🛣️ استعد للاستقبال!',
        },
      'delivered' => {
          'title': '🎉 وصل طلبك بالسلامة!',
          'body':
              'تم التسليم بنجاح ✨ نتمنى أن تكون راضياً تماماً. رأيك يهمنا كثيراً، ونسعد بخدمتك دائماً 🙏💚',
        },
      'cancelled' => {
          'title': '💛 بخصوص طلبك',
          'body':
              'نأسف على الإزعاج، واجهنا ظرفاً طارئاً اضطررنا فيه لإيقاف هذا الطلب مؤقتاً. يسعدنا خدمتك في أقرب وقت 🙏',
        },
      'rejected' => {
          'title': '💛 بخصوص طلبك',
          'body':
              'نعتذر منك بصدق، لم نتمكن من تنفيذ طلبك هذه المرة لأسباب خارجة عن إرادتنا. نقدّر ثقتك ونتطلع لخدمتك في المرة القادمة 🙏',
        },
      _ => {
          'title': '📦 تحديث طلبك',
          'body': 'تم تحديث حالة طلبك. نحن هنا لخدمتك دائماً 💚',
        },
    };
  }

// ── إشعارات ──
  Future<List<Map<String, dynamic>>> getUserNotifications(String userId) async {
    try {
      final snap = await _db
          .collection('user_notifications')
          .where('user_id', isEqualTo: userId)
          .orderBy('created_at', descending: true)
          .limit(50)
          .get();
      final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      list.sort((a, b) {
        final aDate = a['created_at'] is Timestamp
            ? (a['created_at'] as Timestamp).toDate()
            : DateTime(2000);
        final bDate = b['created_at'] is Timestamp
            ? (b['created_at'] as Timestamp).toDate()
            : DateTime(2000);
        return bDate.compareTo(aDate);
      });
      return list.take(30).toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdminService] silent error at getUserNotifications: $e');
        debugPrintStack(stackTrace: st);
      }
      return [];
    }
  }

  Future<void> markNotificationRead(String notifId) async {
    try {
      await _db
          .collection('user_notifications')
          .doc(notifId)
          .update({'is_read': true});
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Return notification failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }

      rethrow;
    }
  }

  Future<int> getUnreadCount(String userId) async {
    try {
      final snap = await _db
          .collection('user_notifications')
          .where('user_id', isEqualTo: userId)
          .where('is_read', isEqualTo: false)
          .count()
          .get();
      return snap.count ?? 0;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdminService] silent error at line ~720: $e');
        debugPrintStack(stackTrace: st);
      }
      return 0;
    }
  }

  // ── الأصناف (مع كاش مدمج) ──
  Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      final snap = await _db
          .collection('categories')
          .orderBy('sort_order')
          .limit(200)
          .get(const GetOptions(source: Source.serverAndCache));
      return snap.docs
          .where((d) => d.data()['is_deleted'] != true)
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdminService] silent error in getCategories: $e');
        debugPrintStack(stackTrace: st);
      }
      return [];
    }
  }

  Future<void> addCategory(String name, {String? imageUrl}) async {
    // جلب آخر sort_order لوضع الصنف الجديد في آخر القائمة
    final snap = await _db
        .collection('categories')
        .orderBy('sort_order', descending: true)
        .limit(1)
        .get();
    final lastOrder = snap.docs.isEmpty
        ? 0
        : ((snap.docs.first.data()['sort_order'] as num?)?.toInt() ?? 0);

    await _db.collection('categories').add({
      'name': name,
      if (imageUrl != null) 'image_url': imageUrl,
      'sort_order': lastOrder + 1,
      'is_active': true,
      'is_deleted': false,
      'created_at': FieldValue.serverTimestamp(),
    });

    await AppCache.instance.invalidateCategories();
  }

  /// حذف الصنف تسلسلياً مع جميع الشركات والمنتجات والكميات التابعة له والصور
  Future<bool> deleteCategory(String id) async {
    try {
      final cleanId = id.trim();
      if (cleanId.isEmpty) return false;

      // 1. جلب الشركات التابعة للصنف
      final brandsSnap = await _db
          .collection('brands')
          .where('category_id', isEqualTo: cleanId)
          .get();

      final brandIds = brandsSnap.docs.map((d) => d.id).toList();

      // 2. جلب المنتجات التابعة للصنف
      final productsByCatSnap = await _db
          .collection('products')
          .where('category_id', isEqualTo: cleanId)
          .get();

      final allProductDocs = <DocumentSnapshot<Map<String, dynamic>>>[
        ...productsByCatSnap.docs
      ];

      // جلب منتجات الشركات التابعة للصنف بشكل متوازي
      if (brandIds.isNotEmpty) {
        final futures = chunked(brandIds, size: 30).map((chunk) =>
            _db.collection('products').where('brand_id', whereIn: chunk).get());

        final results = await Future.wait(futures);
        for (final snap in results) {
          allProductDocs.addAll(snap.docs);
        }
      }
// 🚀 3. استخراج صور المنتجات وشعارات الشركات وصورة الصنف لحذفها بالكامل من Firebase Storage
      final Set<String> imageUrls = <String>{};
      final catSnap = await _db.collection('categories').doc(cleanId).get();
      final catImg = catSnap.data()?['image_url'] as String?;
      if (catImg != null && catImg.trim().isNotEmpty) {
        imageUrls.add(catImg.trim());
      }

      for (final b in brandsSnap.docs) {
        final bLogo = b.data()['logo_url'] as String?;
        if (bLogo != null && bLogo.trim().isNotEmpty) {
          imageUrls.add(bLogo.trim());
        }
      }

      for (final doc in allProductDocs) {
        final d = doc.data();
        if (d == null) continue;
        final mainUrl = d['image_url'] as String?;
        if (mainUrl != null && mainUrl.trim().isNotEmpty) {
          imageUrls.add(mainUrl.trim());
        }
        final rawUnits = d['units'];
        if (rawUnits is List) {
          for (final u in rawUnits) {
            if (u is Map && u['image_url'] != null) {
              final uUrl = u['image_url'].toString().trim();
              if (uUrl.isNotEmpty) imageUrls.add(uUrl);
            }
          }
        }
      }
      // 4. جمع كافة المراجع لتحديثها كـ Soft-Delete بدلاً من الحذف الفعلي
      // ⚠️ الحذف الفعلي يكسر order_items التاريخية ويمنع استرجاع المخزون عند الإرجاع
      final Map<String, DocumentReference> uniqueRefs = {};
      for (final p in allProductDocs) {
        uniqueRefs[p.reference.path] = p.reference;
      }
      for (final b in brandsSnap.docs) {
        uniqueRefs[b.reference.path] = b.reference;
      }
      final catRef = _db.collection('categories').doc(cleanId);
      uniqueRefs[catRef.path] = catRef;

      final allRefsToDelete = uniqueRefs.values.toList();
      // 5. تطبيق Soft-Delete — البيانات تبقى في Firestore للحفاظ على مرجعية order_items
      const chunkSize = 400;
      for (int i = 0; i < allRefsToDelete.length; i += chunkSize) {
        final chunk = allRefsToDelete.sublist(
          i,
          (i + chunkSize) > allRefsToDelete.length
              ? allRefsToDelete.length
              : i + chunkSize,
        );
        final batch = _db.batch();
        for (final ref in chunk) {
          batch.update(ref, {
            'is_deleted': true,
            'is_active': false,
            'deleted_at': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      // 6. حذف الصور من Storage فقط بعد نجاح الحذف من Firestore
      if (imageUrls.isNotEmpty) {
        const batchSize = 10;
        for (int i = 0; i < imageUrls.length; i += batchSize) {
          final batch = imageUrls.skip(i).take(batchSize).toList();
          await Future.wait(
            batch.map((url) async {
              try {
                await FirebaseStorage.instance.refFromURL(url).delete();
              } catch (_) {}
            }),
          );
        }
      }
      // تنظيف الكاش المحلي
      await AppCache.instance.invalidateCategories();
      await AppCache.instance
          .invalidateBrands(); // ✅ تفريغ كاش الشركات التابعة للصنف
      await AppCache.instance.invalidateProducts();

      return true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdminService] deleteCategory error: $e\n$st');
      }
      return false;
    }
  }

// ── الشركات (مع فرز بالذاكرة لتفادي FAILED_PRECONDITION) ──
  Future<List<Map<String, dynamic>>> getBrands({String? categoryId}) async {
    try {
      final query = categoryId != null
          ? _db.collection('brands').where('category_id', isEqualTo: categoryId)
          : _db.collection('brands');
      final snap = await query
          .limit(500)
          .get(const GetOptions(source: Source.serverAndCache));
      final list = snap.docs
          .where((d) => d.data()['is_deleted'] != true)
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
      list.sort((a, b) =>
          (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
      return list;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdminService] silent error in getBrands: $e');
        debugPrintStack(stackTrace: st);
      }
      return [];
    }
  }

  Future<void> addBrand({
    required String name,
    required String categoryId,
    String? logoUrl,
  }) async {
    await _db.collection('brands').add({
      'name': name,
      'category_id': categoryId,
      if (logoUrl != null) 'logo_url': logoUrl,
      'is_active': true,
      'is_deleted': false,
      'created_at': FieldValue.serverTimestamp(),
    });
    await AppCache.instance.invalidateBrands();
  }

  /// حذف الشركة تسلسلياً مع جميع المنتجات والكميات التابعة لها والصور
  Future<bool> deleteBrand(String id) async {
    try {
      final cleanId = id.trim();
      if (cleanId.isEmpty) return false;

      // 1. جلب كافة المنتجات التابعة للشركة
      final productsSnap = await _db
          .collection('products')
          .where('brand_id', isEqualTo: cleanId)
          .get();

// 🚀 2. استخراج شعار الشركة وصور المنتجات وصور الوحدات الفرعية وحذفها من Firebase Storage
      final List<String> imageUrls = [];

      final brandDoc = await _db.collection('brands').doc(cleanId).get();
      final brandLogo = brandDoc.data()?['logo_url'] as String?;
      if (brandLogo != null && brandLogo.trim().isNotEmpty) {
        imageUrls.add(brandLogo.trim());
      }

      for (final doc in productsSnap.docs) {
        final d = doc.data();
        final mainUrl = d['image_url'] as String?;
        if (mainUrl != null && mainUrl.trim().isNotEmpty) {
          imageUrls.add(mainUrl.trim());
        }
        final rawUnits = d['units'];
        if (rawUnits is List) {
          for (final u in rawUnits) {
            if (u is Map && u['image_url'] != null) {
              final uUrl = u['image_url'].toString().trim();
              if (uUrl.isNotEmpty) imageUrls.add(uUrl);
            }
          }
        }
      }
      final allRefsToDelete = <DocumentReference>[
        for (final p in productsSnap.docs) p.reference,
        _db.collection('brands').doc(cleanId),
      ];

      // 3. تطبيق Soft-Delete بدلاً من الحذف الفعلي — للحفاظ على مرجعية order_items التاريخية
      const chunkSize = 400;
      for (int i = 0; i < allRefsToDelete.length; i += chunkSize) {
        final chunk = allRefsToDelete.sublist(
          i,
          (i + chunkSize) > allRefsToDelete.length
              ? allRefsToDelete.length
              : i + chunkSize,
        );
        final batch = _db.batch();
        for (final ref in chunk) {
          batch.update(ref, {
            'is_deleted': true,
            'is_active': false,
            'deleted_at': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      // 4. حذف الصور من السيرفر بعد التأكد من نجاح الحذف البرمجي
      if (imageUrls.isNotEmpty) {
        const batchSize = 10;
        for (int i = 0; i < imageUrls.length; i += batchSize) {
          final batch = imageUrls.skip(i).take(batchSize).toList();
          await Future.wait(
            batch.map((url) async {
              try {
                await FirebaseStorage.instance.refFromURL(url).delete();
              } catch (_) {}
            }),
          );
        }
      }
      // تنظيف كاش المنتجات والشركات
      await AppCache.instance.invalidateBrands(); // ✅ تفريغ كاش الشركات المحلي
      await AppCache.instance.invalidateProducts();

      return true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdminService] deleteBrand error: $e\n$st');
      }
      return false;
    }
  }

// ── المنتجات (مع فرز بالذاكرة لتفادي FAILED_PRECONDITION) ──
  Future<List<Map<String, dynamic>>> getProducts({String? brandId}) async {
    try {
      final query = brandId != null
          ? _db.collection('products').where('brand_id', isEqualTo: brandId)
          : _db.collection('products');
      final snap = await query
          .limit(500)
          .get(const GetOptions(source: Source.serverAndCache));
      final list = snap.docs
          .where((d) => d.data()['is_deleted'] != true)
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
      list.sort((a, b) =>
          (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
      return list;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdminService] getProducts error: $e');
        debugPrintStack(stackTrace: st);
      }
      return [];
    }
  }

  Future<void> addProduct({
    required String name,
    required String brandId,
    required double price,
    double costPrice = 0,
    int? itemsPerCarton,
    double? sizeMl,
    String? sizeText,
    double stock = 0.0,
    String? imageUrl,
    String? productionDate,
    String? expiryDate,
    String? barcode,
    List<Map<String, dynamic>> units = const [],
  }) async {
    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError('اسم المنتج مطلوب');
    }

    if (brandId.trim().isEmpty) {
      throw ArgumentError('الشركة مطلوبة');
    }

    if (price < 0) {
      throw ArgumentError('السعر لا يمكن أن يكون سالباً');
    }

    if (costPrice < 0) {
      throw ArgumentError('سعر التكلفة لا يمكن أن يكون سالباً');
    }

    if (stock < 0) {
      throw ArgumentError('المخزون لا يمكن أن يكون سالباً');
    }

    final brandSnap = await _db.collection('brands').doc(brandId).get();

    if (!brandSnap.exists) {
      throw StateError('الشركة غير موجودة');
    }

    final brandData = brandSnap.data() ?? <String, dynamic>{};
    final categoryId = brandData['category_id']?.toString();

    if (categoryId == null || categoryId.isEmpty) {
      throw StateError('الشركة غير مرتبطة بصنف');
    }

    DateTime? parseDate(String? value) {
      if (value == null || value.trim().isEmpty) return null;
      return DateTime.tryParse(value.trim());
    }

    final production = parseDate(productionDate);
    final expiry = parseDate(expiryDate);

    if (productionDate != null && production == null) {
      throw ArgumentError('تاريخ الإنتاج غير صحيح');
    }

    if (expiryDate != null && expiry == null) {
      throw ArgumentError('تاريخ الانتهاء غير صحيح');
    }

    if (production != null && expiry != null && expiry.isBefore(production)) {
      throw ArgumentError('تاريخ الانتهاء يجب أن يكون بعد تاريخ الإنتاج');
    }

    final data = <String, dynamic>{
      'name': cleanName,
      'brand_id': brandId,
      'category_id': categoryId,
      'price': price,
      'cost_price': costPrice,
      'stock': stock,
      'is_active': true,
      'is_deleted': false,
      if (barcode != null && barcode.trim().isNotEmpty)
        'barcode': barcode.trim(),
      'sort_order': DateTime.now().millisecondsSinceEpoch,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (itemsPerCarton != null) {
      if (itemsPerCarton <= 0) {
        throw ArgumentError('عدد الوحدات يجب أن يكون أكبر من صفر');
      }
      data['items_per_carton'] = itemsPerCarton;
    }

    if (sizeMl != null) {
      if (sizeMl <= 0) {
        throw ArgumentError('الحجم يجب أن يكون أكبر من صفر');
      }
      data['size_ml'] = sizeMl;
    }

    if (sizeText != null && sizeText.trim().isNotEmpty) {
      data['size_text'] = sizeText.trim();
    }
    if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      data['image_url'] = imageUrl.trim();
    }

    if (production != null) {
      data['production_date'] = Timestamp.fromDate(production);
    }

    if (expiry != null) {
      data['expiry_date'] = Timestamp.fromDate(expiry);
    }

    if (units.isNotEmpty) {
      data['units'] = units
          .where((unit) {
            final label = unit['label']?.toString().trim() ?? '';
            final unitPrice = (unit['price'] as num?)?.toDouble() ?? -1;
            final qty = (unit['qty'] as num?)?.toInt() ?? 0;
            return label.isNotEmpty && unitPrice >= 0 && qty > 0;
          })
          .map((unit) => Map<String, dynamic>.from(unit))
          .toList();
    }

    await _db.collection('products').add(data);
    await AppCache.instance.invalidateProducts();
  }

  Future<void> updateProduct(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final cleanId = id.trim();

    if (cleanId.isEmpty) {
      throw ArgumentError('معرّف المنتج غير صالح');
    }

    const allowedFields = {
      'name',
      'brand_id',
      'category_id',
      'size_text',
      'price',
      'cost_price',
      'stock',
      'size_ml',
      'items_per_carton',
      'image_url',
      'production_date',
      'expiry_date',
      'barcode',
      'units',
      'is_active',
    };
    final safeUpdates = <String, dynamic>{};

    for (final entry in updates.entries) {
      if (allowedFields.contains(entry.key)) {
        safeUpdates[entry.key] = entry.value;
      }
    }

    if (safeUpdates.isEmpty) {
      throw ArgumentError('لا توجد بيانات صالحة للتحديث');
    }

    if (safeUpdates['price'] is num &&
        (safeUpdates['price'] as num).toDouble() < 0) {
      throw ArgumentError('السعر غير صالح');
    }

    if (safeUpdates['cost_price'] is num &&
        (safeUpdates['cost_price'] as num).toDouble() < 0) {
      throw ArgumentError('سعر التكلفة غير صالح');
    }

    if (safeUpdates['stock'] is num &&
        (safeUpdates['stock'] as num).toDouble() < 0) {
      throw ArgumentError('المخزون لا يمكن أن يكون سالباً');
    }

    safeUpdates['updated_at'] = FieldValue.serverTimestamp();

    await _db.collection('products').doc(cleanId).update(safeUpdates);
    await AppCache.instance.invalidateProducts();
  }

  Future<void> deleteProduct(String id) async {
    final cleanId = id.trim();

    if (cleanId.isEmpty) {
      throw ArgumentError('معرّف المنتج غير صالح');
    }

    final ref = _db.collection('products').doc(cleanId);

    // 🚀 حذف الصورة الأساسية وصور الوحدات الفرعية من Storage لمنع تراكم الملفات اليتيمة
    final snap = await ref.get();
    final pData = snap.data();
    final List<String> urlsToDelete = [];

    final mainImage = pData?['image_url'] as String?;
    if (mainImage != null && mainImage.trim().isNotEmpty) {
      urlsToDelete.add(mainImage.trim());
    }

    final rawUnits = pData?['units'];
    if (rawUnits is List) {
      for (final u in rawUnits) {
        if (u is Map && u['image_url'] != null) {
          final uUrl = u['image_url'].toString().trim();
          if (uUrl.isNotEmpty) urlsToDelete.add(uUrl);
        }
      }
    }

    for (final url in urlsToDelete) {
      if (url.contains('firebasestorage.googleapis.com')) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }
    }

    // ✅ توحيد سياسة الحذف البرمجي الناعم (Soft-Delete) للحفاظ على سلامة الفواتير السابقة واستعادة المخزون عند المرتجع
    await ref.update({
      'is_deleted': true,
      'is_active': false,
      'deleted_at': FieldValue.serverTimestamp(),
    });

    // تفريغ كاش المنتجات
    await AppCache.instance.invalidateProducts();
  }

// ── التجار (بدون تعارض فهارس مركبة) ──
  Future<List<Map<String, dynamic>>> getMerchants({
    int limit = 100,
    DocumentSnapshot? startAfter,
  }) async {
    var query = _db
        .collection('profiles')
        .where('role', isEqualTo: 'merchant')
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap =
        await query.get(const GetOptions(source: Source.serverAndCache));

    final list = snap.docs
        .map((d) => {
              'id': d.id,
              ...d.data(),
            })
        .toList();
    list.sort((a, b) {
      final aDate = a['created_at'] is Timestamp
          ? (a['created_at'] as Timestamp).toDate()
          : DateTime(2000);
      final bDate = b['created_at'] is Timestamp
          ? (b['created_at'] as Timestamp).toDate()
          : DateTime(2000);
      return bDate.compareTo(aDate);
    });
    return list;
  }

  Future<void> updateMerchantStatus(
    String id,
    bool isActive,
  ) async {
    final cleanId = id.trim();

    if (cleanId.isEmpty) {
      throw ArgumentError('معرّف التاجر غير صالح');
    }

    await _db.collection('profiles').doc(cleanId).update({
      'is_active': isActive,
      'account_status': isActive ? 'active' : 'suspended',
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> toggleMerchantStatus(
    String merchantId,
    bool isActive,
  ) =>
      updateMerchantStatus(merchantId, isActive);
// ── إحصائيات تاجر محدد (خالية من تعارض الفهارس المركبة - محدث) ──
  Future<Map<String, dynamic>> getMerchantStats(String merchantId) async {
    try {
      // 🚀 استعلام بسيط جداً لا يتطلب Composite Index، يجلب طلبات التاجر المعني فقط
      final snap = await _db
          .collection('orders')
          .where('merchant_id', isEqualTo: merchantId)
          .get(const GetOptions(source: Source.serverAndCache));

      int totalOrders = snap.docs.length;
      int deliveredOrders = 0;
      int cancelledOrders = 0;
      double totalRevenue = 0.0;

      // 🚀 الحساب يتم بسرعة الضوء في الذاكرة (RAM) مهما كان عدد الطلبات
      for (final doc in snap.docs) {
        final data = doc.data();
        final status = data['status']?.toString() ?? '';

        if (status == 'delivered') {
          deliveredOrders++;
          totalRevenue += (data['total_amount'] as num?)?.toDouble() ??
              (data['total'] as num?)?.toDouble() ??
              0.0;
        } else if (status == 'cancelled' || status == 'rejected') {
          cancelledOrders++;
        }
      }

      return {
        'total_orders': totalOrders,
        'delivered_orders': deliveredOrders,
        'cancelled_orders': cancelledOrders,
        'total_revenue': totalRevenue,
      };
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdminService] getMerchantStats error: $e');
        debugPrintStack(stackTrace: st);
      }
      return {
        'total_orders': 0,
        'delivered_orders': 0,
        'cancelled_orders': 0,
        'total_revenue': 0.0,
      };
    }
  }

  // ── إرسال إشعار لتاجر محدد ──
  Future<void> sendNotificationToMerchant({
    required String merchantId,
    required String title,
    required String body,
  }) async {
    await _db.collection('user_notifications').add({
      'user_id': merchantId,
      'title': title,
      'body': body,
      'is_read': false,
      'type': 'admin_message',
      'created_at': FieldValue.serverTimestamp(),
    });
  }

// ── حظر تاجر نهائياً من التطبيق ──
  Future<void> banMerchant(String merchantId) async {
    await _db.collection('profiles').doc(merchantId).update({
      'is_active': false,
      'is_banned': true,
      'account_status': 'banned',
      'banned_at': FieldValue.serverTimestamp(),
    });
  }

  // ── تغيير دور المستخدم ──
  Future<void> changeUserRole(
    String userId,
    String newRole,
  ) async {
    final cleanUserId = userId.trim();
    final cleanRole = newRole.trim().toLowerCase();

    if (cleanUserId.isEmpty) {
      throw ArgumentError('معرّف المستخدم غير صالح');
    }

    const allowedRoles = {
      'merchant',
      'driver',
      'admin',
      'super_admin',
      'accountant',
      'warehouse_manager',
    };

    if (!allowedRoles.contains(cleanRole)) {
      throw ArgumentError('دور المستخدم غير صالح');
    }

    final updates = <String, dynamic>{
      'role': cleanRole,
      'updated_at': FieldValue.serverTimestamp(),
    };

    if (cleanRole == 'driver') {
      updates['is_active'] = true;
      updates['is_banned'] = false;
    }

    await _db.collection('profiles').doc(cleanUserId).update(updates);
  }

// ── رفع الحظر عن تاجر ──
  Future<void> unbanMerchant(String merchantId) async {
    await _db.collection('profiles').doc(merchantId).update({
      'is_active': true,
      'is_banned': false,
      'account_status': 'active',
      'banned_at': null,
    });
  }

// ── إشعارات الإدارة (قراءة سجل البث العام المُرسل للتجار) ──
  Future<List<Map<String, dynamic>>> getNotifications() async {
    try {
      final snap = await _db
          .collection('broadcast_notifications')
          .orderBy('created_at', descending: true)
          .limit(50)
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdminService] getNotifications error: $e');
        debugPrintStack(stackTrace: st);
      }
      return [];
    }
  }

  Future<void> sendNotification({
    required String title,
    required String body,
  }) async {
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty || cleanBody.isEmpty) return;

    // ✅ 1. تسجيل وثيقة البث المركزي للبث السحابي الفوري لجميع الأجهزة المشتركة في Topic merchants
    await _db.collection('broadcast_notifications').add({
      'title': cleanTitle,
      'body': cleanBody,
      'target_role': 'merchant',
      'topic': 'merchants',
      'created_at': FieldValue.serverTimestamp(),
      'status': 'sent',
    });

    // ✅ 2. حفظ عينة سريعة في صندوق إشعارات التجار المتصلين دون إرهاق معالج وشبكة هاتف الأدمن
    try {
      final merchantsSnap = await _db
          .collection('profiles')
          .where('role', isEqualTo: 'merchant')
          .limit(100)
          .get(const GetOptions(source: Source.serverAndCache));

      final activeMerchants = merchantsSnap.docs
          .where((d) => d.data()['is_banned'] != true)
          .toList();

      if (activeMerchants.isNotEmpty) {
        final batch = _db.batch();
        for (final merchantDoc in activeMerchants) {
          final notifRef = _db.collection('user_notifications').doc();
          batch.set(notifRef, {
            'user_id': merchantDoc.id,
            'title': cleanTitle,
            'body': cleanBody,
            'is_read': false,
            'type': 'notification',
            'created_at': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AdminService] Broadcast sample write: $e');
      }
    }
  }

// ── طلبات تاجر محدد ──
  Future<List<Map<String, dynamic>>> getMerchantOrders(
      String merchantId) async {
    try {
      final snap = await _db
          .collection('orders')
          .where('merchant_id', isEqualTo: merchantId)
          .orderBy('created_at', descending: true)
          .limit(50)
          .get(const GetOptions(source: Source.serverAndCache));
      final list = snap.docs.map((d) {
        final rawDate = d.data()['created_at'];
        final String formattedDate = rawDate is Timestamp
            ? rawDate.toDate().toIso8601String()
            : (rawDate?.toString() ?? '');
        return {
          'status': d.data()['status'] ?? '',
          'total': (d.data()['total_amount'] as num?)?.toDouble() ??
              (d.data()['total'] as num?)?.toDouble() ??
              0,
          'created_at': formattedDate,
          '_raw_date': rawDate,
        };
      }).toList()
        ..sort((a, b) {
          DateTime parse(dynamic v) {
            if (v is Timestamp) return v.toDate();
            if (v is DateTime) return v;
            if (v is String) return DateTime.tryParse(v) ?? DateTime(2000);
            return DateTime(2000);
          }

          return parse(b['_raw_date']).compareTo(parse(a['_raw_date']));
        });
      return list.take(20).toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdminService] silent error in getMerchantOrders: $e');
        debugPrintStack(stackTrace: st);
      }
      return [];
    }
  }

  // ── مرجوعات طلب محدد (فرز بالذاكرة لتفادي FAILED_PRECONDITION) ──
  Future<List<Map<String, dynamic>>> getOrderReturns(String orderId) async {
    if (orderId.isEmpty) return [];
    try {
      final snap = await _db
          .collection('order_returns')
          .where('order_id', isEqualTo: orderId)
          .get(const GetOptions(source: Source.serverAndCache));
      final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList()
        ..sort((a, b) {
          DateTime parse(dynamic v) {
            if (v is Timestamp) return v.toDate();
            if (v is DateTime) return v;
            if (v is String) return DateTime.tryParse(v) ?? DateTime(2000);
            return DateTime(2000);
          }

          return parse(b['created_at']).compareTo(parse(a['created_at']));
        });
      return list;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdminService] silent error in getOrderReturns: $e');
        debugPrintStack(stackTrace: st);
      }
      return [];
    }
  }

// ── تحديث حالة المرجوع فائق السرعة وبشكل متوازي ──
  Future<void> updateReturnStatus(String returnId, String status,
      {String? rejectionReason}) async {
    final cleanReturnId = returnId.trim();
    final cleanStatus = status.trim().toLowerCase();
    if (cleanReturnId.isEmpty ||
        (cleanStatus != 'accepted' && cleanStatus != 'rejected')) return;

    final returnRef = _db.collection('order_returns').doc(cleanReturnId);

    // جلب بيانات المرجع والطلب في نفس اللحظة بشكل متوازي
    final preReturnSnap =
        await returnRef.get(const GetOptions(source: Source.serverAndCache));
    if (!preReturnSnap.exists || preReturnSnap.data() == null) return;
    final preReturnData = preReturnSnap.data()!;

    final currentReturnStatus = preReturnData['status']?.toString();
    if (currentReturnStatus != 'pending') return;

    final orderId = preReturnData['order_id']?.toString() ?? '';
    final merchantId = preReturnData['merchant_id']?.toString() ?? '';
    final itemId = preReturnData['order_item_id']?.toString() ?? '';
    final qty = (preReturnData['quantity'] as num?)?.toInt() ?? 0;

    final itemsSnap = orderId.isNotEmpty
        ? await _db
            .collection('order_items')
            .where('order_id', isEqualTo: orderId)
            .get(const GetOptions(source: Source.serverAndCache))
        : null;
    final itemRefs = itemsSnap?.docs.map((d) => d.reference).toList() ?? [];

    await _db.runTransaction((tx) async {
      final txReturnSnap = await tx.get(returnRef);
      if (!txReturnSnap.exists) return;
      final txReturnData = txReturnSnap.data()!;
      if (txReturnData['status']?.toString() != 'pending') return;

      // 🚀 قراءة متوازية بدون أي تكرار لوثيقة العنصر داخل المعاملة
      final futures = <Future<DocumentSnapshot<Map<String, dynamic>>>>[
        if (orderId.trim().isNotEmpty)
          tx.get(_db.collection('orders').doc(orderId.trim())),
        for (final ref in itemRefs) tx.get(ref),
      ];

      final results = await Future.wait(futures);
      int readIdx = 0;
      final DocumentSnapshot<Map<String, dynamic>>? txOrderSnap =
          orderId.trim().isNotEmpty ? results[readIdx++] : null;
      final txAllItemsSnaps = results.sublist(readIdx);
      final DocumentSnapshot<Map<String, dynamic>>? txItemSnap =
          itemId.isNotEmpty
              ? txAllItemsSnaps.where((d) => d.id == itemId).firstOrNull
              : null;
      DocumentSnapshot<Map<String, dynamic>>? txProductSnap;
      if (txItemSnap != null && txItemSnap.exists) {
        final productId = txItemSnap.data()?['product_id']?.toString() ?? '';
        if (productId.isNotEmpty) {
          txProductSnap =
              await tx.get(_db.collection('products').doc(productId));
        }
      }

      final currentPendingCount =
          (txOrderSnap?.data()?['pending_returns_count'] as num?)?.toInt() ?? 0;
      final newPendingCount = (currentPendingCount - 1).clamp(0, 9999);
      final hasOtherPending = newPendingCount > 0;

      // ── 1. إجراء الحسابات بالكامل قبل تنفيذ أي كتابة ──
      double cartonsToRestore = 0.0;
      bool allFullyReturned = true;
      double refundAmount = 0.0;
      double deductedProfit = 0.0;
      double safeNewTotal = 0.0;
      bool isCompletelyReturned = false;

      if (cleanStatus == 'accepted') {
        if (txItemSnap != null &&
            txItemSnap.exists &&
            txProductSnap != null &&
            txProductSnap.exists) {
          final itemData = txItemSnap.data()!;
          final orderedLimit = (itemData['quantity'] as num?)?.toInt() ?? 0;
          final currentReturned =
              (itemData['returned_quantity'] as num?)?.toInt() ?? 0;

          if (currentReturned + qty > orderedLimit) {
            throw StateError(
                'الكمية المرتجعة تتجاوز الكمية المتبقية المباعة في الفاتورة');
          }

          final cartonCapacity =
              (itemData['carton_capacity'] as num?)?.toInt() ?? 1;
          final capacity = cartonCapacity > 0 ? cartonCapacity : 1;
          final unitQty = (itemData['unit_qty'] as num?)?.toInt() ?? capacity;
          cartonsToRestore = InventoryMath.cartonsFor(
            qty: qty,
            unitQty: unitQty,
            cartonCapacity: capacity,
          );

          refundAmount =
              (((itemData['price'] as num?)?.toDouble() ?? 0.0) * qty);
          final unitCost = (itemData['unit_cost'] as num?)?.toDouble() ??
              (((itemData['cost_price'] as num?)?.toDouble() ?? 0.0) /
                  capacity *
                  unitQty);
          deductedProfit = refundAmount - (unitCost * qty);
        }

        if (orderId.isNotEmpty && txAllItemsSnaps.isNotEmpty) {
          for (final doc in txAllItemsSnaps) {
            if (!doc.exists || doc.data() == null) continue;
            final oQty = (doc.data()!['quantity'] as num?)?.toInt() ?? 0;
            final baseReturned =
                (doc.data()!['returned_quantity'] as num?)?.toInt() ?? 0;
            final effectiveReturned =
                (doc.id == itemId) ? (baseReturned + qty) : baseReturned;

            if (effectiveReturned < oQty) {
              allFullyReturned = false;
              break;
            }
          }

          final currentTotalVal =
              (txOrderSnap?.data()?['total_amount'] as num?)?.toDouble() ??
                  (txOrderSnap?.data()?['total'] as num?)?.toDouble() ??
                  0.0;
          safeNewTotal =
              (currentTotalVal - refundAmount).clamp(0.0, double.infinity);

          isCompletelyReturned =
              (allFullyReturned || safeNewTotal <= 0.01) && !hasOtherPending;
        }
      }

      // ── 2. تنفيذ كافة عمليات الكتابة معاً بعد انتهاء القراءات ──
      tx.update(returnRef, {
        'status': cleanStatus,
        if (cleanStatus == 'rejected' &&
            rejectionReason != null &&
            rejectionReason.trim().isNotEmpty)
          'rejection_reason': rejectionReason.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      if (cleanStatus == 'accepted') {
        if (txItemSnap != null &&
            txItemSnap.exists &&
            txProductSnap != null &&
            txProductSnap.exists) {
          tx.update(txProductSnap.reference, {
            'stock': FieldValue.increment(cartonsToRestore),
            'updated_at': FieldValue.serverTimestamp(),
          });

          tx.update(txItemSnap.reference, {
            'returned_quantity': FieldValue.increment(qty),
            'updated_at': FieldValue.serverTimestamp(),
          });
        }

        if (orderId.isNotEmpty && txAllItemsSnaps.isNotEmpty) {
          final existingTotal =
              (txOrderSnap?.data()?['total_amount'] as num?)?.toDouble() ??
                  (txOrderSnap?.data()?['total'] as num?)?.toDouble() ??
                  0.0;

          tx.update(_db.collection('orders').doc(orderId), {
            'status': isCompletelyReturned
                ? 'returned'
                : (hasOtherPending ? 'return_requested' : 'delivered'),
            'pending_returns_count': newPendingCount,
            'total': safeNewTotal,
            'total_amount': safeNewTotal,
            'original_total':
                txOrderSnap?.data()?['original_total'] ?? existingTotal,
            'returned_amount': FieldValue.increment(refundAmount),
            'total_profit': FieldValue.increment(-deductedProfit),
            'updated_at': FieldValue.serverTimestamp(),
          });
          final bool wasProfitRecorded =
              txOrderSnap?.data()?['profit_recorded'] == true;
          final summaryRef = _db.collection('stats').doc('profit_summary');
          tx.set(
            summaryRef,
            {
              if (wasProfitRecorded && deductedProfit != 0) ...{
                'accumulated_profit': FieldValue.increment(-deductedProfit),
                'cycle_profit': FieldValue.increment(-deductedProfit),
              },
              if (wasProfitRecorded && refundAmount != 0)
                'accumulated_revenue': FieldValue.increment(-refundAmount),
              if (refundAmount != 0)
                'accumulated_returns': FieldValue.increment(refundAmount),
              'last_updated': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      } else if (cleanStatus == 'rejected') {
        if (orderId.isNotEmpty && (txOrderSnap?.exists ?? false)) {
          final currentOrderStatus =
              txOrderSnap?.data()?['status']?.toString().trim().toLowerCase() ??
                  '';
          final fallbackStatus =
              (currentOrderStatus == 'returned') ? 'returned' : 'delivered';
          tx.update(_db.collection('orders').doc(orderId), {
            'status': hasOtherPending ? 'return_requested' : fallbackStatus,
            'pending_returns_count': newPendingCount,
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      }
    });
    if (cleanStatus == 'accepted') {
      await AppCache.instance.invalidateProducts();
    }
// 🚀 إرسال الإشعار بعد التحديث بنجاح (سواء قبول أو رفض)
    if (merchantId.isNotEmpty) {
      String title = '';
      String body = '';

      if (status == 'accepted') {
        title = 'تم قبول طلب الإرجاع ✅';
        body =
            'نعتذر عن أي إزعاج واجهته. تم قبول طلب الإرجاع الخاص بك بنجاح، وسيتم التنسيق معك قريباً لاستلام المرتجع.';
      } else if (status == 'rejected') {
        title = 'تحديث بخصوص طلب الإرجاع ⚠️';
        final reasonText =
            (rejectionReason != null && rejectionReason.trim().isNotEmpty)
                ? '\nسبب الرفض: ${rejectionReason.trim()}'
                : '';
        body =
            'نعتذر منك بصدق، لم نتمكن من قبول طلب الإرجاع الأخير بعد مراجعته.$reasonText\nنسعد بتواصلك مع الدعم لأي استفسار أو توضيح.';
      }

      if (title.isNotEmpty) {
        try {
          await _db.collection('user_notifications').add({
            'user_id': merchantId,
            'title': title,
            'body': body,
            'order_id': orderId,
            'type': 'order_status',
            'is_read': false,
            'created_at': FieldValue.serverTimestamp(),
          });
        } catch (_) {
          // يتم تجاهل الخطأ في الإشعار لعدم كسر عملية التحديث الرئيسية
        }
      }
    }
  }

// ── كل طلبات الإرجاع ──
  Future<List<Map<String, dynamic>>> getAllOrderReturns({
    int limit = 100,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      var query = _db
          .collection('order_returns')
          .orderBy('created_at', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snap = await query.get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdminService] silent error at line ~690: $e');
        debugPrintStack(stackTrace: st);
      }
      return [];
    }
  }
}
