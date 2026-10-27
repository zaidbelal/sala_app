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

class LedgerService {
  LedgerService._();
  static final instance = LedgerService._();
  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  // 🔒 مصفوفة ذاكرة لحجب الزبائن المحذوفين فورياً في 0ms ومنع ظهورهم نهائياً
  final Set<String> _locallyDeletedCustomerIds = {};

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

      // 🛡️ دمج الكاش المحلي مع استبعاد أي زبون محذوف نهائياً لمنع انبعاثه
      final existingLocalCached = await getCachedCustomers(cleanMerchantId);
      for (final cached in existingLocalCached) {
        if (deletedCustomerIds.contains(cached.id) ||
            _locallyDeletedCustomerIds.contains(cached.id) ||
            pendingDeletes.contains(cached.id)) continue;
        if (!serverMap.containsKey(cached.id)) {
          serverMap[cached.id] = cached;
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

      // 🔒 التحقق المحاسبي: إضافة فوارق الأوفلاين فقط للحركات التي لم يُقيدها السيرفر بعد
      final pendingTxs = allPending
          .where((t) => t['type'] == 'debt' || t['type'] == 'payment');

      for (final entry in serverMap.entries) {
        final c = entry.value;
        final docRaw = serverDocRaws[c.id];
        final appliedIds = (docRaw?['applied_tx_ids'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toSet();
        final lastTxId = docRaw?['last_transaction_id']?.toString();
        if (lastTxId != null && lastTxId.isNotEmpty) {
          appliedIds.add(lastTxId);
        }

        final unappliedPending = pendingTxs.where((tx) {
          if (tx['customer_id'] != c.id) return false;
          final txId = tx['id']?.toString() ?? '';
          return !appliedIds.contains(txId);
        });

        double delta = 0.0;
        for (final tx in unappliedPending) {
          final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
          delta += (tx['type'] == 'debt') ? amt : -amt;
        }

        if (delta != 0.0) {
          serverMap[c.id] = LedgerCustomer(
            id: c.id,
            merchantId: c.merchantId,
            name: c.name,
            phone: c.phone,
            currentBalance: sanitizeMoney(c.currentBalance + delta),
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
      final now = DateTime.now();
      final customer = LedgerCustomer(
        id: clientGeneratedId,
        merchantId: merchantId,
        name: cleanName,
        phone: phone.trim(),
        currentBalance: 0.0,
        creditLimit: sanitizeMoney(creditLimit),
        salaryDay: salaryDay,
        createdAt: now,
        updatedAt: now,
      );
      final cached = await getCachedCustomers(merchantId);
      final existsIdx = cached.indexWhere((c) => c.id == clientGeneratedId);
      if (existsIdx != -1) {
        cached[existsIdx] = customer;
      } else {
        cached.insert(0, customer);
      }
      await _cacheCustomersLocally(merchantId, cached);

      await AppStorage.savePendingLedgerTx({
        'id': 'cust_$clientGeneratedId',
        'merchant_id': merchantId,
        'customer_id': clientGeneratedId,
        'type': 'add_customer',
        'name': cleanName,
        'phone': phone.trim(),
        'credit_limit': creditLimit,
        'salary_day': salaryDay,
        'created_at': now
            .toIso8601String(), // 👈 تثبيت الختم الزمني لضبط ترتيب طابور المزامنة
      });
      return;
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
      // 🛡️ تأمين أوفلاين فوري: حفظ الزبون محلياً وفي طابور المزامنة في حال تعثر الشبكة اللحظي
      final now = DateTime.now();
      final customer = LedgerCustomer(
        id: clientGeneratedId,
        merchantId: merchantId,
        name: cleanName,
        phone: phone.trim(),
        currentBalance: 0.0,
        creditLimit: sanitizeMoney(creditLimit),
        salaryDay: salaryDay,
        createdAt: now,
        updatedAt: now,
      );
      final cached = await getCachedCustomers(merchantId);
      final existsIdx = cached.indexWhere((c) => c.id == clientGeneratedId);
      if (existsIdx != -1) {
        cached[existsIdx] = customer;
      } else {
        cached.insert(0, customer);
      }
      await _cacheCustomersLocally(merchantId, cached);

      await AppStorage.savePendingLedgerTx({
        'id': 'cust_$clientGeneratedId',
        'merchant_id': merchantId,
        'customer_id': clientGeneratedId,
        'type': 'add_customer',
        'name': cleanName,
        'phone': phone.trim(),
        'credit_limit': creditLimit,
        'salary_day': salaryDay,
      });
    }
  }

// ─── حذف زبون من الدفتر سحابياً ومحلياً مع ضمان الاختفاء الفوري (0ms) ───
  Future<void> deleteCustomer({
    required String merchantId,
    required String customerId,
    double currentBalance = 0.0,
  }) async {
    final cleanMerchantId = merchantId.trim();
    final cleanCustomerId = customerId.trim();
    if (cleanCustomerId.isEmpty || cleanMerchantId.isEmpty) return;

    // 1. الإخفاء الفوري اللحظي من شاشة المستخدم وقوائم التطبيق (0ms)
    _locallyDeletedCustomerIds.add(cleanCustomerId);

    // 2. الحذف الفوري من كاش القرص الصلب بالهاتف
    final cached = await getCachedCustomers(cleanMerchantId);
    cached.removeWhere((c) => c.id == cleanCustomerId);
    await _cacheCustomersLocally(cleanMerchantId, cached);

    // 3. تحديث مباشر وفوري في Firestore لوثيقة الزبون لتختفي من تدفقات البيانات فوراً
    try {
      await _db.collection('merchant_customers').doc(cleanCustomerId).update({
        'is_deleted': true,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    // 4. استدعاء السيرفر لتسوية ديون السوق أو حفظها في طابور الأوفلاين
    final hasInternet = await ConnectivityHelper.hasActiveInternet();
    if (!hasInternet) {
      await AppStorage.savePendingLedgerTx({
        'id': 'del_$cleanCustomerId',
        'merchant_id': cleanMerchantId,
        'customer_id': cleanCustomerId,
        'type': 'delete_customer',
        'amount': currentBalance,
      });
      return;
    }

    try {
      final callable = _functions.httpsCallable(
        'deleteLedgerCustomer',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );
      await callable.call({'customerId': cleanCustomerId});
    } catch (_) {
      await AppStorage.savePendingLedgerTx({
        'id': 'del_$cleanCustomerId',
        'merchant_id': cleanMerchantId,
        'customer_id': cleanCustomerId,
        'type': 'delete_customer',
        'amount': currentBalance,
      });
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

    // 🔒 التحقق المحاسبي من سقف الائتمان أوفلاين ومحلياً
    if (cleanType == 'debt') {
      final cached = await getCachedCustomers(cleanMerchantId);
      final idx = cached.indexWhere((c) => c.id == cleanCustomerId);
      if (idx != -1) {
        final cust = cached[idx];
        if (cust.creditLimit > 0 &&
            (cust.currentBalance + safeAmount) > cust.creditLimit) {
          debugPrint(
              '⚠️ تحذير: المعاملة تجاوزت سقف الدين المحدد (${cust.creditLimit})');
        }
      }
    }

    final autoId = _db.collection('merchant_ledger_entries').doc().id;
    final entryId = (transactionId != null && transactionId.trim().isNotEmpty)
        ? transactionId.trim()
        : 'ledger_${cleanMerchantId.substring(0, cleanMerchantId.length > 5 ? 5 : cleanMerchantId.length)}_${DateTime.now().millisecondsSinceEpoch}_$autoId';

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

    // 🔒 1. تدوين نية المعاملة في WAL
    await WalService.instance.writeIntent(
      transactionId: entryId,
      type: WalOperationType.ledgerTransaction,
      payload: payload,
    );
    final hasInternet = await ConnectivityHelper.hasActiveInternet();

    // ── في وضع عدم الاتصال (أوفلاين) ──
    if (!hasInternet) {
      await AppStorage.savePendingLedgerTx(payload);

      if (!kIsWeb) {
        final prevFileLock = _durableFileLock;
        final fileCompleter = Completer<void>();
        _durableFileLock = fileCompleter.future;
        try {
          await prevFileLock;
        } catch (_) {}

        try {
          final dir = await getApplicationDocumentsDirectory();
          final durableFile =
              File('${dir.path}/ledger_durable_journal_$cleanMerchantId.db');
          final line = '${jsonEncode(payload)}\n';
          await durableFile.writeAsString(line,
              mode: FileMode.append, flush: true);
        } catch (_) {
        } finally {
          fileCompleter.complete();
        }
      }

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
      // 🔒 رمي استثناء حتمي لمنع دالة syncPendingLedgerQueue من حذف القيد قبل وصوله للسيرفر
      throw TimeoutException('لا يوجد اتصال بالإنترنت، تم تأمين القيد أوفلاين');
    }
// ── في وضع الاتصال: استدعاء الدالة السحابية الرسمية مع تحصين كامل ضد انقطاع الشبكة ──
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
      final isFatalBusinessError = err.contains('not_found') ||
          err.contains('permission-denied') ||
          err.contains('invalid-argument') ||
          err.contains('unauthenticated');

      // 🛡️ حفظ القيد في طابور الأوفلاين لأي خطأ شبكي مهما كان نوعه (Socket / DNS / Timeout / Drop)
      if (!isFatalBusinessError) {
        await AppStorage.savePendingLedgerTx(payload);
        if (!kIsWeb) {
          try {
            final dir = await getApplicationDocumentsDirectory();
            final durableFile =
                File('${dir.path}/ledger_durable_journal_$cleanMerchantId.db');
            final alreadyLogged = await durableFile.exists() &&
                (await durableFile.readAsString()).contains('"id":"$entryId"');
            if (!alreadyLogged) {
              final line = '${jsonEncode(payload)}\n';
              await durableFile.writeAsString(line,
                  mode: FileMode.append, flush: true);
            }
          } catch (_) {}
        }
        throw TimeoutException(
            'تعثر الاتصال بالسيرفر، تم تأمين القيد المالي في طابور الأوفلاين بنجاح');
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
    double? knownAmount,
    bool? knownIsDebt,
  }) async {
    final cleanMerchantId = merchantId.trim();
    final cleanCustomerId = customerId.trim();
    final cleanEntryId = entryId.trim();
// 1. فحص طابور الأوفلاين: إذا كانت العملية محلية فقط ولم ترسل للسيرفر، يتم إلغاؤها دون جدولة void_request
    final pendingQueue = AppStorage.getPendingLedgerTxs(cleanMerchantId);
    final pendingIdx = pendingQueue.indexWhere((t) => t['id'] == cleanEntryId);
    if (pendingIdx != -1) {
      final pendingItem = pendingQueue[pendingIdx];
      final amt = sanitizeMoney((pendingItem['amount'] as num).toDouble());
      final isDebt = pendingItem['type'] == 'debt';
      final reverseDelta = isDebt ? -amt : amt;

      // إزالة الحركة نهائياً من الطابور دون إرسال طلب شطب وهمي للسيرفر
      await AppStorage.removePendingLedgerTx(cleanEntryId, cleanMerchantId);

      final prevFileLock = _durableFileLock;
      final fileCompleter = Completer<void>();
      _durableFileLock = fileCompleter.future;
      try {
        await prevFileLock;
      } catch (_) {}

      try {
        if (!kIsWeb) {
          final dir = await getApplicationDocumentsDirectory();
          final durableFile =
              File('${dir.path}/ledger_durable_journal_$cleanMerchantId.db');
          final voidMarker = jsonEncode({
            'id': cleanEntryId,
            'customer_id': cleanCustomerId,
            'merchant_id': cleanMerchantId,
            'action': 'void_local',
            'is_voided': true,
            'timestamp': DateTime.now().toIso8601String(),
          });
          await durableFile.writeAsString('$voidMarker\n',
              mode: FileMode.append, flush: true);
        }
      } catch (_) {
      } finally {
        fileCompleter.complete();
      }

      final cached = await getCachedCustomers(cleanMerchantId);
      final cIdx = cached.indexWhere((c) => c.id == cleanCustomerId);
      if (cIdx != -1) {
        final old = cached[cIdx];
        cached[cIdx] = LedgerCustomer(
          id: old.id,
          merchantId: old.merchantId,
          name: old.name,
          phone: old.phone,
          currentBalance: sanitizeMoney(old.currentBalance + reverseDelta),
          creditLimit: old.creditLimit,
          salaryDay: old.salaryDay,
          lastReminderSentAt: old.lastReminderSentAt,
          createdAt: old.createdAt,
          updatedAt: DateTime.now(),
        );
        await _cacheCustomersLocally(cleanMerchantId, cached);
      }
      return;
    }
    final hasInternet = await ConnectivityHelper.hasActiveInternet();
    final targetAmount = knownAmount ?? 0.0;
    final isDebtTarget = knownIsDebt ?? true;

    // 🔒 تدوين نية الإبطال في WAL فوراً سواء كان الهاتف متصلاً أو أوفلاين
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

    if (!hasInternet) {
      await AppStorage.savePendingLedgerTx({
        'id': 'void_$cleanEntryId',
        'merchant_id': cleanMerchantId,
        'customer_id': cleanCustomerId,
        'type': 'void_request',
        'target_entry_id': cleanEntryId,
        'amount': targetAmount,
        'is_debt': isDebtTarget,
      });

      final cached = await getCachedCustomers(cleanMerchantId);
      final cIdx = cached.indexWhere((c) => c.id == cleanCustomerId);
      if (cIdx != -1) {
        final old = cached[cIdx];
        final reverseDelta = isDebtTarget ? -targetAmount : targetAmount;
        cached[cIdx] = LedgerCustomer(
          id: old.id,
          merchantId: old.merchantId,
          name: old.name,
          phone: old.phone,
          currentBalance: sanitizeMoney(old.currentBalance + reverseDelta),
          creditLimit: old.creditLimit,
          salaryDay: old.salaryDay,
          lastReminderSentAt: old.lastReminderSentAt,
          createdAt: old.createdAt,
          updatedAt: DateTime.now(),
        );
        await _cacheCustomersLocally(cleanMerchantId, cached);
      }
      return;
    }
    try {
      final callable = _functions.httpsCallable(
        'voidLedgerTransaction',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );

      await callable.call({
        'customerId': cleanCustomerId,
        'entryId': cleanEntryId,
      });

      await WalService.instance.markCommitted(cleanEntryId);
    } catch (e) {
      // 🛡️ حفظ طلب الشطب في طابور الأوفلاين عند تعثر الاتصال بالسيرفر
      await AppStorage.savePendingLedgerTx({
        'id': 'void_$cleanEntryId',
        'merchant_id': cleanMerchantId,
        'customer_id': cleanCustomerId,
        'type': 'void_request',
        'target_entry_id': cleanEntryId,
        'amount': targetAmount,
        'is_debt': isDebtTarget,
      });

      final cached = await getCachedCustomers(cleanMerchantId);
      final cIdx = cached.indexWhere((c) => c.id == cleanCustomerId);
      if (cIdx != -1) {
        final old = cached[cIdx];
        final reverseDelta = isDebtTarget ? -targetAmount : targetAmount;
        cached[cIdx] = LedgerCustomer(
          id: old.id,
          merchantId: old.merchantId,
          name: old.name,
          phone: old.phone,
          currentBalance: sanitizeMoney(old.currentBalance + reverseDelta),
          creditLimit: old.creditLimit,
          salaryDay: old.salaryDay,
          lastReminderSentAt: old.lastReminderSentAt,
          createdAt: old.createdAt,
          updatedAt: DateTime.now(),
        );
        await _cacheCustomersLocally(cleanMerchantId, cached);
      }
      throw TimeoutException(
          'تعثر الاتصال بالسيرفر، تم حفظ طلب الشطب في طابور الأوفلاين');
    }
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
// قفل تزامني خاص بملف اليومية الدائم لمنع تضارب القراءة والكتابة
  static Future<void> _durableFileLock = Future.value();

  Future<int> syncPendingLedgerQueue(String merchantId) async {
    final Map<String, Map<String, dynamic>> unifiedQueue = {};
// 1. قراءة الطابور المخزن محلياً في SharedPreferences أولاً
    for (final item in AppStorage.getPendingLedgerTxs(merchantId)) {
      final id = item['id']?.toString() ?? '';
      if (id.isNotEmpty) unifiedQueue[id] = item;
    }

    // 2. دمج كافة القيود والعمليات المحفوظة في ملف القرص الصلب الدائم قبل الترتيب والفرز
    File? durableFile;
    if (!kIsWeb) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        durableFile = File('${dir.path}/ledger_durable_journal_$merchantId.db');
        if (await durableFile.exists()) {
          final lines = await durableFile.readAsLines();
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            try {
              final item = Map<String, dynamic>.from(jsonDecode(line.trim()));
              final id = item['id']?.toString() ?? '';
              if (id.isEmpty) continue;
              if (item['action'] == 'void_local' || item['is_voided'] == true) {
                unifiedQueue.remove(id);
              } else if (!unifiedQueue.containsKey(id)) {
                unifiedQueue[id] = item;
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    if (unifiedQueue.isEmpty) return 0;

    // 🔒 الترتيب الزمني الفعلي لكامل الطابور الموحد (SharedPreferences + ملف القرص الدائم معاً)
    final sortedQueueList = unifiedQueue.values.toList()
      ..sort((a, b) {
        final aTime = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime(2000);
        final bTime = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime(2000);
        return aTime.compareTo(bTime);
      });

    int synced = 0;
    final List<String> successfullySyncedIds = [];

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
          successfullySyncedIds.add(txId);
          synced++;
          continue;
        }
        if (type == 'delete_customer') {
          await deleteCustomer(
            merchantId: merchantId,
            customerId: custId,
            currentBalance: (item['amount'] as num?)?.toDouble() ?? 0.0,
          );
          await AppStorage.removePendingLedgerTx(txId, merchantId);
          successfullySyncedIds.add(txId);
          synced++;
          continue;
        }
        if (type == 'void_request') {
          final targetEntryId = item['target_entry_id']?.toString() ?? '';
          if (targetEntryId.isNotEmpty) {
            try {
              await voidTransaction(
                merchantId: merchantId,
                customerId: custId,
                entryId: targetEntryId,
                knownAmount: (item['amount'] as num?)?.toDouble(),
                knownIsDebt: item['is_debt'] != false,
              );
            } catch (voidErr) {
              final errText = voidErr.toString().toLowerCase();
              // إذا كان القيد غير موجود على السيرفر أصلاً (أُنشئ وحُذف أوفلاين)، نعتبر الإلغاء ناجحاً
              if (errText.contains('not-found') ||
                  errText.contains('غير موجود')) {
                debugPrint(
                    'Void target $targetEntryId was never on server. Clearing from queue.');
              } else {
                rethrow;
              }
            }
          }
          await AppStorage.removePendingLedgerTx(txId, merchantId);
          successfullySyncedIds.add(txId);
          synced++;
          continue;
        }

        await recordTransaction(
          merchantId: item['merchant_id'] ?? merchantId,
          customerId: custId,
          type: type,
          amount: (item['amount'] as num).toDouble(),
          notes: item['notes'],
          items: item['items'] ?? const [],
          transactionId: txId,
        );
        await AppStorage.removePendingLedgerTx(txId, merchantId);
        successfullySyncedIds.add(txId);
        synced++;
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        final bool isTerminalError = errStr.contains('alreadyrecorded') ||
            errStr.contains('alreadyvoided') ||
            errStr.contains('already-exists') ||
            errStr.contains('customer_deleted') ||
            errStr.contains('not-found');

        if (isTerminalError) {
          // إزالة المعاملة التي حُذف زبونها أو سُجلت مسبقاً لمنع حبس وتسميم الطابور للأبد
          await AppStorage.removePendingLedgerTx(txId, merchantId);
          successfullySyncedIds.add(txId);
          synced++;
        } else {
          if (kDebugMode) {
            debugPrint('⚠️ تأجيل مزامنة القيد $txId لحين استقرار الاتصال: $e');
          }
        }
      }
    }
// 3. إعادة كتابة ملف القرص الدائم داخل قفل Mutex لقراءة التعديلات اللحظية الطازجة
    if (!kIsWeb && durableFile != null && successfullySyncedIds.isNotEmpty) {
      final prevLock = _durableFileLock;
      final completer = Completer<void>();
      _durableFileLock = completer.future;
      try {
        await prevLock;
      } catch (_) {}

      try {
        final syncedSet = successfullySyncedIds.toSet();
        // قراءة الملف مجدداً داخل القفل لالتقاط أي عمليات كُتبت أثناء استجابة الشبكة
        final freshLines = await durableFile.exists()
            ? await durableFile.readAsLines()
            : <String>[];
        final remainingLines = <String>[];

        for (final line in freshLines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          try {
            final entry = jsonDecode(trimmed);
            final id = entry['id']?.toString() ?? '';
            if (!syncedSet.contains(id)) {
              remainingLines.add(trimmed);
            }
          } catch (_) {
            remainingLines.add(trimmed);
          }
        }

        final tempFile = File(
            '${durableFile.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
        await tempFile.writeAsString(
          remainingLines.isEmpty ? '' : '${remainingLines.join('\n')}\n',
          flush: true,
        );
        if (remainingLines.isEmpty) {
          if (await durableFile.exists()) await durableFile.delete();
          if (await tempFile.exists()) await tempFile.delete();
        } else {
          await tempFile.rename(durableFile.path);
        }
      } catch (e) {
        debugPrint('⚠️ فشل التحديث الذري لملف اليومية الدائم: $e');
      } finally {
        completer.complete();
      }
    }

    return synced;
  }

// ─── استماع فوري للقيود محصن أمنياً ومطابق لقواعد Firestore الصارمة ───
  Stream<List<LedgerEntry>> watchCustomerEntries(String customerId,
      {int limit = 50}) {
    final currentMerchantId = AppStorage.userId ?? '';
    final cleanCustomerId = customerId.trim();
    if (cleanCustomerId.isEmpty || currentMerchantId.trim().isEmpty) {
      return const Stream.empty();
    }
// 🛡️ استعلام مؤمن وفوري بدون اشتراط فهارس مركبة معقدة
    // 🔒 استعلام يعتمد فقط على شروط المساواة دون إجبار Firestore على فهرس مركب
    // الفرز يتم في الذاكرة المحلية (In-Memory) مما يمنع خطأ FAILED_PRECONDITION نهائياً
    // 🔒 استعلام مفهرس سحابياً تنازلياً يضمن جلب أحدث الحركات فوراً مهما بلغت آلاف السجلات
// 🔒 استعلام خفيف لا يتطلب أي Composite Index على السيرفر ويمنع FAILED_PRECONDITION
    final Query<Map<String, dynamic>> query = _db
        .collection('merchant_ledger_entries')
        .where('merchant_id', isEqualTo: currentMerchantId.trim())
        .where('customer_id', isEqualTo: cleanCustomerId)
        .orderBy('created_at', descending: true)
        .limit(limit);

    return query.snapshots(includeMetadataChanges: true).map((snap) {
      final list = snap.docs
          .where((d) =>
              d.data()['merchant_id'] == currentMerchantId.trim() &&
              d.data()['is_voided'] != true)
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

      if (voidedTargetIds.isNotEmpty) {
        list.removeWhere((e) => voidedTargetIds.contains(e.id));
      }

      // فرز نهائي لدمج حركات الأوفلاين الأحدث في القمة
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

// ─── إشعار / تذكير محاسبي معتمد عبر واتساب ───
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
      if (customer.currentBalance <= 0) {
        buffer.writeln('✅ *الحساب الآن: خالص تماماً (0 ر.ي)*');
        buffer.writeln('جزاكم الله خيراً وبارك الله في مالكم ورزقكم 🌸');
      } else {
        buffer.writeln(
            '📊 *الرصيد المتبقي بذمتكم:* ${customer.currentBalance.round()} ر.ي');
        buffer.writeln('شكراً لوفائكم وحسن تعاملكم 🙏');
      }
    }
    // ── حالة 2: إشعار قيد مشتريات جديدة (فاتورة دين) ──
    else if (lastEntry != null && lastEntry.isDebt) {
      buffer.writeln('🧾 *فاتورة مشتريات بالآجل (دين)*');
      buffer.writeln('🏪 *المحل:* $storeName');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln('العميل المحترم: *${customer.name}*');
      buffer.writeln(
          '➕ *مبلغ الفاتورة الجديدة:* ${lastEntry.amount.round()} ر.ي');
      buffer.writeln('📅 *التاريخ:* $dateStr ($timeStr)');
      if (lastEntry.items.isNotEmpty) {
        buffer.writeln('🛒 *الأصناف المسجلة بالتفصيل:*');
        for (final item in lastEntry.items) {
          final name = item['name'] ?? item['product_name'] ?? 'صنف';
          final qty = item['quantity'] ?? 1;
          final unit = item['unit_label'] ?? 'حبة';
          final price = (item['unit_price'] as num?)?.round() ?? 0;
          final total = (item['subtotal'] as num?)?.round() ??
              (price * (qty as num).round());
          buffer.writeln('  • $name: $qty $unit × $price ر.ي = $total ر.ي');
        }
      } else if (lastEntry.notes != null &&
          lastEntry.notes!.trim().isNotEmpty) {
        buffer.writeln('📝 *البيان:* ${lastEntry.notes!.trim()}');
      }
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln(
          '💰 *إجمالي الحساب التراكمي المطلوب:* ${customer.currentBalance.round()} ر.ي');
      buffer.writeln('نسعد دائماً بخدمتكم وتلبية طلباتكم 💐');
    }
    // ── حالة 3: رسالة تذكير دورية بالمطالبة ──
    else {
      buffer.writeln(
          'السلام عليكم ورحمة الله وبركاته يا أخي العزيز *${customer.name}* 🌸');
      buffer.writeln('نود تذكيركم بالحساب المتبقي لديكم لدى *($storeName)*:');
      buffer.writeln(
          '💰 *المبلغ المطلوب سداده:* ${customer.currentBalance.round()} ر.ي');
      buffer.writeln('📅 *تاريخ المطابقة:* $dateStr');
      buffer.writeln('');
      buffer.writeln(
          'شاكرين ومقدرين حسن تعاملكم الدائم معنا، وبارك الله في رزقكم 🙏');
    }

    final encodedMessage = Uri.encodeComponent(buffer.toString());
    final whatsappUri =
        Uri.parse('whatsapp://send?phone=$phone&text=$encodedMessage');
    final webUri = Uri.parse('https://wa.me/$phone?text=$encodedMessage');

    try {
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }

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
    final entries = (args['entries'] as List)
        .map((e) => LedgerEntry.fromMap(e as Map<String, dynamic>))
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

    // ── 2. ترتيب الحركات (الأحدث أولاً لكي تظهر حركة اليوم مباشرة في أول الجدول) ──
    final sortedEntries = List<LedgerEntry>.from(entries)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
// حساب الرصيد التنازلي التراكمي بدقة مطلقة
    double currentRunningBalance = customer.currentBalance;
    final List<List<dynamic>> tableRows = [];

    final double openingBalance = LedgerCustomer.sanitizeAmount(
      customer.currentBalance - (periodTotalDebt - periodTotalPayment),
    );
    for (int i = 0; i < sortedEntries.length; i++) {
      final e = sortedEntries[i];
      final eDate =
          '${e.createdAt.year}/${e.createdAt.month.toString().padLeft(2, '0')}/${e.createdAt.day.toString().padLeft(2, '0')}';
      final eTime = formatTime12H(e.createdAt);

      final balanceAfterThisTx = currentRunningBalance;
      if (e.isDebt) {
        currentRunningBalance -= e.amount;
      } else {
        currentRunningBalance += e.amount;
      }

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
