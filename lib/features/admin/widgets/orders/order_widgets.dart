import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import '../../../merchant/orders/models/order_model.dart';

class OrderSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const OrderSection(
      {super.key,
      required this.title,
      required this.icon,
      required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary)),
            ]),
          ),
          Divider(height: 1, color: context.borderColor),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }
}

class OrderInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  const OrderInfoRow(
      {super.key,
      required this.label,
      required this.value,
      this.icon,
      this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: Colors.grey[500])),
          ),
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class OrderDetail extends StatelessWidget {
  final IconData icon;
  final String label;
  const OrderDetail({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontFamily: 'Cairo', fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

// ── ألوان وأسماء الحالة موحدة من OrderStatusX ──
class OrderStatusHelper {
  static Color color(String s) => OrderStatusX.parse(s).color;

  static String label(String s) => OrderStatusX.parse(s).label;
  static String payment(String m) => switch (m) {
        'cash' => 'نقدي',
        'transfer' => 'تحويل بنكي',
        'credit' => 'آجل',
        'deferred' => 'آجل',
        _ => m,
      };
}
