import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../services/admin_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminReturnsPaginationState {
  final List<Map<String, dynamic>> returns;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;

  const AdminReturnsPaginationState({
    required this.returns,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  AdminReturnsPaginationState copyWith({
    List<Map<String, dynamic>>? returns,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
  }) {
    return AdminReturnsPaginationState(
      returns: returns ?? this.returns,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

class AdminReturnsPaginationNotifier
    extends StateNotifier<AdminReturnsPaginationState> {
  static const int _pageSize = 30;
  DocumentSnapshot? _lastDoc;

  AdminReturnsPaginationNotifier()
      : super(const AdminReturnsPaginationState(returns: [], isLoading: true)) {
    loadInitial();
  }

  // 🚀 تحديث محلي فوري (0ms) للواجهة دون أي انتظار
  void updateLocally(String returnId, String newStatus,
      {String? rejectionReason}) {
    final updated = state.returns.map((r) {
      if (r['id']?.toString() == returnId) {
        return {
          ...r,
          'status': newStatus,
          if (rejectionReason != null) 'rejection_reason': rejectionReason,
        };
      }
      return r;
    }).toList();
    state = state.copyWith(returns: updated);
  }

  Future<void> loadInitial() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      // 🚀 إزالة التعارض لجعل الاستعلام يعمل فوراً بدون طلب Composite Index
      final snap = await FirebaseFirestore.instance
          .collection('order_returns')
          .orderBy('created_at', descending: true)
          .limit(_pageSize)
          .get();
      if (!mounted) return;
      _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      final returns = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

      state = state.copyWith(
        returns: returns,
        isLoading: false,
        hasMore: snap.docs.length == _pageSize,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || _lastDoc == null) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('order_returns')
          .orderBy('created_at', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize)
          .get();
      if (!mounted) return;
      _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      final more = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

      final map = {for (final r in state.returns) r['id'].toString(): r};
      for (final r in more) {
        map[r['id'].toString()] = r;
      }

      state = state.copyWith(
        returns: map.values.toList(),
        isLoadingMore: false,
        hasMore: snap.docs.length == _pageSize,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }
}

final adminReturnsPaginationProvider = StateNotifierProvider.autoDispose<
    AdminReturnsPaginationNotifier, AdminReturnsPaginationState>((ref) {
  return AdminReturnsPaginationNotifier();
});

class AdminReturnsTab extends ConsumerWidget {
  const AdminReturnsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paginationState = ref.watch(adminReturnsPaginationProvider);
    final notifier = ref.read(adminReturnsPaginationProvider.notifier);

    return SafeArea(
      child: Column(
        children: [
          // ── العنوان ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('المرجوعات',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A2E))),
                      Text(
                        'إجمالي المرجوعات المحملة: ${paginationState.returns.length}',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded,
                      color: AppColors.primary),
                  onPressed: () => notifier.loadInitial(),
                ),
              ],
            ),
          ),

          // ── القائمة مع التصفح ──
          Expanded(
            child: paginationState.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : paginationState.error != null
                    ? Center(
                        child: Text('خطأ: ${paginationState.error}',
                            style: const TextStyle(fontFamily: 'Cairo')))
                    : paginationState.returns.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.assignment_return_outlined,
                                    size: 64, color: Colors.grey[300]),
                                const SizedBox(height: 12),
                                Text('لا توجد مرجوعات',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        color: Colors.grey[500])),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            color: AppColors.primary,
                            onRefresh: () async => notifier.loadInitial(),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: paginationState.returns.length +
                                  (paginationState.hasMore ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i == paginationState.returns.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    child: Center(
                                      child: TextButton.icon(
                                        onPressed: paginationState.isLoadingMore
                                            ? null
                                            : () => notifier.loadMore(),
                                        icon: paginationState.isLoadingMore
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              )
                                            : const Icon(
                                                Icons.arrow_downward_rounded),
                                        label: const Text(
                                          'تحميل المزيد من المرجوعات',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return _ReturnCard(
                                  data: paginationState.returns[i],
                                  onStatusChanged: () => notifier.loadInitial(),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════
// بطاقة الإرجاع
// ════════════════════════════════════════
class _ReturnCard extends ConsumerWidget {
  final Map<String, dynamic> data;
  final VoidCallback onStatusChanged;
  const _ReturnCard({required this.data, required this.onStatusChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = data['status']?.toString() ?? 'pending';
    final productName = data['product_name']?.toString() ?? 'منتج';
    final qty = (data['quantity'] as num?)?.toInt() ?? 0;
    final reason = data['reason']?.toString() ?? '';
    final storeName = data['store_name']?.toString() ?? '';
    final contact = data['contact']?.toString() ?? '';
    final createdAt = data['created_at'] != null
        ? (data['created_at'] is Timestamp
            ? (data['created_at'] as Timestamp).toDate()
            : DateTime.tryParse(data['created_at'].toString()))
        : null;

    final orderId = data['order_id']?.toString() ?? '';
    final phone = contact;
    final invoiceNum = orderId.isNotEmpty && orderId.length >= 8
        ? orderId.substring(0, 8).toUpperCase()
        : orderId;
    final displayStore = storeName.isNotEmpty
        ? storeName
        : (contact.isNotEmpty ? 'هاتف: $contact' : 'عميل #$invoiceNum');
    final customerPersonName =
        (data['customer_name'] ?? data['merchant_name'] ?? '')
            .toString()
            .trim();
    final (statusLabel, statusColor) = switch (status) {
      'accepted' => ('مقبول ✓', Colors.green),
      'rejected' => ('مرفوض ✗', Colors.red),
      _ => ('قيد المراجعة', Colors.orange),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── رأس ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.assignment_return_rounded,
                      color: statusColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayStore,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Color(0xFF1A1A2E)),
                      ),
                      if (customerPersonName.isNotEmpty &&
                          customerPersonName != displayStore)
                        Text(customerPersonName,
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: Colors.grey[500])),
                      if (phone.isNotEmpty)
                        Text(phone,
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: Colors.grey[500])),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(statusLabel,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor)),
                    ),
                    if (invoiceNum.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(invoiceNum,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              color: Colors.grey)),
                    ],
                    if (createdAt != null)
                      Text(
                        '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10,
                            color: Colors.grey),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── المنتج ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(productName,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$qty كرتون',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: statusColor)),
                ),
              ],
            ),
          ),

          // ── السبب ──
          if (reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('سبب الإرجاع: $reason',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.orange,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),

          // ── أزرار القبول / الرفض (للمعلقة فقط) ──
          if (status == 'pending')
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmReject(
                          context, ref, data['id']?.toString() ?? ''),
                      icon: const Icon(Icons.close_rounded,
                          size: 16, color: Colors.red),
                      label: const Text('رفض',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700,
                              color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _updateStatus(context, ref,
                          data['id']?.toString() ?? '', 'accepted'),
                      icon: const Icon(Icons.check_rounded,
                          size: 16, color: Colors.white),
                      label: const Text('قبول',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 14),
        ],
      ),
    );
  }

  Future<void> _confirmReject(
      BuildContext context, WidgetRef ref, String returnId) async {
    String? enteredReason;
    await showDialog(
      context: context,
      builder: (ctx) {
        final reasonCtrl = TextEditingController();
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            'رفض طلب الإرجاع',
            style: TextStyle(
                fontFamily: 'Cairo', fontWeight: FontWeight.w800, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'اكتب سبب الرفض ليظهر للتاجر في السجل والإشعار:',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                decoration: InputDecoration(
                  hintText:
                      'مثال: المنتج مستخدم / تلف سوء تخزين / مضت مهلة الإرجاع...',
                  hintStyle: const TextStyle(
                      fontFamily: 'Cairo', fontSize: 11, color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFB),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(ctx).unfocus();
                Navigator.pop(ctx);
              },
              child: const Text('إلغاء',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                enteredReason = reasonCtrl.text.trim();
                FocusScope.of(ctx).unfocus();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('تأكيد الرفض',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );

    if (enteredReason != null && context.mounted) {
      _updateStatus(context, ref, returnId, 'rejected',
          rejectionReason: enteredReason!.isNotEmpty ? enteredReason : null);
    }
  }

  Future<void> _updateStatus(
      BuildContext context, WidgetRef ref, String returnId, String newStatus,
      {String? rejectionReason}) async {
    if (returnId.isEmpty) return;

    HapticFeedback.mediumImpact();

    // 🚀 تطبيق التحديث فوراً في جزء من الثانية (0ms) بدون أي تعليق أو انتظار
    ref.read(adminReturnsPaginationProvider.notifier).updateLocally(
          returnId,
          newStatus,
          rejectionReason: rejectionReason,
        );

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        newStatus == 'accepted' ? 'تم قبول الإرجاع بنجاح ✓' : 'تم رفض الإرجاع',
        style: const TextStyle(fontFamily: 'Cairo'),
      ),
      backgroundColor: newStatus == 'accepted' ? Colors.green : Colors.red,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));

    // إرسال التحديث للسيرفر في الخلفية
    try {
      await ref.read(adminServiceProvider).updateReturnStatus(
            returnId,
            newStatus,
            rejectionReason: rejectionReason,
          );
    } catch (e) {
      // في حال فشل الشبكة يتم استرجاع الحالة السابقة فوراً
      ref.read(adminReturnsPaginationProvider.notifier).updateLocally(
            returnId,
            'pending',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل الاتصال: $e',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
        ));
      }
    }
  }
}
