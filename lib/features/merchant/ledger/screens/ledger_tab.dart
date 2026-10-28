import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sala/core/constants/app_colors.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import 'package:sala/core/services/local_storage.dart';
import 'package:sala/features/merchant/barcode/barcode_scanner_screen.dart';
import '../models/ledger_models.dart';
import '../services/ledger_service.dart';
import 'customer_statement_screen.dart';

class LedgerTab extends StatefulWidget {
  const LedgerTab({super.key});

  @override
  State<LedgerTab> createState() => _LedgerTabState();
}

class _LedgerTabState extends State<LedgerTab> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  int _selectedFilter = 0; // 0: الكل، 1: عليهم ديون فقط، 2: تجاوزوا السقف
  final List<LedgerCustomer> _remoteSearchResults = [];
  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── نافذة إضافة زبون جديد للدفتر (محصنة بنسبة 100% ضد الشاشات الحمراء) ──
  void _openAddCustomerDialog() {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _AddCustomerDialog(),
    );
  }

  // ── فتح جلسة كاشير الديون بالباركود ──
  void _startBarcodeDebtSale(List<LedgerCustomer> customers,
      [LedgerCustomer? preSelected]) {
    HapticFeedback.mediumImpact();
    if (customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إضافة زبون أولاً لتسجيل الدين في حسابه',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DebtPosSheet(
        customers: customers,
        initialCustomer: preSelected ?? customers.first,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final merchantId = AppStorage.userId ?? '';
    final storeName = AppStorage.storeName ?? AppStorage.userName ?? 'البقالة';

    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: StreamBuilder<Map<String, dynamic>>(
          stream: LedgerService.instance.watchMerchantLedgerSummary(merchantId),
          builder: (context, summarySnap) {
            final summaryData = summarySnap.data ?? {};
            final totalMarketDebt =
                (summaryData['total_market_debt'] as num?)?.toDouble() ?? 0.0;
            return StreamBuilder<List<LedgerCustomer>>(
              stream: LedgerService.instance.watchCustomers(merchantId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'جاري تهيئة قاعدة البيانات أو أن الفهرس قيد الإنشاء...\n${snapshot.error}',
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
                      child:
                          CircularProgressIndicator(color: AppColors.primary));
                }
                final streamCustomers = snapshot.data ?? [];
                // دمج ذكي دائم لا يفقد الزبائن المجلوبين عبر البحث السحابي نهائياً أثناء الجلسة
                final Map<String, LedgerCustomer> unifiedMap = {
                  for (final c in _remoteSearchResults) c.id: c,
                  for (final c in streamCustomers) c.id: c,
                };
                final allCustomers = unifiedMap.values.toList();
                String normalize(String text) {
                  return text
                      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
                      .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
                      .replaceAll('ة', 'ه')
                      .replaceAll('ى', 'ي')
                      .replaceAll('ـ', '')
                      .toLowerCase()
                      .trim();
                }

                final normQuery = normalize(_searchQuery);

                var filtered = allCustomers.where((c) {
                  if (_selectedFilter == 1 && c.currentBalance < 1.0) {
                    return false;
                  }
                  if (_selectedFilter == 2 && !c.isOverLimit) return false;
                  if (normQuery.isNotEmpty) {
                    final normName = normalize(c.name);
                    final normPhone = c.phone.trim();
                    return normName.contains(normQuery) ||
                        normPhone.contains(_searchQuery.trim());
                  }
                  return true;
                }).toList();

                // 🔍 تمكين البحث السحابي دائماً عند كتابة نص للوصول لآلاف الزبائن غير المحملين في الذاكرة
                final bool showRemoteSearchOption = normQuery.isNotEmpty;
                return Column(
                  children: [
                    // ── ترويسة دفتر الديون ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'دفتر ديون الزبائن 📒',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: context.textPrimary,
                                  ),
                                ),
                                Text(
                                  'متابعة حسابات أهل الحارة والمطالبة عبر واتساب',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11.5,
                                    color: context.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _openAddCustomerDialog,
                            icon:
                                const Icon(Icons.person_add_rounded, size: 16),
                            label: const Text('زبون جديد',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),

                    // ── كارت إجمالي الديون في السوق وزر الباركود ──
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1B8E3D), Color(0xFF2DB85B)],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'إجمالي ديونك في السوق',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      color: Colors.white70),
                                ),
                                Text(
                                  '${totalMarketDebt.toStringAsFixed(0)} ر.ي',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'عدد المدينين: ${summaryData['debtors_count'] ?? allCustomers.where((c) => c.currentBalance > 0).length} زبون',
                                  style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () =>
                                _startBarcodeDebtSale(allCustomers),
                            icon: const Icon(Icons.qr_code_scanner_rounded,
                                size: 18),
                            label: const Text(
                              'بيع بالدين 🛒',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── شريط البحث ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) =>
                            setState(() => _searchQuery = v.trim()),
                        decoration: InputDecoration(
                          hintText: 'ابحث عن زبون بالاسم أو رقم الهاتف...',
                          hintStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: context.textHint),
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 20),
                          filled: true,
                          fillColor: context.bgCard,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: context.borderColor),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),

                    // ── الفلاتر ──
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('الكل',
                                style: TextStyle(
                                    fontFamily: 'Cairo', fontSize: 11)),
                            selected: _selectedFilter == 0,
                            onSelected: (_) =>
                                setState(() => _selectedFilter = 0),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: const Text('عليهم ديون فقط',
                                style: TextStyle(
                                    fontFamily: 'Cairo', fontSize: 11)),
                            selected: _selectedFilter == 1,
                            selectedColor: Colors.red.withValues(alpha: 0.15),
                            onSelected: (_) =>
                                setState(() => _selectedFilter = 1),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: const Text('تجاوزوا السقف ⚠️',
                                style: TextStyle(
                                    fontFamily: 'Cairo', fontSize: 11)),
                            selected: _selectedFilter == 2,
                            selectedColor: Colors.amber.withValues(alpha: 0.2),
                            onSelected: (_) =>
                                setState(() => _selectedFilter = 2),
                          ),
                        ],
                      ),
                    ),
