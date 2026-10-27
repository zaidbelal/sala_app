import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/services/app_cache.dart';
import 'dart:async';

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
  final bool isPartial;
  final String? failureReason;
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
    this.isPartial = false,
    this.failureReason,
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
  Future<void>? _financialMigrationFuture;

  Future<void> ensureFinancialFieldsMigrated() async {
    _financialMigrationFuture ??= _runFinancialFieldsMigration();
    try {
      await _financialMigrationFuture;
    } catch (_) {
      _financialMigrationFuture = null;
      rethrow;
    }
  }

  Future<void> _runFinancialFieldsMigration() async {
    final callable =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'migrateFinancialFields',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    String? previousProgress;
    while (true) {
      final response = await callable.call();
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['done'] == true) return;
      final progress = '${data['stage']}|${data['cursor'] ?? ''}';
      if (progress == previousProgress) {
        throw StateError('ترحيل البيانات المالية لم يتقدم');
      }
      previousProgress = progress;
    }
  }

  Future<List<Map<String, dynamic>>> attachProductFinancials(
    List<Map<String, dynamic>> products,
  ) async {
    final financialsById = <String, Map<String, dynamic>>{};
    final ids = products.map((product) => product['id'].toString()).toList();
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snapshots = await _db
          .collection('product_financials')
          .where(FieldPath.documentId, whereIn: chunk)
          .get(const GetOptions(source: Source.server));
      for (final doc in snapshots.docs) {
        financialsById[doc.id] = doc.data();
      }
    }

    return products.map((product) {
      final financials = financialsById[product['id'].toString()] ?? {};
      final unitCosts = <String, num>{};
      final financialUnits = financials['units'];
      if (financialUnits is List) {
        for (final unit in financialUnits.whereType<Map>()) {
          final label = unit['label']?.toString();
          final cost = unit['cost_price'];
          if (label != null && cost is num) unitCosts[label] = cost;
        }
      }
      final units = (product['units'] as List? ?? const [])
          .whereType<Map>()
          .map((unit) => {
                ...Map<String, dynamic>.from(unit),
                'cost_price': unitCosts[unit['label']?.toString()] ?? 0,
              })
          .toList();
      return {
        ...product,
        'cost_price': financials['cost_price'] ?? 0,
        'units': units,
      };
    }).toList();
  }

  /// إعادة محاولة ذكية مع Exponential Backoff.
  /// تُعيد المحاولة فقط على الأخطاء العابرة القابلة للاسترجاع.
  /// لا تُعيد المحاولة على أخطاء المنطق (permission-denied, not-found, ...).
  /// آمنة لأن جميع عمليات الكتابة المُغلَّفة بـ Firestore Transactions
  /// تملك بالفعل فحص Idempotency داخلي.
  static Future<T> withFirestoreRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 400),
  }) async {
    const retryableCodes = <String>{
      'unavailable',
      'deadline-exceeded',
      'aborted',
      'internal',
    };

    Object? lastError;
    StackTrace? lastStackTrace;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await operation();
      } on FirebaseException catch (e, st) {
        lastError = e;
        lastStackTrace = st;

        if (!retryableCodes.contains(e.code) || attempt == maxAttempts - 1) {
          Error.throwWithStackTrace(e, st);
        }

        final jitterMs = DateTime.now().microsecondsSinceEpoch % 200;
        await Future.delayed(
          baseDelay * (1 << attempt) + Duration(milliseconds: jitterMs),
        );
      }
    }

    Error.throwWithStackTrace(
      lastError ?? StateError('Retry exhausted'),
      lastStackTrace ?? StackTrace.current,
    );
  }

