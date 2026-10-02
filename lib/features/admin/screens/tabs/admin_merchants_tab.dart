// ==================================================
// FILE: lib\features\admin\screens\tabs\admin_merchants_tab.dart
// ==================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../services/admin_service.dart';
import 'package:flutter/foundation.dart';
import 'package:sala/core/widgets/app_map.dart';

// ══════════════════════════════════════════
// Providers
// ══════════════════════════════════════════
// جلب التجار بنظام التصفح على دفعات لتوفير استهلاك الفايربيز
final merchantsLoadingMoreProvider =
    StateProvider.autoDispose<bool>((ref) => false);

class MerchantsPaginationNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  MerchantsPaginationNotifier(this._ref) : super(const AsyncValue.loading()) {
    loadInitial();
  }

  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  static const int _pageSize = 30;

  bool get hasMore => _hasMore;
  Future<void> loadInitial() async {
    if (!mounted) return;
    state = const AsyncValue.loading();
    try {
      // 🚀 جلب التجار بدون دمج where مع orderBy لتجاوز خطأ الفهرس السحابي نهائياً
      final snap = await FirebaseFirestore.instance
          .collection('profiles')
          .where('role', isEqualTo: 'merchant')
          .limit(_pageSize)
          .get(const GetOptions(source: Source.serverAndCache));
      if (!mounted) return;

      _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      _hasMore = snap.docs.length == _pageSize;

      final list = snap.docs
          .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
          .toList();

      // الفرز الزمني التنازلي يتم في الذاكرة بأعلى سرعة دون أي أخطاء
      list.sort((a, b) {
        DateTime parse(dynamic v) {
          if (v is Timestamp) return v.toDate();
          if (v is DateTime) return v;
          if (v is String) return DateTime.tryParse(v) ?? DateTime(2000);
          return DateTime(2000);
        }

        return parse(b['created_at']).compareTo(parse(a['created_at']));
      });

      if (!mounted) return;
      state = AsyncValue.data(list);
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore ||
        _ref.read(merchantsLoadingMoreProvider) ||
        _lastDoc == null) return;
    _ref.read(merchantsLoadingMoreProvider.notifier).state = true;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('profiles')
          .where('role', isEqualTo: 'merchant')
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 6));
      if (!mounted) return;
      _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      _hasMore = snap.docs.length == _pageSize;

      final current = state.value ?? [];
      final more = snap.docs
          .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
          .toList();

      final Map<String, Map<String, dynamic>> mergedMap = {
        for (final item in current) item['id'] as String: item
      };
      for (final item in more) {
        mergedMap[item['id'] as String] = item;
      }

      final sortedList = mergedMap.values.toList()
        ..sort((a, b) {
          DateTime parse(dynamic v) {
            if (v is Timestamp) return v.toDate();
            if (v is DateTime) return v;
            if (v is String) return DateTime.tryParse(v) ?? DateTime(2000);
            return DateTime(2000);
          }

          return parse(b['created_at']).compareTo(parse(a['created_at']));
        });

      if (!mounted) return;
      state = AsyncValue.data(sortedList);
    } catch (e, st) {
      if (kDebugMode) debugPrint('Error loading more merchants: $e\n$st');
    } finally {
      _ref.read(merchantsLoadingMoreProvider.notifier).state = false;
    }
  }
}

final _merchantsProvider = StateNotifierProvider.autoDispose<
    MerchantsPaginationNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return MerchantsPaginationNotifier(ref);
});
final _merchantStatsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, merchantId) {
  return ref.read(adminServiceProvider).getMerchantStats(merchantId);
});

// ══════════════════════════════════════════
// الصفحة الرئيسية
// ══════════════════════════════════════════

class AdminMerchantsTab extends ConsumerStatefulWidget {
  const AdminMerchantsTab({super.key});

  @override
  ConsumerState<AdminMerchantsTab> createState() => _AdminMerchantsTabState();
}

class _AdminMerchantsTabState extends ConsumerState<AdminMerchantsTab> {
  String _search = '';
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final merchantsAsync = ref.watch(_merchantsProvider);

