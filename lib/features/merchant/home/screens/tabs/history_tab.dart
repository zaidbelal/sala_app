import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_radius.dart';
import '../../../../../core/services/local_storage.dart';
import '../../../orders/models/order_model.dart';
import '../../../orders/services/orders_service.dart';
import '../../../invoice/invoice_screen.dart';
import '../../../invoice/return_invoice_screen.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

class HistoryTab extends ConsumerStatefulWidget {
  const HistoryTab({super.key});

  @override
  ConsumerState<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<HistoryTab> {
  Key _key = UniqueKey();
  static const _historyStatuses = ['delivered', 'returned', 'return_requested'];
  Stream<List<OrderModel>>? _ordersStream;
  Stream<List<Map<String, dynamic>>>? _returnsStream;
  String? _cachedUid;

  void _initStreams() {
    final uid = AppStorage.userId ?? '';
    _cachedUid = uid;
    _ordersStream =
        OrdersService.watchMerchantOrdersByStatuses(uid, _historyStatuses);
    _returnsStream = OrdersService.watchMerchantReturns(uid);
  }

  void _refresh() {
    setState(() {
      _key = UniqueKey();
      _initStreams();
    });
  }

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  @override
  Widget build(BuildContext context) {
    final uid = AppStorage.userId ?? '';
    if (_cachedUid != uid || _ordersStream == null) {
      _initStreams();
    }

    return StreamBuilder<List<OrderModel>>(
      key: _key,
      stream: _ordersStream,
      builder: (context, orderSnap) {
        if (orderSnap.hasError) {
          return Scaffold(
            backgroundColor: context.bgPage,
            body: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async => _refresh(),
              child: ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sync_problem_rounded,
                            size: 72, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('تعذر جلب السجل حالياً',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary)),
                        const SizedBox(height: 6),
                        Text('تحقق من الاتصال بالشبكة أو اضغط لتحديث البيانات',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                color: context.textSecondary)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('تحديث البيانات',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 12),
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

        if (orderSnap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }

        final orders = (orderSnap.data ?? [])
            .where((o) =>
                o.status == OrderStatus.delivered ||
                o.status == OrderStatus.returned ||
                o.status == OrderStatus.returnRequested)
            .toList();

        // الاستماع لفواتير المرتجعات المقبولة
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _returnsStream,
          builder: (context, returnSnap) {
            final rawReturns = returnSnap.data ?? [];
            final returnInvoices =
                rawReturns.map((m) => ReturnInvoiceModel.fromMap(m)).toList();

            // دمج الفواتير العادية مع فواتير الإرجاع وترتيبها تنازلياً حسب التاريخ
            final combinedItems = <dynamic>[...orders, ...returnInvoices]
              ..sort((a, b) {
                final DateTime dateA = a is OrderModel
                    ? a.createdAt
                    : (a as ReturnInvoiceModel).createdAt;
                final DateTime dateB = b is OrderModel
                    ? b.createdAt
                    : (b as ReturnInvoiceModel).createdAt;
                return dateB.compareTo(dateA);
              });

            return Scaffold(
              backgroundColor: context.bgPage,
              body: SafeArea(
                child: Column(
                  children: [
                    _HistoryHeader.from(orders, returnInvoices),
                    if (combinedItems.isEmpty)
                      const Expanded(child: _EmptyHistory())
                    else
                      Expanded(
                        child: RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: () async => _refresh(),
                          child: _OrdersList(items: combinedItems),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ══════════════════════════════════════════
// Header + إحصائيات
// ══════════════════════════════════════════
class _HistoryHeader extends StatelessWidget {
  final int thisMonthCount;
  final int returnedCount;
  final double totalSpent;

  factory _HistoryHeader.from(
      List<OrderModel> orders, List<ReturnInvoiceModel> returnInvoices) {
    final now = DateTime.now();
    int thisMonth = 0;
    double spent = 0;

    for (final o in orders) {
      if (o.createdAt.year == now.year && o.createdAt.month == now.month) {
        thisMonth++;
      }
      if (o.status == OrderStatus.delivered) spent += o.total;
    }

    return _HistoryHeader._(
      thisMonthCount: thisMonth,
      returnedCount: returnInvoices.length,
      totalSpent: spent,
    );
  }

  const _HistoryHeader._({
    required this.thisMonthCount,
    required this.returnedCount,
    required this.totalSpent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.bgHeader,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'سجل الطلبات',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: context.textPrimary,
                    ),
                  ),
                  Text(
                    'الفواتير المكتملة وفواتير المرتجعات',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: context.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'طلبات الشهر',
                  value: '$thisMonthCount',
                  icon: Icons.receipt_long_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  label: 'إجمالي المصروف',
                  value: '${totalSpent.toStringAsFixed(0)} ر.ي',
                  icon: Icons.payments_rounded,
                  color: const Color(0xFF8B5CF6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  label: 'فواتير المرتجع',
                  value: '$returnedCount',
                  icon: Icons.assignment_return_rounded,
                  color: const Color(0xFFEA580C),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: color)),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10,
                  color: context.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════
// تجميع كل الفواتير (طلبات + مرتجعات) بالتاريخ
// ══════════════════════════════════════════
Map<String, List<dynamic>> _groupItems(List<dynamic> items) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final groups = <String, List<dynamic>>{};

  for (final item in items) {
    final DateTime createdAt = item is OrderModel
        ? item.createdAt
        : (item as ReturnInvoiceModel).createdAt;
    final d = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final diff = today.difference(d).inDays;
    final label = diff == 0
        ? 'اليوم'
        : diff == 1
            ? 'أمس'
            : diff <= 7
                ? 'هذا الأسبوع'
                : diff <= 30
                    ? 'هذا الشهر'
                    : 'أقدم';
    groups.putIfAbsent(label, () => []).add(item);
  }
  return groups;
}

class _OrdersList extends StatelessWidget {
  final List<dynamic> items;
  final Map<String, List<dynamic>> groups;
  final List<dynamic> _flattenedData = [];

  _OrdersList({required this.items}) : groups = _groupItems(items) {
    const groupOrder = ['اليوم', 'أمس', 'هذا الأسبوع', 'هذا الشهر', 'أقدم'];
    for (final group in groupOrder) {
      if (groups.containsKey(group)) {
        _flattenedData.add(group);
        _flattenedData.addAll(groups[group]!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: _flattenedData.length,
      itemBuilder: (_, i) {
        final item = _flattenedData[i];
        if (item is String) {
          return _GroupLabel(label: item);
        } else if (item is OrderModel) {
          return _OrderCard(order: item);
        } else if (item is ReturnInvoiceModel) {
          return _ReturnInvoiceCard(returnItem: item);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ══════════════════════════════════════════
// بطاقة فاتورة الإرجاع الجديدة في السجل
// ══════════════════════════════════════════
class _ReturnInvoiceCard extends StatelessWidget {
  final ReturnInvoiceModel returnItem;
  const _ReturnInvoiceCard({required this.returnItem});

  @override
  Widget build(BuildContext context) {
    final time =
        '${returnItem.createdAt.hour.toString().padLeft(2, '0')}:${returnItem.createdAt.minute.toString().padLeft(2, '0')}';
    final date =
        '${returnItem.createdAt.day}/${returnItem.createdAt.month}/${returnItem.createdAt.year}';
    final shortRetId = returnItem.id.length >= 6
        ? returnItem.id.substring(0, 6).toUpperCase()
        : returnItem.id.toUpperCase();
    final isAccepted = returnItem.status == 'accepted';
    final isRejected = returnItem.status == 'rejected';
    final statusColor = isAccepted
        ? const Color(0xFFEA580C)
        : isRejected
            ? Colors.red
            : Colors.amber.shade800;
    final statusText = isAccepted
        ? 'مرتجع مقبول ✓'
        : isRejected
            ? 'تم الرفض'
            : 'قيد المراجعة ⏳';

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReturnInvoiceScreen(returnItem: returnItem),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: statusColor.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isRejected
                    ? Icons.cancel_rounded
                    : Icons.assignment_return_rounded,
                size: 22,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'فاتورة إرجاع #$shortRetId',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: AppRadius.circleAll,
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: statusColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${returnItem.productName} • ${returnItem.quantity} كرتون',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isRejected
                                  ? Colors.red
                                  : const Color(0xFFEA580C)),
                        ),
                      ),
                    ],
                  ),
                  if (isRejected &&
                      returnItem.rejectionReason != null &&
                      returnItem.rejectionReason!.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 13, color: Colors.red),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'سبب الرفض: ${returnItem.rejectionReason}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: Colors.red,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 12, color: context.iconSecondary),
                      const SizedBox(width: 3),
                      Text('$time • $date',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: context.textSecondary)),
                      const Spacer(),
                      Text(
                        isRejected
                            ? 'مرفوض'
                            : '-${returnItem.refundAmount.toStringAsFixed(0)} ر.ي',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color:
                              isRejected ? Colors.red : const Color(0xFFEA580C),
                        ),
                      ),
                    ],
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

class _GroupLabel extends StatelessWidget {
  final String label;
  const _GroupLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: context.textSecondary)),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: context.borderColor)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════
// كارت الطلب
// ══════════════════════════════════════════
class _OrderCard extends StatelessWidget {
  final OrderModel order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    const statusColor = Color(0xFF10B981);
    final time =
        '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';
    final date =
        '${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}';
    final shortOrderId = order.invoiceNumber ??
        order.orderNumber ??
        (order.id.length >= 6
            ? order.id.substring(0, 6).toUpperCase()
            : order.id.toUpperCase());

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InvoiceScreen(order: order),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: statusColor.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.done_all_rounded,
                  size: 22, color: statusColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'فاتورة طلب #$shortOrderId',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: AppRadius.circleAll,
                        ),
                        child: const Text(
                          'تم التوصيل ✓',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (order.storeName != null &&
                      order.storeName!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      order.storeName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 12, color: context.iconSecondary),
                      const SizedBox(width: 3),
                      Text(
                        '$time • $date',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: context.textSecondary),
                      ),
                      const Spacer(),
                      Text(
                        '${order.total.toStringAsFixed(0)} ر.ي',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: statusColor,
                        ),
                      ),
                    ],
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

class StatusInfo {
  final Color color;
  final IconData icon;
  final String label;
  const StatusInfo(
      {required this.color, required this.icon, required this.label});
}

// ══════════════════════════════════════════
// حالة فارغة
// ══════════════════════════════════════════
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.history_rounded,
                size: 44, color: AppColors.primary.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 16),
          const Text('لا توجد طلبات مكتملة بعد',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  color: Color(0xFFAAAAAA),
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('ستظهر طلباتك هنا بعد اكتمال التوصيل',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 12, color: Color(0xFFAAAAAA))),
        ],
      ),
    );
  }
}