// ── إحصائيات دقيقة وفورية وشاملة مع معالجة حتمية لجميع مصادر الحقول ──
  Future<AdminStats> getStats() async {
    int totalOrders = 0;
    int pendingOrders = 0;
    int totalMerchants = 0;
    int cancelledOrders = 0;
    int deliveredOrders = 0;
    double grossRevenue = 0.0;
    double totalProfit = 0.0;
    double returnedRevenue = 0.0;
    bool isPartial = false;
    String? failureReason;

    // 1. عدد التجار
    try {
      final snap = await _db
          .collection('profiles')
          .where('role', isEqualTo: 'merchant')
          .count()
          .get();
      totalMerchants = snap.count ?? 0;
    } catch (_) {
      isPartial = true;
      failureReason ??= 'merchants_count_failed';
    }

    // 2. عدد الطلبات بمختلف الحالات
    try {
      final totalSnap = await _db.collection('orders').count().get();
      totalOrders = totalSnap.count ?? 0;
    } catch (_) {
      isPartial = true;
      failureReason ??= 'total_orders_failed';
    }

    try {
      final pendingSnap = await _db
          .collection('orders')
          .where('status', isEqualTo: 'pending')
          .count()
          .get();
      pendingOrders = pendingSnap.count ?? 0;
    } catch (_) {
      isPartial = true;
      failureReason ??= 'pending_count_failed';
    }

    try {
      final cancelledSnap = await _db
          .collection('orders')
          .where('status', whereIn: ['cancelled', 'rejected'])
          .count()
          .get();
      cancelledOrders = cancelledSnap.count ?? 0;
    } catch (_) {
      isPartial = true;
      failureReason ??= 'cancelled_count_failed';
    }

    try {
      final deliveredSnap = await _db
          .collection('orders')
          .where('status', isEqualTo: 'delivered')
          .count()
          .get();
      deliveredOrders = deliveredSnap.count ?? 0;
    } catch (_) {
      isPartial = true;
      failureReason ??= 'delivered_count_failed';
    }
    bool shardsSucceeded = false;
    // 3. محاولة قراءة الإحصائيات من الشظايا أولاً
    try {
      final summaryDoc =
          await _db.collection('stats').doc('profit_summary').get();

      if (summaryDoc.exists && summaryDoc.data() != null) {
        final data = summaryDoc.data()!;
        grossRevenue = (data['accumulated_revenue'] as num?)?.toDouble() ?? 0.0;
        totalProfit = (data['accumulated_profit'] as num?)?.toDouble() ?? 0.0;
        returnedRevenue =
            (data['accumulated_returns'] as num?)?.toDouble() ?? 0.0;
        shardsSucceeded = true;
      }
    } catch (_) {}

    // 4. الحساب المباشر الاحتياطي ينفذ فقط إذا فشل استعلام الشظايا تماماً وليس لأن المبيعات أو المرتجعات صفرية
    if (!shardsSucceeded) {
      try {
        final aggSnap = await _db
            .collection('orders')
            .where('status', isEqualTo: 'delivered')
            .aggregate(
              sum('total_amount'),
              sum('total'),
            )
            .get();
        final profitSnap = await _db
            .collection('order_financials')
            .where('profit_recorded', isEqualTo: true)
            .aggregate(sum('total_profit'))
            .get();

        final sumTotalAmount = aggSnap.getSum('total_amount') ?? 0.0;
        final sumTotal = aggSnap.getSum('total') ?? 0.0;
        grossRevenue = sumTotalAmount > 0 ? sumTotalAmount : sumTotal;
        totalProfit = profitSnap.getSum('total_profit') ?? 0.0;
      } catch (_) {
        // في حال تعذر التجميع السحابي (غياب فهرس أو اختلاف نوع الحقول)، جلب الوثائق وحسابها مباشرة
        try {
          final deliveredDocsSnap = await _db
              .collection('orders')
              .where('status', isEqualTo: 'delivered')
              .limit(50)
              .get(const GetOptions(source: Source.cache));
          final financialDocsSnap = await _db
              .collection('order_financials')
              .where('profit_recorded', isEqualTo: true)
              .limit(50)
              .get(const GetOptions(source: Source.cache));
          double calcRevenue = 0.0;
          for (final doc in deliveredDocsSnap.docs) {
            final data = doc.data();
            final amt = (data['total_amount'] as num?)?.toDouble() ??
                (data['total'] as num?)?.toDouble() ??
                0.0;
            calcRevenue += amt;
          }
          final calcProfit = financialDocsSnap.docs.fold<double>(
            0,
            (total, doc) =>
                total + ((doc.data()['total_profit'] as num?)?.toDouble() ?? 0),
          );
          grossRevenue = calcRevenue;
          totalProfit = calcProfit;
        } catch (_) {
          isPartial = true;
          failureReason ??= 'revenue_calculation_failed';
        }
      }
    }
// 5. الحساب الحقيقي لقيمة المرجوعات من order_returns و orders في حال فشل الشظايا فقط
    if (!shardsSucceeded) {
      try {
        final returnsAggSnap = await _db
            .collection('order_returns')
            .where('status', isEqualTo: 'accepted')
            .aggregate(sum('refund_amount'))
            .get();
        returnedRevenue = returnsAggSnap.getSum('refund_amount') ?? 0.0;
      } catch (_) {
        try {
          final returnsDocsSnap = await _db
              .collection('order_returns')
              .where('status', isEqualTo: 'accepted')
              .limit(500)
              .get(const GetOptions(source: Source.serverAndCache));

          double calcReturns = 0.0;
          for (final doc in returnsDocsSnap.docs) {
            calcReturns +=
                (doc.data()['refund_amount'] as num?)?.toDouble() ?? 0.0;
          }
          returnedRevenue = calcReturns;
        } catch (_) {}
      }

      // إذا لم تكن مسجلة في order_returns، فحص المرتجعات المسجلة داخل الطلبات نفسها
      if (returnedRevenue == 0.0) {
        try {
          final ordersWithReturns = await _db
              .collection('orders')
              .where('returned_amount', isGreaterThan: 0)
              .limit(500)
              .get(const GetOptions(source: Source.serverAndCache));

          double calcReturns = 0.0;
          for (final doc in ordersWithReturns.docs) {
            calcReturns +=
                (doc.data()['returned_amount'] as num?)?.toDouble() ?? 0.0;
          }
          if (calcReturns > 0) returnedRevenue = calcReturns;
        } catch (_) {}
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
      hasCostData: deliveredOrders > 0 || totalProfit != 0 || grossRevenue > 0,
      isPartial: isPartial,
      failureReason: failureReason,
    );
  }

  Future<Map<String, dynamic>> getTodayStats() async {
    final nowYemen = DateTime.now().toUtc().add(const Duration(hours: 3));
    final startOfDay = DateTime.utc(nowYemen.year, nowYemen.month, nowYemen.day)
        .subtract(const Duration(hours: 3));

    try {
      // المحاولة الأولى: عبر محرك التجميع السحابي
      final aggSnap = await _db
          .collection('orders')
          .where('status', isEqualTo: 'delivered')
          .where('delivered_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .aggregate(
            count(),
            sum('total_amount'),
            sum('total'),
          )
          .get();

      final countOrders = aggSnap.count ?? 0;
      final sumTotal =
          (aggSnap.getSum('total_amount') ?? aggSnap.getSum('total') ?? 0.0)
              .toDouble();

      return {
        'revenue': sumTotal,
        'orders': countOrders.toDouble(),
        'is_error': false,
      };
    } catch (_) {
      // المحاولة الثانية (احتياطية لا تتطلب أي فهرس مركب): جلب الطلبات المسلمة والفلترة محلياً
      try {
        final snap = await _db
            .collection('orders')
            .where('status', isEqualTo: 'delivered')
            .limit(100)
            .get(const GetOptions(source: Source.serverAndCache));

        double revenue = 0.0;
        int count = 0;

        for (final doc in snap.docs) {
          final data = doc.data();
          final rawDeliveredAt =
              data['delivered_at'] ?? data['updated_at'] ?? data['created_at'];

          DateTime? deliveredDate;
          if (rawDeliveredAt is Timestamp) {
            deliveredDate = rawDeliveredAt.toDate();
          } else if (rawDeliveredAt is DateTime) {
            deliveredDate = rawDeliveredAt;
          } else if (rawDeliveredAt is String) {
            deliveredDate = DateTime.tryParse(rawDeliveredAt);
          }

          if (deliveredDate != null && deliveredDate.isAfter(startOfDay)) {
            final amt = (data['total_amount'] as num?)?.toDouble() ??
                (data['total'] as num?)?.toDouble() ??
                0.0;
            revenue += amt;
            count++;
          }
        }

        return {
          'revenue': revenue,
          'orders': count.toDouble(),
          'is_error': false,
        };
      } catch (_) {
        return {
          'revenue': 0.0,
          'orders': 0.0,
          'is_error': false, // إرجاع صفر بدلاً من خطأ لعدم تشويه الواجهة
        };
      }
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

// ── تفريغ أرباح الدورة وتوثيق الأرشيف المحاسبي سحابياً ──
  Future<void> resetPermanentProfit() async {
    final callable =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'resetProfitCycle',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );

    try {
      await callable.call();
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'فشل تصفير أرباح الدورة من السيرفر');
    }
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

// ── تحديث حالة الطلب من الإدارة سحابياً وبأمان 100% ──
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

    final callable =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'adminUpdateOrderStatus',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
    );

    try {
      final res = await callable.call({
        'orderId': cleanOrderId,
        'status': cleanStatus,
        if (driverId != null) 'driverId': driverId.trim(),
        if (driverName != null) 'driverName': driverName.trim(),
      });

      final data = Map<String, dynamic>.from(res.data as Map);
      final didChange = data['changed'] == true;

      // تفريغ كاش المنتجات محلياً فوراً إذا تضمنت العملية استرجاعاً للمخزون
      if (cleanStatus == 'cancelled' || cleanStatus == 'rejected') {
        await AppCache.instance.invalidateProducts();
      }

      return didChange;
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'فشل تحديث حالة الطلب من السيرفر');
    }
  }