// ── قائمة الزبائن مع دعم البحث السحابي الشامل لآلاف الزبائن ──
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.menu_book_rounded,
                                      size: 56, color: context.iconSecondary),
                                  const SizedBox(height: 10),
                                  Text(
                                    _searchQuery.isEmpty
                                        ? 'دفتر الديون فارغ، أضف أول زبون الآن'
                                        : 'لا توجد نتائج مطابقة في القائمة الحالية',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        color: context.textSecondary),
                                  ),
                                  if (showRemoteSearchOption) ...[
                                    const SizedBox(height: 12),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      icon: const Icon(Icons.cloud_sync_rounded,
                                          size: 18),
                                      label: const Text(
                                        'بحث في كامل سجل الزبائن بالسحابة',
                                        style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      onPressed: () async {
                                        final results = await LedgerService
                                            .instance
                                            .searchCustomersRemotely(
                                          merchantId: merchantId,
                                          query: _searchQuery,
                                        );
                                        if (context.mounted &&
                                            results.isNotEmpty) {
                                          setState(() {
                                            for (final r in results) {
                                              if (!_remoteSearchResults
                                                  .any((ex) => ex.id == r.id)) {
                                                _remoteSearchResults.add(r);
                                              }
                                            }
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final c = filtered[index];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: context.bgCard,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: c.isOverLimit
                                          ? Colors.red.withValues(alpha: 0.4)
                                          : context.borderColor,
                                    ),
                                  ),
                                  child: ListTile(
                                    onLongPress: () async {
                                      HapticFeedback.heavyImpact();
                                      final hasDebt = c.currentBalance > 0;
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (dCtx) => AlertDialog(
                                          backgroundColor: dCtx.bgCard,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20)),
                                          title: Row(
                                            children: [
                                              Icon(Icons.warning_amber_rounded,
                                                  color: hasDebt
                                                      ? Colors.red
                                                      : Colors.orange),
                                              const SizedBox(width: 8),
                                              Text('حذف الزبون',
                                                  style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                      color: dCtx.textPrimary)),
                                            ],
                                          ),
                                          content: Text(
                                            hasDebt
                                                ? 'تنبيه مالي ⚠️: الزبون (${c.name}) في ذمته دين قدره (${c.currentBalance.toStringAsFixed(0)} ر.ي).\n\nحذفه سيشطب هذا الدين ويسقطه من إجمالي ديون السوق لديك.\n\nهل أنت متأكد من الحذف؟'
                                                : 'هل تريد حذف الزبون (${c.name}) نهائياً من الدفتر؟',
                                            style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 13,
                                                height: 1.6,
                                                color: dCtx.textSecondary),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dCtx, false),
                                              child: const Text('إلغاء',
                                                  style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      color: Colors.grey)),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.red),
                                              onPressed: () =>
                                                  Navigator.pop(dCtx, true),
                                              child: const Text('تأكيد الحذف',
                                                  style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirmed == true && mounted) {
                                        String? queuedMessage;
                                        try {
                                          await LedgerService.instance
                                              .deleteCustomer(
                                            merchantId: merchantId,
                                            customerId: c.id,
                                            currentBalance: c.currentBalance,
                                          );
                                        } on LedgerQueuedException catch (e) {
                                          queuedMessage = e.message;
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content:
                                                    Text('تعذر حذف الزبون: $e'),
                                                backgroundColor: Colors.red,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                          return;
                                        }

                                        if (mounted) {
                                          setState(() {
                                            _remoteSearchResults.removeWhere(
                                                (r) => r.id == c.id);
                                          });
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                queuedMessage ??
                                                    'تم حذف الزبون (${c.name}) بنجاح ✅',
                                                style: const TextStyle(
                                                    fontFamily: 'Cairo'),
                                              ),
                                              backgroundColor:
                                                  queuedMessage == null
                                                      ? Colors.red.shade700
                                                      : Colors.orange.shade700,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              duration:
                                                  const Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CustomerStatementScreen(
                                          customer: c,
                                          storeName: storeName,
                                        ),
                                      ),
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: c.currentBalance > 0
                                          ? Colors.red.withValues(alpha: 0.1)
                                          : Colors.green.withValues(alpha: 0.1),
                                      child: Text(
                                        c.name.isNotEmpty ? c.name[0] : 'ز',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold,
                                          color: c.currentBalance > 0
                                              ? Colors.red
                                              : Colors.green,
                                        ),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            c.name,
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                              color: context.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          '${c.currentBalance.toStringAsFixed(0)} ر.ي',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            color: c.currentBalance > 0
                                                ? Colors.red
                                                : Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Row(
                                      children: [
                                        Text(
                                          c.phone.isNotEmpty
                                              ? c.phone
                                              : 'بدون هاتف',
                                          style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: context.textSecondary),
                                        ),
                                        if (c.creditLimit > 0) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            '• السقف: ${c.creditLimit.toStringAsFixed(0)}',
                                            style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 10,
                                                color: c.isOverLimit
                                                    ? Colors.red
                                                    : Colors.grey),
                                          ),
                                        ],
                                      ],
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'تذكير واتساب',
                                      icon: const Icon(Icons.chat_rounded,
                                          color: Colors.green, size: 20),
                                      onPressed: () async {
                                        if (c.phone.trim().isEmpty) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  '⚠️ هذا الزبون لا يملك رقم هاتف مسجل للتذكير',
                                                  style: TextStyle(
                                                      fontFamily: 'Cairo')),
                                              backgroundColor: Colors.orange,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }
                                        final sent = await LedgerService
                                            .instance
                                            .sendWhatsAppReminder(
                                          customer: c,
                                          storeName: storeName,
                                        );
                                        if (!sent && context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'تعذر فتح تطبيق واتساب، تحقق من صحة الرقم',
                                                  style: TextStyle(
                                                      fontFamily: 'Cairo')),
                                              backgroundColor: Colors.red,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// كلاس نافذة إضافة الزبون كـ StatefulWidget مستقل تماماً
