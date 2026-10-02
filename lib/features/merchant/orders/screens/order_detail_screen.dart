import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_radius.dart';
import '../../../../../core/services/local_storage.dart';
import '../models/order_model.dart';
import '../services/orders_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class OrderDetailScreen extends StatefulWidget {
  final OrderModel order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _returns = [];
  bool _loading = true;
  late OrderModel _currentOrder;
  StreamSubscription<DocumentSnapshot>? _orderSubscription;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _load();
    _listenToOrderRealtime();
  }

  void _listenToOrderRealtime() {
    _orderSubscription = FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.order.id)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists || doc.data() == null) return;
      setState(() {
        _currentOrder = OrderModel.fromJson({'id': doc.id, ...doc.data()!});
      });
    });
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      // ✅ الاكتفاء بجلب عناصر الطلب لأن مستند الطلب يُحدّث تلقائياً عبر _listenToOrderRealtime()
      final items = await OrdersService.getOrderItems(widget.order.id);
      if (mounted) {
        setState(() {
          _items = items;
        });
      }
      try {
        final returnsSnap = await FirebaseFirestore.instance
            .collection('order_returns')
            .where('order_id', isEqualTo: widget.order.id)
            .get();

        final returnsList =
            returnsSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

        returnsList.sort((a, b) {
          DateTime parseDate(dynamic v) {
            if (v is Timestamp) return v.toDate();
            if (v is DateTime) return v;
            if (v is String && v.isNotEmpty) {
              return DateTime.tryParse(v) ?? DateTime(2000);
            }
            return DateTime(2000);
          }

          return parseDate(b['created_at'])
              .compareTo(parseDate(a['created_at']));
        });

        if (mounted) {
          setState(() {
            _returns = returnsList;
          });
        }
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // كمية مُرجعة (مقبولة أو معلقة) لكل عنصر
  Map<String, int> get _returnedQtyPerItem {
    final Map<String, int> result = {};
    for (final r in _returns) {
      if (r['status'] == 'rejected') continue;
      final itemId = r['order_item_id']?.toString() ?? '';
      if (itemId.isEmpty) continue;
      result[itemId] =
          (result[itemId] ?? 0) + ((r['quantity'] as num?)?.toInt() ?? 0);
    }
    return result;
  }

  // الكمية المتبقية القابلة للإرجاع لكل عنصر
  Map<String, int> get _remainingQty {
    final returned = _returnedQtyPerItem;
    final Map<String, int> result = {};
    for (final item in _items) {
      final itemId = item['id']?.toString() ?? '';
      final ordered = (item['quantity'] as num?)?.toInt() ?? 0;
      final alreadyReturned = returned[itemId] ?? 0;
      result[itemId] = (ordered - alreadyReturned).clamp(0, ordered);
    }
    return result;
  }

  bool get _canReturn =>
      _currentOrder.status == OrderStatus.delivered &&
      _items.isNotEmpty &&
      _remainingQty.values.any((q) => q > 0);

  String _returnStatus(String itemId) {
    final matches =
        _returns.where((r) => r['order_item_id'] == itemId).toList();
    if (matches.isEmpty) return '';
    // أولوية: معلق > مقبول > مرفوض
    if (matches.any((r) => r['status'] == 'pending')) return 'pending';
    if (matches.any((r) => r['status'] == 'accepted')) return 'accepted';
    return 'rejected';
  }

  bool _hasActiveReturn(String itemId) {
    return _returns
        .any((r) => r['order_item_id'] == itemId && r['status'] != 'rejected');
  }

  void _openReturnSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReturnSheet(
        order: _currentOrder,
        items: _items,
        remainingQty: _remainingQty,
        onSuccess: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = _currentOrder;
    final time =
        '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';
    final date =
        '${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}';

    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            // ── شريط العنوان ──
            Container(
              color: context.bgHeader,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: context.bgPage,
                        borderRadius: AppRadius.mdAll,
                      ),
                      child:
                          const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.orderNumber ??
                              order.invoiceNumber ??
                              '#${order.id.length >= 6 ? order.id.substring(0, 6).toUpperCase() : order.id.toUpperCase()}',
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 17,
                              fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '$time  •  $date',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: context.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(status: order.status),
                ],
              ),
            ),

            // ── المحتوى ──
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        children: [
                          _SummaryCard(order: order),
                          const SizedBox(height: 12),
                          _OrderProgressStepper(status: order.status),
                          const SizedBox(height: 12),
                          // ── التوقيع الرقمي المعتمد لحظياً ──
                          if (order.signatureUrl != null &&
                              order.signatureUrl!.isNotEmpty) ...[
                            _SignatureLiveCard(
                              signatureUrl: order.signatureUrl!,
                              signerName: order.storeName ??
                                  order.customerName ??
                                  'المستلم المعتمد',
                            ),
                            const SizedBox(height: 12),
                          ],
                          _DeliveryCard(order: order),
                          const SizedBox(height: 12),

                          // ── المنتجات ──
                          const _SectionTitle(
                              title: 'المنتجات المطلوبة',
                              icon: Icons.inventory_2_rounded),
                          const SizedBox(height: 8),
                          if (_items.isEmpty)
                            const _EmptyHint(
                                text: 'لا توجد منتجات',
                                icon: Icons.inventory_2_outlined)
                          else
                            ..._items.map((item) {
                              final itemId = item['id']?.toString() ?? '';
                              final remaining = _remainingQty[itemId] ?? 0;
                              final ordered =
                                  (item['quantity'] as num?)?.toInt() ?? 0;
                              return _ItemCard(
                                item: item,
                                hasReturn: _hasActiveReturn(itemId),
                                returnStatus: _returnStatus(itemId),
                                returnedQty: ordered - remaining,
                              );
                            }),

// ── ملخص الإرجاع إذا وُجد ──
                          if (_returns.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _ReturnSummaryBanner(returns: _returns),
                            const SizedBox(height: 8),
                            const _SectionTitle(
                                title: 'طلبات الإرجاع',
                                icon: Icons.assignment_return_rounded),
                            const SizedBox(height: 8),
                            ..._returns.map((r) => _ReturnCard(data: r)),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _canReturn
          ? Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              decoration: BoxDecoration(
                color: context.bgCard,
                boxShadow: [
                  BoxShadow(
                    color: context.shadowColor.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _openReturnSheet,
                  icon: const Icon(Icons.assignment_return_rounded, size: 20),
                  label: const Text(
                    'طلب إرجاع أصناف',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

// ════════════════════════════════════════
// بانر ملخص الإرجاع
// ════════════════════════════════════════
class _ReturnSummaryBanner extends StatelessWidget {
  final List<Map<String, dynamic>> returns;
  const _ReturnSummaryBanner({required this.returns});

  @override
  Widget build(BuildContext context) {
    final pending = returns.where((r) => r['status'] == 'pending').length;
    final accepted = returns.where((r) => r['status'] == 'accepted').length;
    final rejected = returns.where((r) => r['status'] == 'rejected').length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFFEA580C).withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: Color(0xFFEA580C)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                if (pending > 0) '$pending معلق',
                if (accepted > 0) '$accepted مقبول',
                if (rejected > 0) '$rejected مرفوض',
              ].join('  •  '),
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFEA580C)),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════
// كارت إجمالي المبلغ
// ════════════════════════════════════════
class _SummaryCard extends StatelessWidget {
  final OrderModel order;
  const _SummaryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.09),
            context.bgCard,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إجمالي الطلب',
                    style: TextStyle(
                        fontFamily: 'Cairo', fontSize: 13, color: Colors.grey)),
                Text(
                  '${order.total.toStringAsFixed(0)} ر.ي',
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                order.paymentMethod == 'cash'
                    ? 'نقداً عند الاستلام'
                    : 'دفع آجل',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: context.textSecondary),
              ),
              const SizedBox(height: 4),
              const Text('ضريبة: صفر',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 11, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════
// كارت بيانات التوصيل
// ════════════════════════════════════════
class _DeliveryCard extends StatelessWidget {
  final OrderModel order;
  const _DeliveryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppRadius.lgAll,
        boxShadow: [
          BoxShadow(
              color: context.shadowColor.withValues(alpha: 0.06),
              blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.local_shipping_rounded,
                size: 16, color: AppColors.primary),
            SizedBox(width: 6),
            Text('بيانات التوصيل',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          if (order.storeName != null)
            _InfoRow(Icons.storefront_rounded, 'البقالة', order.storeName!),
          if (order.customerName != null)
            _InfoRow(Icons.person_rounded, 'العميل', order.customerName!),
          if (order.contact != null)
            _InfoRow(Icons.phone_rounded, 'الهاتف', order.contact!),
          if (order.latitude != null)
            _InfoRow(
              Icons.location_on_rounded,
              'الموقع',
              '${order.latitude!.toStringAsFixed(4)}, ${order.longitude!.toStringAsFixed(4)}',
            ),
          if (order.notes != null && order.notes!.isNotEmpty)
            _InfoRow(Icons.notes_rounded, 'ملاحظات', order.notes!),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: context.iconSecondary),
          const SizedBox(width: 6),
          Text('$label: ',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: context.textSecondary)),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary)),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════
// كارت المنتج
// ════════════════════════════════════════
class _ItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool hasReturn;
  final String returnStatus;
  final int returnedQty;

  const _ItemCard({
    required this.item,
    required this.hasReturn,
    required this.returnStatus,
    required this.returnedQty,
  });

  @override
  Widget build(BuildContext context) {
    final rawName = item['product_name']?.toString() ?? '';
    final unitLabel = item['unit_label']?.toString().trim() ?? 'كرتون';
    final name = unitLabel.isNotEmpty ? '$rawName ($unitLabel)' : rawName;
    final originalQty = (item['quantity'] as num?)?.toInt() ?? 0;
    final netQty = (originalQty - returnedQty).clamp(0, originalQty);
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    final netSubtotal = price * netQty;
    final isFullyReturned = returnedQty >= originalQty && originalQty > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isFullyReturned ? context.bgInput : context.bgCard,
        borderRadius: AppRadius.lgAll,
        border: hasReturn
            ? Border.all(
                color: _returnColor(returnStatus).withValues(alpha: 0.35))
            : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: context.bgInput,
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(Icons.inventory_2_outlined,
                size: 22,
                color: isFullyReturned ? Colors.grey[400] : AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isFullyReturned ? Colors.grey[400] : null,
                        decoration: isFullyReturned
                            ? TextDecoration.lineThrough
                            : null)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      '$netQty $unitLabel مستلم',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary),
                    ),
                    if (returnedQty > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$returnedQty مرتجع',
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.red),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'سعر $unitLabel: ${price.toStringAsFixed(0)} ر.ي',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${netSubtotal.toStringAsFixed(0)} ر.ي',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color:
                        isFullyReturned ? Colors.grey[400] : AppColors.primary),
              ),
              if (returnedQty > 0)
                Text(
                  'الصافي بعد الإرجاع',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 9,
                      color: Colors.grey[500]),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _returnColor(String status) {
    switch (status) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }
}

