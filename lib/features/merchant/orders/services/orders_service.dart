import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/order_model.dart';
import '../../../../core/utils/inventory_math.dart';
import 'package:sala/core/services/app_cache.dart';
import 'package:sala/core/constants/app_colors.dart';

class OrdersService {
  static final _db = FirebaseFirestore.instance;

  static void _assertMerchantSession(String merchantId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final cleanMerchantId = merchantId.trim();

    if (uid == null ||
        uid.isEmpty ||
        cleanMerchantId.isEmpty ||
        uid != cleanMerchantId) {
      throw StateError('جلسة التاجر غير صالحة');
    }
  }

  /// 🚀 تنفيذ آمن للمعاملات مع ترك إدارة المهلة لمحرك Firestore داخلياً لمنع تعارض الـ Completer
  static Future<T> _runContentionSafeTransaction<T>(
    Future<T> Function(Transaction tx) action,
  ) async {
    return _db.runTransaction<T>(action);
  }

// ════════════════════════════════════════
  // استلام السائق للطلب (فصل المنطق عن UI)
  // ════════════════════════════════════════
  static Future<void> assignOrderToDriver({
    required String orderId,
    String? driverId,
    String? driverName,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw StateError('غير مصرح: يجب تسجيل الدخول كسائق');
    }

    final verifiedDriverId = currentUser.uid;
    final driverDoc =
        await _db.collection('profiles').doc(verifiedDriverId).get();
    if (!driverDoc.exists) {
      throw StateError('غير مصرح: حساب السائق غير موجود');
    }

    final driverData = driverDoc.data()!;
    final role = (driverData['role'] as String?)?.trim().toLowerCase();
    final isActive = driverData['is_active'] as bool? ?? false;
    final isBanned = driverData['is_banned'] == true;

    if (isBanned || !isActive || role != 'driver') {
      throw StateError('غير مصرح: حساب السائق معطل أو غير مصرح');
    }

    final resolvedDriverName = (driverData['full_name'] as String?)?.trim() ??
        driverName?.trim() ??
        'سائق معتمد';

    final cleanOrderId = orderId.trim();
    if (cleanOrderId.isEmpty) {
      throw ArgumentError('معرّف الطلب غير صالح');
    }

    final orderRef = _db.collection('orders').doc(cleanOrderId);

    await _runContentionSafeTransaction((tx) async {
      final snapshot = await tx.get(orderRef);

      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('الطلب لم يعد موجوداً');
      }

      final orderData = snapshot.data()!;
      final status = orderData['status']?.toString() ?? '';
      final assignedDriver = orderData['driver_id']?.toString() ?? '';

      if ((status != 'confirmed' && status != 'pending') ||
          (assignedDriver.isNotEmpty && assignedDriver != verifiedDriverId)) {
        throw StateError('تم استلام هذا الطلب من قِبل سائق آخر');
      }

      tx.update(orderRef, {
        'status': 'shipped',
        'driver_id': verifiedDriverId,
        'driver_name': resolvedDriverName,
        'picked_up_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    });

    final freshSnap = await orderRef.get();
    final merchantId = freshSnap.data()?['merchant_id']?.toString() ?? '';
    if (merchantId.isNotEmpty) {
      try {
        await _db.collection('user_notifications').add({
          'user_id': merchantId,
          'title': '🚚 طلبك في الطريق!',
          'body': 'المندوب استلم طلبك وهو في الطريق إليك الآن 🛣️',
          'order_id': cleanOrderId,
          'type': 'order_status',
          'is_read': false,
          'created_at': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[OrdersService] failed to notify merchant (shipped): $e');
        }
      }
    }
  }

  // ════════════════════════════════════════
  // تأكيد تسليم السائق للطلب
  // ════════════════════════════════════════
  static Future<void> deliverOrderByDriver({
    required String orderId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw StateError('غير مصرح: يجب تسجيل الدخول كسائق');
    }

    final verifiedDriverId = currentUser.uid;
    final cleanOrderId = orderId.trim();
    if (cleanOrderId.isEmpty) {
      throw ArgumentError('معرّف الطلب غير صالح');
    }

    final orderRef = _db.collection('orders').doc(cleanOrderId);

    await _runContentionSafeTransaction((tx) async {
      final snapshot = await tx.get(orderRef);

      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('الطلب لم يعد موجوداً');
      }

      final orderData = snapshot.data()!;
      final currentStatus = orderData['status']?.toString() ?? '';
      final assignedDriver = orderData['driver_id']?.toString() ?? '';

      final bool isAlreadyDeliveredOffline = currentStatus == 'delivered';
      final bool isValidDeliveryState =
          currentStatus == 'shipped' || currentStatus == 'on_the_way';

      if ((!isValidDeliveryState && !isAlreadyDeliveredOffline) ||
          (assignedDriver.isNotEmpty && assignedDriver != verifiedDriverId)) {
        throw StateError('لا يمكنك تسليم طلب غير مسند إليك');
      }
      final profit = (orderData['total_profit'] as num?)?.toDouble() ?? 0.0;
      final totalAmount = (orderData['total_amount'] as num?)?.toDouble() ??
          (orderData['total'] as num?)?.toDouble() ??
          0.0;
      if (orderData['profit_recorded'] != true) {
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
        tx.update(orderRef, {
          'status': 'delivered',
          'delivered_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
          'profit_recorded': true,
        });
      } else {
        tx.update(orderRef, {
          'status': 'delivered',
          'delivered_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
    });

    final freshSnap = await orderRef.get();
    final merchantId = freshSnap.data()?['merchant_id']?.toString() ?? '';
    if (merchantId.isNotEmpty) {
      try {
        await _db.collection('user_notifications').add({
          'user_id': merchantId,
          'title': '🎉 تم تسليم طلبك!',
          'body': 'تم تسليم طلبك بنجاح ✨ شكراً لثقتك بنا 🙏',
          'order_id': cleanOrderId,
          'type': 'order_status',
          'is_read': false,
          'created_at': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              '[OrdersService] failed to notify merchant (delivered): $e');
        }
      }
    }
  }

  // ════════════════════════════════════════
  // تقديم طلب جديد
  // ════════════════════════════════════════
  static Future<OrderModel> placeOrder({
    required String merchantId,
    required List<Map<String, dynamic>> items,
    required double expectedTotal,
    String? notes,
    Map<String, dynamic>? extraData,
    String? orderId, // ✅ Idempotency Key
  }) async {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final cleanMerchantId = merchantId.trim();

    if (authUid == null ||
        authUid.isEmpty ||
        cleanMerchantId.isEmpty ||
        authUid != cleanMerchantId) {
      throw StateError('جلسة التاجر غير صالحة');
    }
    if (items.isEmpty) {
      throw ArgumentError('السلة فارغة');
    }

// ✅ حد آمن موحد مركزي عبر AppConfig.maxOrderItems يضمن عدم تجاوز حدود معاملات Firestore
    if (items.length > AppConfig.maxOrderItems) {
      throw ArgumentError(
          'لا يمكن تجاوز ${AppConfig.maxOrderItems} صنفاً مختلفاً في الطلب الواحد لتفادي أخطاء المعاملات');
    }
    // ✅ استخدام الـ ID الممرر أو توليد واحد جديد
    final orderRef = orderId != null && orderId.trim().isNotEmpty
        ? _db.collection('orders').doc(orderId.trim())
        : _db.collection('orders').doc();
    late Map<String, dynamic> finalOrderData;
    await _runContentionSafeTransaction((tx) async {
      // ✅ فحص الـ Idempotency الفعلي — يجب أن يكون أول قراءة في الـ Transaction.
      // إن كان orderId مُمرَّرًا مسبقًا (إعادة محاولة بعد انقطاع شبكة) وكان
      // الطلب قد أُنشئ بالفعل، لا نكرر خصم المخزون ولا ننشئ order_items مكررة.
      final existingOrderSnap = await tx.get(orderRef);
      if (existingOrderSnap.exists && existingOrderSnap.data() != null) {
        finalOrderData = existingOrderSnap.data()!;
        return;
      }

      // مهم جدًا:
      // Firestore قد يعيد تنفيذ Transaction أكثر من مرة.
      // لذلك يجب إنشاء هذه المتغيرات داخل المحاولة نفسها،
      // وليس خارج Transaction.
      final enrichedItems = <Map<String, dynamic>>[];
      var serverTotal = 0.0;
      var serverProfit = 0.0;

      // يجب تنفيذ جميع القراءات قبل أي كتابة داخل Transaction
      final productSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};

      final uniqueProductIds = items
          .map((i) => i['product_id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      if (uniqueProductIds.isEmpty) {
        throw ArgumentError('يوجد منتج بدون معرّف');
      }
      for (final productId in uniqueProductIds) {
        if (!productSnapshots.containsKey(productId)) {
          final productRef = _db.collection('products').doc(productId);
          productSnapshots[productId] = await tx.get(productRef);
        }
      }
      final decrements = <String, num>{};

      for (final item in items) {
        final productId = item['product_id']?.toString().trim() ?? '';
        if (productId.isEmpty) {
          throw ArgumentError('عنصر طلب بدون معرّف منتج صالح');
        }
        final productSnap = productSnapshots[productId];
        if (productSnap == null || !productSnap.exists) {
          throw StateError('المنتج غير موجود');
        }
        final productData = productSnap.data()!;

        if (productData['is_active'] == false ||
            productData['is_deleted'] == true) {
          throw StateError(
            'المنتج "${productData['name'] ?? item['product_name']}" غير متاح',
          );
        }

        final quantityValue = item['quantity'];

        if (quantityValue is! num || quantityValue.toInt() <= 0) {
          throw ArgumentError('كمية المنتج غير صالحة');
        }

        final requestedQty = quantityValue.toInt();
        final currentStock = (productData['stock'] as num?)?.toDouble() ?? 0.0;

        var unitPrice = (productData['price'] as num?)?.toDouble() ?? 0.0;
        var costPrice = (productData['cost_price'] as num?)?.toDouble() ?? 0.0;

        final rawCartonItems =
            (productData['items_per_carton'] as num?)?.toInt() ?? 0;
        final cartonCapacity = rawCartonItems > 0
            ? rawCartonItems
            : (productData['units'] is List &&
                    (productData['units'] as List).isNotEmpty
                ? ((productData['units'] as List)
                    .map((u) => (u['qty'] as num?)?.toInt() ?? 1)
                    .reduce((a, b) => a > b ? a : b))
                : 1);
        var unitQty = cartonCapacity;
        final rawUnitLabel = item['unit_label']?.toString().trim();
        String? unitLabel;
        // ✅ تم نقل تعريف المتغير هنا ليصبح متاحاً في حساب التكلفة بالأسفل
        Map<String, dynamic>? selectedUnit;

        if (rawUnitLabel != null && rawUnitLabel.isNotEmpty) {
          final rawUnits = productData['units'];

          if (rawUnits is List) {
            for (final rawUnit in rawUnits) {
              if (rawUnit is Map &&
                  rawUnit['label']?.toString().trim() == rawUnitLabel) {
                selectedUnit = Map<String, dynamic>.from(rawUnit);
                break;
              }
            }
          }

          if (selectedUnit == null) {
            // ✅ إذا كانت الوحدة هي "كرتون" نعتمد سعر ومواصفات الكرتون الأساسي
            if (rawUnitLabel == 'كرتون') {
              unitLabel = 'كرتون';
              unitPrice =
                  (productData['price'] as num?)?.toDouble() ?? unitPrice;
              costPrice =
                  (productData['cost_price'] as num?)?.toDouble() ?? costPrice;
              unitQty = cartonCapacity;
            } else {
              throw StateError(
                'الوحدة المطلوبة ($rawUnitLabel) للمنتج "${productData['name'] ?? item['product_name']}" لم تعد متوفرة، يرجى تحديث السلة',
              );
            }
          } else {
            unitLabel = rawUnitLabel;
            unitPrice =
                (selectedUnit['price'] as num?)?.toDouble() ?? unitPrice;
            costPrice =
                (selectedUnit['cost_price'] as num?)?.toDouble() ?? costPrice;
            unitQty = (selectedUnit['qty'] as num?)?.toInt() ?? 1;
          }
        }

        final effectiveUnitQty =
            (unitLabel == null || unitLabel.isEmpty) ? cartonCapacity : unitQty;
        final stockCartonsToDeduct = InventoryMath.cartonsFor(
          qty: requestedQty,
          unitQty: effectiveUnitQty,
          cartonCapacity: cartonCapacity,
        );
        final previousDecrement = decrements[productId] ?? 0.0;
        final totalDecrement = previousDecrement + stockCartonsToDeduct;

        if (currentStock < totalDecrement) {
          throw StateError(
            'الكمية المطلوبة من "${productData['name'] ?? item['product_name']}" '
            'تتجاوز المخزون المتاح بالمستودع',
          );
        }

        decrements[productId] = totalDecrement;

        final subtotal = unitPrice * requestedQty;
        // ✅ حساب تكلفة الوحدة وصافي الربح بدقة بدون أي أخطاء
        final double unitCost;
        if (selectedUnit != null && selectedUnit['cost_price'] != null) {
          unitCost = (selectedUnit['cost_price'] as num).toDouble();
        } else if (costPrice > 0 && cartonCapacity > 0) {
          unitCost = (costPrice / cartonCapacity) * effectiveUnitQty;
        } else {
          unitCost = 0.0;
        }
        final itemProfit = (unitPrice - unitCost) * requestedQty;
        serverTotal += subtotal;
        serverProfit += itemProfit;

        enrichedItems.add({
          'order_id': orderRef.id,
          'product_id': productId,
          'product_name': productData['name'] ?? item['product_name'] ?? '',
          'price': unitPrice,
          'cost_price': costPrice,
          'unit_cost': unitCost,
          'carton_capacity': cartonCapacity,
          'quantity': requestedQty,
          'subtotal': subtotal,
          'unit_label': unitLabel ?? 'كرتون',
          'unit_qty': effectiveUnitQty,
        });
      }

      const double minOrderThreshold = AppConfig.minOrderValue;
      if (serverTotal < minOrderThreshold) {
        throw StateError(
          'الحد الأدنى للطلب هو ${minOrderThreshold.toStringAsFixed(0)} ر.ي، وإجمالي طلبك الحالي هو ${serverTotal.toStringAsFixed(0)} ر.ي',
        );
      }

      if ((serverTotal - expectedTotal).abs() > 0.1) {
        throw StateError(
            'تغيرت أسعار بعض المنتجات، يرجى تحديث السلة وإعادة المحاولة');
      }

      // لا تسمح للعميل بتغيير الحقول الحساسة
      final safeExtraData = Map<String, dynamic>.from(extraData ?? const {});
      const protectedFields = {
        'merchant_id',
        'total',
        'total_amount',
        'total_profit',
        'profit_recorded',
        'driver_id',
        'driver_name',
        'delivered_at',
        'offline_delivered',
        'signature_url',
        'status',
        'items_count',
        'created_at',
        'updated_at',
      };
      safeExtraData.removeWhere(
        (key, value) => protectedFields.contains(key),
      );
      final generatedShortNumber = orderRef.id.length >= 8
          ? orderRef.id.substring(0, 8).toUpperCase()
          : orderRef.id.toUpperCase();

      finalOrderData = {
        ...safeExtraData,
        'merchant_id': cleanMerchantId,
        'total': serverTotal,
        'total_amount': serverTotal,
        'total_profit': serverProfit,
        'order_number': safeExtraData['order_number'] ?? generatedShortNumber,
        'invoice_number':
            safeExtraData['invoice_number'] ?? generatedShortNumber,
        'notes': notes?.trim(),
        'status': 'pending',
        'items_count': enrichedItems.length,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };
      for (final entry in decrements.entries) {
        final productRef = _db.collection('products').doc(entry.key);

        tx.update(productRef, {
          'stock': FieldValue.increment(-entry.value),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      tx.set(orderRef, finalOrderData);

      for (final item in enrichedItems) {
        final itemRef = _db.collection('order_items').doc();
        tx.set(itemRef, item);
      }
    });

    final fresh = await orderRef.get();

    if (!fresh.exists || fresh.data() == null) {
      throw StateError('تعذر إنشاء الطلب');
    }

    // 🚀 إبطال كاش المنتجات فوراً لضمان تحديث عداد المخزون على أجهزة التجار
    await AppCache.instance.invalidateProducts();

    return OrderModel.fromJson({
      'id': fresh.id,
      ...fresh.data()!,
    });
  }

  // ════════════════════════════════════════
  // مراقبة طلب واحد (Realtime)
  // ════════════════════════════════════════
  static Stream<OrderModel?> watchOrder(String orderId) {
    return _db.collection('orders').doc(orderId).snapshots().map(
          (d) =>
              d.exists ? OrderModel.fromJson({'id': d.id, ...d.data()!}) : null,
        );
  }

// ════════════════════════════════════════
  // مراقبة كل طلبات التاجر (Realtime)
  // ════════════════════════════════════════
  static Stream<List<OrderModel>> watchMerchantOrders(String merchantId) {
    return _db
        .collection('orders')
        .where('merchant_id', isEqualTo: merchantId)
        .orderBy('created_at', descending: true)
        .limit(100)
        .snapshots(includeMetadataChanges: false)
        .map((snap) {
      return snap.docs
          .map((d) => OrderModel.fromJson({'id': d.id, ...d.data()}))
          .toList();
    });
  }

  // ════════════════════════════════════════
  // مراقبة طلبات التاجر بحالات محددة (مطلوبة لشاشة السجل)
  // ════════════════════════════════════════
  static Stream<List<OrderModel>> watchMerchantOrdersByStatuses(
    String merchantId,
    List<String> statuses,
  ) {
    return _db
        .collection('orders')
        .where('merchant_id', isEqualTo: merchantId)
        .where('status', whereIn: statuses.take(10).toList())
        .orderBy('created_at', descending: true)
        .limit(100)
        .snapshots(includeMetadataChanges: false)
        .map((snap) {
      return snap.docs
          .map((d) => OrderModel.fromJson({'id': d.id, ...d.data()}))
          .toList();
    });
  }

  // ════════════════════════════════════════
  // مراقبة فواتير المرتجعات للتاجر (مطلوبة لشاشة السجل)
  // ════════════════════════════════════════
  static Stream<List<Map<String, dynamic>>> watchMerchantReturns(
    String merchantId,
  ) {
    return _db
        .collection('order_returns')
        .where('merchant_id', isEqualTo: merchantId)
        .orderBy('created_at', descending: true)
        .limit(100)
        .snapshots(includeMetadataChanges: false)
        .map(
            (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  static Future<List<Map<String, dynamic>>> getOrderItems(
      String orderId) async {
    final snap = await _db
        .collection('order_items')
        .where('order_id', isEqualTo: orderId)
        .get(const GetOptions(source: Source.serverAndCache));
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ════════════════════════════════════════
  // جلب الطلبات حسب الحالة — فرز بالذاكرة لمنع FAILED_PRECONDITION
  // ════════════════════════════════════════
  static Future<List<Map<String, dynamic>>> getOrdersByStatus({
    required String merchantId,
    required String status,
  }) async {
    final snap = await _db
        .collection('orders')
        .where('merchant_id', isEqualTo: merchantId)
        .where('status', isEqualTo: status)
        .limit(200)
        .get(const GetOptions(source: Source.serverAndCache));
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
    return list;
  }

  // ════════════════════════════════════════
  // جلب الطلبات متعددة الحالات دفعةً واحدة
  // ════════════════════════════════════════
  static Future<List<Map<String, dynamic>>> getOrdersByStatuses({
    required String merchantId,
    required List<String> statuses,
  }) async {
    final snap = await _db
        .collection('orders')
        .where('merchant_id', isEqualTo: merchantId)
        .limit(200)
        .get(const GetOptions(source: Source.serverAndCache));
    final list = snap.docs
        .where((d) => statuses.contains(d.data()['status']?.toString()))
        .map((d) => {'id': d.id, ...d.data()})
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

// ════════════════════════════════════════
  // إرسال طلب إرجاع (معالجة ذرية آمنة وخالية من الأخطاء)
  // ════════════════════════════════════════
  static Future<void> submitReturns({
    required String orderId,
    required List<Map<String, dynamic>> itemsToReturn,
    required String merchantId,
    String? storeName,
    String? contact,
    double? latitude,
    double? longitude,
    required String reason,
  }) async {
    final cleanOrderId = orderId.trim();
    final cleanMerchantId = merchantId.trim();
    final cleanReason = reason.trim();

    if (cleanOrderId.isEmpty) {
      throw ArgumentError('معرّف الطلب غير صالح');
    }

    if (cleanMerchantId.isEmpty) {
      throw ArgumentError('معرّف التاجر غير صالح');
    }
    _assertMerchantSession(cleanMerchantId);

    if (itemsToReturn.isEmpty) {
      throw ArgumentError('يجب تحديد عنصر واحد على الأقل للإرجاع');
    }

    if (cleanReason.isEmpty) {
      throw ArgumentError('سبب الإرجاع مطلوب');
    }

    final orderRef = _db.collection('orders').doc(cleanOrderId);

    // تجميع وتوحيد كميات العناصر المكررة لمنع تعارض المعاملة الذرية
    final aggregated = <String, Map<String, dynamic>>{};
    for (final item in itemsToReturn) {
      final id = item['order_item_id']?.toString().trim() ?? '';
      if (id.isEmpty) throw ArgumentError('معرّف عنصر الطلب غير صالح');
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      if (qty <= 0) throw StateError('كمية الإرجاع يجب أن تكون أكبر من صفر');

      if (aggregated.containsKey(id)) {
        aggregated[id]!['quantity'] =
            (aggregated[id]!['quantity'] as int) + qty;
      } else {
        aggregated[id] = Map<String, dynamic>.from(item);
      }
    }
    final cleanItemsToReturn = aggregated.values.toList();
    final itemRefs = cleanItemsToReturn.map((item) {
      final id = item['order_item_id']?.toString().trim() ?? '';
      return _db.collection('order_items').doc(id);
    }).toList();

    await _runContentionSafeTransaction((tx) async {
      final orderSnap = await tx.get(orderRef);

      if (!orderSnap.exists || orderSnap.data() == null) {
        throw StateError('الطلب غير موجود');
      }

      final orderData = orderSnap.data()!;

      if (orderData['merchant_id']?.toString() != cleanMerchantId) {
        throw StateError('غير مصرح لك بإرجاع هذا الطلب');
      }

      // فحص ذري لمنع إرسال طلب إرجاع جديد إذا كان هناك إرجاع معلق قيد المراجعة
      final currentPendingReturns =
          (orderData['pending_returns_count'] as num?)?.toInt() ?? 0;

      if (currentPendingReturns > 0) {
        throw StateError('يوجد طلب إرجاع قيد المعالجة مسبقاً لهذا الطلب');
      }

      final orderStatus =
          orderData['status']?.toString().trim().toLowerCase() ?? '';

      if (orderStatus != 'delivered' && orderStatus != 'return_requested') {
        throw StateError('لا يمكن إرجاع طلب بحالة: $orderStatus');
      }
      // قراءة كافة العناصر داخل المعاملة
      final itemSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in itemRefs) {
        itemSnaps.add(await tx.get(ref));
      }

      final returnDocsToCreate = <Map<String, dynamic>>[];
      for (int i = 0; i < itemSnaps.length; i++) {
        final itemSnap = itemSnaps[i];
        final returnReq = cleanItemsToReturn[i];

        if (!itemSnap.exists || itemSnap.data() == null) {
          throw StateError('عنصر الطلب غير موجود');
        }

        final itemData = itemSnap.data()!;
        final itemOrderId = itemData['order_id']?.toString() ?? '';

        if (itemOrderId != cleanOrderId) {
          throw StateError('عنصر الطلب لا ينتمي إلى هذا الطلب');
        }

        final quantity = (returnReq['quantity'] as num?)?.toInt() ?? 0;
        if (quantity <= 0) {
          throw StateError('كمية الإرجاع يجب أن تكون أكبر من صفر');
        }

        final orderedQuantity = (itemData['quantity'] as num?)?.toInt() ?? 0;
        final alreadyReturned =
            (itemData['returned_quantity'] as num?)?.toInt() ?? 0;

        if (orderedQuantity <= 0) {
          throw StateError('كمية عنصر الطلب غير صالحة');
        }

        // حماية: منع إرجاع ما يتجاوز الكمية المباعة المتبقية
        if (alreadyReturned + quantity > orderedQuantity) {
          throw StateError(
            'الكمية المطلوب إرجاعها من "${itemData['product_name']}" تتجاوز الكمية المتبقية في الطلب',
          );
        }

        final itemPrice = (itemData['price'] as num?)?.toDouble() ?? 0.0;
        final refundAmount = itemPrice * quantity;
        returnDocsToCreate.add({
          'order_id': cleanOrderId,
          'order_item_id': itemSnap.id,
          'merchant_id': cleanMerchantId,
          'refund_amount': refundAmount,
          'product_name': returnReq['product_name']?.toString().trim() ?? '',
          'quantity': quantity,
          if (storeName != null && storeName.trim().isNotEmpty)
            'store_name': storeName.trim(),
          if (contact != null && contact.trim().isNotEmpty)
            'contact': contact.trim(),
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          'reason': cleanReason,
          'status': 'pending',
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      tx.update(orderRef, {
        'status': 'return_requested',
        'return_reason': cleanReason,
        'pending_returns_count':
            FieldValue.increment(returnDocsToCreate.length),
        'updated_at': FieldValue.serverTimestamp(),
      });

      for (final rDoc in returnDocsToCreate) {
        final itemId = rDoc['order_item_id']?.toString() ?? '';
        final returnUniqueDocId =
            '${cleanOrderId}_${itemId}_${DateTime.now().millisecondsSinceEpoch}';
        tx.set(_db.collection('order_returns').doc(returnUniqueDocId), rDoc);
      }
    });
  }

  //═══════════════════════
  // إلغاء الطلب
  // ════════════════════════════════════════
  static Future<void> cancelOrder(
    String orderId,
    String merchantId,
  ) async {
    final cleanOrderId = orderId.trim();
    final cleanMerchantId = merchantId.trim();

    if (cleanOrderId.isEmpty || cleanMerchantId.isEmpty) {
      throw ArgumentError('بيانات الإلغاء غير صالحة');
    }
    _assertMerchantSession(cleanMerchantId);

    // نجلب فقط المراجع (References) خارج المعاملة لأن Firestore لا يدعم Queries داخل الـ TX للموبايل
    final itemsQuery = await _db
        .collection('order_items')
        .where('order_id', isEqualTo: cleanOrderId)
        .get();

    final itemRefs = itemsQuery.docs.map((doc) => doc.reference).toList();
    final orderRef = _db.collection('orders').doc(cleanOrderId);

    await _runContentionSafeTransaction((tx) async {
      // 1. قراءة مستند الطلب
      final snapshot = await tx.get(orderRef);

      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('الطلب غير موجود');
      }

      final data = snapshot.data()!;

      if (data['merchant_id']?.toString() != cleanMerchantId) {
        throw StateError('غير مصرح لك بإلغاء هذا الطلب');
      }

      final status = data['status']?.toString() ?? '';
      if (status != 'pending') {
        throw StateError('لا يمكن إلغاء طلب بحالة: $status');
      }

      final pendingReturnsCount =
          (data['pending_returns_count'] as num?)?.toInt() ?? 0;
      if (pendingReturnsCount > 0 || status == 'return_requested') {
        throw StateError(
            'لا يمكن إلغاء طلب توجد عليه طلبات إرجاع قيد المعالجة');
      }

      // 2. قراءة جميع عناصر الطلب بتسلسل متوافق مع قيود المعاملات
      final txItems = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in itemRefs) {
        txItems.add(await tx.get(ref));
      }

      // 3. قراءة جميع مستندات المنتجات قبل تنفيذ أي كتابة (حفاظاً على سلامة المعاملة)
      final productSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final txDoc in txItems) {
        if (!txDoc.exists || txDoc.data() == null) continue;
        final pId = txDoc.data()!['product_id']?.toString() ?? '';
        if (pId.isNotEmpty && !productSnapshots.containsKey(pId)) {
          productSnapshots[pId] =
              await tx.get(_db.collection('products').doc(pId));
        }
      }

      // 4. تنفيذ جميع عمليات الكتابة بعد اكتمال القراءات بنسبة 100%
      tx.update(orderRef, {
        'status': 'cancelled',
        'updated_at': FieldValue.serverTimestamp(),
        'cancelled_at': FieldValue.serverTimestamp(),
      });
      final Map<String, double> stockToRestoreMap = {};
      for (final txDoc in txItems) {
        if (!txDoc.exists || txDoc.data() == null) continue;

        final itemData = txDoc.data()!;
        final productId = itemData['product_id']?.toString() ?? '';
        final qty = (itemData['quantity'] as num?)?.toInt() ?? 0;
        final cartonCapacity =
            (itemData['carton_capacity'] as num?)?.toInt() ?? 1;
        final capacity = cartonCapacity > 0 ? cartonCapacity : 1;
        final effectiveUnitQty =
            (itemData['unit_qty'] as num?)?.toInt() ?? capacity;
        final cartonsToRestore = InventoryMath.cartonsFor(
          qty: qty,
          unitQty: effectiveUnitQty,
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
    });
// 🚀 إبطال كاش المنتجات لاستعادة المخزون المعروض فوراً للتاجر
    await AppCache.instance.invalidateProducts();

    // ✅ إرسال إشعار للتاجر عند الإلغاء مباشرة إلى قاعدة البيانات
    try {
      await _db.collection('user_notifications').add({
        'user_id': cleanMerchantId,
        'title': '💛 بخصوص طلبك',
        'body':
            'نأسف على الإزعاج، واجهنا ظرفاً طارئاً اضطررنا فيه لإيقاف هذا الطلب مؤقتاً. يسعدنا خدمتك في أقرب وقت 🙏',
        'order_id': cleanOrderId,
        'type': 'order_status',
        'status': 'cancelled',
        'is_read': false,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // ════════════════════════════════════════
  // طلب إرجاع (تغيير حالة + إشعار)
  // ════════════════════════════════════════
  static Future<void> requestReturn(
    String orderId, {
    required String merchantId,
  }) async {
    final cleanOrderId = orderId.trim();
    final cleanMerchantId = merchantId.trim();

    if (cleanOrderId.isEmpty || cleanMerchantId.isEmpty) {
      throw ArgumentError('بيانات طلب الإرجاع غير صالحة');
    }

    _assertMerchantSession(cleanMerchantId);

    final orderRef = _db.collection('orders').doc(cleanOrderId);

    await _runContentionSafeTransaction((tx) async {
      final snap = await tx.get(orderRef);

      if (!snap.exists || snap.data() == null) {
        throw StateError('الطلب غير موجود');
      }

      final data = snap.data()!;

      if (data['merchant_id']?.toString() != cleanMerchantId) {
        throw StateError('غير مصرح لك بطلب إرجاع هذا الطلب');
      }

      final status = data['status']?.toString() ?? '';

      if (status != 'delivered') {
        throw StateError('لا يمكن إرجاع طلب بحالة: $status');
      }

      tx.update(orderRef, {
        'status': 'return_requested',
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }
}