// ══════════════════════════════════════════════════════
class _AddCustomerDialog extends StatefulWidget {
  const _AddCustomerDialog();

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _limitCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _limitCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final merchantId = AppStorage.userId ?? '';
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
        '٩': '9'
      };
      var limitText = _limitCtrl.text.trim();
      arabic.forEach((k, v) => limitText = limitText.replaceAll(k, v));

      await LedgerService.instance.addCustomer(
        merchantId: merchantId,
        name: name,
        phone: _phoneCtrl.text.trim(),
        creditLimit: double.tryParse(limitText) ?? 0.0,
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } on LedgerQueuedException catch (e) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content:
                Text(e.message, style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر إضافة الزبون: ${e.toString().replaceAll("Exception: ", "").replaceAll("StateError: ", "")}',
              style: const TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: context.bgCard,
      title: Text(
        'إضافة زبون إلى دفتر الديون',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: context.textPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            style: TextStyle(fontFamily: 'Cairo', color: context.textPrimary),
            decoration: InputDecoration(
              hintText: 'اسم الزبون (مثال: أبو محمد جار المسجد)...',
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
          const SizedBox(height: 10),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            style: TextStyle(fontFamily: 'Cairo', color: context.textPrimary),
            decoration: InputDecoration(
              hintText: 'رقم الواتساب للتذكير (7xxxxxxxx)...',
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
          const SizedBox(height: 10),
          TextField(
            controller: _limitCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(fontFamily: 'Cairo', color: context.textPrimary),
            decoration: InputDecoration(
              hintText: 'سقف الدين المسموح به (اختياري)...',
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
          child: const Text(
            'إلغاء',
            style: TextStyle(fontFamily: 'Cairo', color: Colors.grey),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'إضافة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════
// كائن السلعة داخل جلسة كاشير الديون
// ══════════════════════════════════════════════════════
class _PosDebtItem {
  final String productId;
  final String productName;
  final double cartonPrice;
  final double cartonCapacity;
  String unitLabel; // 'حبة' أو 'كرتون'
  double unitPrice;
  int quantity;

  _PosDebtItem({
    required this.productId,
    required this.productName,
    required this.cartonPrice,
    required this.cartonCapacity,
    required this.unitLabel,
    required this.unitPrice,
    this.quantity = 1,
  });

  double get total => unitPrice * quantity;
}

// ══════════════════════════════════════════════════════
// شيت جلسة كاشير الديون بالباركود
// ══════════════════════════════════════════════════════
class _DebtPosSheet extends StatefulWidget {
  final List<LedgerCustomer> customers;
  final LedgerCustomer initialCustomer;

  const _DebtPosSheet({
    required this.customers,
    required this.initialCustomer,
  });

  @override
  State<_DebtPosSheet> createState() => _DebtPosSheetState();
}

class _DebtPosSheetState extends State<_DebtPosSheet> {
  late LedgerCustomer _selectedCustomer;
  final List<_PosDebtItem> _items = [];
  bool _isSaving = false;
  String? _billTransactionId; // 🔒 مفتاح التثبيت المالي لمنع تكرار الفاتورة

  @override
  void initState() {
    super.initState();
    _selectedCustomer = widget.initialCustomer;
  }

  double get _grandTotal => _items.fold(0.0, (sum, i) => sum + i.total);
// ── دالة إضافة سلعة يدوياً بدون باركود (بالاسم والسعر والوحدة كتابة حرة) ──
  Future<void> _addManualItem() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final unitCtrl = TextEditingController(text: ''); // تبدأ فارغة على "لاشيء"

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: ctx.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_note_rounded,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                'إضافة سلعة بدون باركود ✍️',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: ctx.textPrimary,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: TextStyle(fontFamily: 'Cairo', color: ctx.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'اسم السلعة (مثال: روتي، بيض، شاي)...',
                    hintStyle: TextStyle(
                        fontFamily: 'Cairo', fontSize: 12, color: ctx.textHint),
                    filled: true,
                    fillColor: ctx.bgInput,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
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
                        '٩': '9'
                      };
                      var t = newVal.text;
                      arabic.forEach((k, v) => t = t.replaceAll(k, v));
                      t = t.replaceAll(RegExp(r'[^0-9.]'), '');
                      return TextEditingValue(
                          text: t,
                          selection: TextSelection.collapsed(offset: t.length));
                    }),
                  ],
                  decoration: InputDecoration(
                    hintText: 'السعر ر.ي *',
                    hintStyle: TextStyle(
                        fontFamily: 'Cairo', fontSize: 13, color: ctx.textHint),
                    filled: true,
                    fillColor: ctx.bgInput,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    // حقل الكمية
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: ctx.textPrimary),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          hintText: 'الكمية',
                          filled: true,
                          fillColor: ctx.bgInput,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // حقل كتابة الوحدة بحرية يدوياً (محددة مسبقاً على لا شيء)
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: unitCtrl,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: ctx.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'الوحدة (كتابة: كيس، حبة)...',
                          hintStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: ctx.textHint),
                          filled: true,
                          fillColor: ctx.bgInput,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // أزرار سريعة لاختيار الوحدة بنقرة واحدة وتعبئتها في الحقل كتابياً
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        ['حبة', 'كيس', 'كرتون', 'كيلو', 'صحن', 'ربطة'].map((u) {
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 5),
                        child: ActionChip(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          label: Text(u,
                              style: const TextStyle(
                                  fontFamily: 'Cairo', fontSize: 11)),
                          backgroundColor: ctx.bgInput,
                          onPressed: () {
                            setDialogState(() => unitCtrl.text = u);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('إلغاء',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final name = nameCtrl.text.trim();
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
                  '٩': '9'
                };
                var priceText = priceCtrl.text.trim();
                arabic
                    .forEach((k, v) => priceText = priceText.replaceAll(k, v));
                final price = double.tryParse(priceText);
                final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
                final customUnit = unitCtrl.text.trim();

                if (name.isEmpty || price == null || price <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('يرجى كتابة اسم السلعة وسعرها بشكل صحيح')),
                  );
                  return;
                }

                setState(() {
                  _items.add(_PosDebtItem(
                    productId:
                        'manual_${DateTime.now().millisecondsSinceEpoch}',
                    productName: name,
                    cartonPrice: price,
                    cartonCapacity: 1,
                    unitLabel:
                        customUnit, // الوحدة التي كتبها التاجر بيده أو فارغة
                    unitPrice: price,
                    quantity: qty > 0 ? qty : 1,
                  ));
                });
                SupermarketSoundHelper.playSupermarketBeep();
                Navigator.pop(dialogCtx, true);
              },
              child: const Text('إضافة للفاتورة',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

// ── 1. دالة مسح الباركود للدفتر: إغلاق الكاميرا فوراً وطلب السعر لأول مرة فقط ──
  Future<void> _scanItem() async {
    final matchedProduct =
        await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(
          findProductMode: true,
          continuousMode: false,
        ),
      ),
    );

    if (matchedProduct == null || !mounted) return;

    final productId = matchedProduct['id']?.toString() ?? '';
    final productName = matchedProduct['name']?.toString() ?? 'سلعة';
    final cartonPrice = (matchedProduct['price'] as num?)?.toDouble() ?? 0.0;
    final cartonCapacity =
        ((matchedProduct['items_per_carton'] as num?)?.toInt() ?? 1).toDouble();
    final merchantId = AppStorage.userId ?? '';

    // 1. فحص هل تم تسعير الحبة مسبقاً لهذا الصنف في دفتر التاجر
    double? piecePrice =
        await LedgerService.instance.getSavedPiecePrice(merchantId, productId);

    // 2. إذا كانت أول مرة يمسح فيها التاجر هذا الصنف: تظهر نافذة إدخال السعر
    if (piecePrice == null || piecePrice <= 0) {
      final safeCapacity = cartonCapacity > 0 ? cartonCapacity : 1.0;
      final suggested = (cartonPrice / safeCapacity).ceilToDouble();

      piecePrice = await promptFirstTimePiecePrice(
        productName: productName,
        cartonPrice: cartonPrice,
        cartonCapacity: cartonCapacity,
        suggested: suggested,
      );

      // إذا تراجع التاجر أو ألغى نافذة السعر لا نضيف السلعة
      if (piecePrice == null || piecePrice <= 0 || !mounted) return;

      // حفظ السعر المدخل في السحابة وذاكرة الهاتف ليتذكره دائماً للمرات القادمة
      await LedgerService.instance
          .setSavedPiecePrice(merchantId, productId, piecePrice);
    }

    // 3. إضافة الصنف مباشرة للفاتورة وإظهاره أمام التاجر
    setState(() {
      final existingIdx = _items
          .indexWhere((i) => i.productId == productId && i.unitLabel == 'حبة');
      if (existingIdx != -1) {
        _items[existingIdx].quantity += 1;
      } else {
        _items.add(_PosDebtItem(
          productId: productId,
          productName: productName,
          cartonPrice: cartonPrice,
          cartonCapacity: cartonCapacity,
          unitLabel: 'حبة',
          unitPrice: piecePrice!,
          quantity: 1,
        ));
      }
    });

    SupermarketSoundHelper.playSupermarketBeep();
  }

  // ── 2. حوار تحديد سعر الحبة لأول مرة ──
  Future<double?> promptFirstTimePiecePrice({
    required String productName,
    required double cartonPrice,
    required double cartonCapacity,
    required double suggested,
  }) async {
    final ctrl = TextEditingController(
      text: suggested > 0 ? suggested.toStringAsFixed(0) : '',
    );
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: dialogCtx.bgCard,
        title: const Text(
          'تحديد سعر الحبة لأول مرة 🏷️',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.primary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              productName,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: dialogCtx.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'سعر الكرتون: ${cartonPrice.toStringAsFixed(0)} ر.ي (${cartonCapacity.toInt()} حبة)',
              style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary),
              decoration: InputDecoration(
                hintText: 'سعر بيع الحبة',
                filled: true,
                fillColor: dialogCtx.bgInput,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 2)),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '💡 سيحفظ التطبيق هذا السعر لتسجيل الديون القادمة تلقائياً',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, null),
            child: const Text('إلغاء',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
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
                '٩': '9'
              };
              var clean = ctrl.text.trim();
              arabic.forEach((k, v) => clean = clean.replaceAll(k, v));
              final val = double.tryParse(clean);
              Navigator.pop(dialogCtx, val);
            },
            child: const Text('حفظ واعتماد',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── 3. شيت ضبط تفاصيل السلعة ──
  Future<void> showProductConfigureSheet({
    required String productId,
    required String productName,
    required double cartonPrice,
    required double cartonCapacity,
    required double initialPiecePrice,
    required String merchantId,
  }) async {
    String selectedUnit = 'حبة';
    double currentUnitPrice = initialPiecePrice;
    int qty = 1;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetSt) {
          final total = currentUnitPrice * qty;

          return Container(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            decoration: BoxDecoration(
              color: ctx.bgCard,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 12),
                Text(
                  productName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: ctx.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: Text(
                          'حبة (${initialPiecePrice.toStringAsFixed(0)} ر.ي)',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: selectedUnit == 'حبة'
                                  ? FontWeight.w900
                                  : FontWeight.w600)),
                      selected: selectedUnit == 'حبة',
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                          color: selectedUnit == 'حبة'
                              ? Colors.white
                              : ctx.textPrimary),
                      onSelected: (val) {
                        if (val) {
                          setSheetSt(() {
                            selectedUnit = 'حبة';
                            currentUnitPrice = initialPiecePrice;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(
                          'كرتون (${cartonPrice.toStringAsFixed(0)} ر.ي)',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: selectedUnit == 'كرتون'
                                  ? FontWeight.w900
                                  : FontWeight.w600)),
                      selected: selectedUnit == 'كرتون',
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                          color: selectedUnit == 'كرتون'
                              ? Colors.white
                              : ctx.textPrimary),
                      onSelected: (val) {
                        if (val) {
                          setSheetSt(() {
                            selectedUnit = 'كرتون';
                            currentUnitPrice = cartonPrice;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: ctx.bgInput,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ctx.borderColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'سعر ال$selectedUnit:',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: ctx.textSecondary),
                      ),
                      Row(
                        children: [
                          Text(
                            '${currentUnitPrice.toStringAsFixed(0)} ر.ي',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.edit_rounded,
                                size: 20, color: Colors.orange),
                            tooltip: 'تعديل السعر',
                            onPressed: () async {
                              final ctrl = TextEditingController(
                                  text: currentUnitPrice.toStringAsFixed(0));
                              final newP = await showDialog<double>(
                                context: ctx,
                                builder: (dCtx) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                  backgroundColor: dCtx.bgCard,
                                  title: Text('تعديل سعر ال$selectedUnit',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          color: dCtx.textPrimary,
                                          fontWeight: FontWeight.w900)),
                                  content: TextField(
                                    controller: ctrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    autofocus: true,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 26,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w900),
                                  ),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(dCtx),
                                        child: const Text('إلغاء')),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary),
                                      onPressed: () => Navigator.pop(dCtx,
                                          double.tryParse(ctrl.text.trim())),
                                      child: const Text('حفظ',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );
                              if (newP != null && newP > 0) {
                                setSheetSt(() {
                                  currentUnitPrice = newP;
                                  if (selectedUnit == 'حبة') {
                                    initialPiecePrice = newP;
                                    LedgerService.instance.setSavedPiecePrice(
                                        merchantId, productId, newP);
                                  }
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          size: 36, color: Colors.redAccent),
                      onPressed: () {
                        if (qty > 1) {
                          HapticFeedback.lightImpact();
                          setSheetSt(() => qty--);
                        }
                      },
                    ),
                    const SizedBox(width: 20),
                    Text(
                      '$qty',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: ctx.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 20),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline,
                          color: AppColors.primary, size: 36),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        setSheetSt(() => qty++);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      Navigator.pop(sheetCtx);
                      if (mounted) {
                        setState(() {
                          final existingIdx = _items.indexWhere((i) =>
                              i.productId == productId &&
                              i.unitLabel == selectedUnit);
                          if (existingIdx != -1) {
                            _items[existingIdx].quantity += qty;
                            _items[existingIdx].unitPrice = currentUnitPrice;
                          } else {
                            _items.add(_PosDebtItem(
                              productId: productId,
                              productName: productName,
                              cartonPrice: cartonPrice,
                              cartonCapacity: cartonCapacity,
                              unitLabel: selectedUnit,
                              unitPrice: currentUnitPrice,
                              quantity: qty,
                            ));
                          }
                        });
                      }
                    },
                    child: Text(
                      'إضافة للفاتورة (${total.toStringAsFixed(0)} ر.ي)',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── 4. اعتماد وحفظ الفاتورة الكاملة بتحصين مالي مشدد ──
  Future<void> _submitFullBill() async {
    if (_items.isEmpty || _grandTotal <= 0 || _isSaving) return;

    // حماية ضد النقرات المتعددة وتجميد فوري للواجهة
    setState(() => _isSaving = true);
    HapticFeedback.heavyImpact();
    if (_selectedCustomer.creditLimit > 0) {
      final projected = _selectedCustomer.currentBalance + _grandTotal;
      if (projected > _selectedCustomer.creditLimit) {
        final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: dialogCtx.bgCard,
            title: const Text('⚠️ تجاوز سقف الدين',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            content: Text(
              'هذه الفاتورة سترفع حساب الزبون إلى ${projected.toStringAsFixed(0)} ر.ي، متجاوزة السقف المحدد (${_selectedCustomer.creditLimit.toStringAsFixed(0)} ر.ي).\n\nهل تريد اعتماد الفاتورة؟',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: const Text('متابعة الاعتماد',
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

    final merchantId = AppStorage.userId ?? '';
    final safeMId =
        merchantId.length > 5 ? merchantId.substring(0, 5) : merchantId;
    _billTransactionId ??=
        'pos_${safeMId}_${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_${_selectedCustomer.id.substring(0, _selectedCustomer.id.length > 4 ? 4 : _selectedCustomer.id.length)}';
    try {
      final itemsPayload = _items.map((i) {
        return {
          'product_id': i.productId,
          'name': '${i.productName} (${i.unitLabel})',
          'quantity': i.quantity,
          'unit_label': i.unitLabel,
          'unit_price': i.unitPrice,
          'subtotal': i.total,
          'carton_capacity': i.cartonCapacity,
        };
      }).toList();

      await LedgerService.instance.recordTransaction(
        merchantId: merchantId,
        customerId: _selectedCustomer.id,
        type: 'debt',
        amount: _grandTotal,
        notes: null,
        items: itemsPayload,
        transactionId: _billTransactionId,
      );
      _billTransactionId = null; // تصفير المعرف فقط عند النجاح التام
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '✅ تم قيد الفاتورة (${_grandTotal.toStringAsFixed(0)} ر.ي) في حساب (${_selectedCustomer.name}) بنجاح',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 3),
        ),
      );
    } on LedgerQueuedException catch (e) {
      // 🔒 التقاط استثناء الأوفلاين المعتمد وإغلاق النافذة فوراً لمنع الضغط المتكرر
      _billTransactionId = null;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '📡 ${e.message} (${_grandTotal.toStringAsFixed(0)} ر.ي)',
            style: const TextStyle(
                fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      final isNetworkOrTimeout = e is TimeoutException ||
          errStr.contains('socket') ||
          errStr.contains('network') ||
          errStr.contains('timeout') ||
          errStr.contains('unavailable') ||
          errStr.contains('host lookup') ||
          errStr.contains('connection');

      if (isNetworkOrTimeout) {
        _billTransactionId = null;
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '📡 تم تأمين الفاتورة (${_grandTotal.toStringAsFixed(0)} ر.ي) أوفلاين وستُرحل فور توفر الإنترنت',
              style: const TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الحفظ: $e',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSaving,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: context.bgInput,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.12),
                      child: Text(
                        _selectedCustomer.name.isNotEmpty
                            ? _selectedCustomer.name[0]
                            : 'ز',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedCustomer.name,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: context.textPrimary,
                            ),
                          ),
                          Text(
                            'الدين السابق: ${_selectedCustomer.currentBalance.toStringAsFixed(0)} ر.ي',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final selected =
                            await showModalBottomSheet<LedgerCustomer>(
                          context: context,
                          isScrollControlled: true,
                          useRootNavigator: true,
                          backgroundColor: Colors.transparent,
                          builder: (sCtx) {
                            final searchCtrl = TextEditingController();
                            return StatefulBuilder(
                              builder: (sheetCtx, setSheetSt) {
                                final q = searchCtrl.text.trim().toLowerCase();
                                final sheetList = q.isEmpty
                                    ? widget.customers
                                    : widget.customers
                                        .where((c) =>
                                            c.name.toLowerCase().contains(q) ||
                                            c.phone.contains(q))
                                        .toList();

                                return Container(
                                  height: MediaQuery.of(sheetCtx).size.height *
                                      0.75,
                                  padding: EdgeInsets.fromLTRB(
                                      16,
                                      16,
                                      16,
                                      MediaQuery.of(sheetCtx)
                                              .viewInsets
                                              .bottom +
                                          16),
                                  decoration: BoxDecoration(
                                    color: sheetCtx.bgCard,
                                    borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(24)),
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 4,
                                        decoration: BoxDecoration(
                                            color: Colors.grey.shade300,
                                            borderRadius:
                                                BorderRadius.circular(2)),
                                      ),
                                      const SizedBox(height: 14),
                                      TextField(
                                        controller: searchCtrl,
                                        autofocus: true,
                                        style: TextStyle(
                                            fontFamily: 'Cairo',
                                            color: sheetCtx.textPrimary),
                                        onChanged: (text) async {
                                          setSheetSt(() {});
                                          if (text.trim().isNotEmpty &&
                                              sheetList.isEmpty) {
                                            final remoteResults =
                                                await LedgerService.instance
                                                    .searchCustomersRemotely(
                                              merchantId:
                                                  AppStorage.userId ?? '',
                                              query: text.trim(),
                                            );
                                            if (remoteResults.isNotEmpty) {
                                              setSheetSt(() {
                                                for (final r in remoteResults) {
                                                  if (!widget.customers.any(
                                                      (c) => c.id == r.id)) {
                                                    widget.customers.add(r);
                                                  }
                                                }
                                              });
                                            }
                                          }
                                        },
                                        decoration: InputDecoration(
                                          hintText:
                                              'ابحث عن اسم الزبون لتحديده (محلياً وسحابياً)...',
                                          hintStyle: TextStyle(
                                              fontFamily: 'Cairo',
                                              color: sheetCtx.textHint),
                                          prefixIcon:
                                              const Icon(Icons.search_rounded),
                                          filled: true,
                                          fillColor: sheetCtx.bgInput,
                                          border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              borderSide: BorderSide.none),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 10),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Expanded(
                                        child: ListView.builder(
                                          itemCount: sheetList.length,
                                          itemBuilder: (_, i) {
                                            final item = sheetList[i];
                                            return ListTile(
                                              leading: CircleAvatar(
                                                backgroundColor: AppColors
                                                    .primary
                                                    .withValues(alpha: 0.1),
                                                child: Text(
                                                    item.name.isNotEmpty
                                                        ? item.name[0]
                                                        : 'ز',
                                                    style: const TextStyle(
                                                        color:
                                                            AppColors.primary,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                              ),
                                              title: Text(item.name,
                                                  style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      color:
                                                          sheetCtx.textPrimary,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              subtitle: Text(item.phone,
                                                  style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      color: sheetCtx
                                                          .textSecondary,
                                                      fontSize: 11)),
                                              trailing: Text(
                                                  '${item.currentBalance.toStringAsFixed(0)} ر.ي',
                                                  style: const TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: Colors.red)),
                                              onTap: () {
                                                FocusScope.of(sheetCtx)
                                                    .unfocus();
                                                Navigator.pop(sCtx, item);
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        );
                        if (selected != null && mounted) {
                          setState(() => _selectedCustomer = selected);
                        }
                      },
                      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                      label: const Text('تغيير الزبون',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  // ── زر مسح الباركود بالعدسة ──
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _scanItem,
                        icon:
                            const Icon(Icons.qr_code_scanner_rounded, size: 20),
                        label: const Text(
                          'مسح باركود [📷]',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // ── زر إضافة صنف يدوي بدون باركود ──
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(
                              color: AppColors.primary, width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _addManualItem,
                        icon: const Icon(Icons.edit_note_rounded, size: 20),
                        label: const Text(
                          'بدون باركود ✍️',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shopping_cart_outlined,
                              size: 50, color: context.iconSecondary),
                          const SizedBox(height: 10),
                          Text(
                            'الفاتورة فارغة حالياً.\nامسح باركود السلعة أو أضفها يدوياً بالاسم والسعر.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                color: context.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: _items.length,
                      itemBuilder: (context, idx) {
                        final item = _items[idx];
                        final merchantId = AppStorage.userId ?? '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.bgInput,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item.productName} (${item.unitLabel})',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: context.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.red,
                                        size: 20),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      setState(() => _items.removeAt(idx));
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () async {
                                      HapticFeedback.lightImpact();
                                      final ctrl = TextEditingController(
                                          text: item.unitPrice
                                              .toStringAsFixed(0));
                                      final newPrice = await showDialog<double>(
                                        context: context,
                                        builder: (dCtx) => AlertDialog(
                                          backgroundColor: dCtx.bgCard,
                                          title: Text(
                                            'تعديل سعر ${item.unitLabel}',
                                            style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontWeight: FontWeight.bold,
                                                color: dCtx.textPrimary,
                                                fontSize: 15),
                                          ),
                                          content: TextField(
                                            controller: ctrl,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                decimal: true),
                                            autofocus: true,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dCtx),
                                              child: const Text('إلغاء'),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.primary,
                                                foregroundColor: Colors.white,
                                              ),
                                              onPressed: () => Navigator.pop(
                                                  dCtx,
                                                  double.tryParse(
                                                      ctrl.text.trim())),
                                              child: const Text('حفظ'),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (newPrice != null && newPrice > 0) {
                                        setState(() {
                                          item.unitPrice = newPrice;
                                          if (item.unitLabel == 'حبة') {
                                            LedgerService.instance
                                                .setSavedPiecePrice(merchantId,
                                                    item.productId, newPrice);
                                          }
                                        });
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.25)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${item.unitPrice.toStringAsFixed(0)} ر.ي',
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.edit_rounded,
                                              size: 13,
                                              color: AppColors.primary),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: context.bgCard,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: context.borderColor),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove_rounded,
                                              size: 16),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 30, minHeight: 30),
                                          onPressed: () {
                                            HapticFeedback.lightImpact();
                                            setState(() {
                                              if (item.quantity > 1) {
                                                item.quantity--;
                                              } else {
                                                _items.removeAt(idx);
                                              }
                                            });
                                          },
                                        ),
                                        GestureDetector(
                                          onTap: () async {
                                            final qCtrl = TextEditingController(
                                                text: '${item.quantity}');
                                            final manualQ =
                                                await showDialog<int>(
                                              context: context,
                                              builder: (qCtx) => AlertDialog(
                                                backgroundColor: qCtx.bgCard,
                                                title: Text('أدخل الكمية',
                                                    style: TextStyle(
                                                        fontFamily: 'Cairo',
                                                        color:
                                                            qCtx.textPrimary)),
                                                content: TextField(
                                                  controller: qCtrl,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  autofocus: true,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontSize: 22,
                                                      color: qCtx.textPrimary,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                                actions: [
                                                  ElevatedButton(
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          AppColors.primary,
                                                      foregroundColor:
                                                          Colors.white,
                                                    ),
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            qCtx,
                                                            int.tryParse(qCtrl
                                                                .text
                                                                .trim())),
                                                    child: const Text('تأكيد'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (manualQ != null &&
                                                manualQ > 0) {
                                              setState(() =>
                                                  item.quantity = manualQ);
                                            }
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8),
                                            child: Text(
                                              '${item.quantity}',
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                                color: context.textPrimary,
                                              ),
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add_rounded,
                                              size: 16,
                                              color: AppColors.primary),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 30, minHeight: 30),
                                          onPressed: () {
                                            HapticFeedback.lightImpact();
                                            setState(() => item.quantity++);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${item.total.toStringAsFixed(0)} ر.ي',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.bgCard,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'الأصناف: ${_items.length}',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.textSecondary,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            'الإجمالي: ',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          Text(
                            '${_grandTotal.toStringAsFixed(0)} ر.ي',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: (_items.isEmpty || _isSaving)
                          ? null
                          : _submitFullBill,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check_circle_rounded, size: 22),
                      label: Text(
                        _isSaving
                            ? 'جاري الحفظ والقيد...'
                            : 'تسجيل في حساب (${_selectedCustomer.name})',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