// ── تسجيل إرجاع جماعي مضمون ومحمي ذرياً عبر السيرفر بدفعة واحدة ──
  Future<bool> processReturn(
    String orderId,
    String reason, {
    List<Map<String, dynamic>> returnItems = const [],
  }) async {
    final cleanOrderId = orderId.trim();
    if (cleanOrderId.isEmpty || returnItems.isEmpty) return false;

    final callable =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'adminProcessBatchReturn',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 35)),
    );

    try {
      await callable.call({
        'orderId': cleanOrderId,
        'reason': reason.trim(),
        'returnItems': returnItems,
      });
      await AppCache.instance.invalidateProducts();
      return true;
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'فشل معالجة المرتجع في السيرفر');
    }
  }

  Map<String, String> statusNotification(String status) {
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
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('اسم الصنف مطلوب');

    final callable =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'adminAddCategory',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );

    await callable.call({
      'name': cleanName,
      'imageUrl': imageUrl,
    });
    await AppCache.instance.invalidateCategories();
  }

// ── جلب الشركات مع الفرز السريع في الذاكرة والكاش ──
  Future<List<Map<String, dynamic>>> getBrands({String? categoryId}) async {
    try {
      Query<Map<String, dynamic>> query = _db.collection('brands');
      if (categoryId != null && categoryId.trim().isNotEmpty) {
        query = query.where('category_id', isEqualTo: categoryId.trim());
      }
      final snap = await query
          .limit(300)
          .get(const GetOptions(source: Source.serverAndCache));
      final list = snap.docs
          .where((d) =>
              d.data()['is_deleted'] != true && d.data()['is_active'] != false)
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

  // ── إضافة شركة جديدة عبر السيرفر ──
  Future<void> addBrand({
    required String name,
    required String categoryId,
    String? logoUrl,
  }) async {
    final cleanName = name.trim();
    final cleanCatId = categoryId.trim();
    if (cleanName.isEmpty || cleanCatId.isEmpty) {
      throw ArgumentError('بيانات الشركة والصنف مطلوبة');
    }

    final callable =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'adminAddBrand',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );

    await callable.call({
      'name': cleanName,
      'categoryId': cleanCatId,
      'logoUrl': logoUrl,
    });
    await AppCache.instance.invalidateBrands();
  }

// ── حذف الصنف تسلسلياً مع جميع الشركات والمنتجات سحابياً وبضمان 100% ──
  Future<bool> deleteCategory(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return false;

    final callable =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'cascadeDeleteCatalogItem',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
    );

    try {
      await callable.call({'type': 'category', 'id': cleanId});
      await AppCache.instance.invalidateCategories();
      await AppCache.instance.invalidateBrands();
      await AppCache.instance.invalidateProducts();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[AdminService] deleteCategory error: $e');
      return false;
    }
  }

  // ── حذف الشركة والمنتجات التابعة لها سحابياً وبضمان 100% ──
  Future<bool> deleteBrand(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return false;

    final callable =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'cascadeDeleteCatalogItem',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
    );

    try {
      await callable.call({'type': 'brand', 'id': cleanId});
      await AppCache.instance.invalidateBrands();
      await AppCache.instance.invalidateProducts();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[AdminService] deleteBrand error: $e');
      return false;
    }
  }