// ════════════════════════════════════════
// كارت طلب الإرجاع
// ════════════════════════════════════════
class _ReturnCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ReturnCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final status = data['status']?.toString() ?? 'pending';
    final productName = data['product_name']?.toString() ?? 'منتج';
    final qty = (data['quantity'] as num?)?.toInt() ?? 0;
    final reason = data['reason']?.toString() ?? '';
    final createdAt = data['created_at'] != null
        ? (data['created_at'] is Timestamp
            ? (data['created_at'] as Timestamp).toDate()
            : DateTime.tryParse(data['created_at'].toString()))
        : null;

    final (statusLabel, statusColor) = switch (status) {
      'accepted' => ('مقبول ✓', Colors.green),
      'rejected' => ('مرفوض ✗', Colors.red),
      _ => ('قيد المراجعة', Colors.orange),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: context.shadowColor.withValues(alpha: 0.04),
              blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.assignment_return_rounded,
                size: 18, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(productName,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('$qty كرتون',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: Colors.grey[500])),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: Colors.grey[600])),
                ],
                if (createdAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        color: context.iconSecondary),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
        ],
      ),
    );
  }
}

// ════════════════════════════════════════
// شيت طلب الإرجاع الموحّد
// ════════════════════════════════════════
class _ReturnSheet extends StatefulWidget {
  final OrderModel order;
  final List<Map<String, dynamic>> items;
  final Map<String, int> remainingQty;
  final VoidCallback onSuccess;

