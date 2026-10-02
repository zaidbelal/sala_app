import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../services/admin_service.dart';
import '../../../auth/login/services/auth_service.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

// ══ Providers ══
final _statsProvider = FutureProvider<AdminStats>((ref) async {
  return ref.read(adminServiceProvider).getStats();
});

// ✅ جديد: إحصائيات اليوم فقط
final _todayStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.read(adminServiceProvider).getTodayStats();
});
final _liveNewOrdersProvider = StreamProvider.autoDispose<int>((ref) {
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);

  return FirebaseFirestore.instance
      .collection('orders')
      .where('status', isEqualTo: 'pending')
      .where('created_at',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
      .limit(150)
      .snapshots(includeMetadataChanges: false)
      .map((snap) => snap.docs.length);
});
// صافي الربح الدائم من Firestore
final _permanentProfitProvider = StreamProvider<double>((ref) {
  return ref.read(adminServiceProvider).watchPermanentProfit();
});

// ══════════════════════════════════════════════
// الشاشة الرئيسية
// ══════════════════════════════════════════════
class AdminDashboardTab extends ConsumerWidget {
  final VoidCallback? onNavigateToOrders;
  const AdminDashboardTab({super.key, this.onNavigateToOrders});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_statsProvider);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        // ✅ جديد: سحب للتحديث
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(_statsProvider);
          ref.invalidate(_todayStatsProvider);
          try {
            await ref.read(_statsProvider.future);
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[AdminDashboardTab] refresh failed: $e');
            }
          }
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            // ── الهيدر ──
            SliverToBoxAdapter(child: _DashboardHeader(ref: ref)),

            // ── بطاقة اليوم المباشرة ──
            SliverToBoxAdapter(child: _TodayLiveCard(ref: ref)),

            // ── إجراءات سريعة ──
            SliverToBoxAdapter(
              child: _QuickActions(
                ref: ref,
                onNavigateToOrders: onNavigateToOrders,
              ),
            ),

            // ── الإحصائيات الكلية ──
            SliverToBoxAdapter(
              child: statsAsync.when(
                loading: () => const SizedBox(
                  height: 200,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
                error: (_, __) =>
                    _ErrorRetry(onRetry: () => ref.invalidate(_statsProvider)),
                data: (stats) => Column(
                  children: [
                    _StatsGrid(stats: stats),
                    const SizedBox(height: 12),
                    _OrdersChartCard(stats: stats),
                    _QuickSummary(stats: stats),
                  ],
                ),
              ),
            ),

            // مسافة سفلية حتى لا يغطي شريط التنقل السفلي آخر البطاقات
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// الهيدر
// ══════════════════════════════════════════════
class _DashboardHeader extends StatelessWidget {
  final WidgetRef ref;
  const _DashboardHeader({required this.ref});

  @override
  Widget build(BuildContext context) {
    // ✅ جديد: عرض عدد الطلبات الجديدة في الهيدر
    final liveAsync = ref.watch(_liveNewOrdersProvider);
    final newCount = liveAsync.maybeWhen(data: (n) => n, orElse: () => 0);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B8E3D), Color(0xFF25C25A)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.dashboard_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('لوحة الإدارة',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
                // ✅ جديد: طلبات اليوم في الهيدر
                Row(
                  children: [
                    Text(
                      'اليوم: $newCount طلب جديد',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: Colors.white70),
                    ),
                    if (newCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFD700),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // ── زر الخروج ──
          GestureDetector(
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: const Text('تسجيل الخروج',
                      style: TextStyle(
                          fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
                  content: const Text('هل تريد تسجيل الخروج؟',
                      style: TextStyle(fontFamily: 'Cairo')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('إلغاء',
                            style: TextStyle(
                                fontFamily: 'Cairo', color: Colors.grey))),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                        child: const Text('خروج',
                            style: TextStyle(fontFamily: 'Cairo'))),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(authServiceProvider).signOut();
                if (context.mounted) context.go('/login');
              }
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.logout_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// ✅ جديد: بطاقة إحصائيات اليوم المباشرة
// ══════════════════════════════════════════════
class _TodayLiveCard extends ConsumerWidget {
  final WidgetRef ref;
  const _TodayLiveCard({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(_todayStatsProvider);

    return todayAsync.maybeWhen(
      data: (today) {
        final revenue = (today['revenue'] as double?) ?? 0;
        final ordersCount = (today['orders'] as double?)?.toInt() ?? 0;
        final now = DateTime.now();

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: const Color(0xFFFCD34D).withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFCD34D).withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCD34D).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.wb_sunny_rounded,
                    color: Color(0xFFD97706), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إيرادات اليوم  •  ${now.day}/${now.month}/${now.year}',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: Color(0xFFD97706)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${revenue.toStringAsFixed(0)} ر.ي',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF92400E)),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$ordersCount',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFD97706)),
                  ),
                  const Text(
                    'طلب مُسلَّم',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: Color(0xFF92400E)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ══════════════════════════════════════════════
// شبكة الإحصائيات
// ══════════════════════════════════════════════
class _StatsGrid extends StatelessWidget {
  final AdminStats stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── عنوان القسم ──
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'الإحصائيات الكلية',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary),
            ),
          ),

          // ── الصف الأول ──
          Row(children: [
            Expanded(
              child: _StatCard(
                title: 'إجمالي الطلبات',
                value: '${stats.totalOrders}',
                icon: Icons.receipt_long_rounded,
                color: AppColors.primary,
                trend: null,
                fillPercent: stats.totalOrders > 0
                    ? (stats.deliveredOrders.clamp(0, stats.totalOrders) /
                        stats.totalOrders)
                    : 0,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                title: 'طلبات معلقة',
                value: '${stats.pendingOrders}',
                icon: Icons.hourglass_top_rounded,
                color: Colors.orange,
                trend: stats.pendingOrders > 10
                    ? '⚠️ كثيرة'
                    : stats.pendingOrders > 5
                        ? '⚡ متوسطة'
                        : null,
                fillPercent: stats.totalOrders > 0
                    ? (stats.pendingOrders / stats.totalOrders).clamp(0.0, 1.0)
                    : 0,
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // ── الصف الثاني ──
          Row(children: [
            Expanded(
              child: _StatCard(
                title: 'التجار المسجلون',
                value: '${stats.totalMerchants}',
                icon: Icons.store_rounded,
                color: const Color(0xFF3B82F6),
                trend: null,
                fillPercent: stats.totalMerchants > 0
                    ? (stats.totalMerchants / (stats.totalMerchants + 10))
                        .clamp(0.0, 1.0)
                    : 0,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                title: 'إجمالي الإيرادات',
                value: '${stats.totalRevenue.toStringAsFixed(0)} ر.ي',
                icon: Icons.payments_rounded,
                color: const Color(0xFF8B5CF6),
                trend: null,
                fillPercent: stats.totalRevenue > 0 ? 0.75 : 0,
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // ── صف إضافي — ملغية + مرجوعات ──
          Row(children: [
            Expanded(
              child: _StatCard(
                title: 'طلبات ملغاة',
                value: '${stats.cancelledOrders}',
                icon: Icons.cancel_rounded,
                color: Colors.red,
                trend: null,
                fillPercent: stats.totalOrders > 0
                    ? (stats.cancelledOrders / stats.totalOrders)
                        .clamp(0.0, 1.0)
                    : 0,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                title: 'قيمة المرجوعات',
                value: '${stats.returnedAmount.toStringAsFixed(0)} ر.ي',
                icon: Icons.assignment_return_rounded,
                color: Colors.deepOrange,
                trend: stats.returnedAmount > 0 ? '↩️' : null,
                fillPercent: stats.totalRevenue > 0
                    ? (stats.returnedAmount / stats.totalRevenue)
                        .clamp(0.0, 1.0)
                    : 0,
              ),
            ),
          ]),

          const SizedBox(height: 12),

          // ── بطاقة الربح ──
          _ProfitCard(
            revenue: stats.totalRevenue,
            profit: stats.totalProfit,
            hasCostData: stats.hasCostData,
          ),
          const SizedBox(height: 12),
          // ── بطاقة الربح الدائم القابل للتفريغ ──
          _PermanentProfitCard(),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// بطاقة الإحصاء — محسّنة
// ══════════════════════════════════════════════
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? trend;
  final double? fillPercent; // 0.0 → 1.0 لرسم المؤشر

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.trend,
    this.fillPercent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              if (trend != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(trend!,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          color: Colors.orange)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: color)),
          const SizedBox(height: 3),
          Text(title,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: context.textSecondary)),
          // ── Mini Bar ──
          if (fillPercent != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fillPercent!.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: color.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// بطاقة الربح الصافي الدائم (قابل للتفريغ)
// ══════════════════════════════════════════════
class _PermanentProfitCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profitAsync = ref.watch(_permanentProfitProvider);

    return profitAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (profit) {
        final isPositive = profit >= 0;
        return Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isPositive
                  ? [const Color(0xFF0F4C2A), const Color(0xFF1B8E3D)]
                  : [const Color(0xFF7F1D1D), const Color(0xFFDC2626)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: (isPositive ? const Color(0xFF1B8E3D) : Colors.red)
                    .withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isPositive
                      ? Icons.savings_rounded
                      : Icons.trending_down_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'أرباح الدورة الحالية (قابلة للتفريغ)',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${profit.toStringAsFixed(0)} ر.ي',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'عداد دوري للشحنات • لا يؤثر على الأرباح الكلية',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          color: Colors.white70),
                    ),
                  ],
                ),
              ),
              // ── زر التفريغ ──
              GestureDetector(
                onTap: () => _confirmReset(context, ref),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 20),
                      SizedBox(height: 2),
                      Text('تفريغ',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmReset(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('تفريغ صافي الربح؟',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
        content: const Text(
          'سيتم إعادة العداد إلى صفر.\nاستخدم هذا عند شراء بضاعة جديدة لتتبع الربح من نقطة البداية.',
          style: TextStyle(fontFamily: 'Cairo', fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(adminServiceProvider).resetPermanentProfit();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('تم تفريغ صافي الربح',
                        style: TextStyle(fontFamily: 'Cairo')),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: const StadiumBorder(),
            ),
            child: const Text('تفريغ',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// بطاقة الربح الصافي
// ══════════════════════════════════════════════
class _ProfitCard extends StatelessWidget {
  final double revenue;
  final double profit;
  final bool hasCostData;

  const _ProfitCard({
    required this.revenue,
    required this.profit,
    required this.hasCostData,
  });

  @override
  Widget build(BuildContext context) {
    // إذا لا يوجد بيانات سعر شراء
    if (!hasCostData) {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, color: Colors.amber, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'أضف سعر الشراء للمنتجات من الكاتالوج لعرض الربح الصافي',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 13, color: Colors.amber),
            ),
          ),
        ]),
      );
    }

    // ✅ إصلاح: حساب هامش الربح بشكل صحيح
    final margin = revenue > 0 ? (profit / revenue * 100) : 0.0;
    final isPositive = profit >= 0;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPositive
              ? [const Color(0xFF1B8E3D), const Color(0xFF22B34A)]
              : [const Color(0xFFE53935), const Color(0xFFEF5350)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: (isPositive ? AppColors.primary : Colors.red)
                .withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isPositive
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ إصلاح: اسم صادق — إجمالي لا "اليوم"
                const Text('الربح الصافي الإجمالي',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: Colors.white70)),
                const SizedBox(height: 4),
                Text('${profit.toStringAsFixed(0)} ر.ي',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${margin.toStringAsFixed(1)}%',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
              const SizedBox(height: 4),
              const Text('هامش الربح',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      color: Colors.white60)),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// ملخص الأداء — محسّن
// ══════════════════════════════════════════════
class _QuickSummary extends StatelessWidget {
  final AdminStats stats;
  const _QuickSummary({required this.stats});

  @override
  Widget build(BuildContext context) {
    final delivered = stats.deliveredOrders;
    final efficiency = stats.totalOrders > 0
        ? (delivered.clamp(0, stats.totalOrders) / stats.totalOrders * 100)
            .toStringAsFixed(0)
        : '0';

    // ✅ إصلاح: استخدام totalRevenue
    final avgOrder = stats.totalOrders > 0
        ? (stats.totalRevenue / stats.totalOrders).toStringAsFixed(0)
        : '—';

    // ✅ جديد: نسبة الإلغاء
    final cancelRate = stats.totalOrders > 0
        ? (stats.cancelledOrders / stats.totalOrders * 100).toStringAsFixed(1)
        : '0';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(18),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text('ملخص الأداء',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary)),
            ],
          ),
          const SizedBox(height: 14),

          _SummaryRow(
            label: 'كفاءة التسليم',
            value: '$efficiency%',
            icon: Icons.local_shipping_rounded,
            color: AppColors.primary,
          ),
          const Divider(height: 16),

          _SummaryRow(
            label: 'متوسط قيمة الطلب',
            value: '$avgOrder ر.ي',
            icon: Icons.calculate_rounded,
            color: const Color(0xFF8B5CF6),
          ),
          const Divider(height: 16),

          _SummaryRow(
            label: 'التجار المسجلون',
            value: '${stats.totalMerchants} تاجر',
            icon: Icons.people_rounded,
            color: const Color(0xFF3B82F6),
          ),
          const Divider(height: 16),

          // ✅ جديد: نسبة الإلغاء
          _SummaryRow(
            label: 'نسبة الإلغاء',
            value: '$cancelRate%',
            icon: Icons.cancel_outlined,
            color: (double.tryParse(cancelRate) ?? 0.0) > 15
                ? Colors.red
                : Colors.grey,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// ✅ جديد: أزرار الإجراءات السريعة
// ══════════════════════════════════════════════
class _QuickActions extends StatelessWidget {
  final WidgetRef ref;
  final VoidCallback? onNavigateToOrders;
  const _QuickActions({required this.ref, this.onNavigateToOrders});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(18),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flash_on_rounded,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text('إجراءات سريعة',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.refresh_rounded,
                  label: 'تحديث',
                  color: AppColors.primary,
                  onTap: () {
                    ref.invalidate(_statsProvider);
                    ref.invalidate(_todayStatsProvider);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: Icons.receipt_long_rounded,
                  label: 'الطلبات',
                  color: Colors.blue,
                  onTap: () => onNavigateToOrders?.call(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: Icons.notifications_rounded,
                  label: 'إشعار عام',
                  color: Colors.purple,
                  onTap: () => _showSendNotificationDialog(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSendNotificationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _BroadcastNotificationDialog(),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// صف الملخص
// ══════════════════════════════════════════════
class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                fontFamily: 'Cairo', fontSize: 13, color: Color(0xFF666666))),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color)),
      ],
    );
  }
}

// ══════════════════════════════════════════════
// ويدجت الخطأ مع زر إعادة المحاولة
// ══════════════════════════════════════════════
class _ErrorRetry extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorRetry({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          const Text('فشل تحميل الإحصائيات',
              style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('إعادة المحاولة',
                style: TextStyle(fontFamily: 'Cairo')),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

// ── مخطط الطلبات حسب الحالة ──
class _OrdersChartCard extends StatelessWidget {
  final AdminStats stats;
  const _OrdersChartCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = stats.totalOrders == 0 ? 1 : stats.totalOrders;

    final delivered = stats.deliveredOrders;

    final bars = [
      _BarData(
          label: 'انتظار',
          count: stats.pendingOrders,
          color: const Color(0xFFFF9800)),
      _BarData(
          label: 'مُسلَّمة', count: delivered, color: const Color(0xFF4CAF50)),
      _BarData(
          label: 'ملغاة',
          count: stats.cancelledOrders,
          color: const Color(0xFFF44336)),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'توزيع الطلبات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: bars.map((bar) {
              final pct = bar.count / total;
              final height = 80.0 * pct.clamp(0.05, 1.0);
              return Column(
                children: [
                  Text(
                    '${bar.count}',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: bar.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    width: 40,
                    height: height,
                    decoration: BoxDecoration(
                      color: bar.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: bar.color.withValues(alpha: 0.4), width: 1),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        height: height,
                        decoration: BoxDecoration(
                          color: bar.color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    bar.label,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: Color(0xFF888888),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: const Color(0xFFEEEEEE),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 13, color: Color(0xFFAAAAAA)),
              const SizedBox(width: 4),
              Text(
                'إجمالي ${stats.totalOrders} طلب',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: Color(0xFFAAAAAA),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BarData {
  final String label;
  final int count;
  final Color color;
  const _BarData(
      {required this.label, required this.count, required this.color});
}

class _BroadcastNotificationDialog extends ConsumerStatefulWidget {
  const _BroadcastNotificationDialog();

  @override
  ConsumerState<_BroadcastNotificationDialog> createState() =>
      _BroadcastNotificationDialogState();
}

class _BroadcastNotificationDialogState
    extends ConsumerState<_BroadcastNotificationDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _bodyCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('إرسال إشعار لجميع التجار',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(
              labelText: 'عنوان الإشعار',
              labelStyle: const TextStyle(fontFamily: 'Cairo'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'نص الإشعار',
              labelStyle: const TextStyle(fontFamily: 'Cairo'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء',
              style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () async {
            final title = _titleCtrl.text.trim();
            final body = _bodyCtrl.text.trim();
            if (title.isEmpty || body.isEmpty) return;
            Navigator.pop(context);
            try {
              await ref.read(adminServiceProvider).sendNotification(
                    title: title,
                    body: body,
                  );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('تم إرسال الإشعار بنجاح ✅',
                        style: TextStyle(fontFamily: 'Cairo')),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            } catch (_) {}
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('إرسال',
              style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
        ),
      ],
    );
  }
}