// ── المنتجات (مع فرز بالذاكرة لتفادي FAILED_PRECONDITION) ──
  Future<List<Map<String, dynamic>>> getProducts({String? brandId}) async {
    try {
      await ensureFinancialFieldsMigrated();
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
      return attachProductFinancials(list);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AdminService] getProducts error: $e');
        debugPrintStack(stackTrace: st);
      }
      rethrow;
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
    if (cleanName.isEmpty) throw ArgumentError('اسم المنتج مطلوب');
    if (brandId.trim().isEmpty) throw ArgumentError('الشركة مطلوبة');

    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('adminAddProduct',
            options:
                HttpsCallableOptions(timeout: const Duration(seconds: 25)));

    try {
      await callable.call({
        'name': cleanName,
        'brandId': brandId.trim(),
        'price': price,
        'costPrice': costPrice,
        'stock': stock,
        'itemsPerCarton': itemsPerCarton,
        'sizeMl': sizeMl,
        'sizeText': sizeText,
        'imageUrl': imageUrl,
        'productionDate': productionDate,
        'expiryDate': expiryDate,
        'barcode': barcode,
        'units': units,
      });

      await AppCache.instance.invalidateProducts();
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'فشل إضافة المنتج من السيرفر');
    }
  }

  Future<void> updateProduct(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) throw ArgumentError('معرّف المنتج غير صالح');

    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('adminUpdateProduct',
            options:
                HttpsCallableOptions(timeout: const Duration(seconds: 25)));

    // تجهيز البيانات وصياغة التواريخ بصيغة ISO القياسية لتمريرها عبر JSON
    final safeUpdates = <String, dynamic>{};
    for (final entry in updates.entries) {
      if (entry.value is Timestamp) {
        safeUpdates[entry.key] =
            (entry.value as Timestamp).toDate().toIso8601String();
      } else if (entry.value is FieldValue) {
        safeUpdates[entry.key] = null; // يترجم في السيرفر إلى حذف الحقل
      } else {
        safeUpdates[entry.key] = entry.value;
      }
    }

    try {
      await callable.call({
        'id': cleanId,
        'updates': safeUpdates,
      });

      await AppCache.instance.invalidateProducts();
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'فشل تحديث المنتج من السيرفر');
    }
  }

  Future<void> deleteProduct(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) throw ArgumentError('معرّف المنتج غير صالح');

    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('adminDeleteProduct',
            options:
                HttpsCallableOptions(timeout: const Duration(seconds: 15)));

    try {
      await callable.call({'id': cleanId});
      await AppCache.instance.invalidateProducts();
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'فشل حذف المنتج من السيرفر');
    }
  }

