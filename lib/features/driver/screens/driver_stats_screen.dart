import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../../core/services/local_storage.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

// ══════════════════════════════════════════════════════════
//  Provider — إحصائيات السائق
// ══════════════════════════════════════════════════════════

final driverStatsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final driverId = AppStorage.userId ?? '';
  if (driverId.isEmpty) return {};

  try {
    final db = FirebaseFirestore.instance;
    final baseQuery =
        db.collection('orders').where('driver_id', isEqualTo: driverId);

    // ✅ استخدام count() بدلاً من تحميل 500 مستند — دقة لا نهائية بتكلفة صفرية تقريباً
    final totalSnap = await baseQuery.count().get();
    final deliveredSnap =
        await baseQuery.where('status', isEqualTo: 'delivered').count().get();
    final cancelledSnap =
        await baseQuery.where('status', isEqualTo: 'cancelled').count().get();

    final total = totalSnap.count ?? 0;
    final delivered = deliveredSnap.count ?? 0;
    final cancelled = cancelledSnap.count ?? 0;
    final pending = (total - delivered - cancelled).clamp(0, total);

    // ✅ aggregate(sum) لدقة كاملة على أي عدد من الطلبات
    double totalEarnings = 0.0;
    try {
      final sumSnap = await baseQuery
          .where('status', isEqualTo: 'delivered')
          .aggregate(sum('delivery_fee'))
          .get();
      totalEarnings = sumSnap.getSum('delivery_fee') ?? 0.0;
    } catch (_) {
      // fallback: pagination نظيف إذا كانت نسخة Firestore لا تدعم aggregate
      const pageSize = 500;
      DocumentSnapshot? cursor;
      bool hasMore = true;
      while (hasMore) {
        var q =
            baseQuery.where('status', isEqualTo: 'delivered').limit(pageSize);
        if (cursor != null) q = q.startAfterDocument(cursor);
        final page = await q.get();
        for (final d in page.docs) {
          totalEarnings +=
              (d.data()['delivery_fee'] as num?)?.toDouble() ?? 0.0;
        }
        hasMore = page.docs.length == pageSize;
        cursor = page.docs.isNotEmpty ? page.docs.last : null;
        if (cursor == null) hasMore = false;
      }
    }

    return {
      'total': total,
      'delivered': delivered,
      'cancelled': cancelled,
      'pending': pending,
      'earnings': totalEarnings,
    };
  } catch (e, st) {
    if (kDebugMode) debugPrint('❌ driverStatsProvider error: $e\n$st');
    return {};
  }
});

// ══════════════════════════════════════════════════════════
//  الشاشة الرئيسية
// ══════════════════════════════════════════════════════════
class DriverStatsScreen extends ConsumerWidget {
  const DriverStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(driverStatsProvider);

    return Scaffold(
      backgroundColor: context.bgPage,
      appBar: AppBar(
        title: Text(
          'إحصائياتي',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: context.textPrimary,
          ),
        ),
        backgroundColor: context.bgHeader,
        elevation: 0,
        centerTitle: true,
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              const Text(
                'تعذّر تحميل الإحصائيات',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 16),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.invalidate(driverStatsProvider),
                child: const Text('إعادة المحاولة',
                    style: TextStyle(fontFamily: 'Cairo')),
              ),
            ],
          ),
        ),
        data: (stats) {
          if (stats.isEmpty) {
            return const Center(
              child: Text(
                'لا توجد بيانات بعد',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 16),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(driverStatsProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── بطاقة الأرباح ─────────────────────────────
                _EarningsCard(
                  earnings: (stats['earnings'] as num?)?.toDouble() ?? 0.0,
                ),
                const SizedBox(height: 16),

                // ── شبكة الإحصائيات ───────────────────────────
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
                  children: [
                    _StatCard(
                      label: 'إجمالي الطلبات',
                      value: '${stats['total'] ?? 0}',
                      icon: Icons.list_alt_rounded,
                      color: const Color(0xFF6366F1),
                    ),
                    _StatCard(
                      label: 'تم التوصيل',
                      value: '${stats['delivered'] ?? 0}',
                      icon: Icons.check_circle_rounded,
                      color: const Color(0xFF22C55E),
                    ),
                    _StatCard(
                      label: 'قيد التنفيذ',
                      value: '${stats['pending'] ?? 0}',
                      icon: Icons.pending_rounded,
                      color: const Color(0xFFF59E0B),
                    ),
                    _StatCard(
                      label: 'ملغاة',
                      value: '${stats['cancelled'] ?? 0}',
                      icon: Icons.cancel_rounded,
                      color: const Color(0xFFEF4444),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── نسبة الإنجاز ──────────────────────────────
                _CompletionRate(
                  delivered: (stats['delivered'] as int?) ?? 0,
                  total: (stats['total'] as int?) ?? 0,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
//  Widgets مساعدة
// ══════════════════════════════════════════════════════════

class _EarningsCard extends StatelessWidget {
  final double earnings;
  const _EarningsCard({required this.earnings});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white70, size: 20),
              SizedBox(width: 8),
              Text(
                'إجمالي الأرباح',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${earnings.toStringAsFixed(0)} ر.ي',
            style: const TextStyle(
              fontFamily: 'Cairo',
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
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

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompletionRate extends StatelessWidget {
  final int delivered;
  final int total;

  const _CompletionRate({required this.delivered, required this.total});

  @override
  Widget build(BuildContext context) {
    final rate = total == 0 ? 0.0 : delivered / total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
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
          Text(
            'نسبة الإنجاز',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 12,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF22C55E)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(rate * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              color: Color(0xFF22C55E),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
