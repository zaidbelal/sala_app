import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:sala/core/services/local_storage.dart';

enum WalOperationType {
  placeOrder,
  ledgerTransaction,
}

enum WalStatus {
  pending,
  committed,
  aborted,
}

class WalEntry {
  final String id;
  final WalOperationType type;
  final Map<String, dynamic> payload;
  final WalStatus status;
  final DateTime timestamp;

  const WalEntry({
    required this.id,
    required this.type,
    required this.payload,
    required this.status,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'payload': payload,
        'status': status.name,
        'timestamp': timestamp.toIso8601String(),
      };

  factory WalEntry.fromMap(Map<String, dynamic> m) => WalEntry(
        id: m['id'] as String,
        type: WalOperationType.values.byName(m['type'] as String),
        payload: Map<String, dynamic>.from(m['payload'] as Map),
        status: WalStatus.values.byName(m['status'] as String),
        timestamp: DateTime.parse(m['timestamp'] as String),
      );
}

/// محرك Write-Ahead Logging بنمط Append-Only المقاوم للانهيارات (Crash-Safe)
class WalService {
  WalService._();
  static final WalService instance = WalService._();

  static const String _logFileName = 'sala_transactions_wal.log';
  static const int _maxLogSizeBytes = 120 * 1024; // 120 KB
  File? _logFile;
  Future<void>? _initFuture;
  bool _isInitialized = false;

