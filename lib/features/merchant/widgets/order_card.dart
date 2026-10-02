import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/app_colors.dart';
import '../orders/models/order_model.dart';
import '../orders/screens/order_detail_screen.dart';
import '../orders/screens/order_status_screen.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

class OrderCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback? onTap;
  const OrderCard({super.key, required this.order, this.onTap});

  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard> {
  int? _itemCount;

  @override
  void initState() {
    super.initState();
    _resolveItemCount();
  }

  @override
  void didUpdateWidget(covariant OrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order['id'] != widget.order['id'] ||
        oldWidget.order['items_count'] != widget.order['items_count']) {
      _resolveItemCount();
    }
  }

  void _resolveItemCount() {
    final stored = (widget.order['items_count'] as num?)?.toInt() ??
        (widget.order['item_count'] as num?)?.toInt();
    if (stored != null) {
      _itemCount = stored;
    } else {
      _fetchItemCount();
    }
  }

  Future<void> _fetchItemCount() async {
    final orderId = widget.order['id'] as String? ?? '';
    if (orderId.isEmpty) return;
    final snap = await FirebaseFirestore.instance
        .collection('order_items')
        .where('order_id', isEqualTo: orderId)
        .count()
        .get();
    if (mounted) setState(() => _itemCount = snap.count ?? 0);
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';

    try {
      final DateTime dt;

      if (raw is Timestamp) {
        dt = raw.toDate().toLocal();
      } else if (raw is DateTime) {
        dt = raw.toLocal();
      } else {
        dt = DateTime.parse(raw.toString()).toLocal();
      }

      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');

      return '${dt.year}/${dt.month}/${dt.day}  $h:$m';
    } catch (_) {
      return '';
    }
  }

  Map<String, dynamic> _statusConfig(String status) {
    final parsed = OrderStatusX.parse(status);
    final icon = switch (parsed) {
      OrderStatus.pending => Icons.hourglass_top_rounded,
      OrderStatus.accepted => Icons.check_circle_rounded,
      OrderStatus.preparing => Icons.inventory_2_rounded,
      OrderStatus.onTheWay => Icons.local_shipping_rounded,
      OrderStatus.delivered => Icons.done_all_rounded,
      OrderStatus.cancelled || OrderStatus.rejected => Icons.cancel_rounded,
      OrderStatus.returned ||
      OrderStatus.returnRequested =>
        Icons.assignment_return_rounded,
    };
    return {
      'icon': icon,
      'label': parsed.label,
      'color': parsed.color,
    };
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final status = order['status'] as String? ?? 'pending';
    final config = _statusConfig(status);
    final createdAt = _formatDate(order['created_at']);
    final total = (order['total'] as num?)?.toStringAsFixed(0) ?? '0';
    final itemCount = _itemCount ?? 0;
    final isDelivered = status == 'delivered';

    return GestureDetector(
        onTap: () {
          if (widget.onTap != null) {
            widget.onTap!();
            return;
          }
          try {
            final orderModel = OrderModel.fromJson(order);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => OrderStatusScreen(order: orderModel),
              ),
            );
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[OrderCard] failed to open order details: $e');
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('تعذر فتح تفاصيل الطلب، حاول مجدداً')),
            );
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: context.shadowColor.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // ── رأس البطاقة ──
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: (config['color'] as Color).withValues(alpha: 0.06),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color:
                            (config['color'] as Color).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        config['icon'] as IconData,
                        color: config['color'] as Color,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            config['label'] as String,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: config['color'] as Color,
                            ),
                          ),
                          Text(
                            createdAt,
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: context.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (status == 'returned' &&
                            (total == '0' || total == '0.0'))
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance
                                .collection('order_returns')
                                .where('order_id', isEqualTo: order['id'])
                                .snapshots(),
                            builder: (context, snap) {
                              double displayAmount =
                                  (order['returned_amount'] as num?)
                                          ?.toDouble() ??
                                      (order['original_total'] as num?)
                                          ?.toDouble() ??
                                      0.0;
                              if (displayAmount == 0 && snap.hasData) {
                                for (final doc in snap.data!.docs) {
                                  if (doc.data()['status'] != 'rejected') {
                                    displayAmount +=
                                        (doc.data()['refund_amount'] as num?)
                                                ?.toDouble() ??
                                            0.0;
                                  }
                                }
                              }
                              return Text(
                                '${displayAmount.toStringAsFixed(0)} ر.ي',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFEA580C),
                                ),
                              );
                            },
                          )
                        else
                          Text(
                            '$total ر.ي',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: status == 'returned'
                                    ? const Color(0xFFEA580C)
                                    : context.textPrimary),
                          ),
                        Text(
                          status == 'returned'
                              ? 'مرتجع مسترد'
                              : '$itemCount منتج',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: status == 'returned'
                                  ? const Color(0xFFEA580C)
                                  : context.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── بيانات الطلب ──
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (order['store_name'] != null)
                      _InfoRow(
                        icon: Icons.storefront_rounded,
                        label: order['store_name'] as String,
                        color: context.textPrimary,
                      ),
                    if (order['customer_name'] != null) ...[
                      const SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.person_rounded,
                        label: order['customer_name'] as String,
                        color: context.textSecondary,
                      ),
                    ],
                    if (order['contact'] != null) ...[
                      const SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.phone_rounded,
                        label: order['contact'] as String,
                        color: context.textSecondary,
                      ),
                    ],
                    if (order['notes'] != null &&
                        (order['notes'] as String).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.notes_rounded,
                        label: order['notes'] as String,
                        color: Colors.grey[500]!,
                      ),
                    ],
                  ],
                ),
              ),

              // ── شريط التقدم ──
              _StatusStepper(status: status),

              // ── زر طلب الإرجاع (للطلبات المسلّمة فقط) ──
              if (isDelivered) ...[
                Divider(height: 1, color: context.borderColor),
                InkWell(
                  onTap: () {
                    final orderModel = OrderModel.fromJson(order);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrderDetailScreen(order: orderModel),
                      ),
                    );
                  },
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: const BoxDecoration(
                      borderRadius:
                          BorderRadius.vertical(bottom: Radius.circular(16)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment_return_rounded,
                            size: 18, color: Color(0xFFEA580C)),
                        SizedBox(width: 8),
                        Text(
                          'طلب إرجاع',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFEA580C),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else
                const SizedBox(height: 4),
            ],
          ),
        ));
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoRow(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: color),
          ),
        ),
      ],
    );
  }
}