  const _ReturnSheet({
    required this.order,
    required this.items,
    required this.remainingQty,
    required this.onSuccess,
  });

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  final Map<int, int> _returnQty = {};
  late final TextEditingController _storeCtrl;
  late final TextEditingController _contactCtrl;
  final TextEditingController _reasonCtrl = TextEditingController();
  bool _loading = false;

  List<Map<String, dynamic>> get _returnableItems => widget.items.where((item) {
        final id = item['id']?.toString() ?? '';
        return (widget.remainingQty[id] ?? 0) > 0;
      }).toList();

  @override
  void initState() {
    super.initState();
    _storeCtrl = TextEditingController(text: widget.order.storeName ?? '');
    _contactCtrl = TextEditingController(text: widget.order.contact ?? '');
    for (var i = 0; i < _returnableItems.length; i++) {
      _returnQty[i] = 0;
    }
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
    _contactCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  bool get _hasSelection => _returnQty.values.any((q) => q > 0);

  int get _totalSelectedQty =>
      _returnQty.values.fold(0, (total, q) => total + q);

  Future<void> _submit() async {
    if (!_hasSelection) {
      _snack('اختر كمية إرجاع لمنتج واحد على الأقل', Colors.orange);
      return;
    }
    if (_reasonCtrl.text.trim().isEmpty) {
      _snack('سبب الإرجاع مطلوب', Colors.orange);
      return;
    }
    if (_storeCtrl.text.trim().isEmpty) {
      _snack('اسم البقالة مطلوب', Colors.orange);
      return;
    }
    final uid = AppStorage.userId ?? '';
    if (uid.isEmpty) {
      _snack('انتهت جلستك، أعد تسجيل الدخول', Colors.red);
      return;
    }

    setState(() => _loading = true);
    HapticFeedback.mediumImpact();

    try {
      final itemsToReturn = <Map<String, dynamic>>[];

      for (var i = 0; i < _returnableItems.length; i++) {
        final qty = _returnQty[i] ?? 0;
        if (qty <= 0) continue;

        final item = _returnableItems[i];
        final rawName = item['product_name']?.toString() ??
            item['name']?.toString() ??
            'منتج';
        final unitLabel = item['unit_label']?.toString().trim() ?? '';
        final fullNameWithUnit = unitLabel.isNotEmpty && !rawName.contains('(')
            ? '$rawName ($unitLabel)'
            : rawName;

        itemsToReturn.add({
          'order_item_id': item['id']?.toString() ?? '',
          'quantity': qty,
          'product_name': fullNameWithUnit,
        });
      }
      if (itemsToReturn.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final returnData = {
        'orderId': widget.order.id,
        'merchantId': uid,
        'itemsToReturn': itemsToReturn,
        'storeName': _storeCtrl.text.trim(),
        'contact': _contactCtrl.text.trim(),
        'latitude': widget.order.latitude,
        'longitude': widget.order.longitude,
        'reason': _reasonCtrl.text.trim(),
      };

      // 🚀 فحص سريع للإنترنت
      final netResults = await Connectivity().checkConnectivity();
      final bool isOffline =
          netResults.every((r) => r == ConnectivityResult.none);

      if (isOffline) {
        await AppStorage.savePendingReturn(returnData);
        if (!mounted) return;
        Navigator.of(context).pop();
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.cloud_done_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
                child: Text(
                    'أنت غير متصل. تم حفظ طلب الإرجاع وسيُرسل تلقائياً فور توفر الإنترنت 📡',
                    style: TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.w700))),
          ]),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ));
        return;
      }
      try {
        await OrdersService.submitReturns(
          orderId: widget.order.id,
          itemsToReturn: itemsToReturn,
          merchantId: uid,
          storeName: _storeCtrl.text.trim(),
          contact: _contactCtrl.text.trim(),
          latitude: widget.order.latitude,
          longitude: widget.order.longitude,
          reason: _reasonCtrl.text.trim(),
        ).timeout(const Duration(seconds: 10));

        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        widget.onSuccess();
        messenger.showSnackBar(SnackBar(
          content: Text(
            'تم إرسال طلب إرجاع $_totalSelectedQty كرتون بنجاح ✓',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        final isNetworkError = errorStr.contains('network') ||
            errorStr.contains('unavailable') ||
            errorStr.contains('timeout') ||
            errorStr.contains('socket');

        if (isNetworkError) {
          // 🚀 إنترنت ضعيف جداً؟ احفظه أوفلاين
          await AppStorage.savePendingReturn(returnData);
          if (!mounted) return;
          Navigator.of(context).pop();
          widget.onSuccess();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Row(children: [
              Icon(Icons.cloud_done_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'ضعف في الشبكة. تم حفظ الطلب وسيُرسل تلقائياً فور استقرار الإنترنت 📡',
                      style: TextStyle(
                          fontFamily: 'Cairo', fontWeight: FontWeight.w700))),
            ]),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ));
        } else {
          throw e; // خطأ حقيقي (مثل: حاولت إرجاع منتج تم إرجاعه مسبقاً)
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('فشل الإرسال: $e', Colors.red);
      }
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color:
              context.bgPage, // 👈 استبدال اللون الثابت F5F7FA باللون المتكيف
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // مقبض
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),

            // رأس الشيت
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.assignment_return_rounded,
                      color: Color(0xFFEA580C), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('طلب إرجاع',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      Text(
                        widget.order.orderNumber ??
                            '#${widget.order.id.length >= 6 ? widget.order.id.substring(0, 6).toUpperCase() : widget.order.id.toUpperCase()}',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                if (_totalSelectedQty > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEA580C).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_totalSelectedQty كرتون',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFEA580C)),
                    ),
                  ),
              ]),
            ),
            const Divider(height: 20),

            // المحتوى
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    // بيانات التاجر
                    _Card(
                      title: 'بيانات التاجر',
                      icon: Icons.storefront_rounded,
                      child: Column(children: [
                        _SheetField(
                          controller: _storeCtrl,
                          label: 'اسم البقالة',
                          icon: Icons.storefront_rounded,
                        ),
                        const SizedBox(height: 10),
                        _SheetField(
                          controller: _contactCtrl,
                          label: 'رقم الهاتف',
                          icon: Icons.phone_rounded,
                          keyboardType: TextInputType.phone,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // اختيار المنتجات
                    _Card(
                      title: 'اختر المنتجات المرتجعة',
                      icon: Icons.inventory_2_rounded,
                      child: _returnableItems.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'لا توجد كميات متبقية للإرجاع',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    color: Colors.grey),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _returnableItems.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 16),
                              itemBuilder: (_, i) {
                                final item = _returnableItems[i];
                                final name = item['product_name']?.toString() ??
                                    item['name']?.toString() ??
                                    'منتج';
                                final itemId = item['id']?.toString() ?? '';
                                final maxQty = widget.remainingQty[itemId] ?? 0;
                                final ordered =
                                    (item['quantity'] as num?)?.toInt() ?? 0;
                                final current = _returnQty[i] ?? 0;

                                return Row(children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(name,
                                            style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700)),
                                        Text(
                                          'متبقي: $maxQty من $ordered كرتون',
                                          style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: maxQty < ordered
                                                  ? Colors.orange[700]
                                                  : Colors.grey[500]),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: current > 0
                                          ? const Color(0xFFFFF7ED)
                                          : const Color(0xFFF5F7FA),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: current > 0
                                            ? const Color(0xFFEA580C)
                                            : Colors.grey[300]!,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _CounterBtn(
                                          icon: Icons.remove,
                                          enabled: current > 0,
                                          onTap: () => setState(() =>
                                              _returnQty[i] = current - 1),
                                        ),
                                        SizedBox(
                                          width: 36,
                                          child: Text(
                                            '$current',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: current > 0
                                                    ? const Color(0xFFEA580C)
                                                    : Colors.grey[600]),
                                          ),
                                        ),
                                        _CounterBtn(
                                          icon: Icons.add,
                                          enabled: current < maxQty,
                                          onTap: () => setState(() =>
                                              _returnQty[i] = current + 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ]);
                              },
                            ),
                    ),
                    const SizedBox(height: 12),

                    // ── سبب الإرجاع ──
                    _Card(
                      title: 'سبب الإرجاع *',
                      icon: Icons.notes_rounded,
                      iconColor: const Color(0xFFEA580C),
                      child: TextField(
                        controller: _reasonCtrl,
                        maxLines: 3,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14,
                            color: context.textPrimary), // 👈 نص واضح
                        decoration: InputDecoration(
                          hintText:
                              'مثال: منتج تالف / كمية خاطئة / منتهي الصلاحية...',
                          hintStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: context.textHint),
                          filled: true,
                          fillColor: context.isDark
                              ? Colors.red.withValues(alpha: 0.08)
                              : const Color(
                                  0xFFFFF5F5), // 👈 يتكيف مع الثيم الداكن
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.red.withValues(alpha: 0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Colors.redAccent, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // أزرار
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            side: const BorderSide(color: Color(0xFFDDDDDD)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('إلغاء',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed:
                              (_loading || !_hasSelection) ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEA580C),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: context.isDark
                                ? Colors.grey[800]
                                : Colors.grey[300], // 👈 لون تعطيل واضح للثيمين
                            disabledForegroundColor: context.isDark
                                ? Colors.grey[400]
                                : Colors.grey[600], // 👈 لون نص التعطيل
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  _hasSelection
                                      ? 'تأكيد إرجاع $_totalSelectedQty كرتون'
                                      : 'اختر كمية أولاً',
                                  style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800),
                                ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── حاوية كارت ──
class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Color? iconColor;
  const _Card(
      {required this.title,
      required this.icon,
      required this.child,
      this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgCard, // 👈 جعلناها تتكيف مع الثيم
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor), // 👈 إضافة إطار خفيف
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: iconColor ?? AppColors.primary),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary)), // 👈 لون نص متكيف
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── حقل نصي ──
class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  const _SheetField(
      {required this.controller,
      required this.label,
      required this.icon,
      this.keyboardType});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.bgInput, // 👈 خلفية متكيفة (رمادي فاتح/داكن)
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor),
      ),
      child: TextField(
        controller: controller,
        textDirection: TextDirection.rtl,
        keyboardType: keyboardType,
        style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.textPrimary), // 👈 نص واضح
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
              fontFamily: 'Cairo', fontSize: 12, color: context.textSecondary),
          prefixIcon: Icon(icon, size: 18, color: context.iconSecondary),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}