  Future<void> init() {
    if (kIsWeb || _isInitialized) return Future.value();
    return _initFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/$_logFileName');
      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
      }
      _isInitialized = true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('❌ WAL Init Error: $e');
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'WAL Init failed');
      }
      _initFuture = null;
      rethrow;
    }
  }

  Future<void> _walFileLock = Future.value();

  Future<T> _withLock<T>(Future<T> Function() action) async {
    final prev = _walFileLock;
    final completer = Completer<void>();
    _walFileLock = completer.future;

    try {
      await prev;
    } catch (_) {}

    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  Future<void> writeIntent({
    required String transactionId,
    required WalOperationType type,
    required Map<String, dynamic> payload,
  }) async {
    if (kIsWeb) return;
    await init();
    if (_logFile == null) {
      throw StateError('WAL file is unavailable after initialization');
    }

    return _withLock(() async {
      final entry = WalEntry(
        id: transactionId,
        type: type,
        payload: payload,
        status: WalStatus.pending,
        timestamp: DateTime.now(),
      );

      final line = '${jsonEncode(entry.toMap())}\n';
      await _logFile!.writeAsString(line, mode: FileMode.append, flush: true);
    });
  }

  Future<void> markCommitted(String transactionId) async {
    if (kIsWeb) return;
    await init();
    return _withLock(
        () => _appendStateTransition(transactionId, WalStatus.committed));
  }

  Future<void> markAborted(String transactionId) async {
    if (kIsWeb) return;
    await init();
    return _withLock(
        () => _appendStateTransition(transactionId, WalStatus.aborted));
  }

  Future<void> _appendStateTransition(String transactionId, WalStatus status,
      {bool autoCompact = true}) async {
    if (_logFile == null || !await _logFile!.exists()) return;
    try {
      final transition = {
        'id': transactionId,
        'status': status.name,
        'transition': true,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await _logFile!.writeAsString('${jsonEncode(transition)}\n',
          mode: FileMode.append, flush: true);

      if (autoCompact) {
        final fileLength = await _logFile!.length();
        if (fileLength > _maxLogSizeBytes) {
          // 🔒 تجنب Deadlock: فك الحجز أولاً وجدولة الـ compactLog بعد اكتمال القفل الحالي
          Timer.run(() => compactLog());
        }
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('WAL State Transition Failed: $e');
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'WAL append transition failed');
      }
    }
  }

  Future<List<WalEntry>> _readUncommittedInternal() async {
    if (_logFile == null || !await _logFile!.exists()) return [];
    final Map<String, WalEntry> entries = {};
    try {
      final lines = await _logFile!.readAsLines();
      for (final l in lines) {
        final line = l.trim();
        if (line.isEmpty) continue;
        try {
          final map = jsonDecode(line) as Map<String, dynamic>;
          final id = map['id'] as String;

          if (map['transition'] == true) {
            final st = WalStatus.values.byName(map['status'] as String);
            if (st == WalStatus.committed || st == WalStatus.aborted) {
              entries.remove(id);
            }
          } else {
            final entry = WalEntry.fromMap(map);
            if (entry.status == WalStatus.pending) {
              entries[id] = entry;
            }
          }
        } catch (_) {}
      }
    } catch (e, st) {
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.recordError(e, st,
            reason: 'WAL _readUncommittedInternal read failure');
      }
      rethrow;
    }
    return entries.values.toList();
  }

  Future<List<WalEntry>> getUncommittedEntries() async {
    if (kIsWeb) return [];
    await init();
    return _withLock(() => _readUncommittedInternal());
  }

  Future<void> reconcilePendingEntries() async {
    if (kIsWeb) return;
    await init();
    if (_logFile == null || !await _logFile!.exists()) return;

    final pending = await getUncommittedEntries();
    if (pending.isEmpty) {
      await compactLog();
      return;
    }

    for (final entry in pending) {
      try {
        final merchantId =
            entry.payload['merchant_id']?.toString() ?? AppStorage.userId ?? '';
        if (merchantId.isEmpty) {
          throw StateError('WAL entry has no merchant identity');
        }

        if (entry.type == WalOperationType.placeOrder) {
          final items = entry.payload['items'];
          final expectedTotal =
              entry.payload['expectedTotal'] ?? entry.payload['expected_total'];
          if (items is! List || items.isEmpty || expectedTotal is! num) {
            throw FormatException('WAL order payload is incomplete');
          }
          await AppStorage.savePendingOrder({
            'orderId': entry.id,
            'merchantId': merchantId,
            'items': items
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList(),
            'expectedTotal': expectedTotal,
            if (entry.payload['notes'] != null) 'notes': entry.payload['notes'],
            if (entry.payload['extraData'] is Map)
              'extraData':
                  Map<String, dynamic>.from(entry.payload['extraData'] as Map),
            if (entry.payload['cart_revision'] != null)
              'cart_revision': entry.payload['cart_revision'],
          });
        } else {
          final payload = Map<String, dynamic>.from(entry.payload);
          if (payload['action'] == 'void') {
            await AppStorage.savePendingLedgerTx({
              'id': 'void_${entry.id}',
              'merchant_id': merchantId,
              'customer_id': payload['customer_id'],
              'type': 'void_request',
              'target_entry_id': entry.id,
              'amount': payload['amount'],
              'is_debt': payload['is_debt'],
              'created_at': entry.timestamp.toIso8601String(),
            });
          } else {
            payload['id'] = entry.id;
            await AppStorage.savePendingLedgerTx(payload);
          }
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('WAL recovery could not restore ${entry.id}: $e');
        }
        if (!kIsWeb) {
          FirebaseCrashlytics.instance.recordError(
            e,
            st,
            reason: 'WAL intent recovery failed for ${entry.id}',
          );
        }
      }
    }

    final db = FirebaseFirestore.instance;
    final verifiedIds = <String>[];
    final verifiedVoidedLedgerIds = <String>{};
    final verifiedOrderUids = <String>{};
// 🔒 تنفيذ التحقق بالتوازي بمهلة إجمالية واحدة لا تتجاوز 3 ثوانٍ
    await Future.wait(
      pending.map((entry) async {
        try {
          bool verifiedOnServer = false;
          if (entry.type == WalOperationType.placeOrder) {
            final doc = await db
                .collection('orders')
                .doc(entry.id)
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 3));
            final merchantId =
                entry.payload['merchant_id']?.toString() ?? AppStorage.userId;
            final orderNumber = doc.data()?['order_number']?.toString() ?? '';
            verifiedOnServer = doc.exists &&
                doc.data()?['merchant_id'] == merchantId &&
                orderNumber.isNotEmpty;
            if (verifiedOnServer) {
              if (merchantId != null) verifiedOrderUids.add(merchantId);
            }
          } else if (entry.type == WalOperationType.ledgerTransaction) {
            final doc = await db
                .collection('merchant_ledger_entries')
                .doc(entry.id)
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 3));
            final data = doc.data();
            final matchesIntent = doc.exists &&
                data?['merchant_id'] == entry.payload['merchant_id'] &&
                data?['customer_id'] == entry.payload['customer_id'];
            if (matchesIntent && data?['is_voided'] == true) {
              verifiedVoidedLedgerIds.add(entry.id);
            }
            if (entry.payload['action'] == 'void') {
              verifiedOnServer = matchesIntent && data?['is_voided'] == true;
            } else {
              verifiedOnServer = matchesIntent &&
                  data?['type'] == entry.payload['type'] &&
                  (data?['amount'] as num?)?.toDouble() ==
                      (entry.payload['amount'] as num?)?.toDouble();
            }
          }
          if (verifiedOnServer) {
            verifiedIds.add(entry.id);
          }
        } catch (_) {}
      }),
    );
    // حذف السلة فقط إذا كانت سلتها مطابقة لعناصر الطلب المؤكد بالسيرفر لمنع مسح سلة جديدة
    if (verifiedOrderUids.isNotEmpty) {
      for (final uid in verifiedOrderUids) {
        if (!kIsWeb) {
          try {
            final dir = await getApplicationDocumentsDirectory();
            final file = File('${dir.path}/sala_cart_v2_$uid.json');
            if (await file.exists()) {
              final content = await file.readAsString();
              if (content.trim().isEmpty || content == '{}') {
                await file.delete();
                continue;
              }
              final decoded = jsonDecode(content);
              final cartProductIds = (decoded is Map)
                  ? decoded.values
                      .map((v) => (v['product']?['id'])?.toString())
                      .whereType<String>()
                      .toSet()
                  : <String>{};
              final revisionFile =
                  File('${dir.path}/sala_cart_v2_$uid.revision');
              final cartRevision = await revisionFile.exists()
                  ? (await revisionFile.readAsString()).trim()
                  : '';
              final matchingEntries = pending.where((e) =>
                  verifiedIds.contains(e.id) &&
                  (e.payload['merchant_id']?.toString() ?? AppStorage.userId) ==
                      uid &&
                  e.payload['cart_revision']?.toString() == cartRevision);

              final verifiedProductIds = matchingEntries
                  .expand((e) => (e.payload['items'] as List? ?? []))
                  .map((it) => (it['product_id'])?.toString())
                  .whereType<String>()
                  .toSet();

              // 🔒 التحقق الشامل: مطابقة المعرفات والكميات معاً لضمان عدم مسح سلة جديدة لنفس الصنف
              final matchingItemsList = matchingEntries
                  .expand((e) => (e.payload['items'] as List? ?? []))
                  .toList();

              bool isExactCartMatch = cartProductIds.isNotEmpty &&
                  cartProductIds.length == verifiedProductIds.length &&
                  cartProductIds.every((id) => verifiedProductIds.contains(id));

              if (isExactCartMatch && decoded is Map) {
                for (final itemVal in decoded.values) {
                  final pId = itemVal['product']?['id']?.toString();
                  final qty = (itemVal['quantity'] as num?)?.toInt() ?? 0;
                  final matchingOrderQty = matchingItemsList
                      .where((m) => m['product_id']?.toString() == pId)
                      .fold<int>(
                          0,
                          (sum, m) =>
                              sum + ((m['quantity'] as num?)?.toInt() ?? 0));
                  if (matchingOrderQty != qty) {
                    isExactCartMatch = false;
                    break;
                  }
                }
              }

              final isAssociatedWithPending = cartRevision.isNotEmpty &&
                  matchingEntries.isNotEmpty &&
                  isExactCartMatch;

              if (isAssociatedWithPending) {
                await file.delete();
                await AppStorage.remove('sala_cart_v2_$uid');
              }
            }
          } catch (_) {}
        }
      }
    }
    if (verifiedIds.isNotEmpty) {
      await _withLock(() async {
        for (final id in verifiedIds) {
          await _appendStateTransition(id, WalStatus.committed,
              autoCompact: false);
        }
      });
      for (final entry in pending.where((e) => verifiedIds.contains(e.id))) {
        final targetMerchantId =
            entry.payload['merchant_id']?.toString() ?? AppStorage.userId;
        if (entry.type == WalOperationType.placeOrder) {
          if (targetMerchantId != null) {
            await AppStorage.removePendingOrder(entry.id, targetMerchantId);
          }
        } else if (entry.type == WalOperationType.ledgerTransaction) {
          await AppStorage.removePendingLedgerTx(entry.id, targetMerchantId);
          if (verifiedVoidedLedgerIds.contains(entry.id)) {
            await AppStorage.removePendingLedgerTx(
                'void_${entry.id}', targetMerchantId);
          }
        }
      }
    }
    await compactLog();
  }

  Future<void> compactLog() async {
    if (kIsWeb) return;
    await init();
    if (_logFile == null || !await _logFile!.exists()) return;

    return _withLock(() async {
      try {
        // ✅ استخدام القراءة المباشرة داخل القفل بدون طلب قفل إضافي لمنع الـ Deadlock
        final pending = await _readUncommittedInternal();
        final tempFile = File(
            '${_logFile!.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
        final sink = tempFile.openWrite();
        for (final entry in pending) {
          sink.writeln(jsonEncode(entry.toMap()));
        }
        await sink.flush();
        await sink.close();

        // استبدال ذري آمن
        try {
          await tempFile.rename(_logFile!.path);
        } catch (_) {
          await tempFile.copy(_logFile!.path);
          if (await tempFile.exists()) await tempFile.delete();
        }
      } catch (e, st) {
        if (!kIsWeb) {
          FirebaseCrashlytics.instance
              .recordError(e, st, reason: 'WAL compactLog failed');
        }
      }
    });
  }
}
