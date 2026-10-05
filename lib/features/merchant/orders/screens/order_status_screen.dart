import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_radius.dart';
import '../models/order_model.dart';
import '../services/orders_service.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

class OrderStatusScreen extends StatelessWidget {
  final OrderModel order;
  const OrderStatusScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OrderModel?>(
      stream: OrdersService.watchOrder(order.id),
      initialData: order,
      builder: (context, snapshot) {
        final current = snapshot.data ?? order;
        return Scaffold(
          backgroundColor: context.bgPage,
          body: SafeArea(
            child: Column(
              children: [
                _Header(order: current),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    child: Column(
                      children: [
                        _StatusHero(order: current),
                        const SizedBox(height: 16),
                        _StepTracker(status: current.status),
                        const SizedBox(height: 16),
                        _InfoGrid(order: current),
                        const SizedBox(height: 16),
                        _OrderSummaryCard(order: current),
                        if (current.status == OrderStatus.pending) ...[
                          const SizedBox(height: 16),
                          _CancelButton(order: current),
                        ],
                        const SizedBox(height: 8),
                        _LiveIndicator(snapshot: snapshot),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════
// HEADER
// ══════════════════════════════════════════════════════
class _Header extends StatelessWidget {
  final OrderModel order;
  const _Header({required this.order});

  static _StatusMeta _meta(OrderStatus s) => switch (s) {
        OrderStatus.pending => const _StatusMeta(Colors.orange, 'قيد الانتظار'),
        OrderStatus.accepted => const _StatusMeta(AppColors.primary, 'مقبول'),
        OrderStatus.preparing => const _StatusMeta(Colors.blue, 'جاري التحضير'),
        OrderStatus.onTheWay => const _StatusMeta(Colors.indigo, 'في الطريق'),
        OrderStatus.delivered =>
          const _StatusMeta(Color(0xFF10B981), 'تم التسليم'),
        OrderStatus.cancelled => const _StatusMeta(Colors.red, 'ملغي'),
        OrderStatus.rejected => const _StatusMeta(Colors.red, 'مرفوض'),
        OrderStatus.returned => const _StatusMeta(Colors.orange, 'مرتجع'),
        OrderStatus.returnRequested =>
          const _StatusMeta(Colors.orange, 'طلب إرجاع'),
      };

  @override
  Widget build(BuildContext context) {
    final meta = _meta(order.status);
    final fallbackNum = order.id.length >= 6
        ? '#${order.id.substring(0, 6).toUpperCase()}'
        : '#${order.id.toUpperCase()}';
    final displayNumber =
        order.invoiceNumber ?? order.orderNumber ?? fallbackNum;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: context.bgHeader,
        boxShadow: [
          BoxShadow(
            color: context.shadowColor.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _BackBtn(onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          }),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تتبع الطلب',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: context.textPrimary)),
                Text(displayNumber,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: meta.color.withValues(alpha: 0.3)),
            ),
            child: Text(meta.label,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: meta.color)),
          ),
        ],
      ),
    );
  }
}

class _BackBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _BackBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: context.bgPage,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.arrow_back_ios_new_rounded,
            size: 16, color: context.textPrimary),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// STATUS HERO — الكارت الرئيسي مع أنيميشن
// ══════════════════════════════════════════════════════
class _StatusHero extends StatelessWidget {
  final OrderModel order;
  const _StatusHero({required this.order});

  static _StatusVisual _visual(OrderStatus s) => switch (s) {
        OrderStatus.pending =>
          const _StatusVisual(Icons.hourglass_top_rounded, Colors.orange),
        OrderStatus.accepted =>
          const _StatusVisual(Icons.thumb_up_rounded, AppColors.primary),
        OrderStatus.preparing =>
          const _StatusVisual(Icons.inventory_2_rounded, Colors.blue),
        OrderStatus.onTheWay =>
          const _StatusVisual(Icons.local_shipping_rounded, Colors.indigo),
        OrderStatus.delivered =>
          const _StatusVisual(Icons.verified_rounded, Color(0xFF10B981)),
        OrderStatus.cancelled =>
          const _StatusVisual(Icons.cancel_rounded, Colors.red),
        OrderStatus.rejected =>
          const _StatusVisual(Icons.do_not_disturb_rounded, Colors.red),
        OrderStatus.returned =>
          const _StatusVisual(Icons.assignment_return_rounded, Colors.orange),
        OrderStatus.returnRequested =>
          const _StatusVisual(Icons.assignment_return_outlined, Colors.orange),
      };

  @override
  Widget build(BuildContext context) {
    final v = _visual(order.status);
    final isReturn = order.status == OrderStatus.returned ||
        order.status == OrderStatus.returnRequested;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: Container(
        key: ValueKey(order.status),
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              v.color.withValues(alpha: 0.12),
              context.bgCard,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: AppRadius.xxlAll,
          border: Border.all(color: v.color.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: v.color.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            _PulsingIcon(icon: v.icon, color: v.color),
            const SizedBox(height: 16),
            Text(order.status.label,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: v.color)),
            const SizedBox(height: 6),
            Text(order.status.description,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: context.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            // ✅ فحص ذكي: إذا كان الطلب مرتجعاً وقيمته 0، يتم إظهار مبلغ المرتجع المسترد فوراً حتى للطلبات القديمة
            if (isReturn && order.total == 0)
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('order_returns')
                    .where('order_id', isEqualTo: order.id)
                    .snapshots(),
                builder: (context, snap) {
                  double displayAmount = order.returnedAmount;
                  if (displayAmount == 0 && snap.hasData) {
                    for (final doc in snap.data!.docs) {
                      if (doc.data()['status'] != 'rejected') {
                        displayAmount +=
                            (doc.data()['refund_amount'] as num?)?.toDouble() ??
                                0.0;
                      }
                    }
                  }
                  if (displayAmount == 0 && order.originalTotal > 0) {
                    displayAmount = order.originalTotal;
                  }
                  return _TotalChip(
                    total: displayAmount,
                    color: v.color,
                    customLabel: 'المبلغ المسترد للمرتجع',
                    icon: Icons.assignment_return_rounded,
                  );
                },
              )
            else
              _TotalChip(total: order.total, color: v.color),
          ],
        ),
      ),
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  const _PulsingIcon({required this.icon, required this.color});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulse,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(
              color: widget.color.withValues(alpha: 0.3), width: 2.5),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.2),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(widget.icon, size: 48, color: widget.color),
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  final double total;
  final Color color;
  final String? customLabel;
  final IconData? icon;
  const _TotalChip({
    required this.total,
    required this.color,
    this.customLabel,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.payments_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          if (customLabel != null) ...[
            Text(
              '$customLabel: ',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.textSecondary,
              ),
            ),
          ],
          Text(
            '${total.toStringAsFixed(0)} ر.ي',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// STEP TRACKER
// ══════════════════════════════════════════════════════
class _StepTracker extends StatelessWidget {
  final OrderStatus status;
  const _StepTracker({required this.status});

  static const _steps = [
    _Step(OrderStatus.pending, 'استلام الطلب', Icons.receipt_rounded),
    _Step(OrderStatus.accepted, 'قبول الطلب', Icons.thumb_up_rounded),
    _Step(OrderStatus.preparing, 'التحضير', Icons.inventory_rounded),
    _Step(OrderStatus.onTheWay, 'في الطريق', Icons.local_shipping_rounded),
    _Step(OrderStatus.delivered, 'التسليم', Icons.verified_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    // حالات خاصة
    if (status == OrderStatus.cancelled || status == OrderStatus.rejected) {
      final isRejected = status == OrderStatus.rejected;
      return _AlertBox(
        icon: isRejected ? Icons.do_not_disturb_rounded : Icons.cancel_rounded,
        color: Colors.red,
        title: isRejected ? 'تم رفض هذا الطلب' : 'تم إلغاء هذا الطلب',
        subtitle: isRejected
            ? 'تواصل مع الإدارة لمعرفة السبب'
            : 'يمكنك إنشاء طلب جديد في أي وقت',
      );
    }

    if (status == OrderStatus.returned ||
        status == OrderStatus.returnRequested) {
      return _AlertBox(
        icon: Icons.assignment_return_rounded,
        color: Colors.orange,
        title: status == OrderStatus.returned
            ? 'تم إرجاع الطلب'
            : 'طلب الإرجاع قيد المراجعة',
        subtitle: 'سيتم التواصل معك قريباً',
      );
    }

    final currentStep = status.step;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppRadius.xxlAll,
        boxShadow: [
          BoxShadow(
            color: context.shadowColor.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.timeline_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'مراحل الطلب',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...List.generate(_steps.length, (i) {
            final step = _steps[i];
            final stepNum = step.status.step;
            final isDone = currentStep >= stepNum;
            final isActive = currentStep == stepNum;
            final isLast = i == _steps.length - 1;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 44,
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isDone
                              ? AppColors.primary
                              : isActive
                                  ? AppColors.primary.withValues(alpha: 0.15)
                                  : context.bgInput,
                          shape: BoxShape.circle,
                          border: isActive
                              ? Border.all(color: AppColors.primary, width: 2)
                              : null,
                          boxShadow: isDone
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        child: Icon(
                          isDone ? Icons.check_rounded : step.icon,
                          size: 20,
                          color: isDone
                              ? Colors.white
                              : isActive
                                  ? AppColors.primary
                                  : context.textHint,
                        ),
                      ),
                      if (!isLast)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 600),
                          width: 2,
                          height: 36,
                          color: currentStep > stepNum
                              ? AppColors.primary
                              : context.borderColor,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 8, bottom: isLast ? 0 : 20),
                    child: Row(
                      children: [
                        Text(step.label,
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: isActive
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: isDone || isActive
                                    ? context.textPrimary
                                    : context.textHint)),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          _BlinkDot(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _BlinkDot extends StatefulWidget {
  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
            color: AppColors.primary, shape: BoxShape.circle),
      ),
    );
  }
}

class _AlertBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _AlertBox(
      {required this.icon,
      required this.color,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: context.textSecondary)),
            ],
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════
// INFO GRID — شبكة المعلومات
// ══════════════════════════════════════════════════════
class _InfoGrid extends StatelessWidget {
  final OrderModel order;
  const _InfoGrid({required this.order});

  @override
  Widget build(BuildContext context) {
    final date = order.createdAt;
    final dateStr = '${date.day}/${date.month}/${date.year}';
    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    final items = [
      if (order.storeName != null)
        _InfoItem(
            Icons.store_rounded, 'المتجر', order.storeName!, AppColors.primary),
      if (order.paymentMethod != null)
        _InfoItem(
            Icons.payments_rounded,
            'الدفع',
            order.paymentMethod == 'cash' ? 'كاش' : order.paymentMethod!,
            Colors.green),
      _InfoItem(Icons.calendar_today_rounded, 'التاريخ', dateStr, Colors.blue),
      _InfoItem(Icons.access_time_rounded, 'الوقت', timeStr, Colors.indigo),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppRadius.xxlAll,
        boxShadow: [
          BoxShadow(
            color: context.shadowColor.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: items.map((item) => _InfoTile(item: item)).toList(),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final _InfoItem item;
  const _InfoTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final w = (MediaQuery.of(context).size.width - 64) / 2;
    return SizedBox(
      width: w,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, size: 18, color: item.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        color: context.textHint)),
                Text(item.value,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// ORDER SUMMARY
// ══════════════════════════════════════════════════════
class _OrderSummaryCard extends StatelessWidget {
  final OrderModel order;
  const _OrderSummaryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppRadius.xxlAll,
        boxShadow: [
          BoxShadow(
            color: context.shadowColor.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'تفاصيل الطلب',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (order.notes != null && order.notes!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes_rounded,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(order.notes!,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: Color(0xFF7A5C00))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Divider(color: Color(0xFFF0F0F0)),
          const SizedBox(height: 8),
          if (order.status == OrderStatus.returned ||
              order.status == OrderStatus.returnRequested) ...[
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('order_returns')
                  .where('order_id', isEqualTo: order.id)
                  .snapshots(),
              builder: (context, snap) {
                double displayAmount = order.returnedAmount;
                if (displayAmount == 0 && snap.hasData) {
                  for (final doc in snap.data!.docs) {
                    if (doc.data()['status'] != 'rejected') {
                      displayAmount +=
                          (doc.data()['refund_amount'] as num?)?.toDouble() ??
                              0.0;
                    }
                  }
                }
                if (displayAmount == 0 && order.originalTotal > 0) {
                  displayAmount = order.originalTotal;
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'قيمة المرتجع المسترد للتاجر',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.orange,
                      ),
                    ),
                    Text(
                      '${displayAmount.toStringAsFixed(0)} ر.ي',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الصافي المطلوب دفعه',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondary,
                  ),
                ),
                const Text(
                  '0 ر.ي (تمت التسوية)',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'المجموع الكلي',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                ),
                Text('${order.total.toStringAsFixed(0)} ر.ي',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// CANCEL BUTTON
// ══════════════════════════════════════════════════════
class _CancelButton extends StatefulWidget {
  final OrderModel order;
  const _CancelButton({required this.order});

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _confirm,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.red))
            : const Icon(Icons.cancel_outlined, size: 18),
        label: Text(_loading ? 'جاري الإلغاء...' : 'إلغاء الطلب',
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  Future<void> _confirm() async {
    if (_loading) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('تأكيد الإلغاء',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
        content: const Text('هل أنت متأكد من إلغاء هذا الطلب؟',
            style: TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('لا',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('نعم، إلغاء',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await OrdersService.cancelOrder(widget.order.id, widget.order.merchantId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إلغاء الطلب واستعادة المنتجات للمخزون بنجاح ✅',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          context.go('/merchant');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                e
                    .toString()
                    .replaceAll('Exception: ', '')
                    .replaceAll('StateError: ', ''),
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ══════════════════════════════════════════════════════
// LIVE INDICATOR
// ══════════════════════════════════════════════════════
class _LiveIndicator extends StatelessWidget {
  final AsyncSnapshot snapshot;
  const _LiveIndicator({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
              color: Color(0xFF10B981), shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        const Text('تحديث فوري مباشر',
            style: TextStyle(
                fontFamily: 'Cairo', fontSize: 11, color: Color(0xFFAAAAAA))),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════
// DATA CLASSES
// ══════════════════════════════════════════════════════
class _StatusMeta {
  final Color color;
  final String label;
  const _StatusMeta(this.color, this.label);
}

class _StatusVisual {
  final IconData icon;
  final Color color;
  const _StatusVisual(this.icon, this.color);
}

class _Step {
  final OrderStatus status;
  final String label;
  final IconData icon;
  const _Step(this.status, this.label, this.icon);
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _InfoItem(this.icon, this.label, this.value, this.color);
}
