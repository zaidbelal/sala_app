import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sala/core/services/local_storage.dart';
import 'package:sala/core/services/connectivity_service.dart';
import 'package:sala/core/services/wal_service.dart';
import '../models/ledger_models.dart';

class LedgerQueuedException implements Exception {
  final String message;

  const LedgerQueuedException(this.message);

  @override
  String toString() => message;
}

class LedgerSyncResult {
  final int syncedCount;
  final int unresolvedCount;

  const LedgerSyncResult({
    required this.syncedCount,
    required this.unresolvedCount,
  });
}

class LedgerService {
  LedgerService._();
  static final instance = LedgerService._();
  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

// 🔒 مصفوفة مدعومة بقرص الهاتف لمنع عودة الزبائن المحذوفين نهائياً حتى بعد إغلاق التطبيق
  Set<String> get _locallyDeletedCustomerIds {
    final list = AppStorage.getString('ledger_deleted_cust_ids_set');
    if (list == null || list.isEmpty) return <String>{};
    try {
      return Set<String>.from(jsonDecode(list));
    } catch (_) {
      return <String>{};
    }
  }

  void _recordDeletedCustomerId(String id) {
    final set = _locallyDeletedCustomerIds..add(id);
    AppStorage.setString(
        'ledger_deleted_cust_ids_set', jsonEncode(set.toList()));
  }

  void _removeDeletedCustomerId(String id) {
    final set = _locallyDeletedCustomerIds..remove(id);
    AppStorage.setString(
        'ledger_deleted_cust_ids_set', jsonEncode(set.toList()));
  }

  // ─── مراقبة ملخص ديون التاجر الإجمالية في السوق لحظياً ───
  Stream<Map<String, dynamic>> watchMerchantLedgerSummary(String merchantId) {
    final cleanMerchantId = merchantId.trim();
    if (cleanMerchantId.isEmpty) return const Stream.empty();

    return _db
        .collection('merchant_ledger_summaries')
        .doc(cleanMerchantId)
        .snapshots(includeMetadataChanges: true)
        .map((doc) {
      if (!doc.exists || doc.data() == null) {
        return {'total_market_debt': 0.0, 'debtors_count': 0};
      }
      return doc.data()!;
    });
  }

  String _piecePriceKey(String merchantId, String productId) =>
      'retail_piece_price_${merchantId}_$productId';

  static int toCents(num val) => (val * 100).round();
  static double fromCents(int cents) => cents / 100.0;
  static double sanitizeMoney(num val) => fromCents(toCents(val));