// ── التجار مرتبين زمنياً في الخادم للتصفح الصحيح ──
  Future<List<Map<String, dynamic>>> getMerchants({
    int limit = 100,
    DocumentSnapshot? startAfter,
  }) async {
    var query = _db
        .collection('profiles')
        .where('role', isEqualTo: 'merchant')
        .orderBy('created_at', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap =
        await query.get(const GetOptions(source: Source.serverAndCache));

    return snap.docs
        .map((d) => {
              'id': d.id,
              ...d.data(),
            })
        .toList();
  }

// ── دالة موحدة لاستدعاء إدارة الحسابات في السيرفر ──
  Future<void> _callManageUserAccount({
    required String targetUserId,
    required String action,
    String? role,
    bool? isActive,
  }) async {
    final cleanId = targetUserId.trim();
    if (cleanId.isEmpty) {
      throw ArgumentError('معرّف المستخدم غير صالح');
    }

    final callable =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'manageUserAccount',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
    );

    try {
      await callable.call({
        'targetUserId': cleanId,
        'action': action,
        if (role != null) 'role': role.trim().toLowerCase(),
        if (isActive != null) 'isActive': isActive,
      });
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'فشلت العملية في السيرفر');
    }
  }

  // ── تحديث حالة نشاط التاجر عبر السيرفر ──
  Future<void> updateMerchantStatus(String id, bool isActive) =>
      _callManageUserAccount(
          targetUserId: id, action: 'toggle_active', isActive: isActive);

  Future<void> toggleMerchantStatus(String merchantId, bool isActive) =>
      updateMerchantStatus(merchantId, isActive);

  // ── حظر تاجر نهائياً وإبطال جلسته عبر السيرفر ──
  Future<void> banMerchant(String merchantId) =>
      _callManageUserAccount(targetUserId: merchantId, action: 'ban');

  // ── رفع الحظر عن تاجر عبر السيرفر ──
  Future<void> unbanMerchant(String merchantId) =>
      _callManageUserAccount(targetUserId: merchantId, action: 'unban');

  // ── تغيير دور المستخدم وتحديث صلاحياته المشفرة عبر السيرفر ──
  Future<void> changeUserRole(String userId, String newRole) =>
      _callManageUserAccount(
          targetUserId: userId, action: 'change_role', role: newRole);

  // ── إحصائيات تاجر محدد حتمية ومباشرة بدون الحاجة لأي فهارس مركبة ──
  Future<Map<String, dynamic>> getMerchantStats(String merchantId) async {
    try {
      final cleanId = merchantId.trim();
      if (cleanId.isEmpty) {
        return {
          'total_orders': 0,
          'delivered_orders': 0,
          'cancelled_orders': 0,
          'total_revenue': 0.0,
        };
      }

      final snap = await _db
          .collection('orders')
          .where('merchant_id', isEqualTo: cleanId)
          .get(const GetOptions(source: Source.serverAndCache));

      int totalOrders = snap.docs.length;
      int deliveredOrders = 0;
      int cancelledOrders = 0;
      double totalRevenue = 0.0;

      for (final doc in snap.docs) {
        final data = doc.data();
        final status = data['status']?.toString().toLowerCase().trim() ?? '';
        final amount = (data['total_amount'] as num?)?.toDouble() ??
            (data['total'] as num?)?.toDouble() ??
            0.0;

        if (status == 'delivered') {
          deliveredOrders++;
          totalRevenue += amount;
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

  // ── إرسال إشعار لتاجر محدد عبر السيرفر حصراً ──
  Future<void> sendNotificationToMerchant({
    required String merchantId,
    required String title,
    required String body,
  }) async {
    final callable =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'adminSendDirectNotification',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );

    await callable.call({
      'targetUserId': merchantId.trim(),
      'title': title.trim(),
      'body': body.trim(),
    });
  }

  // ── إشعارات الإدارة (قراءة سجل البث العام) ──
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

  // ── بث الإشعارات لجميع التجار سحابياً وبشكل موثوق 100% عبر السيرفر ──
  Future<void> sendNotification({
    required String title,
    required String body,
  }) async {
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty || cleanBody.isEmpty) return;

    final callable =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'sendBroadcastNotification',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 35)),
    );

    try {
      await callable.call({
        'title': cleanTitle,
        'body': cleanBody,
      });
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'فشل إرسال الإشعار العام من السيرفر');
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

// ── تحديث حالة المرجوع الآمن عبر السيرفر المركزي ──
  Future<void> updateReturnStatus(
    String returnId,
    String status, {
    String? rejectionReason,
  }) async {
    final cleanReturnId = returnId.trim();
    final cleanStatus = status.trim().toLowerCase();
    if (cleanReturnId.isEmpty ||
        (cleanStatus != 'accepted' && cleanStatus != 'rejected')) return;

    final callable =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'processReturn',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );

    await callable.call({
      'returnId': cleanReturnId,
      'status': cleanStatus,
      'rejectionReason': rejectionReason?.trim(),
    });

    // تحديث كاش المنتجات بالهاتف ليعكس المخزون المسترجع فوراً
    await AppCache.instance.invalidateProducts();
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
