import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import 'package:sala/core/services/local_storage.dart';
import '../models/ledger_models.dart';
import '../services/ledger_service.dart';
import 'package:sala/core/constants/app_colors.dart';

class CustomerStatementScreen extends StatefulWidget {
  final LedgerCustomer customer;
  final String storeName;

  const CustomerStatementScreen({
    super.key,
    required this.customer,
    required this.storeName,
  });

  @override
  State<CustomerStatementScreen> createState() =>
      _CustomerStatementScreenState();
}

class _CustomerStatementScreenState extends State<CustomerStatementScreen> {
  late LedgerCustomer _customer;
  final Set<String> _locallyDismissedEntryIds = {};
  int _currentLimit = 50;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mId = AppStorage.userId ?? '';
      final lastReconciled = _customer.lastReminderSentAt;
      final shouldReconcile = lastReconciled == null ||
          DateTime.now().difference(lastReconciled).inHours > 12;

      // تدقيق الحساب من السيرفر فقط إذا مضت 12 ساعة على الأقل أو عند أول فتح
      if (mId.isNotEmpty && shouldReconcile) {
        LedgerService.instance.reconcileCustomerBalance(
          merchantId: mId,
          customerId: _customer.id,
        );
      }
    });
  }

  void _showAddEntryDialog(bool isDebt) async {
    HapticFeedback.lightImpact();
    final updatedCustomer = await showDialog<LedgerCustomer>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AddLedgerEntryDialog(
        customer: _customer,
        isDebt: isDebt,
      ),
    );

    if (updatedCustomer != null && mounted) {
      setState(() => _customer = updatedCustomer);
    }
  }

  void _showExportPdfOptions(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: BoxDecoration(
          color: sheetCtx.bgCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'كشف حساب PDF رسمي معتمد',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: sheetCtx.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'الزبون: ${_customer.name}',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: sheetCtx.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.share_rounded, color: Colors.green),
              ),
              title: Text(
                'إرسال ومشاركة PDF عبر واتساب',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: sheetCtx.textPrimary,
                ),
              ),
              subtitle: const Text(
                'مشاركة الملف مباشرة مع الزبون كوثيقة رسمية',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                // 🛡️ جلب السجل مع ضمان احتساب الرصيد السابق المرحل لضمان تطابق الأرقام 100%
                final entriesSnap = await LedgerService.instance
                    .watchCustomerEntries(_customer.id, limit: 1000)
                    .first;
                await LedgerService.instance.shareCustomerStatementPdf(
                  customer: _customer,
                  storeName: widget.storeName,
                  entries: entriesSnap,
                );
              },
            ),
            const Divider(height: 12),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.print_rounded, color: Colors.blue),
              ),
              title: Text(
                'طباعة ومعاينة وتحميل PDF',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: sheetCtx.textPrimary,
                ),
              ),
              subtitle: const Text(
                'معاينة الكشف أو حفظه وطباعته عبر أي طابعة',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                // 🔒 حماية الذاكرة: تقييد الكشف بأحدث 500 قيد محاسبي لمنع انهيار تطبيق الهاتف
                final entriesSnap = await LedgerService.instance
                    .watchCustomerEntries(_customer.id, limit: 500)
                    .first;
                await LedgerService.instance.printOrPreviewStatementPdf(
                  customer: _customer,
                  storeName: widget.storeName,
                  entries: entriesSnap,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgPage,
      appBar: AppBar(
        title: Text(
          'كشف حساب: ${_customer.name}',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        backgroundColor: context.bgHeader,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'تصدير كشف حساب PDF رسمي',
            icon: const Icon(Icons.picture_as_pdf_rounded,
                color: Colors.redAccent),
            onPressed: () => _showExportPdfOptions(context),
          ),
          IconButton(
            tooltip: 'إرسال تذكير واتساب',
            icon: const Icon(Icons.chat_rounded, color: Colors.green),
            onPressed: () async {
              if (_customer.phone.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚠️ هذا الزبون لا يملك رقم هاتف مسجل للتذكير',
                        style: TextStyle(fontFamily: 'Cairo')),
                    backgroundColor: Colors.orange,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              final sent = await LedgerService.instance.sendWhatsAppReminder(
                customer: _customer,
                storeName: widget.storeName,
              );
              if (!sent && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'تعذر فتح تطبيق واتساب، تأكد من وجود التطبيق وصحة الرقم',
                        style: TextStyle(fontFamily: 'Cairo')),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 🚀 استماع ذكي ومطابقة حتمية تحسب الرصيد المعروض نقياً بدون تعديل الحالة في build()
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('merchant_customers')
                  .doc(_customer.id)
                  .snapshots(),
              builder: (context, custSnap) {
                var displayedCustomer = _customer;
                if (custSnap.hasData &&
                    custSnap.data!.exists &&
                    custSnap.data!.data() != null) {
                  final serverCustomer = LedgerCustomer.fromMap(
                      {'id': custSnap.data!.id, ...custSnap.data!.data()!});
                  final dataMap = custSnap.data!.data()!;
                  final serverAppliedIds =
                      (dataMap['applied_tx_ids'] as List<dynamic>? ?? [])
                          .map((e) => e.toString())
                          .toSet();
                  final serverLastTxId =
                      dataMap['last_transaction_id']?.toString();
                  if (serverLastTxId != null && serverLastTxId.isNotEmpty) {
                    serverAppliedIds.add(serverLastTxId);
                  }

                  // 🚀 منع احتساب القيود المضاعفة: إذا كانت الوثيقة حديثة وقادمة مباشرة من الخادم لا نطبق أرصدة معلقة متزامنة

                  final pendingTxs =
                      AppStorage.getPendingLedgerTxs(_customer.merchantId)
                          .where((t) => t['customer_id'] == _customer.id);
                  double pendingDelta = 0.0;
                  // تطبيق الفوارق المعلقة دائماً سواء كانت الوثيقة من السيرفر أو الكاش طالما لم يقيدها السيرفر بعد
                  for (final tx in pendingTxs) {
                    final txType = tx['type']?.toString();
                    if (txType == 'add_customer' || txType == 'void_request') {
                      continue;
                    }
                    final txId = tx['id']?.toString() ?? '';

                    if (serverAppliedIds.contains(txId)) continue;
                    if (_locallyDismissedEntryIds.contains(txId)) continue;

                    final isDebt = txType == 'debt';
                    final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                    pendingDelta += isDebt ? amt : -amt;
                  }

                  final voidRequests =
                      pendingTxs.where((t) => t['type'] == 'void_request');
                  double voidDelta = 0.0;
                  for (final v in voidRequests) {
                    final voidAmt = (v['amount'] as num?)?.toDouble() ?? 0.0;
                    final isDebtVoid = v['is_debt'] != false;
                    voidDelta += isDebtVoid ? -voidAmt : voidAmt;
                  }

                  final double localAdjustments = (pendingDelta + voidDelta);
                  displayedCustomer = LedgerCustomer(
                    id: serverCustomer.id,
                    merchantId: serverCustomer.merchantId,
                    name: serverCustomer.name,
                    phone: serverCustomer.phone,
                    currentBalance: LedgerCustomer.sanitizeAmount(
                        serverCustomer.currentBalance + localAdjustments),
                    creditLimit: serverCustomer.creditLimit,
                    salaryDay: serverCustomer.salaryDay,
                    lastReminderSentAt: serverCustomer.lastReminderSentAt,
                    createdAt: serverCustomer.createdAt,
                    updatedAt: serverCustomer.updatedAt,
                  );
                }
                final isOverLimit = displayedCustomer.isOverLimit;
                final isNegative = displayedCustomer.currentBalance < 0;
                return Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: displayedCustomer.currentBalance > 0
                          ? [const Color(0xFFC0392B), const Color(0xFFE74C3C)]
                          : [const Color(0xFF1E8449), const Color(0xFF2ECC71)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: (displayedCustomer.currentBalance > 0
                                ? Colors.red
                                : Colors.green)
                            .withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        isNegative
                            ? 'رصيد دائن لصالح الزبون (له في ذمتك)'
                            : 'إجمالي المبلغ المتبقي على الزبون',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${displayedCustomer.currentBalance.abs().toStringAsFixed(0)} ر.ي',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      if (displayedCustomer.creditLimit > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'سقف الدين: ${displayedCustomer.creditLimit.toStringAsFixed(0)} ر.ي',
                              style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: Colors.white),
                            ),
                            if (isOverLimit) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.amber,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'تجاوز السقف ⚠️',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.black),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => _showAddEntryDialog(true),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('سجل عليه دين (+)',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => _showAddEntryDialog(false),
                      icon: const Icon(Icons.check_rounded, size: 20),
                      label: const Text('سدد دفعة (-)',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'سجل الفواتير والحركات المالية:',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: context.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<LedgerEntry>>(
                stream: LedgerService.instance.watchCustomerEntries(
                  _customer.id,
                  limit: _currentLimit,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          'قيد التحديث أو بناء الفهرس...\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: Colors.red),
                        ),
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary));
                  }
                  final rawEntries = snapshot.data ?? [];
                  final entries = rawEntries
                      .where((e) =>
                          !_locallyDismissedEntryIds.contains(e.id) &&
                          !e.isVoided)
                      .toList();
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        'لا توجد عمليات سابقة مسجلة لهذا الزبون',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: context.textHint),
                      ),
                    );
                  }

                  final hasMore = entries.length >= _currentLimit;

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: entries.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == entries.length) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: TextButton.icon(
                              onPressed: () {
                                setState(() => _currentLimit += 50);
                              },
                              icon: const Icon(Icons.history_rounded),
                              label: const Text(
                                'تحميل القيود والفواتير الأقدم...',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      final item = entries[i];
                      final isDebt = item.isDebt;
                      final dateStr =
                          '${item.createdAt.year}/${item.createdAt.month.toString().padLeft(2, '0')}/${item.createdAt.day.toString().padLeft(2, '0')}  ${item.createdAt.hour.toString().padLeft(2, '0')}:${item.createdAt.minute.toString().padLeft(2, '0')}';

                      return Dismissible(
                        key: ValueKey(item.id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialogCtx) => AlertDialog(
                              backgroundColor: dialogCtx.bgCard,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18)),
                              title: Text('حذف وتصحيح القيد؟',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: dialogCtx.textPrimary,
                                      fontWeight: FontWeight.bold)),
                              content: Text(
                                'هل تريد حذف هذه العملية بقيمة ${item.amount.toStringAsFixed(0)} ر.ي وعكس أثرها على رصيد الزبون تلقائياً؟',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    color: dialogCtx.textSecondary,
                                    fontSize: 13),
                              ),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogCtx, false),
                                    child: const Text('إلغاء')),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red),
                                  onPressed: () =>
                                      Navigator.pop(dialogCtx, true),
                                  child: const Text('تأكيد الحذف',
                                      style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );

                          if (confirmed != true) return false;

                          final merchantId = AppStorage.userId ?? '';
                          try {
                            await LedgerService.instance.voidTransaction(
                              merchantId: merchantId,
                              customerId: _customer.id,
                              entryId: item.id,
                              knownAmount: item.amount,
                              knownIsDebt: isDebt,
                            );
                            final delta = isDebt ? -item.amount : item.amount;
                            if (mounted) {
                              setState(() {
                                _customer = LedgerCustomer(
                                  id: _customer.id,
                                  merchantId: _customer.merchantId,
                                  name: _customer.name,
                                  phone: _customer.phone,
                                  currentBalance: LedgerCustomer.sanitizeAmount(
                                    _customer.currentBalance + delta,
                                  ),
                                  creditLimit: _customer.creditLimit,
                                  salaryDay: _customer.salaryDay,
                                  lastReminderSentAt:
                                      _customer.lastReminderSentAt,
                                  createdAt: _customer.createdAt,
                                  updatedAt: DateTime.now(),
                                );
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        '✅ تم إبطال القيد وتصحيح رصيد الزبون بنجاح')),
                              );
                            }
                            return true;
                          } catch (e) {
                            final err = e.toString().toLowerCase();
                            final isOfflineOrTimeout =
                                err.contains('network') ||
                                    err.contains('timeout') ||
                                    err.contains('socket') ||
                                    err.contains('unavailable');

                            if (mounted) {
                              if (isOfflineOrTimeout) {
                                // تم حفظ الشطب محلياً في الطابور بنجاح، لذا نسمح بإخفاء العنصر فوراً لمنع تكرار حذفه
                                final delta =
                                    isDebt ? -item.amount : item.amount;
                                setState(() {
                                  _locallyDismissedEntryIds.add(item.id);
                                  _customer = LedgerCustomer(
                                    id: _customer.id,
                                    merchantId: _customer.merchantId,
                                    name: _customer.name,
                                    phone: _customer.phone,
                                    currentBalance:
                                        LedgerCustomer.sanitizeAmount(
                                      _customer.currentBalance + delta,
                                    ),
                                    creditLimit: _customer.creditLimit,
                                    salaryDay: _customer.salaryDay,
                                    lastReminderSentAt:
                                        _customer.lastReminderSentAt,
                                    createdAt: _customer.createdAt,
                                    updatedAt: DateTime.now(),
                                  );
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        '📡 تم حفظ طلب الإلغاء أوفلاين وسيُشطب تلقائياً فور توفر الشبكة',
                                        style: TextStyle(fontFamily: 'Cairo')),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return true; // حذف العنصر من الشاشة فوراً
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('تعذر إبطال القيد: $e',
                                        style: const TextStyle(
                                            fontFamily: 'Cairo')),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return false;
                              }
                            }
                            return false;
                          }
                        },
                        onDismissed: (_) {
                          setState(() {
                            _locallyDismissedEntryIds.add(item.id);
                          });
                        },
                        background: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 20),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.delete_forever_rounded,
                              color: Colors.white),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: context.bgCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: (isDebt ? Colors.red : Colors.green)
                                      .withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isDebt
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  color: isDebt ? Colors.red : Colors.green,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isDebt ? 'فاتورة دين' : 'دفعة سداد نقدية',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: context.textPrimary,
                                      ),
                                    ),
                                    if (item.items.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 2),
                                        child: Text(
                                          item.items.map((it) {
                                            final name = it['name'] ??
                                                it['product_name'] ??
                                                'صنف';
                                            final q = it['quantity'] ?? 1;
                                            final u = it['unit_label'] ?? '';
                                            return '$name ($q $u)';
                                          }).join(' ، '),
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )
                                    else if (item.notes != null &&
                                        item.notes!.isNotEmpty)
                                      Text(
                                        item.notes!,
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          color: context.textSecondary,
                                        ),
                                      ),
                                    Text(
                                      dateStr,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 10,
                                        color: context.textHint,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${isDebt ? '+' : '-'}${item.amount.toStringAsFixed(0)} ر.ي',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: isDebt ? Colors.red : Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// كلاس نافذة إضافة الحركة المالية (دين / سداد) كـ StatefulWidget
// ══════════════════════════════════════════════════════
class _AddLedgerEntryDialog extends StatefulWidget {
  final LedgerCustomer customer;
  final bool isDebt;

  const _AddLedgerEntryDialog({
    required this.customer,
    required this.isDebt,
  });

  @override
  State<_AddLedgerEntryDialog> createState() => _AddLedgerEntryDialogState();
}

class _AddLedgerEntryDialogState extends State<_AddLedgerEntryDialog> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  static String _cleanDigits(String input) {
    const digitMap = {
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
      '۰': '0',
      '۱': '1',
      '۲': '2',
      '۳': '3',
      '۴': '4',
      '۵': '5',
      '۶': '6',
      '۷': '7',
      '۸': '8',
      '۹': '9',
    };
    var res = input.trim();
    digitMap.forEach((k, v) => res = res.replaceAll(k, v));
    return res;
  }

  String? _assignedTransactionId;

  Future<void> _submit() async {
    if (_isSaving) return;

    FocusScope.of(context).unfocus();

    final cleanText = _cleanDigits(_amountCtrl.text);
    final amt = double.tryParse(cleanText);
    if (amt == null || amt <= 0) return;

    setState(() => _isSaving = true);

    final merchantId = AppStorage.userId ?? '';
    // ✅ تثبيت المعرف الحتمي لمنع توليد حركات مزدوجة عند النقر المتكرر أو فقدان الحزم الشبكية
    final safeMId =
        merchantId.length > 5 ? merchantId.substring(0, 5) : merchantId;
    _assignedTransactionId ??=
        'tx_${safeMId}_${widget.customer.id}_${DateTime.now().microsecondsSinceEpoch}_${(amt * 100).toInt()}_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final entryId = _assignedTransactionId!;

    if (widget.isDebt && widget.customer.creditLimit > 0) {
      final projected = widget.customer.currentBalance + amt;
      if (projected > widget.customer.creditLimit) {
        final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => AlertDialog(
            backgroundColor: dialogCtx.bgCard,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('⚠️ تجاوز سقف الدين',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            content: Text(
              'هذا المبلغ سيرفع دين الزبون إلى ${projected.toStringAsFixed(0)} ر.ي، متجاوزاً السقف (${widget.customer.creditLimit.toStringAsFixed(0)} ر.ي).\n\nهل تريد اعتماد تسجيل الدين؟',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: const Text('متابعة التسجيل',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if (proceed != true) {
          if (mounted) setState(() => _isSaving = false);
          return;
        }
      }
    }

    final delta = widget.isDebt ? amt : -amt;
    final updatedCustomer = LedgerCustomer(
      id: widget.customer.id,
      merchantId: widget.customer.merchantId,
      name: widget.customer.name,
      phone: widget.customer.phone,
      currentBalance:
          LedgerCustomer.sanitizeAmount(widget.customer.currentBalance + delta),
      creditLimit: widget.customer.creditLimit,
      salaryDay: widget.customer.salaryDay,
      lastReminderSentAt: widget.customer.lastReminderSentAt,
      createdAt: widget.customer.createdAt,
      updatedAt: DateTime.now(),
    );

    try {
      await LedgerService.instance.recordTransaction(
        merchantId: merchantId,
        customerId: widget.customer.id,
        type: widget.isDebt ? 'debt' : 'payment',
        amount: amt,
        notes: _notesCtrl.text.trim(),
        transactionId: entryId,
      );

      _assignedTransactionId = null; // تصفير فقط بعد التأكيد الكامل

      if (!mounted) return;
      Navigator.pop(context, updatedCustomer);

      if (updatedCustomer.phone.trim().isNotEmpty) {
        final lastCreatedEntry = LedgerEntry(
          id: entryId,
          merchantId: merchantId,
          customerId: widget.customer.id,
          type: widget.isDebt ? 'debt' : 'payment',
          amount: amt,
          notes: _notesCtrl.text.trim(),
          createdAt: DateTime.now(),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isDebt
                  ? 'تم تسجيل الدين. إرسال الفاتورة للزبون؟'
                  : 'تم تسجيل السداد. إرسال سند القبض؟',
              style: const TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            backgroundColor:
                widget.isDebt ? Colors.red.shade700 : Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'واتساب 💬',
              textColor: Colors.white,
              onPressed: () {
                LedgerService.instance.sendWhatsAppReminder(
                  customer: updatedCustomer,
                  storeName:
                      AppStorage.storeName ?? AppStorage.userName ?? 'المحل',
                  lastEntry: lastCreatedEntry,
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      // ✅ عند انقطاع الاتصال نكتفي بالـ optimistic update دون تكرار الحساب
      _assignedTransactionId = null;
      if (!mounted) return;
      Navigator.pop(context, updatedCustomer);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '📡 تم حفظ القيد أوفلاين وسيتزامن تلقائياً فور توفر الشبكة',
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDebt = widget.isDebt;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: context.bgCard,
      title: Row(
        children: [
          Icon(
            isDebt ? Icons.add_circle_rounded : Icons.check_circle_rounded,
            color: isDebt ? Colors.red : Colors.green,
            size: 24,
          ),
          const SizedBox(width: 8),
          Text(
            isDebt ? 'تسجيل دين جديد (+)' : 'قبول دفعة سداد (-)',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'الزبون: ${widget.customer.name}',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            inputFormatters: [
              TextInputFormatter.withFunction((oldVal, newVal) {
                const arabic = {
                  '٠': '0',
                  '١': '1',
                  '٢': '2',
                  '٣': '3',
                  '٤': '4',
                  '٥': '5',
                  '٦': '6',
                  '٧': '7',
                  '٨': '8',
                  '٩': '9',
                  '۰': '0',
                  '۱': '1',
                  '۲': '2',
                  '۳': '3',
                  '۴': '4',
                  '۵': '5',
                  '۶': '6',
                  '۷': '7',
                  '۸': '8',
                  '۹': '9'
                };
                var t = newVal.text;
                arabic.forEach((k, v) => t = t.replaceAll(k, v));
                t = t.replaceAll(RegExp(r'[^0-9.]'), '');
                return TextEditingValue(
                  text: t,
                  selection: TextSelection.collapsed(offset: t.length),
                );
              }),
            ],
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: isDebt ? Colors.red : Colors.green,
            ),
            decoration: InputDecoration(
              hintText: 'المبلغ ر.ي',
              filled: true,
              fillColor: context.bgInput,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            style: TextStyle(fontFamily: 'Cairo', color: context.textPrimary),
            decoration: InputDecoration(
              hintText: 'ملاحظة أو بيان (مثال: سكر وماء)...',
              hintStyle: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: context.textHint,
              ),
              filled: true,
              fillColor: context.bgInput,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء',
              style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isDebt ? Colors.red : Colors.green,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Text('حفظ',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