    return SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          _buildSearchBar(),
          _buildFilterChips(),
          Expanded(
            child: merchantsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (_, __) => _buildError(),
              data: (merchants) => _buildList(merchants),
            ),
          ),
        ],
      ),
    );
  }

  // ── الرأس ──
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'إدارة التجار',
              style: AppTextStyles.headlineMedium.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1A1A2E),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: () =>
                ref.read(_merchantsProvider.notifier).loadInitial(),
            tooltip: 'تحديث',
          ),
        ],
      ),
    );
  }

  // ── شريط البحث ──
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: 'بحث في التجار المحمّلين حالياً...',
          hintStyle: const TextStyle(
              fontFamily: 'Cairo', color: Color(0xFFAAAAAA), fontSize: 13),
          prefixIcon:
              const Icon(Icons.search_rounded, color: Colors.grey, size: 20),
          suffixIcon: _search.isNotEmpty
              ? GestureDetector(
                  onTap: () => setState(() => _search = ''),
                  child: const Icon(Icons.close_rounded,
                      size: 18, color: Colors.grey))
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
                color: Colors.grey.withValues(alpha: 0.15), width: 1),
          ),
        ),
        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
      ),
    );
  }

  // ── فلاتر الحالة ──
  Widget _buildFilterChips() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FilterChip(
              label: 'الكل',
              filter: _Filter.all,
              current: _filter,
              onTap: () => setState(() => _filter = _Filter.all)),
          const SizedBox(width: 8),
          _FilterChip(
              label: 'مفعّل',
              filter: _Filter.active,
              current: _filter,
              onTap: () => setState(() => _filter = _Filter.active)),
          const SizedBox(width: 8),
          _FilterChip(
              label: 'معطّل',
              filter: _Filter.inactive,
              current: _filter,
              onTap: () => setState(() => _filter = _Filter.inactive)),
          const SizedBox(width: 8),
          _FilterChip(
              label: 'محظور',
              filter: _Filter.banned,
              current: _filter,
              onTap: () => setState(() => _filter = _Filter.banned)),
        ],
      ),
    );
  }

  // ── قائمة التجار الموفرة لاستهلاك البيانات ──
  Widget _buildList(List<Map<String, dynamic>> merchants) {
    late final filtered = _applyFilters(merchants);
    final pagination = ref.watch(_merchantsProvider.notifier);
    final isLoadingMore = ref.watch(merchantsLoadingMoreProvider);

    if (merchants.isEmpty) {
      return _buildEmpty('لا يوجد تجار مسجلون', Icons.store_outlined);
    }
    if (filtered.isEmpty) {
      return _buildEmpty(
          _search.isNotEmpty
              ? 'لا نتائج لـ "$_search"'
              : 'لا يوجد في هذه الفئة',
          Icons.search_off_rounded);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'عرض ${filtered.length} تاجر',
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary),
              ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async =>
                ref.read(_merchantsProvider.notifier).loadInitial(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount: filtered.length +
                  (pagination.hasMore && _search.isEmpty ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == filtered.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: TextButton.icon(
                        onPressed:
                            isLoadingMore ? null : () => pagination.loadMore(),
                        icon: isLoadingMore
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.arrow_downward_rounded),
                        label: const Text(
                          'تحميل المزيد من التجار',
                          style: TextStyle(
                              fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  );
                }
                return _MerchantCard(
                  merchant: filtered[i],
                  onTap: () => _showMerchantDetails(context, ref, filtered[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> all) {
    List<Map<String, dynamic>> result = all;

    // فلتر الحالة
    result = result.where((m) {
      final isBanned = m['is_banned'] as bool? ?? false;
      final isActive = m['is_active'] as bool? ?? false;
      return switch (_filter) {
        _Filter.all => true,
        _Filter.active => isActive && !isBanned,
        _Filter.inactive => !isActive && !isBanned,
        _Filter.banned => isBanned,
      };
    }).toList();

    // فلتر البحث
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      result = result.where((m) {
        final name = (m['full_name'] ?? '').toString().toLowerCase();
        final store = (m['store_name'] ?? '').toString().toLowerCase();
        final phone = (m['phone_number'] ?? '').toString();
        return name.contains(q) || store.contains(q) || phone.contains(q);
      }).toList();
    }

    return result;
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 56, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('فشل تحميل التجار',
              style: TextStyle(fontFamily: 'Cairo', color: Colors.grey[500])),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => ref.invalidate(_merchantsProvider),
            child: const Text('إعادة المحاولة',
                style:
                    TextStyle(fontFamily: 'Cairo', color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(String msg, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(msg,
              style: TextStyle(fontFamily: 'Cairo', color: Colors.grey[500])),
        ],
      ),
    );
  }

  void _showMerchantDetails(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> merchant,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MerchantDetailsSheet(
        merchant: merchant,
        onRefresh: () => ref.invalidate(_merchantsProvider),
      ),
    );
  }
}

// ══════════════════════════════════════════
// Enum الفلتر
// ══════════════════════════════════════════

enum _Filter { all, active, inactive, banned }

// ══════════════════════════════════════════
// شريحة الفلتر
// ══════════════════════════════════════════

class _FilterChip extends StatelessWidget {
  final String label;
  final _Filter filter;
  final _Filter current;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.filter,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = filter == current;
    final color = switch (filter) {
      _Filter.active => AppColors.primary,
      _Filter.inactive => Colors.orange,
      _Filter.banned => Colors.red,
      _Filter.all => AppColors.primary,
    };

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════
// بطاقة التاجر
// ══════════════════════════════════════════
class _MerchantCard extends StatelessWidget {
  final Map<String, dynamic> merchant;
  final VoidCallback onTap;

  const _MerchantCard({required this.merchant, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isBanned = merchant['is_banned'] as bool? ?? false;
    final isActive = merchant['is_active'] as bool? ?? false;
    final name = merchant['full_name'] ?? 'بدون اسم';
    final store = merchant['store_name'] as String? ?? '';
    final phone =
        (merchant['phone_number'] as String? ?? '').replaceFirst('+967', '0');

    final lat = (merchant['latitude'] as num?)?.toDouble();
    final lng = (merchant['longitude'] as num?)?.toDouble();
    final hasLocation = lat != null && lng != null;

    final Color statusColor = isBanned
        ? Colors.red
        : isActive
            ? AppColors.primary
            : Colors.orange;
    final String statusLabel = isBanned
        ? 'محظور'
        : isActive
            ? 'مفعّل'
            : 'معطّل';
    final IconData statusIcon = isBanned
        ? Icons.block_rounded
        : isActive
            ? Icons.check_circle_rounded
            : Icons.pause_circle_rounded;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: isBanned
              ? Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.store_rounded, color: statusColor, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.isNotEmpty ? store : name,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    if (store.isNotEmpty)
                      Text(
                        name,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.grey[500]),
                      ),
                    Row(
                      children: [
                        Icon(Icons.phone_outlined,
                            size: 12, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          phone,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: Colors.grey[500]),
                        ),
                      ],
                    ),
                    if (hasLocation)
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 12, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text(
                            '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: Colors.grey[400]),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 11, color: statusColor),
                    const SizedBox(width: 3),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── شارة إحصائية صغيرة ──
class StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const StatBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color),
        ),
        Text(
          label,
          style: TextStyle(
              fontFamily: 'Cairo', fontSize: 9, color: Colors.grey[400]),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════
// ورقة تفاصيل التاجر الكاملة
// ══════════════════════════════════════════

class _MerchantDetailsSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> merchant;
  final VoidCallback onRefresh;

  const _MerchantDetailsSheet({
    required this.merchant,
    required this.onRefresh,
  });

  @override
  ConsumerState<_MerchantDetailsSheet> createState() =>
      _MerchantDetailsSheetState();
}

class _MerchantDetailsSheetState extends ConsumerState<_MerchantDetailsSheet> {
  bool _isSendingNotif = false;
  bool _isBanning = false;
  bool _isChangingRole = false;
  late Future<List<Map<String, dynamic>>> _merchantOrdersFuture;

  @override
  void initState() {
    super.initState();
    _merchantOrdersFuture = ref
        .read(adminServiceProvider)
        .getMerchantOrders(widget.merchant['id'].toString());
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.merchant;
    final name = m['full_name'] ?? '';
    final store = m['store_name'] as String? ?? '';
    final phone =
        (m['phone_number'] as String? ?? '').replaceFirst('+967', '0');
    final isActive = m['is_active'] as bool? ?? false;
    final isBanned = m['is_banned'] as bool? ?? false;
    final lat = (m['latitude'] as num?)?.toDouble();
    final lng = (m['longitude'] as num?)?.toDouble();

    final rawCreatedAt = m['created_at'];
    final createdAt = rawCreatedAt is Timestamp
        ? rawCreatedAt.toDate()
        : DateTime.tryParse(rawCreatedAt?.toString() ?? '');

    final statsAsync = ref.watch(_merchantStatsProvider(m['id'].toString()));

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8F9FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // ── المقبض ──
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 0),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  // ── بطاقة هوية التاجر ──
                  _buildIdentityCard(name, store, phone, isActive, isBanned,
                      lat, lng, createdAt),

                  const SizedBox(height: 12),

                  // ── بطاقة الإحصائيات ──
                  statsAsync.when(
                    loading: () => const _LoadingCard(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (stats) => _buildStatsCard(stats),
                  ),

                  const SizedBox(height: 12),

                  // ── آخر الطلبات ──
                  _buildOrdersSection(),

                  const SizedBox(height: 12),

                  // ── أزرار الإجراءات ──
                  _buildActions(isBanned, isActive),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // بطاقة هوية التاجر
  Widget _buildIdentityCard(
    String name,
    String store,
    String phone,
    bool isActive,
    bool isBanned,
    double? lat,
    double? lng,
    DateTime? createdAt,
  ) {
    final statusColor = isBanned
        ? Colors.red
        : isActive
            ? AppColors.primary
            : Colors.orange;
    final statusLabel = isBanned
        ? 'محظور'
        : isActive
            ? 'مفعّل'
            : 'معطّل';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.store_rounded, color: statusColor, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.isNotEmpty ? store : name,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    if (store.isNotEmpty)
                      Text(name,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: Colors.grey[500])),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // التفاصيل
          _InfoRow(
              icon: Icons.phone_rounded, label: 'رقم الهاتف', value: phone),
          if (lat != null && lng != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showMapSheet(context, lat, lng, name),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('الموقع الجغرافي',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10,
                                  color: Colors.grey)),
                          Text(
                            '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('🗺️ عرض',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (createdAt != null)
            _InfoRow(
              icon: Icons.calendar_today_rounded,
              label: 'تاريخ التسجيل',
              value: '${createdAt.day}/${createdAt.month}/${createdAt.year}',
            ),
        ],
      ),
    );
  }

// بطاقة الإحصائيات
  Widget _buildStatsCard(Map<String, dynamic> stats) {
    final revenue = (stats['total_revenue'] as num?)?.toDouble() ?? 0.0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إحصائيات التاجر',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _BigStatCard(
                  icon: Icons.receipt_long_rounded,
                  label: 'إجمالي الطلبات',
                  value: '${stats['total_orders']}',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BigStatCard(
                  icon: Icons.check_circle_rounded,
                  label: 'طلبات مُسلَّمة',
                  value: '${stats['delivered_orders']}',
                  color: const Color(0xFF1565C0),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BigStatCard(
                  icon: Icons.cancel_rounded,
                  label: 'طلبات ملغاة',
                  value: '${stats['cancelled_orders']}',
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // إجمالي الإيراد
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.08),
                  AppColors.primary.withValues(alpha: 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.monetization_on_rounded,
                    color: AppColors.primary, size: 28),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إجمالي الإيراد من هذا التاجر',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: Colors.grey[600]),
                    ),
                    Text(
                      '${revenue.toStringAsFixed(2)} ر.ي',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // آخر الطلبات
  Widget _buildOrdersSection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'آخر الطلبات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _merchantOrdersFuture,
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 2),
                  ),
                );
              }
              final orders = snap.data ?? [];
              if (orders.isEmpty) {
                return Text('لا توجد طلبات بعد',
                    style: TextStyle(
                        fontFamily: 'Cairo', color: Colors.grey[400]));
              }
              return Column(
                children: orders.map((o) => _OrderRow(order: o)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // أزرار الإجراءات
  Widget _buildActions(bool isBanned, bool isActive) {
    final currentRole = widget.merchant['role'] as String? ?? 'merchant';

    return Column(
      children: [
        // زر إرسال إشعار
        _ActionButton(
          icon: Icons.notifications_active_rounded,
          label: 'إرسال إشعار خاص',
          color: const Color(0xFF1565C0),
          isLoading: _isSendingNotif,
          onTap: () => _showSendNotificationDialog(),
        ),
        const SizedBox(height: 10),

        // ── زر تغيير الدور ──
        _ActionButton(
          icon: Icons.manage_accounts_rounded,
          label: _roleLabel(currentRole),
          color: const Color(0xFF6A1B9A),
          isLoading: _isChangingRole,
          onTap: () => _showRoleDialog(currentRole),
        ),
        const SizedBox(height: 10),

        // زر تفعيل/تعطيل
        if (!isBanned)
          _ActionButton(
            icon: isActive
                ? Icons.pause_circle_outline_rounded
                : Icons.play_circle_outline_rounded,
            label: isActive ? 'تعطيل الحساب' : 'تفعيل الحساب',
            color: isActive ? Colors.orange : AppColors.primary,
            onTap: () => _toggleStatus(isActive),
          ),

        if (!isBanned) const SizedBox(height: 10),

        // زر الحظر / رفع الحظر
        _ActionButton(
          icon: isBanned ? Icons.lock_open_rounded : Icons.block_rounded,
          label: isBanned ? 'رفع الحظر عن التاجر' : 'حظر التاجر نهائياً',
          color: isBanned ? AppColors.primary : Colors.red,
          isLoading: _isBanning,
          onTap: () => isBanned ? _confirmUnban() : _confirmBan(),
        ),
      ],
    );
  }

  // ── تسمية الدور الحالي ──
  String _roleLabel(String role) => switch (role) {
        'driver' => '🚚 الدور الحالي: سائق — تغيير',
        'admin' => '👑 الدور الحالي: مدير — تغيير',
        'user' => '👤 الدور الحالي: مستخدم — تغيير',
        _ => '🏪 الدور الحالي: تاجر — تغيير',
      };

  // ── حوارات التأكيد ──

  void _showSendNotificationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _MerchantNotificationDialog(
        merchantName: widget.merchant['full_name'] ?? '',
        onSend: (title, body) async {
          setState(() => _isSendingNotif = true);
          final messenger = ScaffoldMessenger.of(context);
          try {
            await ref.read(adminServiceProvider).sendNotificationToMerchant(
                  merchantId: widget.merchant['id'].toString(),
                  title: title,
                  body: body,
                );
            if (mounted) {
              _showSnackSafe(
                  messenger, '✅ تم إرسال الإشعار بنجاح', AppColors.primary);
            }
          } catch (_) {
            if (mounted) {
              _showSnackSafe(messenger, '❌ فشل إرسال الإشعار', Colors.red);
            }
          } finally {
            if (mounted) setState(() => _isSendingNotif = false);
          }
        },
      ),
    );
  }

  Future<void> _toggleStatus(bool isActive) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminServiceProvider).toggleMerchantStatus(
            widget.merchant['id'].toString(),
            !isActive,
          );
      widget.onRefresh();
      if (mounted) Navigator.pop(context);
      _showSnackSafe(
        messenger,
        isActive ? '⏸ تم تعطيل حساب التاجر' : '✅ تم تفعيل حساب التاجر',
        isActive ? Colors.orange : AppColors.primary,
      );
    } catch (_) {
      if (mounted) _showSnackSafe(messenger, '❌ فشلت العملية', Colors.red);
    }
  }

  void _confirmBan() {
    final name = widget.merchant['full_name'] ?? 'هذا التاجر';
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '⚠️ تأكيد الحظر',
          style: TextStyle(
              fontFamily: 'Cairo', fontWeight: FontWeight.w800, fontSize: 16),
          textAlign: TextAlign.right,
        ),
        content: Text(
          'هل أنت متأكد من حظر "$name" نهائياً من التطبيق؟\n\nلن يتمكن من الدخول بعد ذلك.',
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('حظر نهائياً',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && mounted) {
        _banMerchant();
      }
    });
  }

  void _confirmUnban() {
    final name = widget.merchant['full_name'] ?? 'هذا التاجر';
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'رفع الحظر',
          style: TextStyle(
              fontFamily: 'Cairo', fontWeight: FontWeight.w800, fontSize: 16),
          textAlign: TextAlign.right,
        ),
        content: Text(
          'هل تريد رفع الحظر عن "$name" وإعادة تفعيل حسابه؟',
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('رفع الحظر',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && mounted) {
        _unbanMerchant();
      }
    });
  }

  Future<void> _banMerchant() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isBanning = true);
    try {
      await ref
          .read(adminServiceProvider)
          .banMerchant(widget.merchant['id'].toString());
      widget.onRefresh();
      if (mounted) Navigator.pop(context);
      _showSnackSafe(messenger, '🚫 تم حظر التاجر نهائياً', Colors.red);
    } catch (_) {
      if (mounted) _showSnackSafe(messenger, '❌ فشلت عملية الحظر', Colors.red);
    } finally {
      if (mounted) setState(() => _isBanning = false);
    }
  }

  Future<void> _unbanMerchant() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isBanning = true);
    try {
      await ref
          .read(adminServiceProvider)
          .unbanMerchant(widget.merchant['id'].toString());
      widget.onRefresh();
      if (mounted) Navigator.pop(context);
      _showSnackSafe(messenger, '✅ تم رفع الحظر عن التاجر', AppColors.primary);
    } catch (_) {
      if (mounted) _showSnackSafe(messenger, '❌ فشلت العملية', Colors.red);
    } finally {
      if (mounted) setState(() => _isBanning = false);
    }
  }

  void _showRoleDialog(String currentRole) {
    final roles = [
      {'value': 'merchant', 'label': 'تاجر 🏪', 'color': AppColors.primary},
      {'value': 'driver', 'label': 'سائق 🚚', 'color': Colors.blue},
      {'value': 'admin', 'label': 'مدير 👑', 'color': const Color(0xFF6A1B9A)},
    ];

    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 18),
            const Text(
              'تغيير دور المستخدم',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1A1A2E)),
            ),
            const SizedBox(height: 6),
            Text(
              widget.merchant['full_name'] ?? '',
              style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ...roles.map((r) {
              final isSelected = r['value'] == currentRole;
              final color = r['color'] as Color;
              return GestureDetector(
                onTap: isSelected
                    ? null
                    : () {
                        Navigator.pop(ctx, r['value'] as String);
                      },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.1)
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? color : Colors.grey[200]!,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(r['label'] as String,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isSelected
                                  ? color
                                  : const Color(0xFF1A1A2E))),
                      const Spacer(),
                      if (isSelected)
                        Icon(Icons.check_circle_rounded,
                            color: color, size: 20),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    ).then((newRole) {
      if (newRole != null && mounted) {
        _changeRole(newRole);
      }
    });
  }

  Future<void> _changeRole(String newRole) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isChangingRole = true);
    try {
      await ref
          .read(adminServiceProvider)
          .changeUserRole(widget.merchant['id'].toString(), newRole);

      widget.onRefresh();

      final roleAr = switch (newRole) {
        'driver' => 'سائق',
        'user' => 'مستخدم عادي',
        'admin' => 'مدير',
        _ => 'تاجر',
      };

      if (mounted) {
        _showSnackSafe(
            messenger, '✅ تم تغيير الدور إلى $roleAr', const Color(0xFF6A1B9A));
        widget.merchant['role'] = newRole;
        setState(() {});
      }
    } catch (_) {
      if (mounted) _showSnackSafe(messenger, '❌ فشل تغيير الدور', Colors.red);
    } finally {
      if (mounted) setState(() => _isChangingRole = false);
    }
  }

  void _showSnackSafe(
      ScaffoldMessengerState messenger, String msg, Color color) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showMapSheet(
    BuildContext context,
    double lat,
    double lng,
    String name,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MerchantMapSheet(
        lat: lat,
        lng: lng,
        merchantName: name,
      ),
    );
  }
}
// ══════════════════════════════════════════
// Widgets مساعدة
// ══════════════════════════════════════════

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
                fontFamily: 'Cairo', fontSize: 13, color: Colors.grey[500]),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _BigStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
                fontFamily: 'Cairo', fontSize: 10, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final Map<String, dynamic> order;
  const _OrderRow({required this.order});

  String _statusLabel(String s) => switch (s) {
        'pending' => 'معلق',
        'confirmed' || 'accepted' => 'مقبول',
        'preparing' => 'قيد التحضير',
        'shipped' || 'on_the_way' => 'في الطريق',
        'delivered' => 'مُسلَّم',
        'cancelled' => 'ملغي',
        'rejected' => 'مرفوض',
        'returned' => 'مُرجَع',
        'return_requested' => 'طلب إرجاع',
        _ => s,
      };

  Color _statusColor(String s) => switch (s) {
        'pending' => const Color(0xFFF59E0B),
        'confirmed' || 'accepted' => const Color(0xFF3B82F6),
        'preparing' => const Color(0xFF3B82F6),
        'shipped' || 'on_the_way' => const Color(0xFF8B5CF6),
        'delivered' => AppColors.primary,
        'cancelled' || 'rejected' => const Color(0xFFEF4444),
        'returned' => const Color(0xFFEA580C),
        'return_requested' => const Color(0xFFF59E0B),
        _ => Colors.grey,
      };
  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? '';
    final total = (order['total'] as num?)?.toStringAsFixed(0) ?? '0';
    final color = _statusColor(status);

    final rawDate = order['created_at'];
    final date = rawDate is Timestamp
        ? rawDate.toDate()
        : DateTime.tryParse(rawDate?.toString() ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusLabel(status),
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
            ),
          ),
          Text(
            (order['is_returned'] == true || status == 'returned')
                ? '-$total ر.ي'
                : '$total ر.ي',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          if (date != null) ...[
            const SizedBox(width: 10),
            Text(
              '${date.day}/${date.month}/${date.year}',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 11, color: Colors.grey[400]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isLoading;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onTap,
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Icon(icon, size: 18, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child:
            CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
      ),
    );
  }
}

