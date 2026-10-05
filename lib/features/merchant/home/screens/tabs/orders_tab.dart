import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/services/local_storage.dart';
import '../../../orders/models/order_model.dart';
import '../../../orders/screens/order_status_screen.dart';
import '../../../widgets/order_card.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

class OrdersTab extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToHistory;
  const OrdersTab({super.key, this.onNavigateToHistory});

  @override
  ConsumerState<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends ConsumerState<OrdersTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = [
    (label: 'الكل', icon: Icons.list_alt_rounded),
    (label: 'الجارية', icon: Icons.pending_actions_rounded),
    (label: 'مُسلَّمة', icon: Icons.check_circle_rounded),
    (label: 'مرفوضة', icon: Icons.cancel_rounded),
    (label: 'مرتجعات', icon: Icons.assignment_return_rounded),
  ];

  bool _historyTriggered = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.animation!.addListener(_onTabAnimation);
  }

  void _onTabAnimation() {
    final val = _tabController.animation!.value;
    final lastIdx = (_tabs.length - 1).toDouble(); // = 4.0
    // المستخدم سحب يساراً تجاوز آخر تبويب → انتقل للسجل
    if (val > lastIdx + 0.4 && !_historyTriggered) {
      _historyTriggered = true;
      widget.onNavigateToHistory?.call();
    } else if (val <= lastIdx + 0.1) {
      _historyTriggered = false;
    }
  }

  @override
  void dispose() {
    _tabController.animation?.removeListener(_onTabAnimation);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final merchantId = AppStorage.userId ?? '';
    if (merchantId.isEmpty) {
      return const Scaffold(
        body:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Container(
              color: context.bgHeader,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'طلباتي',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'اضغط على أي طلب لتتبع حالته',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: Color(0xFFAAAAAA),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelStyle: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                    ),
                    labelColor: AppColors.primary,
                    unselectedLabelColor: const Color(0xFFAAAAAA),
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 2.5,
                    tabs: _tabs
                        .map((t) => Tab(
                              child: Row(
                                children: [
                                  Icon(t.icon, size: 15),
                                  const SizedBox(width: 5),
                                  Text(t.label),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),

            // ── TabBarView ──
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('orders')
                    .where('merchant_id', isEqualTo: merchantId)
                    .orderBy('created_at', descending: true)
                    .limit(100)
                    .snapshots(includeMetadataChanges: false),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: 5,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, __) => const _OrderSkeletonCard(),
                    );
                  }

                  final allOrders = (snapshot.data?.docs ?? []).map((d) {
                    return {'id': d.id, ...d.data()};
                  }).toList()
                    ..sort((a, b) {
                      DateTime parse(dynamic v) {
                        if (v is Timestamp) return v.toDate();
                        if (v is DateTime) return v;
                        if (v is String) {
                          return DateTime.tryParse(v) ?? DateTime(2000);
                        }
                        return DateTime(2000);
                      }

                      return parse(b['created_at'])
                          .compareTo(parse(a['created_at']));
                    });

                  List<Map<String, dynamic>> filterBy(List<String> statuses) {
                    return allOrders
                        .where((d) => statuses.contains(d['status']))
                        .toList();
                  }

                  return TabBarView(
                    controller: _tabController,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _OrdersList(
                        orders: allOrders,
                        emptyType: _EmptyType.all,
                      ),
                      _OrdersList(
                        orders: filterBy(const [
                          'pending',
                          'confirmed',
                          'accepted',
                          'preparing',
                          'shipped',
                          'on_the_way',
                        ]),
                        emptyType: _EmptyType.pending,
                      ),
                      _OrdersList(
                        orders: filterBy(const ['delivered']),
                        emptyType: _EmptyType.delivered,
                      ),
                      _OrdersList(
                        orders: filterBy(const ['cancelled', 'rejected']),
                        emptyType: _EmptyType.rejected,
                      ),
                      _OrdersList(
                        orders:
                            filterBy(const ['returned', 'return_requested']),
                        emptyType: _EmptyType.returned,
                      ),
                    ],
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

// ══════════════════════════════════════════════════════════
enum _EmptyType { all, pending, delivered, rejected, returned }

// ══════════════════════════════════════════════════════════
class _OrdersList extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final _EmptyType emptyType;

  const _OrdersList({
    required this.orders,
    required this.emptyType,
  });
  void _openOrder(BuildContext context, Map<String, dynamic> raw) {
    HapticFeedback.lightImpact();
    final order = OrderModel.fromJson(raw);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderStatusScreen(order: order),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return _EmptyState(emptyType: emptyType);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _TappableCard(
        key: ValueKey(orders[i]['id']?.toString() ?? '$i'),
        order: orders[i],
        onTap: () => _openOrder(context, orders[i]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// كارت قابل للنقر مع تأثير بصري
// ══════════════════════════════════════════════════════════
class _TappableCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback onTap;

  const _TappableCard({
    super.key,
    required this.order,
    required this.onTap,
  });

  @override
  State<_TappableCard> createState() => _TappableCardState();
}

class _TappableCardState extends State<_TappableCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: OrderCard(
          order: widget.order,
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Skeleton Card
// ══════════════════════════════════════════════════════════
class _OrderSkeletonCard extends StatefulWidget {
  const _OrderSkeletonCard();

  @override
  State<_OrderSkeletonCard> createState() => _OrderSkeletonCardState();
}

class _OrderSkeletonCardState extends State<_OrderSkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _box(double w, double h, {double radius = 8}) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: context.borderColor,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: context.shadowColor.withValues(alpha: 0.05),
              blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          _box(48, 48, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _box(double.infinity, 14),
                const SizedBox(height: 8),
                _box(120, 11),
                const SizedBox(height: 8),
                _box(80, 11),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _box(60, 16),
              const SizedBox(height: 8),
              _box(40, 24, radius: 12),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// حالة فارغة
// ══════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final _EmptyType emptyType;
  const _EmptyState({required this.emptyType});

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, subtitle) = switch (emptyType) {
      _EmptyType.all => (
          Icons.list_alt_rounded,
          AppColors.primary,
          'لا توجد طلبات بعد',
          'جميع طلباتك ستظهر هنا',
        ),
      _EmptyType.pending => (
          Icons.hourglass_empty_rounded,
          AppColors.primary,
          'لا توجد طلبات جارية',
          'طلباتك الجديدة ستظهر هنا',
        ),
      _EmptyType.delivered => (
          Icons.check_circle_outline_rounded,
          const Color(0xFF10B981),
          'لا توجد طلبات مُسلَّمة',
          'الطلبات المكتملة ستظهر هنا',
        ),
      _EmptyType.rejected => (
          Icons.cancel_outlined,
          Colors.red,
          'لا توجد طلبات مرفوضة',
          'الطلبات المرفوضة أو الملغاة ستظهر هنا',
        ),
      _EmptyType.returned => (
          Icons.assignment_return_outlined,
          Colors.orange,
          'لا توجد مرتجعات',
          'الطلبات المرتجعة ستظهر هنا',
        ),
    };

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 44, color: color.withValues(alpha: 0.45)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 15,
              color: context.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: context.textHint,
            ),
          ),
        ],
      ),
    );
  }
}