  bool _isFatalLedgerError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('permission-denied') ||
        message.contains('invalid-argument') ||
        message.contains('unauthenticated') ||
        message.contains('not-found') ||
        message.contains('already-exists') ||
        message.contains('failed-precondition');
  }

  bool _matchesLedgerValue(Object? persisted, Object? intended) {
    if (persisted is num && intended is num) {
      return persisted == intended;
    }
    if (persisted is List && intended is List) {
      if (persisted.length != intended.length) return false;
      for (var i = 0; i < persisted.length; i++) {
        if (!_matchesLedgerValue(persisted[i], intended[i])) return false;
      }
      return true;
    }
    if (persisted is Map && intended is Map) {
      if (persisted.length != intended.length) return false;
      for (final key in intended.keys) {
        if (!persisted.containsKey(key) ||
            !_matchesLedgerValue(persisted[key], intended[key])) {
          return false;
        }
      }
      return true;
    }
    return persisted == intended;
  }

  Future<bool> _matchesPersistedLedgerIntent(
    String transactionId,
    Map<String, dynamic> intent,
  ) async {
    final doc = await _db
        .collection('merchant_ledger_entries')
        .doc(transactionId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 5));
    final data = doc.data();
    final persistedAmount = data?['amount'];
    final intendedAmount = intent['amount'];
    final persistedNotes = data?['notes'] ?? '';
    final intendedNotes = intent['notes'] ?? '';
    final persistedItems = data?['items'] ?? const [];
    final intendedItems = intent['items'] ?? const [];

    return doc.exists &&
        data?['merchant_id'] == intent['merchant_id'] &&
        data?['customer_id'] == intent['customer_id'] &&
        data?['type'] == intent['type'] &&
        persistedAmount is num &&
        intendedAmount is num &&
        toCents(persistedAmount) == toCents(intendedAmount) &&
        _matchesLedgerValue(persistedNotes, intendedNotes) &&
        _matchesLedgerValue(persistedItems, intendedItems);
  }

  Future<double?> getSavedPiecePrice(
      String merchantId, String productId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localPrice = prefs.getDouble(_piecePriceKey(merchantId, productId));
      if (localPrice != null && localPrice > 0) return localPrice;

      // مزامنة احتياطية من السحابة في حال قام التاجر بتغيير الهاتف أو مسح البيانات
      if (merchantId.isNotEmpty && productId.isNotEmpty) {
        final doc = await _db
            .collection('profiles')
            .doc(merchantId)
            .collection('retail_pricing')
            .doc(productId)
            .get(const GetOptions(source: Source.serverAndCache));
        if (doc.exists && doc.data() != null) {
          final cloudPrice = (doc.data()!['price'] as num?)?.toDouble();
          if (cloudPrice != null && cloudPrice > 0) {
            await prefs.setDouble(
                _piecePriceKey(merchantId, productId), cloudPrice);
            return cloudPrice;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setSavedPiecePrice(
      String merchantId, String productId, double price) async {
    try {
      final safePrice = sanitizeMoney(price);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_piecePriceKey(merchantId, productId), safePrice);

      // حفظ نسخة دائمة في السحابة لتبقى مع حساب التاجر مدى الحياة
      if (merchantId.isNotEmpty && productId.isNotEmpty) {
        unawaited(_db
            .collection('profiles')
            .doc(merchantId)
            .collection('retail_pricing')
            .doc(productId)
            .set({
          'price': safePrice,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)));
      }
    } catch (_) {}
  }

  // ─── كاش ملفات الزبائن المحلي السريع ───
  Future<File?> _getCustomerCacheFile(String merchantId) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/ledger_cust_$merchantId.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> _customerCacheLock = Future.value();

  Future<void> _cacheCustomersLocally(
      String merchantId, List<LedgerCustomer> list) async {
    final prev = _customerCacheLock;
    final completer = Completer<void>();
    _customerCacheLock = completer.future;

    try {
      await prev;
    } catch (_) {}

    try {
      final file = await _getCustomerCacheFile(merchantId);
      if (file == null) return;

      final rawList = list.map((c) => c.toMap()).toList();
      final encoded = await compute(_isolateJsonEncode, rawList);

      final nonce = DateTime.now().microsecondsSinceEpoch;
      final tempFile = File('${file.path}_$nonce.tmp');
      await tempFile.writeAsString(encoded, flush: true);
      await tempFile.rename(file.path);
    } catch (_) {
    } finally {
      completer.complete();
    }
  }

  static String _isolateJsonEncode(List<Map<String, dynamic>> data) =>
      jsonEncode(data, toEncodable: (item) {
        if (item is Timestamp) return item.toDate().toIso8601String();
        if (item is DateTime) return item.toIso8601String();
        return item.toString();
      });

  Future<List<LedgerCustomer>> getCachedCustomers(String merchantId) async {
    try {
      final file = await _getCustomerCacheFile(merchantId);
      if (file == null || !await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((m) => LedgerCustomer.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Stream<List<LedgerCustomer>> watchCustomers(String merchantId,
      {int limit = 1000}) {
    final cleanMerchantId = merchantId.trim();
    if (cleanMerchantId.isEmpty) return const Stream.empty();

    return _db
        .collection('merchant_customers')
        .where('merchant_id', isEqualTo: cleanMerchantId)
        .limit(limit)
        .snapshots(includeMetadataChanges: true)
        .asyncMap((snap) async {
      final serverMap = <String, LedgerCustomer>{};
      final serverDocRaws = <String, Map<String, dynamic>>{};
      final deletedCustomerIds = <String>{};

      // 1. التقاط الحركات المحذوفة في طابور الأوفلاين لاستبعادها فوراً
      final allPending = AppStorage.getPendingLedgerTxs(cleanMerchantId);
      final pendingDeletes = allPending
          .where((t) => t['type'] == 'delete_customer')
          .map((t) => t['customer_id']?.toString() ?? '')
          .toSet();

      for (final d in snap.docs) {
        final custId = d.id;
        // إذا كان محذوفاً في السيرفر أو محلياً بالذاكرة أو في طابور الحذف يتم حذفه فوراً
        if (d.data()['is_deleted'] == true ||
            _locallyDeletedCustomerIds.contains(custId) ||
            pendingDeletes.contains(custId)) {
          deletedCustomerIds.add(custId);
          continue;
        }
        serverMap[custId] = LedgerCustomer.fromMap({'id': custId, ...d.data()});
        serverDocRaws[custId] = d.data();
      }
// 🛡️ دمج الكاش المحلي مع تتبع معرّفات الكاش لمنع مضاعفة الرصيد في الأوفلاين
      final Set<String> fromDiskCacheIds = {};
      final existingLocalCached = await getCachedCustomers(cleanMerchantId);
      for (final cached in existingLocalCached) {
        if (deletedCustomerIds.contains(cached.id) ||
            _locallyDeletedCustomerIds.contains(cached.id) ||
            pendingDeletes.contains(cached.id)) continue;
        if (!serverMap.containsKey(cached.id)) {
          serverMap[cached.id] = cached;
          fromDiskCacheIds.add(cached.id);
        }
      }

      final pendingNewCustomers =
          allPending.where((t) => t['type'] == 'add_customer');

      for (final p in pendingNewCustomers) {
        final custId = p['customer_id']?.toString() ?? '';
        if (custId.isNotEmpty &&
            !serverMap.containsKey(custId) &&
            !_locallyDeletedCustomerIds.contains(custId) &&
            !pendingDeletes.contains(custId)) {
          serverMap[custId] = LedgerCustomer(
            id: custId,
            merchantId: cleanMerchantId,
            name: p['name'] ?? 'زبون',
            phone: p['phone'] ?? '',
            currentBalance: 0.0,
            creditLimit: (p['credit_limit'] as num?)?.toDouble() ?? 0.0,
            salaryDay: p['salary_day'],
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        }
      }

      // 🔒 التحقق المحاسبي: إضافة فوارق الأوفلاين فقط للبيانات القادمة من السيرفر الحي
      final pendingTxs = allPending.where((t) =>
          t['type'] == 'debt' ||
          t['type'] == 'payment' ||
          t['type'] == 'void_request');

      for (final entry in serverMap.entries) {
        final c = entry.value;

        // 🛡️ حماية حاسمة: إذا كان الزبون مقروءاً من كاش القرص (fromDiskCacheIds)،
        // فرصيده يحتوي مسبقاً على الحركات المعلقة محلياً ولا يجوز إعادة جمعها أبداً
        if (fromDiskCacheIds.contains(c.id)) {
          continue;
        }

        final docRaw = serverDocRaws[c.id];
        final appliedIds = (docRaw?['applied_tx_ids'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toSet();
        final lastTxId = docRaw?['last_transaction_id']?.toString();
        if (lastTxId != null && lastTxId.isNotEmpty) {
          appliedIds.add(lastTxId);
        }
        final customerPendingList =
            pendingTxs.where((tx) => tx['customer_id'] == c.id).toList();

        final pendingCreationIds = customerPendingList
            .where((t) => t['type'] == 'debt' || t['type'] == 'payment')
            .map((t) => t['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();

        final pendingVoidTargetIds = customerPendingList
            .where((t) => t['type'] == 'void_request')
            .map((t) => t['target_entry_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();

        int deltaCents = 0;
        for (final tx in customerPendingList) {
          final txType = tx['type']?.toString();
          final txId = tx['id']?.toString() ?? '';
          final amtCents = toCents((tx['amount'] as num?)?.toDouble() ?? 0.0);

          // التحقق الأمني: إذا تم تطبيق الحركة بالسيرفر نتخطاها فوراً
          if (appliedIds.contains(txId) || appliedIds.contains('void_$txId')) {
            continue;
          }

          if (txType == 'void_request') {
            final targetId = tx['target_entry_id']?.toString() ?? '';
            if (appliedIds.contains('void_$targetId')) continue;

            final isCreatedOffline = pendingCreationIds.contains(targetId);
            if (!isCreatedOffline) {
              final isDebt = tx['is_debt'] != false;
              deltaCents += isDebt ? -amtCents : amtCents;
            }
            continue;
          }

          if (pendingVoidTargetIds.contains(txId)) continue;

          deltaCents += (txType == 'debt') ? amtCents : -amtCents;
        }
        if (deltaCents != 0) {
          final computedBalance =
              fromCents(toCents(c.currentBalance) + deltaCents);
          serverMap[c.id] = LedgerCustomer(
            id: c.id,
            merchantId: c.merchantId,
            name: c.name,
            phone: c.phone,
            currentBalance: sanitizeMoney(computedBalance),
            creditLimit: c.creditLimit,
            salaryDay: c.salaryDay,
            lastReminderSentAt: c.lastReminderSentAt,
            createdAt: c.createdAt,
            updatedAt: c.updatedAt,
          );
        }
      }
      final combinedList = serverMap.values.toList()
        ..sort((a, b) => b.currentBalance.compareTo(a.currentBalance));

      unawaited(_cacheCustomersLocally(cleanMerchantId, combinedList));
      return combinedList;
    });
  }

  /// بحث سحابي مباشر بالاسم ورقم الهاتف في حال تجاوز التاجر للحدود أو كان الزبون غير محمل بالذاكرة
  Future<List<LedgerCustomer>> searchCustomersRemotely({
    required String merchantId,
    required String query,
  }) async {
    final cleanMerchantId = merchantId.trim();
    final cleanQuery = query.trim();
    if (cleanMerchantId.isEmpty || cleanQuery.isEmpty) return [];

    final bool isPhoneQuery = RegExp(r'^\+?[0-9]+$').hasMatch(cleanQuery);

    try {
      Query<Map<String, dynamic>> baseQ = _db
          .collection('merchant_customers')
          .where('merchant_id', isEqualTo: cleanMerchantId);

      if (isPhoneQuery) {
        final snap = await baseQ
            .where('phone', isEqualTo: cleanQuery)
            .limit(10)
            .get(const GetOptions(source: Source.serverAndCache));
        return snap.docs
            .map((d) => LedgerCustomer.fromMap({'id': d.id, ...d.data()}))
            .toList();
      } else {
        final snap = await baseQ
            .where('name', isGreaterThanOrEqualTo: cleanQuery)
            .where('name', isLessThanOrEqualTo: '$cleanQuery\uf8ff')
            .limit(20)
            .get(const GetOptions(source: Source.serverAndCache));
        return snap.docs
            .map((d) => LedgerCustomer.fromMap({'id': d.id, ...d.data()}))
            .toList();
      }
    } catch (_) {
      // 🛡️ بحث سحابي موسع يستوعب آلاف الزبائن مع دعم التصفح الذكي
      try {
        final fallbackSnap = await _db
            .collection('merchant_customers')
            .where('merchant_id', isEqualTo: cleanMerchantId)
            .where('is_deleted', isEqualTo: false)
            .limit(500) // رفع السقف لتغطية واسعة للزبائن
            .get(const GetOptions(source: Source.serverAndCache));

        return fallbackSnap.docs
            .map((d) => LedgerCustomer.fromMap({'id': d.id, ...d.data()}))
            .where((c) =>
                c.name.toLowerCase().contains(cleanQuery.toLowerCase()) ||
                c.phone.contains(cleanQuery))
            .toList();
      } catch (_) {
        return [];
      }
    }
  }

// ─── إضافة زبون عبر السيرفر مع الحفاظ على المعرّف المولد مسبقاً أوفلاين ───
  Future<void> addCustomer({
    required String merchantId,
    required String name,
    required String phone,
    double creditLimit = 0.0,
    int? salaryDay,
    String? existingCustomerId,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('اسم الزبون مطلوب');

    final hasInternet = await ConnectivityHelper.hasActiveInternet();
    final clientGeneratedId =
        (existingCustomerId != null && existingCustomerId.trim().isNotEmpty)
            ? existingCustomerId.trim()
            : _db.collection('merchant_customers').doc().id;

    if (!hasInternet) {
      await _queueCustomerLocally(
        merchantId: merchantId,
        customerId: clientGeneratedId,
        name: cleanName,
        phone: phone,
        creditLimit: creditLimit,
        salaryDay: salaryDay,
      );
      throw const LedgerQueuedException(
          'لا يوجد اتصال بالإنترنت، حُفظ الزبون للمزامنة');
    }

    try {
      final callable = _functions.httpsCallable(
        'addLedgerCustomer',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );

      await callable.call({
        'customerId': clientGeneratedId,
        'name': cleanName,
        'phone': phone.trim(),
        'creditLimit': creditLimit,
        'salaryDay': salaryDay,
      });
    } catch (e) {
      if (_isFatalLedgerError(e)) rethrow;
      await _queueCustomerLocally(
        merchantId: merchantId,
        customerId: clientGeneratedId,
        name: cleanName,
        phone: phone,
        creditLimit: creditLimit,
        salaryDay: salaryDay,
      );
      throw const LedgerQueuedException(
          'تعذر الاتصال بالسيرفر، حُفظ الزبون للمزامنة');
    }
  }

  Future<void> _queueCustomerLocally({
    required String merchantId,
    required String customerId,
    required String name,
    required String phone,
    required double creditLimit,
    int? salaryDay,
  }) async {
    final now = DateTime.now();
    final customer = LedgerCustomer(
      id: customerId,
      merchantId: merchantId,
      name: name,
      phone: phone.trim(),
      currentBalance: 0.0,
      creditLimit: sanitizeMoney(creditLimit),
      salaryDay: salaryDay,
      createdAt: now,
      updatedAt: now,
    );
    final cached = await getCachedCustomers(merchantId);
    final existsIdx = cached.indexWhere((c) => c.id == customerId);
    if (existsIdx != -1) {
      cached[existsIdx] = customer;
    } else {
      cached.insert(0, customer);
    }
    await _cacheCustomersLocally(merchantId, cached);
    await AppStorage.savePendingLedgerTx({
      'id': 'cust_$customerId',
      'merchant_id': merchantId,
      'customer_id': customerId,
      'type': 'add_customer',
      'name': name,
      'phone': phone.trim(),
      'credit_limit': creditLimit,
      'salary_day': salaryDay,
      'created_at': now.toIso8601String(),
    });
  }

// ─── حذف زبون من الدفتر سحابياً ومحلياً مع ضمان الاختفاء الفوري (0ms) ───
  Future<void> deleteCustomer({
    required String merchantId,
    required String customerId,
    double currentBalance = 0.0,
    bool isSyncing =
        false, // 👈 راية تمنع تكرار الحفظ في طابور الأوفلاين عند المزامنة
  }) async {
    final cleanMerchantId = merchantId.trim();
    final cleanCustomerId = customerId.trim();
    if (cleanCustomerId.isEmpty || cleanMerchantId.isEmpty) return;

    // قراءة الزبون والاحتفاظ بنسخة حية كاملة منه قبل لمس أي كاش
    final cached = await getCachedCustomers(cleanMerchantId);
    final cachedIndex = cached.indexWhere((c) => c.id == cleanCustomerId);
    final cachedCustomer = cachedIndex == -1 ? null : cached[cachedIndex];

    // دالة تراجع متزامنة تضمن عودة الزبون فوراً للواجهة والقرص إذا حدث أي خطأ
    Future<void> restoreCustomer() async {
      _removeDeletedCustomerId(cleanCustomerId);
      if (cachedCustomer != null) {
        final currentCached = await getCachedCustomers(cleanMerchantId);
        if (!currentCached.any((c) => c.id == cleanCustomerId)) {
          final insertIdx = cachedIndex.clamp(0, currentCached.length);
          currentCached.insert(insertIdx, cachedCustomer);
          await _cacheCustomersLocally(cleanMerchantId, currentCached);
        }
      }
    }

    // 1. تطبيق الحذف التفاؤلي الفوري محلياً لتحسين الاستجابة (Optimistic UI)
    _recordDeletedCustomerId(cleanCustomerId);
    cached.removeWhere((c) => c.id == cleanCustomerId);
    await _cacheCustomersLocally(cleanMerchantId, cached);

    final hasInternet = await ConnectivityHelper.hasActiveInternet();
    final deletedAt = DateTime.now().toIso8601String();

    if (!hasInternet) {
      if (!isSyncing) {
        try {
          await AppStorage.savePendingLedgerTx({
            'id': 'del_$cleanCustomerId',
            'merchant_id': cleanMerchantId,
            'customer_id': cleanCustomerId,
            'type': 'delete_customer',
            'amount': currentBalance,
            'created_at': deletedAt,
          });
        } catch (_) {
          await restoreCustomer();
          rethrow;
        }
      }
      throw const LedgerQueuedException(
          'لا يوجد اتصال بالإنترنت، حُذف الزبون محلياً وحُفظ طلب الحذف للمزامنة');
    }

    try {
      final callable = _functions.httpsCallable(
        'deleteLedgerCustomer',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );
      await callable.call({'customerId': cleanCustomerId});

      // ✅ فور نجاح الحذف في السيرفر: نطهر المعرّف من قائمة الشواهد المؤقتة لأن السيرفر أصبح يحمل is_deleted: true
      _removeDeletedCustomerId(cleanCustomerId);
    } catch (e) {
      // 🛡️ إذا رفض السيرفر الحذف لأسباب أمنية أو صلاحيات: تراجع فوري واستعادة الزبون وديونه للشاشة
      if (_isFatalLedgerError(e)) {
        await restoreCustomer();
        // إزالة أمر الحذف العالق من طابور المزامنة إن وجد لمنع إعادة تكراره
        await AppStorage.removePendingLedgerTx(
            'del_$cleanCustomerId', cleanMerchantId);
        rethrow;
      }

      // إذا كان الخطأ مجرد انقطاع في الشبكة ولم نكن في وضع مزامنة: نحفظ الحركة في طابور الأوفلاين
      if (!isSyncing) {
        try {
          await AppStorage.savePendingLedgerTx({
            'id': 'del_$cleanCustomerId',
            'merchant_id': cleanMerchantId,
            'customer_id': cleanCustomerId,
            'type': 'delete_customer',
            'amount': currentBalance,
            'created_at': deletedAt,
          });
        } catch (_) {
          await restoreCustomer();
          rethrow;
        }
      }
      throw const LedgerQueuedException(
          'تعذر الاتصال بالسيرفر، حُفظ طلب حذف الزبون للمزامنة');
    }
  }

// ─── تسجيل حركة مالية (دين أو سداد) عبر السيرفر مع تأمين سقف الائتمان ───
  Future<void> recordTransaction({
    required String merchantId,
    required String customerId,
    required String type,
    required double amount,
    String? notes,
    List<dynamic> items = const [],
    String? transactionId,
    bool isSyncing =
        false, // 🔒 راية تفصل العمليات الجديدة عن عمليات إعادة المزامنة
  }) async {
    final cleanMerchantId = merchantId.trim();
    final cleanCustomerId = customerId.trim();
    final cleanType = type.trim().toLowerCase();
    final safeAmount = sanitizeMoney(amount);

    if (cleanMerchantId.isEmpty || cleanCustomerId.isEmpty) {
      throw ArgumentError('معرّفات العملية غير صالحة');
    }
    if (cleanType != 'debt' && cleanType != 'payment') {
      throw ArgumentError('نوع القيد المالي يجب أن يكون debt أو payment حصراً');
    }
    if (safeAmount <= 0) {
      throw ArgumentError('مبلغ القيد المالي غير صالح');
    }
    final entryId = (transactionId != null && transactionId.trim().isNotEmpty)
        ? transactionId.trim()
        : 'tx_${cleanMerchantId}_${DateTime.now().microsecondsSinceEpoch}';
    final isDebt = cleanType == 'debt';
    final delta = isDebt ? safeAmount : -safeAmount;

    final sanitizedItems = items.map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      return map;
    }).toList();
    final payload = {
      'id': entryId,
      'merchant_id': cleanMerchantId,
      'customer_id': cleanCustomerId,
      'type': cleanType,
      'amount': safeAmount,
      'is_voided': false,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      'items': sanitizedItems,
      'created_at': DateTime.now().toIso8601String(),
    };

    if (!isSyncing) {
      await WalService.instance.writeIntent(
        transactionId: entryId,
        type: WalOperationType.ledgerTransaction,
        payload: payload,
      );
    }

    final hasInternet = await ConnectivityHelper.hasActiveInternet();

    if (!hasInternet) {
      if (!isSyncing) {
        await AppStorage.savePendingLedgerTx(payload);
        // تحديث محلي متسق بالقروش لمنع تشوه الفواصل
        final cached = await getCachedCustomers(cleanMerchantId);
        final idx = cached.indexWhere((c) => c.id == cleanCustomerId);
        if (idx != -1) {
          final old = cached[idx];
          final newCents = toCents(old.currentBalance) + toCents(delta);
          cached[idx] = LedgerCustomer(
            id: old.id,
            merchantId: old.merchantId,
            name: old.name,
            phone: old.phone,
            currentBalance: fromCents(newCents),
            creditLimit: old.creditLimit,
            salaryDay: old.salaryDay,
            lastReminderSentAt: old.lastReminderSentAt,
            createdAt: old.createdAt,
            updatedAt: DateTime.now(),
          );
          await _cacheCustomersLocally(cleanMerchantId, cached);
        }
      }
      throw const LedgerQueuedException(
          'لا يوجد اتصال بالإنترنت، تم تأمين القيد أوفلاين');
    }

    try {
      final callable = _functions.httpsCallable(
        'recordLedgerTransaction',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );

      await callable.call({
        'transactionId': entryId,
        'customerId': cleanCustomerId,
        'type': cleanType,
        'amount': safeAmount,
        'notes': notes?.trim(),
        'items': sanitizedItems,
      });

      await WalService.instance.markCommitted(entryId);
    } catch (e) {
      final err = e.toString().toLowerCase();
      if (err.contains('already-exists') || err.contains('duplicate')) {
        try {
          if (await _matchesPersistedLedgerIntent(entryId, payload)) {
            await WalService.instance.markCommitted(entryId);
            return;
          }
        } catch (verificationError) {
          debugPrint(
              'Could not verify existing ledger entry $entryId; preserving the intent for retry: $verificationError');
          await AppStorage.savePendingLedgerTx(payload);
          throw const LedgerQueuedException(
              'تعذر التحقق من القيد الموجود، تم حفظ الحركة للمزامنة الآمنة');
        }

        await WalService.instance.markAborted(entryId);
        rethrow;
      }

      final isFatalBusinessError = _isFatalLedgerError(e);
      if (!isFatalBusinessError) {
        await AppStorage.savePendingLedgerTx(payload);
        throw const LedgerQueuedException(
            'تعثر الاتصال بالسيرفر، تم حفظ القيد أوفلاين بنجاح');
      }
      await WalService.instance.markAborted(entryId);
      rethrow;
    }
  }

// ─── شطب قيد مالي وعكسه محاسبياً عبر السيرفر مع تأمين كامل لحالات الأوفلاين ───
  Future<void> voidTransaction({
    required String merchantId,
    required String customerId,
    required String entryId,
    required double knownAmount,
    required bool knownIsDebt,
  }) async {
    final cleanMerchantId = merchantId.trim();
    final cleanCustomerId = customerId.trim();
    final cleanEntryId = entryId.trim();
    final voidRequestId = 'void_$cleanEntryId';

    if (!knownAmount.isFinite || knownAmount <= 0) {
      throw ArgumentError.value(
          knownAmount, 'knownAmount', 'يجب أن يكون مبلغ القيد موجباً وصالحاً');
    }
    final targetAmount = sanitizeMoney(knownAmount);
    final isDebtTarget = knownIsDebt;
    final reverseDelta = isDebtTarget ? -targetAmount : targetAmount;

    final hasInternet = await ConnectivityHelper.hasActiveInternet();
    final pendingQueue = AppStorage.getPendingLedgerTxs(cleanMerchantId);
    if (pendingQueue.any((t) => t['id'] == voidRequestId)) return;
    final pendingIdx = pendingQueue.indexWhere((t) => t['id'] == cleanEntryId);

    // 🔒 فحص قاطع: لا يُحذف القيد أوفلاين دون إخطار السيرفر إلا إذا ثبت يقيناً بالاتصال المباشر عدم وجوده بالسيرفر
    if (pendingIdx != -1 && hasInternet) {
      bool existsOnServer = false;
      try {
        final checkDoc = await _db
            .collection('merchant_ledger_entries')
            .doc(cleanEntryId)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 3));
        existsOnServer = checkDoc.exists;
      } catch (_) {
        existsOnServer = true; // نتحوط للأمان في حال تعثر فحص السيرفر
      }

      if (!existsOnServer) {
        // ثبت يقيناً أن القيد لم يصل السيرفر إطلاقاً؛ يُحذف محلياً بأمان تام دون طلب شطب
        await AppStorage.removePendingLedgerTx(cleanEntryId, cleanMerchantId);
        await WalService.instance.markAborted(cleanEntryId);
        await _applyLocalCustomerAdjustment(
            cleanMerchantId, cleanCustomerId, reverseDelta);
        return;
      }
    }

    // 🔒 تدوين نية الشطب في سجل الـ WAL محلياً
    await WalService.instance.writeIntent(
      transactionId: cleanEntryId,
      type: WalOperationType.ledgerTransaction,
      payload: {
        'action': 'void',
        'merchant_id': cleanMerchantId,
        'customer_id': cleanCustomerId,
        'amount': targetAmount,
        'is_debt': isDebtTarget,
      },
    );

    // 🔒 تأمين طلب الشطب في طابور الأوفلاين (Pending Queue) لضمان عدم عودة الدين الشبحي إطلاقاً
    final voidTxPayload = {
      'id': voidRequestId,
      'merchant_id': cleanMerchantId,
      'customer_id': cleanCustomerId,
      'type': 'void_request',
      'target_entry_id': cleanEntryId,
      'amount': targetAmount,
      'is_debt': isDebtTarget,
      'created_at': DateTime.now().toIso8601String(),
    };
    await AppStorage.savePendingLedgerTx(voidTxPayload);
    await _applyLocalCustomerAdjustment(
        cleanMerchantId, cleanCustomerId, reverseDelta);

    if (!hasInternet) {
      return; // تم التأمين محلياً وسيرسل السيرفر عند عودة الاتصال عبر دالة المزامنة
    }

    // محاولة الإرسال الفوري للسيرفر إذا توفر الإنترنت
    try {
      await _sendVoidTransaction(cleanCustomerId, cleanEntryId);
      await AppStorage.removePendingLedgerTx(voidRequestId, cleanMerchantId);
    } catch (e) {
      if (_isFatalLedgerError(e)) {
        await AppStorage.removePendingLedgerTx(voidRequestId, cleanMerchantId);
        await WalService.instance.markAborted(cleanEntryId);
        rethrow;
      }
      // في حال حدوث خطأ شبكة مؤقت، يبقى القيد في AppStorage لترسله دالة المزامنة تلقائياً
    }
  }

  /// دالة مساعدة مركزية لتحديث الكاش المحلي لرصيد الزبون بدقة القروش
  Future<void> _applyLocalCustomerAdjustment(
    String merchantId,
    String customerId,
    double delta,
  ) async {
    final cached = await getCachedCustomers(merchantId);
    final cIdx = cached.indexWhere((c) => c.id == customerId);
    if (cIdx != -1) {
      final old = cached[cIdx];
      final newCents = toCents(old.currentBalance) + toCents(delta);
      cached[cIdx] = LedgerCustomer(
        id: old.id,
        merchantId: old.merchantId,
        name: old.name,
        phone: old.phone,
        currentBalance: fromCents(newCents),
        creditLimit: old.creditLimit,
        salaryDay: old.salaryDay,
        lastReminderSentAt: old.lastReminderSentAt,
        createdAt: old.createdAt,
        updatedAt: DateTime.now(),
      );
      await _cacheCustomersLocally(merchantId, cached);
    }
  }

  Future<void> _sendVoidTransaction(String customerId, String entryId) async {
    final callable = _functions.httpsCallable(
      'voidLedgerTransaction',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );

    await callable.call({
      'customerId': customerId,
      'entryId': entryId,
    });

    await WalService.instance.markCommitted(entryId);
  }

  // ─── تدقيق ومطابقة رصيد الزبون سحابياً ───

  Future<void> reconcileCustomerBalance({
    required String merchantId,
    required String customerId,
    bool force = false,
  }) async {
    try {
      final hasInternet = await ConnectivityHelper.hasActiveInternet();
      if (!hasInternet) return;

      final pendingQueue = AppStorage.getPendingLedgerTxs(merchantId)
          .where((t) => t['customer_id'] == customerId.trim());
      if (pendingQueue.isNotEmpty) return;

      // 🔒 رفع المهلة إلى 45 ثانية لاستيعاب قراءة وتدقيق آلاف القيود للزبائن القدامى بسلاسة
      final callable = _functions.httpsCallable(
        'reconcileLedgerBalance',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
      );

      await callable.call({'customerId': customerId.trim()});
    } catch (_) {}
  }

// ─── مزامنة طابور الأوفلاين مع السيرفر بدقة موحدة وبدون فقدان للملف الدائم ───
  Future<LedgerSyncResult> syncPendingLedgerQueue(String merchantId) async {
    final rawPending = AppStorage.getPendingLedgerTxs(merchantId);
    if (rawPending.isEmpty) {
      return const LedgerSyncResult(syncedCount: 0, unresolvedCount: 0);
    }

    // فهرسة موحدة مبنية على المفتاح الأساسي للعملية
    final Map<String, Map<String, dynamic>> unifiedQueue = {
      for (final item in rawPending)
        if ((item['id']?.toString() ?? '').isNotEmpty)
          item['id'].toString(): Map<String, dynamic>.from(item)
    };

    int synced = 0;
    int unresolved = 0;

    // ══════════════════════════════════════════════════════════════════════
    // 🛡️ المرحلة 1: التسوية والتصفية المسبقة الذكية (Pre-Sync Netting Pass)
    // إسقاط العمليات الملغاة محلياً بالكامل لمنع إرسال قيود شبحية إلى السيرفر
    // ══════════════════════════════════════════════════════════════════════

    // أ) إسقاط أزواج (القيد + طلب شطبه) التي وُلدت معاً في الأوفلاين
    final voidRequests =
        unifiedQueue.values.where((t) => t['type'] == 'void_request').toList();

    for (final voidReq in voidRequests) {
      final voidTxId = voidReq['id']?.toString() ?? '';
      final targetEntryId = voidReq['target_entry_id']?.toString() ?? '';

      // إذا كان القيد الأصلي لا يزال في الطابور المحلي (لم يسبق اعتماده بالسيرفر)
      if (targetEntryId.isNotEmpty && unifiedQueue.containsKey(targetEntryId)) {
        await AppStorage.removePendingLedgerTx(targetEntryId, merchantId);
        await AppStorage.removePendingLedgerTx(voidTxId, merchantId);
        await WalService.instance.markAborted(targetEntryId);
        unifiedQueue.remove(targetEntryId);
        unifiedQueue.remove(voidTxId);
        synced += 2;
      }
    }

    // ب) إسقاط زبائن الأوفلاين الذين أُضيفوا ثم حُذفوا أوفلاين قبل مزامنتهم للسيرفر
    final deleteCustomerRequests = unifiedQueue.values
        .where((t) => t['type'] == 'delete_customer')
        .toList();

    for (final delReq in deleteCustomerRequests) {
      final delTxId = delReq['id']?.toString() ?? '';
      final custId = delReq['customer_id']?.toString() ?? '';
      final addCustTxId = 'cust_$custId';

      if (custId.isNotEmpty && unifiedQueue.containsKey(addCustTxId)) {
        await AppStorage.removePendingLedgerTx(addCustTxId, merchantId);
        await AppStorage.removePendingLedgerTx(delTxId, merchantId);
        unifiedQueue.remove(addCustTxId);
        unifiedQueue.remove(delTxId);

        // تنظيف أي حركات مالية أُنشئت لهذا الزبون في نفس جلسة الأوفلاين
        final dependentTxs = unifiedQueue.values
            .where((t) => t['customer_id'] == custId)
            .toList();

        for (final dep in dependentTxs) {
          final depId = dep['id']?.toString() ?? '';
          if (depId.isNotEmpty) {
            await AppStorage.removePendingLedgerTx(depId, merchantId);
            await WalService.instance.markAborted(depId);
            unifiedQueue.remove(depId);
            synced++;
          }
        }
        synced += 2;
      }
    }

    if (unifiedQueue.isEmpty) {
      return LedgerSyncResult(syncedCount: synced, unresolvedCount: 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    // 🚀 المرحلة 2: إرسال العمليات المتبقية الحقيقية مرتبة زمنياً
    // ══════════════════════════════════════════════════════════════════════
    final sortedQueueList = unifiedQueue.values.toList()
      ..sort((a, b) {
        final aTime = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime(2000);
        final bTime = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime(2000);
        return aTime.compareTo(bTime);
      });

    // 🔒 مجموعة تتبع ديناميكية تمنع تجويع قيود الزبائن الجدد وتتيح مزامنتها في نفس الدورة
    final pendingCreationCustomerIds = sortedQueueList
        .where((q) => q['type'] == 'add_customer')
        .map((q) => q['customer_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    for (final item in sortedQueueList) {
      final txId = item['id']?.toString() ?? '';
      final custId = item['customer_id']?.toString() ?? '';
      final type = item['type']?.toString() ?? '';
      if (txId.isEmpty || custId.isEmpty) continue;

      try {
        if (type == 'add_customer') {
          await addCustomer(
            merchantId: merchantId,
            name: item['name'] ?? '',
            phone: item['phone'] ?? '',
            creditLimit: (item['credit_limit'] as num?)?.toDouble() ?? 0.0,
            salaryDay: item['salary_day'],
            existingCustomerId: custId,
          );
          await AppStorage.removePendingLedgerTx(txId, merchantId);
          pendingCreationCustomerIds
              .remove(custId); // 👈 فك الحظر فوراً عن قيود هذا الزبون
          synced++;
          continue;
        }

        if (type == 'delete_customer') {
          await deleteCustomer(
            merchantId: merchantId,
            customerId: custId,
            currentBalance: (item['amount'] as num?)?.toDouble() ?? 0.0,
            isSyncing: true,
          );
          await AppStorage.removePendingLedgerTx(txId, merchantId);
          pendingCreationCustomerIds.remove(custId);
          synced++;
          continue;
        }

        if (type == 'void_request') {
          final targetEntryId = item['target_entry_id']?.toString() ?? '';
          if (targetEntryId.isNotEmpty) {
            try {
              await _sendVoidTransaction(custId, targetEntryId);
            } catch (voidErr) {
              final errText = voidErr.toString().toLowerCase();
              if (errText.contains('not-found') ||
                  errText.contains('already-voided') ||
                  errText.contains('alreadyvoided') ||
                  errText.contains('غير موجود')) {
                debugPrint(
                    'Void target $targetEntryId already voided on server. Removing.');
                await WalService.instance.markCommitted(targetEntryId);
              } else {
                rethrow;
              }
            }
          }
          await AppStorage.removePendingLedgerTx(txId, merchantId);
          synced++;
          continue;
        }

        // 🔒 التحقق الدقيق: تأجيل القيد فقط إذا تعثر إنشاء الزبون مسبقاً في هذه الدورة
        if (pendingCreationCustomerIds.contains(custId)) {
          unresolved++;
          continue;
        }

        // قيود الديون والسداد (debt / payment) - تمر الآن بسلاسة تامة للزبائن الجدد
        await recordTransaction(
          merchantId: item['merchant_id'] ?? merchantId,
          customerId: custId,
          type: type,
          amount: (item['amount'] as num).toDouble(),
          notes: item['notes'],
          items: item['items'] ?? const [],
          transactionId: txId,
          isSyncing: true,
        );
        await AppStorage.removePendingLedgerTx(txId, merchantId);
        synced++;
      } catch (e) {
        final errStr = e.toString().toLowerCase();

        // 🛡️ حظر مسح الديون: لا يُحذف القيد المالي إطلاقاً عند خطأ not-found منعاً لضياع أموال التاجر
        if (errStr.contains('customer_deleted')) {
          await AppStorage.removePendingLedgerTx(txId, merchantId);
          await WalService.instance.markAborted(txId);
          continue;
        }

        // إذا كان خطأ not-found، نحاول التحقق هل الزبون موجود محلياً لإعادة إنشائه بدلاً من شطب الدين
        if (errStr.contains('not-found')) {
          final cachedCustomers = await getCachedCustomers(merchantId);
          final match = cachedCustomers.firstWhere((c) => c.id == custId,
              orElse: () => LedgerCustomer(
                  id: '',
                  merchantId: '',
                  name: '',
                  phone: '',
                  currentBalance: 0,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now()));
          if (match.id.isNotEmpty) {
            try {
              await addCustomer(
                merchantId: merchantId,
                name: match.name,
                phone: match.phone,
                creditLimit: match.creditLimit,
                salaryDay: match.salaryDay,
                existingCustomerId: custId,
              );
            } catch (_) {}
          }
        }
        final isIdempotencyConflict = errStr.contains('already-exists');
        if (isIdempotencyConflict) {
          try {
            if (type == 'add_customer') {
              final doc = await _db
                  .collection('merchant_customers')
                  .doc(custId)
                  .get(const GetOptions(source: Source.server))
                  .timeout(const Duration(seconds: 4));
              if (doc.exists && doc.data()?['merchant_id'] == merchantId) {
                await AppStorage.removePendingLedgerTx(txId, merchantId);
                synced++;
                continue;
              }
            } else if (await _matchesPersistedLedgerIntent(txId, item)) {
              await WalService.instance.markCommitted(txId);
              await AppStorage.removePendingLedgerTx(txId, merchantId);
              synced++;
              continue;
            }
          } catch (_) {}
        }

        unresolved++;
      }
    }

    return LedgerSyncResult(
      syncedCount: synced,
      unresolvedCount: unresolved,
    );
  }

// ─── استماع فوري للقيود مفهرس سحابياً لضمان جلب أحدث الفواتير دائماً ───
  Stream<List<LedgerEntry>> watchCustomerEntries(String customerId,
      {int limit = 50}) {
    final currentMerchantId = AppStorage.userId ?? '';
    final cleanCustomerId = customerId.trim();
    if (cleanCustomerId.isEmpty || currentMerchantId.trim().isEmpty) {
      return const Stream.empty();
    }

    // 🔒 استعلام زمني تنازلي محكم يجلب الدفعة كاملة بحدها الأقصى
    final Query<Map<String, dynamic>> query = _db
        .collection('merchant_ledger_entries')
        .where('merchant_id', isEqualTo: currentMerchantId.trim())
        .where('customer_id', isEqualTo: cleanCustomerId)
        .orderBy('created_at', descending: true)
        .limit(limit);

    return query.snapshots(includeMetadataChanges: true).map((snap) {
      // 🛡️ نحتفظ بجميع الحركات بما فيها المشطوبة كـ Audit-Trail لتفادي بتر عداد الصفحات
      final list = snap.docs
          .where((d) => d.data()['merchant_id'] == currentMerchantId.trim())
          .map((d) => LedgerEntry.fromMap({'id': d.id, ...d.data()}))
          .toList();

      final pendingQueue = AppStorage.getPendingLedgerTxs(currentMerchantId)
          .where((t) => t['customer_id'] == cleanCustomerId);

      final voidedTargetIds = pendingQueue
          .where((p) => p['type'] == 'void_request')
          .map((p) => p['target_entry_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final existingIds = list.map((e) => e.id).toSet();
      for (final p in pendingQueue) {
        final type = p['type']?.toString();
        if (type == 'void_request' ||
            type == 'add_customer' ||
            type == 'delete_customer') continue;
        if (!existingIds.contains(p['id'])) {
          list.add(LedgerEntry.fromMap(p));
        }
      }

      // وسم الحركات المشطوبة في طابور الأوفلاين فوراً دون إتلاف حجم المصفوفة
      for (int i = 0; i < list.length; i++) {
        if (voidedTargetIds.contains(list[i].id)) {
          list[i] = LedgerEntry(
            id: list[i].id,
            merchantId: list[i].merchantId,
            customerId: list[i].customerId,
            type: list[i].type,
            amount: list[i].amount,
            notes: list[i].notes,
            items: list[i].items,
            isVoided: true,
            createdAt: list[i].createdAt,
          );
        }
      }

      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

// ─── إشعار / تذكير محاسبي معتمد عبر واتساب (محصن ضد الأرقام السالبة 100%) ───
  Future<bool> sendWhatsAppReminder({
    required LedgerCustomer customer,
    required String storeName,
    LedgerEntry? lastEntry,
  }) async {
    const arabicDigits = {
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9'
    };
    var phone = customer.phone.replaceAll(RegExp(r'[\s()-]'), '').trim();
    arabicDigits.forEach((ar, en) => phone = phone.replaceAll(ar, en));

    if (phone.isEmpty) return false;

    if (phone.startsWith('0')) phone = phone.substring(1);
    if (!phone.startsWith('967') && !phone.startsWith('+967')) {
      phone = '967$phone';
    }
    phone = phone.replaceAll('+', '');
    final now = DateTime.now();
    final dateStr =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final buffer = StringBuffer();
    final balance = customer.currentBalance;
    final absBalance = balance.abs().round();
    final isCustomerInDebt = balance > 0.01; // عليه دين للمحل
    final isCustomerInCredit = balance < -0.01; // له رصيد دائن (فائض سداد)
    final isCustomerSettled =
        !isCustomerInDebt && !isCustomerInCredit; // خالص تماماً

    // ── حالة 1: إشعار سداد دفعة نقدية (سند قبض رسمي) ──
    if (lastEntry != null && !lastEntry.isDebt) {
      buffer.writeln('🧾 *سند قبض إلكتروني رسمي*');
      buffer.writeln('🏪 *المحل:* $storeName');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln('وصلنا من الأخ/ *${customer.name}* المحترم');
      buffer.writeln('💵 *مبلغ وقدره:* ${lastEntry.amount.round()} ر.ي');
      if (lastEntry.notes != null && lastEntry.notes!.trim().isNotEmpty) {
        buffer.writeln('📝 *البيان:* ${lastEntry.notes!.trim()}');
      }
      buffer.writeln('📅 *التاريخ:* $dateStr ($timeStr)');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━');

      if (isCustomerInCredit) {
        buffer.writeln('✨ *حالة الحساب بعد السداد:*');
        buffer
            .writeln('🟢 *يوجد لكم رصيد فائض (دائن لصالحكم):* $absBalance ر.ي');
        buffer.writeln('جزاكم الله خيراً وبارك في مالكم ورزقكم 🌸');
      } else if (isCustomerSettled) {
        buffer.writeln('✅ *الحساب الآن: خالص تماماً (0 ر.ي)*');
        buffer.writeln('بيض الله وجوهكم وبارك في مالكم ورزقكم 🌸');
      } else {
        buffer.writeln('📊 *الرصيد المتبقي بذمتكم:* $absBalance ر.ي');
        buffer.writeln('شكراً لوفائكم وحسن تعاملكم الدائم 🙏');
      }
    }
    // ── حالة 2: إشعار قيد مشتريات جديدة (فاتورة دين) ──
    else if (lastEntry != null && lastEntry.isDebt) {
      buffer.writeln('🧾 *فاتورة مشتريات بالآجل*');
      buffer.writeln('🏪 *المحل:* $storeName');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln('العميل المحترم: *${customer.name}*');
      buffer.writeln('➕ *مبلغ الفاتورة:* ${lastEntry.amount.round()} ر.ي');
      buffer.writeln('📅 *التاريخ:* $dateStr ($timeStr)');
      if (lastEntry.items.isNotEmpty) {
        buffer.writeln('🛒 *الأصناف المسجلة:*');
        for (final item in lastEntry.items) {
          final name = item['name'] ?? item['product_name'] ?? 'صنف';
          final qty = item['quantity'] ?? 1;
          final unit = item['unit_label'] ?? 'حبة';
          final price = (item['unit_price'] as num?)?.round() ?? 0;
          final total = (item['subtotal'] as num?)?.round() ??
              (price * (qty as num).round());
          buffer.writeln('  • $name: $qty $unit × $price = $total ر.ي');
        }
      } else if (lastEntry.notes != null &&
          lastEntry.notes!.trim().isNotEmpty) {
        buffer.writeln('📝 *البيان:* ${lastEntry.notes!.trim()}');
      }
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━');

      if (isCustomerInCredit) {
        buffer.writeln('💡 *تم خصم الفاتورة من رصيدكم الدائن المسبق.*');
        buffer.writeln('🟢 *المتبقي لصالحكم لدى المحل:* $absBalance ر.ي');
      } else if (isCustomerSettled) {
        buffer.writeln(
            '✅ *تمت تغطية الفاتورة بالكامل من رصيدكم، والحساب الآن خالص (0 ر.ي)*');
      } else {
        buffer.writeln('💰 *إجمالي الرصيد المطلوب بذمتكم:* $absBalance ر.ي');
      }
      buffer.writeln('نسعد دائماً بخدمتكم وتلبية طلباتكم 💐');
    }
    // ── حالة 3: رسالة تذكير ومطابقة دورية ──
    else {
      buffer.writeln(
          'السلام عليكم ورحمة الله وبركاته يا أخي العزيز *${customer.name}* 🌸');
      buffer.writeln('نود إحاطتكم بحالة حسابكم الحالي لدى *($storeName)*:');
      buffer.writeln('📅 *تاريخ المطابقة:* $dateStr');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━');

      if (isCustomerInCredit) {
        buffer.writeln(
            '🟢 *لديكم رصيد دائن (لصالحكم في ذمة المحل) بقيمة:* $absBalance ر.ي');
        buffer.writeln('سعداء بتعاملكم الراقي معنا ونتشرف بخدمتكم دائماً 🙏');
      } else if (isCustomerSettled) {
        buffer.writeln('✅ *حسابكم خالص تماماً (0 ر.ي).*');
        buffer.writeln('شاكرين ومقدرين حسن تعاملكم والتزامكم الدائم 🌸');
      } else {
        buffer.writeln(
            '💰 *المبلغ المتبقي المطلوب سداده بذمتكم:* $absBalance ر.ي');
        buffer.writeln('');
        buffer.writeln(
            'شاكرين ومقدرين حسن تعاملكم ووفائكم المعتاد، وبارك الله في رزقكم 🙏');
      }
    }

    final encodedMessage = Uri.encodeComponent(buffer.toString());
    final whatsappUri =
        Uri.parse('whatsapp://send?phone=$phone&text=$encodedMessage');
    final webUri = Uri.parse('https://wa.me/$phone?text=$encodedMessage');

    try {
      final launchedInApp =
          await canLaunchUrl(whatsappUri) && await launchUrl(whatsappUri);
      final launched = launchedInApp ||
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
      if (!launched) return false;

      unawaited(_functions.httpsCallable('logCustomerReminder').call({
        'customerId': customer.id,
      }));
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('WhatsApp launch error: $e');
      return false;
    }
  }

// ─── تصدير PDF الرسمي المنقح والمضبوط 100% ───
  Future<Uint8List> generateStatementPdfData({
    required LedgerCustomer customer,
    required String storeName,
    required List<LedgerEntry> entries,
  }) async {
    // جلب بايتات الخط من الكاش أو الأصول في الـ Main Isolate مسبقاً لضمان عدم اعتماده على الإنترنت
    Uint8List? regularFontBytes;
    Uint8List? boldFontBytes;
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      regularFontBytes = fontData.buffer
          .asUint8List(fontData.offsetInBytes, fontData.lengthInBytes);
      final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      boldFontBytes = boldData.buffer
          .asUint8List(boldData.offsetInBytes, boldData.lengthInBytes);
    } catch (_) {
      try {
        final f1 = await PdfGoogleFonts.cairoRegular();
        final f2 = await PdfGoogleFonts.cairoBold();
        regularFontBytes = (f1 as dynamic).data as Uint8List?;
        boldFontBytes = (f2 as dynamic).data as Uint8List?;
      } catch (_) {}
    }

    return await compute(_generatePdfIsolate, {
      'customer': customer.toMap(),
      'storeName': storeName,
      'entries': entries.map((e) => e.toMap()).toList(),
      'fontRegular': regularFontBytes,
      'fontBold': boldFontBytes,
    });
  }

  static Future<Uint8List> _generatePdfIsolate(
      Map<String, dynamic> args) async {
    final customer =
        LedgerCustomer.fromMap(args['customer'] as Map<String, dynamic>);
    final storeName = args['storeName'] as String;
    // 🔒 فلترة صارمة: استبعاد أي حركة مشطوبة أو ملغاة نهائياً من حسابات وجداول الـ PDF
    final entries = (args['entries'] as List)
        .map((e) => LedgerEntry.fromMap(e as Map<String, dynamic>))
        .where((e) => !e.isVoided)
        .toList();

    final Uint8List? fontRegularBytes = args['fontRegular'] as Uint8List?;
    final Uint8List? fontBoldBytes = args['fontBold'] as Uint8List?;

    if (fontRegularBytes == null || fontBoldBytes == null) {
      throw StateError(
          'خط القاهرة المعتمد غير محمل محلياً، تأكد من وجود ملفات الخط في assets/fonts');
    }
    final pw.Font regularFont = pw.Font.ttf(fontRegularBytes.buffer.asByteData(
        fontRegularBytes.offsetInBytes, fontRegularBytes.lengthInBytes));
    final pw.Font boldFont = pw.Font.ttf(fontBoldBytes.buffer
        .asByteData(fontBoldBytes.offsetInBytes, fontBoldBytes.lengthInBytes));
    final pdf = pw.Document();
    final now = DateTime.now();

    String getArabicDayName(DateTime dt) {
      switch (dt.weekday) {
        case DateTime.saturday:
          return 'السبت';
        case DateTime.sunday:
          return 'الأحد';
        case DateTime.monday:
          return 'الاثنين';
        case DateTime.tuesday:
          return 'الثلاثاء';
        case DateTime.wednesday:
          return 'الأربعاء';
        case DateTime.thursday:
          return 'الخميس';
        case DateTime.friday:
          return 'الجمعة';
        default:
          return '';
      }
    }

    String formatTime12H(DateTime dt) {
      final hour24 = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      var hour12 = hour24 % 12;
      if (hour12 == 0) hour12 = 12;
      final period = hour24 >= 12 ? 'م' : 'ص';
      return '$hour12:$minute $period';
    }

    final dayName = getArabicDayName(now);
    final dateStr =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    final timeStr = formatTime12H(now);

    // ── 1. حساب إجماليات الفترة ──
    double periodTotalDebt = 0.0;
    double periodTotalPayment = 0.0;
    for (final e in entries) {
      if (e.isDebt) {
        periodTotalDebt += e.amount;
      } else {
        periodTotalPayment += e.amount;
      }
    }

    // ── 2. ترتيب الحركات زمنياً تصاعدياً لحساب الأرصدة التراكمية، ثم قلبها للعرض ──
    final chronologicalEntries = List<LedgerEntry>.from(entries)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final double openingBalance = LedgerCustomer.sanitizeAmount(
      customer.currentBalance - (periodTotalDebt - periodTotalPayment),
    );

    double rollingBalance = openingBalance;
    final List<Map<String, dynamic>> calculatedRows = [];

    for (final e in chronologicalEntries) {
      if (e.isDebt) {
        rollingBalance += e.amount;
      } else {
        rollingBalance -= e.amount;
      }
      calculatedRows.add({
        'entry': e,
        'balanceAfter': rollingBalance,
      });
    }

    final displayRows = calculatedRows.reversed.toList();
    final List<List<dynamic>> tableRows = [];

    for (int i = 0; i < displayRows.length; i++) {
      final rowData = displayRows[i];
      final e = rowData['entry'] as LedgerEntry;
      final balanceAfterThisTx = rowData['balanceAfter'] as double;
      final eDate =
          '${e.createdAt.year}/${e.createdAt.month.toString().padLeft(2, '0')}/${e.createdAt.day.toString().padLeft(2, '0')}';
      final eTime = formatTime12H(e.createdAt);

      // ── الحالة 1: فاتورة فيها أصناف متعددة (إظهار كل صنف بكميته وسعره وإجماليه) ──
      if (e.items.isNotEmpty && e.items.length > 1) {
        tableRows.add([
          '${i + 1}',
          '$eDate\n$eTime',
          'فاتورة مشتريات بالدين (${e.items.length} أصناف)',
          '—',
          '—',
          '+ ${e.amount.toStringAsFixed(0)} ريال',
          '${balanceAfterThisTx.toStringAsFixed(0)} ريال',
        ]);

        for (final item in e.items) {
          final pName =
              (item['name'] ?? item['product_name'] ?? 'صنف').toString().trim();
          final q = item['quantity'] ?? 1;
          final u = (item['unit_label'] ?? 'حبة').toString().trim();
          final uPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
          final subtotal =
              (item['subtotal'] as num?)?.toDouble() ?? (uPrice * (q as num));

          tableRows.add([
            '',
            '',
            '  ↳ $pName',
            '$q $u',
            '${uPrice.toStringAsFixed(0)} ريال',
            '${subtotal.toStringAsFixed(0)} ريال',
            '',
          ]);
        }
      }
      // ── الحالة 2: صنف واحد (يُكتب مباشرة: الكمية والسعر والإجمالي في نفس السطر) ──
      else if (e.items.length == 1) {
        final it = e.items.first;
        final pName =
            (it['name'] ?? it['product_name'] ?? 'صنف').toString().trim();
        final q = it['quantity'] ?? 1;
        final u = (it['unit_label'] ?? 'حبة').toString().trim();
        final uPrice = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
        final subtotal =
            (it['subtotal'] as num?)?.toDouble() ?? (uPrice * (q as num));

        tableRows.add([
          '${i + 1}',
          '$eDate\n$eTime',
          pName,
          '$q $u',
          '${uPrice.toStringAsFixed(0)} ريال',
          '+ ${subtotal.toStringAsFixed(0)} ريال',
          '${balanceAfterThisTx.toStringAsFixed(0)} ريال',
        ]);
      }
      // ── الحالة 3: سداد نقدي أو دين مباشر بدون أصناف ──
      else {
        final isDebt = e.isDebt;
        String desc = '';
        if (e.notes != null && e.notes!.trim().isNotEmpty) {
          desc = e.notes!.trim();
        } else {
          desc = isDebt ? 'مشتريات بالدين' : 'سداد دفعة نقدية';
        }

        tableRows.add([
          '${i + 1}',
          '$eDate\n$eTime',
          desc,
          '—',
          '—',
          '${isDebt ? '+' : '-'} ${e.amount.toStringAsFixed(0)} ريال',
          '${balanceAfterThisTx.toStringAsFixed(0)} ريال',
        ]);
      }
    }

    if (openingBalance.abs() > 0.01) {
      tableRows.add([
        '—',
        '—',
        'رصيد افتتاحي سابق مرحّل',
        '—',
        '—',
        '—',
        '${openingBalance.toStringAsFixed(0)} ريال',
      ]);
    }
    final qrPayload =
        'SALA|STORE:$storeName|CUST:${customer.name}|BAL:${customer.currentBalance.toStringAsFixed(0)}|DATE:$dateStr';

    // ── 3. بناء صفحات PDF مع تجزئة الودجتس لمنع قفز الجدول (حل الملاحظة 3) ──
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        header: (context) {
          if (context.pageNumber == 1) return pw.SizedBox.shrink();
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F5F5F5'),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('كشف حساب الزبون: ${customer.name}',
                      style: pw.TextStyle(font: boldFont, fontSize: 8.5)),
                  pw.Text(
                      'تابع الحركات — صفحة ${context.pageNumber} من ${context.pagesCount}',
                      style: pw.TextStyle(font: regularFont, fontSize: 8)),
                ],
              ),
            ),
          );
        },
        build: (context) => [
          // ── ترويسة الصفحة الأولى المدمجة ──
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#1B8E3D'),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.white,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Text('تطبيق سَـلَّـة',
                                style: pw.TextStyle(
                                    font: boldFont,
                                    fontSize: 10,
                                    color: PdfColor.fromHex('#1B8E3D'))),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Text('كشف حساب مالي معتمد',
                              style: pw.TextStyle(
                                  font: boldFont,
                                  fontSize: 12,
                                  color: PdfColors.white)),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('المتجر / البائع: $storeName',
                          style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 11,
                              color: PdfColor.fromHex('#E8F5ED'))),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#146B2E'),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text('$dayName $dateStr - $timeStr',
                        style: pw.TextStyle(
                            font: boldFont,
                            fontSize: 8.5,
                            color: PdfColors.white)),
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 6),

          // ── بيانات العميل والباركود في شريط مدمج ──
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8F9FA'),
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColor.fromHex('#E5E7EB')),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('الزبون: ${customer.name}',
                          style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 12,
                              color: PdfColor.fromHex('#111827'))),
                      pw.Row(
                        children: [
                          pw.Text(
                              'الهاتف: ${customer.phone.isNotEmpty ? customer.phone : "غير مسجل"}',
                              style: pw.TextStyle(
                                  font: regularFont,
                                  fontSize: 9,
                                  color: PdfColors.grey700)),
                          if (customer.creditLimit > 0) ...[
                            pw.SizedBox(width: 12),
                            pw.Text(
                                'سقف الدين: ${customer.creditLimit.toStringAsFixed(0)} ريال',
                                style: pw.TextStyle(
                                    font: boldFont,
                                    fontSize: 9,
                                    color: PdfColor.fromHex('#B91C1C'))),
                          ],
                        ],
                      ),
                    ],
                  ),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: qrPayload,
                    width: 38,
                    height: 38,
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 6),

          // ── الكروت الثلاثة بحجم اقتصادي يترك أكثر من 600pt للجدول في الصفحة الأولى ──
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 6, horizontal: 8),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#FFF5F5'),
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColor.fromHex('#FECACA')),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text('إجمالي المشتريات (ديون)',
                            style: pw.TextStyle(
                                font: regularFont,
                                fontSize: 8.5,
                                color: PdfColors.red900)),
                        pw.Text('${periodTotalDebt.toStringAsFixed(0)} ريال',
                            style: pw.TextStyle(
                                font: boldFont,
                                fontSize: 12,
                                color: PdfColors.red800)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 6, horizontal: 8),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#F0FDF4'),
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColor.fromHex('#BBF7D0')),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text('إجمالي المدفوعات (سداد)',
                            style: pw.TextStyle(
                                font: regularFont,
                                fontSize: 8.5,
                                color: PdfColors.green900)),
                        pw.Text('${periodTotalPayment.toStringAsFixed(0)} ريال',
                            style: pw.TextStyle(
                                font: boldFont,
                                fontSize: 12,
                                color: PdfColors.green800)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 6, horizontal: 8),
                    decoration: pw.BoxDecoration(
                      color: customer.currentBalance > 0
                          ? PdfColor.fromHex('#FEF2F2')
                          : PdfColor.fromHex('#F0FDF4'),
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(
                        color: customer.currentBalance > 0
                            ? PdfColors.red
                            : PdfColors.green,
                        width: 1.2,
                      ),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          customer.currentBalance >= 0
                              ? 'الرصيد المتبقي (مطلوب)'
                              : 'رصيد دائن (له)',
                          style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 8.5,
                              color: customer.currentBalance > 0
                                  ? PdfColors.red900
                                  : PdfColors.green900),
                        ),
                        pw.Text(
                          '${customer.currentBalance.abs().toStringAsFixed(0)} ريال',
                          style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 13,
                              color: customer.currentBalance > 0
                                  ? PdfColors.red900
                                  : PdfColors.green900),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
// ── جدول الحركات التفصيلي المحاسبي بالأعمدة السبعة المعتمدة ──
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.TableHelper.fromTextArray(
              headers: [
                'م',
                'التاريخ والوقت',
                'البيان / الصنف',
                'الكمية',
                'السعر',
                'الإجمالي',
                'الرصيد المتبقي',
              ],
              data: tableRows,
              columnWidths: {
                0: const pw.FixedColumnWidth(20),
                1: const pw.FixedColumnWidth(65),
                2: const pw.FlexColumnWidth(3.5),
                3: const pw.FixedColumnWidth(50),
                4: const pw.FixedColumnWidth(55),
                5: const pw.FixedColumnWidth(65),
                6: const pw.FixedColumnWidth(70),
              },
              headerStyle: pw.TextStyle(
                  font: boldFont, fontSize: 8.5, color: PdfColors.white),
              headerDecoration:
                  pw.BoxDecoration(color: PdfColor.fromHex('#1B8E3D')),
              cellStyle: pw.TextStyle(font: regularFont, fontSize: 8),
              cellAlignment: pw.Alignment.center,
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.center,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.center,
                4: pw.Alignment.center,
                5: pw.Alignment.center,
                6: pw.Alignment.center,
              },
              headerHeight: 22,
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
              rowDecoration: pw.BoxDecoration(color: PdfColors.white),
              oddRowDecoration:
                  pw.BoxDecoration(color: PdfColor.fromHex('#FAFAFA')),
            ),
          ),
          pw.SizedBox(height: 14),

          // ── تذييل التوقيع والاعتماد ──
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('ختم وتوقيع المحل: ...............................',
                    style: pw.TextStyle(
                        font: regularFont,
                        fontSize: 8.5,
                        color: PdfColors.grey700)),
                pw.Text(
                    'توقيع الزبون بالمطابقة: ...............................',
                    style: pw.TextStyle(
                        font: regularFont,
                        fontSize: 8.5,
                        color: PdfColors.grey700)),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> shareCustomerStatementPdf({
    required LedgerCustomer customer,
    required String storeName,
    required List<LedgerEntry> entries,
  }) async {
    final pdfBytes = await generateStatementPdfData(
      customer: customer,
      storeName: storeName,
      entries: entries,
    );

    final safeName = customer.name
        .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '')
        .replaceAll(' ', '_');
    final fileName = 'كشف_حساب_${safeName}.pdf';

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: fileName,
    );
  }

  Future<void> printOrPreviewStatementPdf({
    required LedgerCustomer customer,
    required String storeName,
    required List<LedgerEntry> entries,
  }) async {
    final pdfBytes = await generateStatementPdfData(
      customer: customer,
      storeName: storeName,
      entries: entries,
    );

    final safeName = customer.name
        .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '')
        .replaceAll(' ', '_');

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'كشف_حساب_$safeName',
    );
  }
}