// ── زر العداد ──
class _CounterBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _CounterBtn(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Icon(icon,
            size: 16,
            color: enabled ? const Color(0xFFEA580C) : Colors.grey[300]),
      ),
    );
  }
}

// ── عنوان القسم ──
class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 15, color: AppColors.primary),
      const SizedBox(width: 6),
      Text(title,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ))
    ]);
  }
}

// ── تلميح فارغ ──
class _EmptyHint extends StatelessWidget {
  final String text;
  final IconData icon;
  const _EmptyHint({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Icon(icon, size: 36, color: Colors.grey[300]),
        const SizedBox(height: 8),
        Text(text,
            style: TextStyle(
                fontFamily: 'Cairo', fontSize: 13, color: Colors.grey[400])),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
// شريط تقدم الطلب الأفقي
// ══════════════════════════════════════════════════════════
class _OrderProgressStepper extends StatelessWidget {
  final OrderStatus status;
  const _OrderProgressStepper({required this.status});

  static const _steps = [
    (icon: Icons.receipt_rounded, label: 'استلام'),
    (icon: Icons.thumb_up_rounded, label: 'قبول'),
    (icon: Icons.inventory_rounded, label: 'تحضير'),
    (icon: Icons.local_shipping_rounded, label: 'توصيل'),
    (icon: Icons.verified_rounded, label: 'تسليم'),
  ];

  int get _currentStep => switch (status) {
        OrderStatus.pending => 0,
        OrderStatus.accepted => 1,
        OrderStatus.preparing => 2,
        OrderStatus.onTheWay => 3,
        OrderStatus.delivered => 4,
        _ => -1,
      };

  @override
  Widget build(BuildContext context) {
    if (status == OrderStatus.cancelled ||
        status == OrderStatus.rejected ||
        status == OrderStatus.returned ||
        status == OrderStatus.returnRequested) {
      return const SizedBox.shrink();
    }

    final current = _currentStep;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Row(
        children: List.generate(_steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            // الخط الواصل
            final lineIndex = i ~/ 2;
            final filled = lineIndex < current;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                height: 3,
                decoration: BoxDecoration(
                  color: filled ? AppColors.primary : const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }

          final stepIndex = i ~/ 2;
          final isDone = stepIndex <= current;
          final isActive = stepIndex == current;
          final step = _steps[stepIndex];

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDone ? AppColors.primary : const Color(0xFFF0F0F0),
                  shape: BoxShape.circle,
                  border: isActive
                      ? Border.all(color: AppColors.primary, width: 2.5)
                      : null,
                  boxShadow: isDone
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : null,
                ),
                child: Icon(
                  isDone && !isActive ? Icons.check_rounded : step.icon,
                  size: 16,
                  color: isDone ? Colors.white : Colors.grey[400],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                step.label,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 9,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                  color: isDone ? AppColors.primary : Colors.grey[400],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ── شارة الحالة ──
class _StatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      OrderStatus.pending => ('معلق', Colors.orange),
      OrderStatus.accepted => ('مؤكد', Colors.blue),
      OrderStatus.preparing => ('قيد التحضير', Colors.blue),
      OrderStatus.onTheWay => ('في الطريق', const Color(0xFF8B5CF6)),
      OrderStatus.delivered => ('تم التسليم', Colors.green),
      OrderStatus.cancelled => ('ملغي', Colors.red),
      OrderStatus.rejected => ('مرفوض', Colors.red),
      OrderStatus.returned => ('مُرتجع', const Color(0xFFEA580C)),
      OrderStatus.returnRequested => ('طلب إرجاع', Colors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}

class _SignatureLiveCard extends StatelessWidget {
  final String signatureUrl;
  final String signerName;
  const _SignatureLiveCard(
      {required this.signatureUrl, required this.signerName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.draw_rounded,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('توقيع الاستلام المعتمد',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                    SizedBox(width: 4),
                    Icon(Icons.verified_rounded,
                        size: 14, color: AppColors.primary),
                  ],
                ),
                Text('الموقع: $signerName',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: context.textSecondary)),
              ],
            ),
          ),
          Container(
            height: 52,
            width: 95,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: signatureUrl.startsWith('data:image')
                  ? Builder(
                      builder: (_) {
                        try {
                          final raw = signatureUrl.split(',').last.trim();
                          final bytes = base64Decode(raw);
                          return Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.draw, color: Colors.grey),
                          );
                        } catch (_) {
                          return const Icon(Icons.draw, color: Colors.grey);
                        }
                      },
                    )
                  : Image.network(
                      signatureUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.draw, color: Colors.grey),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
