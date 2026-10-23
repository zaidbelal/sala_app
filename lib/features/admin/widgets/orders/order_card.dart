import 'package:flutter/material.dart';
import '../../services/admin_service.dart';
import 'order_detail_sheet.dart';
import 'order_widgets.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

class OrderCard extends StatelessWidget {
  final AdminOrder order;
  final VoidCallback onStatusChanged;
  const OrderCard(
      {super.key, required this.order, required this.onStatusChanged});

  @override
  Widget build(BuildContext context) {
    final color = OrderStatusHelper.color(order.status);
    final label = OrderStatusHelper.label(order.status);

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => OrderDetailSheet(
          order: order,
          onStatusChanged: onStatusChanged,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.borderColor),
          boxShadow: [
            BoxShadow(
              color: context.shadowColor,
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // شريط اللون العلوي
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: color,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.storeName ?? order.merchantName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: context.textPrimary),
                            ),
                            if (order.storeName != null)
                              Text(order.merchantName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      color: context.textSecondary)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: color.withValues(alpha: 0.2)),
                        ),
                        child: Text(label,
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: color)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      OrderDetail(
                          icon: Icons.tag_rounded,
                          label: order.orderNumber ??
                              (order.id.length >= 8
                                  ? order.id.substring(0, 8).toUpperCase()
                                  : order.id.toUpperCase())),
                      OrderDetail(
                          icon: Icons.attach_money_rounded,
                          label: '${order.total.toStringAsFixed(0)} ر.ي'),
                      OrderDetail(
                          icon: Icons.access_time_rounded,
                          label: _formatDate(order.createdAt)),
                      if (order.phoneNumber != null)
                        OrderDetail(
                            icon: Icons.phone_rounded,
                            label: order.phoneNumber!),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.touch_app_rounded,
                          size: 13, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text('اضغط للتفاصيل وتغيير الحالة',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: Colors.grey[400])),
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

  String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
}