class _StatusStepper extends StatelessWidget {
  final String status;
  const _StatusStepper({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == 'cancelled' || status == 'rejected') {
      return _buildSpecialStepper(
        label: 'تم رفض الطلب',
        icon: Icons.cancel_rounded,
        color: const Color(0xFFEF4444),
      );
    }

    if (status == 'returned' || status == 'return_requested') {
      return _buildSpecialStepper(
        label: 'تم إرجاع الطلب',
        icon: Icons.assignment_return_rounded,
        color: const Color(0xFFF97316),
      );
    }

    final steps = [
      {'label': 'الطلب', 'icon': Icons.receipt_long_rounded},
      {'label': 'تأكيد', 'icon': Icons.check_rounded},
      {'label': 'في الطريق', 'icon': Icons.local_shipping_rounded},
      {'label': 'تسليم', 'icon': Icons.done_all_rounded},
    ];

    final currentStep = _step;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final lineIndex = i ~/ 2;
            final isActive = lineIndex < currentStep;
            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.primary : context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }

          final stepIndex = i ~/ 2;
          final isActive = stepIndex <= currentStep;
          final isCurrent = stepIndex == currentStep;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: isCurrent ? 34 : 28,
                height: isCurrent ? 34 : 28,
                decoration: BoxDecoration(
                  color: isActive
                      ? (isCurrent
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.2))
                      : context.bgInput,
                  shape: BoxShape.circle,
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : [],
                ),
                child: Icon(
                  steps[stepIndex]['icon'] as IconData,
                  size: isCurrent ? 18 : 14,
                  color: isActive
                      ? (isCurrent ? Colors.white : AppColors.primary)
                      : context.iconSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[stepIndex]['label'] as String,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? AppColors.primary : context.iconSecondary,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildSpecialStepper({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  int get _step {
    switch (status) {
      case 'pending':
        return 0;
      case 'confirmed':
        return 1;
      case 'shipped':
      case 'on_the_way':
        return 2;
      case 'delivered':
        return 3;
      default:
        return 0;
    }
  }
}
