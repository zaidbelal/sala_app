import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sala/core/constants/app_colors.dart';

/// شيت الطلب الجديد — يظهر فوراً للسائق مع عداد تنازلي
class NewOrderSheet extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const NewOrderSheet({
    super.key,
    required this.orderId,
    required this.data,
    required this.onAccept,
    required this.onReject,
  });

  /// استدعِ هذا لعرض الشيت — يُرجع true عند القبول
  static Future<bool?> show(
    BuildContext context, {
    required String orderId,
    required Map<String, dynamic> data,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => NewOrderSheet(
        orderId: orderId,
        data: data,
        onAccept: () => Navigator.pop(ctx, true),
        onReject: () => Navigator.pop(ctx, false),
      ),
    );
  }

  @override
  State<NewOrderSheet> createState() => _NewOrderSheetState();
}

class _NewOrderSheetState extends State<NewOrderSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  Timer? _countdown;
  int _secondsLeft = 30;
  bool _isActionTaken = false;

  @override
  void initState() {
    super.initState();
    // اهتزاز فوري لتنبيه السائق
    HapticFeedback.vibrate();

    // أيقونة نابضة
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    // عداد تنازلي 30 ثانية
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        if (!_isActionTaken) {
          _isActionTaken = true;
          widget.onReject();
        }
      }
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _countdown?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final merchantName = d['merchant_name'] ?? d['customer_name'] ?? 'عميل';
    final address = d['delivery_address'] as String? ?? 'لم يُحدد';
    final total = (d['total_amount'] as num?)?.toDouble() ??
        (d['total'] as num?)?.toDouble() ??
        0.0;
    final orderNum =
        d['order_number']?.toString() ?? d['invoice_number']?.toString() ?? '';
    final payMethod = d['payment_method'] as String? ?? 'cash';

    return PopScope(
      canPop: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // مقبض الشيت
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),

            // ── أيقونة نابضة ──
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.orange
                      .withValues(alpha: 0.10 + 0.08 * _pulseCtrl.value),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange
                          .withValues(alpha: 0.35 * _pulseCtrl.value),
                      blurRadius: 22,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(Icons.delivery_dining_rounded,
                    color: Colors.orange, size: 38),
              ),
            ),
            const SizedBox(height: 12),

            // ── عنوان ──
            const Text(
              '🚨 طلب جديد وصلك!',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A1A2E),
              ),
            ),
            if (orderNum.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('#$orderNum',
                  style: const TextStyle(
                      fontFamily: 'Cairo', fontSize: 12, color: Colors.grey)),
            ],

            const SizedBox(height: 18),

            // ── تفاصيل الطلب ──
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _InfoRow(
                      icon: Icons.storefront_rounded,
                      label: 'العميل',
                      value: merchantName,
                      color: Colors.blue),
                  const Divider(height: 14),
                  _InfoRow(
                      icon: Icons.location_on_rounded,
                      label: 'العنوان',
                      value: address,
                      color: Colors.red),
                  const Divider(height: 14),
                  _InfoRow(
                      icon: Icons.payments_rounded,
                      label: 'المبلغ',
                      value: '${total.toStringAsFixed(0)} ر.ي',
                      color: AppColors.primary,
                      bold: true),
                  const Divider(height: 14),
                  _InfoRow(
                    icon: payMethod == 'cash'
                        ? Icons.money_rounded
                        : Icons.credit_card_rounded,
                    label: 'الدفع',
                    value: payMethod == 'cash' ? 'كاش عند الاستلام' : 'بطاقة',
                    color: Colors.purple,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── عداد تنازلي ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer_outlined,
                    size: 14,
                    color: _secondsLeft <= 10 ? Colors.red : Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'ينتهي خلال $_secondsLeft ثانية',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: _secondsLeft <= 10 ? Colors.red : Colors.grey,
                    fontWeight: _secondsLeft <= 10
                        ? FontWeight.w700
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
// ── أزرار القبول والرفض ──
            Row(
              children: [
                // رفض
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (!_isActionTaken) {
                        _isActionTaken = true;
                        widget.onReject();
                      }
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('رفض',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // قبول
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (!_isActionTaken) {
                        _isActionTaken = true;
                        widget.onAccept();
                      }
                    },
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text('قبول الطلب',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══ صف المعلومة ══
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool bold;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontFamily: 'Cairo', fontSize: 10, color: Colors.grey)),
              Text(value,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                      color: const Color(0xFF1A1A2E))),
            ],
          ),
        ),
      ],
    );
  }
}
