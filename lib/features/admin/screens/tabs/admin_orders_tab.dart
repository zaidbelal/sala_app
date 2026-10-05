import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../services/admin_service.dart';
import '../../widgets/orders/order_card.dart';

// ── مزود البث اللحظي الاقتصادي للطلبات مع استعلام مباشر حسب الحالة ──
final adminOrdersRealtimeProvider = StreamProvider.autoDispose
    .family<List<AdminOrder>, List<String>?>((ref, statuses) {
  Query<Map<String, dynamic>> query =
      FirebaseFirestore.instance.collection('orders');

  if (statuses != null && statuses.isNotEmpty) {
    if (statuses.length == 1) {
      query = query.where('status', isEqualTo: statuses.first);
    } else {
      query = query.where('status', whereIn: statuses);
    }
  }

  return query
      .orderBy('created_at', descending: true)
      .limit(100)
      .snapshots(includeMetadataChanges: false)
      .map((snap) => snap.docs
          .map((d) => AdminOrder.fromMap({'id': d.id, ...d.data()}))
          .toList());
});

class AdminOrdersTab extends ConsumerStatefulWidget {
  const AdminOrdersTab({super.key});

  @override
  ConsumerState<AdminOrdersTab> createState() => _AdminOrdersTabState();
}

class _AdminOrdersTabState extends ConsumerState<AdminOrdersTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = [
    (label: 'الكل', statuses: null, color: AppColors.primary),
    (label: 'معلق', statuses: ['pending'], color: Colors.orange),
    (
      label: 'مقبول',
      statuses: ['confirmed', 'accepted', 'preparing'],
      color: Colors.blue
    ),
    (
      label: 'في الطريق',
      statuses: ['shipped', 'on_the_way'],
      color: Colors.indigo
    ),
    (label: 'مُسلّم', statuses: ['delivered'], color: Color(0xFF10B981)),
    (
      label: 'ملغي ومرفوض',
      statuses: ['cancelled', 'rejected'],
      color: Colors.red
    ),
    (label: 'مُرتجع', statuses: ['returned'], color: Colors.deepOrange),
    (
      label: 'طلب إرجاع',
      statuses: ['return_requested'],
      color: Colors.deepOrange
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Text(
                  'إدارة الطلبات',
                  style: AppTextStyles.headlineMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 14, color: Colors.green),
                      SizedBox(width: 4),
                      Text(
                        'مباشر لحظي',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _tabs.length,
              itemBuilder: (context, i) {
                final tab = _tabs[i];
                final chipColor = tab.color;
                return AnimatedBuilder(
                  animation: _tabController,
                  builder: (_, __) {
                    final sel = _tabController.index == i;
                    return GestureDetector(
                      onTap: () => _tabController.animateTo(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel
                              ? chipColor
                              : chipColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: sel
                                ? chipColor
                                : chipColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          tab.label,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: sel ? Colors.white : chipColor,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children:
                  _tabs.map((t) => _OrdersList(statuses: t.statuses)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersList extends ConsumerWidget {
  final List<String>? statuses;
  const _OrdersList({this.statuses});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(adminOrdersRealtimeProvider(statuses));

    return ordersAsync.when(
      loading: () => const Center(
        child:
            CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.red, size: 36),
            const SizedBox(height: 8),
            Text(
              'تعذر جلب الطلبات لحظياً: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
            ),
          ],
        ),
      ),
      data: (orders) {
        if (orders.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 72, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'لا توجد طلبات في هذا القسم حالياً',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          itemCount: orders.length,
          itemBuilder: (_, i) {
            return OrderCard(
              order: orders[i],
              onStatusChanged: () {
                // البث اللحظي يتكفل بتحديث الواجهة تلقائياً دون الحاجة لإعادة الجلب
              },
            );
          },
        );
      },
    );
  }
}