// ══════════════════════════════════════════
// شيت خريطة موقع التاجر
// ══════════════════════════════════════════
class _MerchantMapSheet extends StatelessWidget {
  final double lat;
  final double lng;
  final String merchantName;

  const _MerchantMapSheet({
    required this.lat,
    required this.lng,
    required this.merchantName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.storefront_rounded,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'موقع $merchantName',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: AppMap(
              initialLocation: LatLng(lat, lng),
              defaultCenter: LatLng(lat, lng),
              initialZoom: 16,
              title: 'موقع التاجر',
              markerLabel: merchantName,
              allowPick: false,
              showSearch: true,
              showCurrentLocation: true,
              style: AppMapStyle.terrain,
            ),
          ),
        ],
      ),
    );
  }
}

class _MerchantNotificationDialog extends StatefulWidget {
  final String merchantName;
  final Future<void> Function(String title, String body) onSend;

  const _MerchantNotificationDialog({
    required this.merchantName,
    required this.onSend,
  });

  @override
  State<_MerchantNotificationDialog> createState() =>
      _MerchantNotificationDialogState();
}

class _MerchantNotificationDialogState
    extends State<_MerchantNotificationDialog> {
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
      title: const Text(
        'إرسال إشعار للتاجر',
        style: TextStyle(
            fontFamily: 'Cairo', fontWeight: FontWeight.w800, fontSize: 16),
        textAlign: TextAlign.right,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              hintText: 'عنوان الإشعار',
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bodyCtrl,
            textDirection: TextDirection.rtl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'نص الرسالة',
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
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
          onPressed: () {
            final title = _titleCtrl.text.trim();
            final body = _bodyCtrl.text.trim();
            if (title.isEmpty || body.isEmpty) return;
            Navigator.pop(context);
            widget.onSend(title, body);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1565C0),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('إرسال',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
      ],
    );
  }
}
