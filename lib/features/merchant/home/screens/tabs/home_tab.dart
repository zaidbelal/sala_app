import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_radius.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../../../../core/services/catalog_service.dart';
import '../../../categories/services/categories_service.dart';
import '../../../categories/widgets/category_card.dart';
import '../../../cart/providers/cart_provider.dart';
import '../../../cart/screens/cart_screen.dart';
import '../../../brands/screens/brands_screen.dart';
import '../../widgets/merchant_search_bar.dart';
import '../../../widgets/search_results_view.dart';
import '../../../notifications/notifications_screen.dart';
import '../../../../../core/services/realtime_hub.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

final _searchQueryProvider = StateProvider<String>((ref) => '');

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  final _searchController = TextEditingController();
  bool _isSearching = false;
  Timer? _searchDebounce;
  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

// ══ تحديث الصفحة عند السحب أو الضغط على رسالة الإنترنت ══
  Future<void> _handleRefresh() async {
    ref.invalidate(categoriesProvider);
    try {
      await ref.read(categoriesProvider.notifier).refresh();
    } catch (_) {}
  }

  void _onSearchChanged(String value) {
    setState(() => _isSearching = value.isNotEmpty);
    ref.read(_searchQueryProvider.notifier).state = value;
  }

  void _clearAndExit() {
    _searchController.clear();
    ref.read(_searchQueryProvider.notifier).state = '';
    setState(() => _isSearching = false);
    FocusScope.of(context).unfocus();
  }

  void _openCart() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CartScreen()),
    );
  }

  void _openNotifications() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        )
        .then((_) {}); // unreadCountProvider يتحدث تلقائياً
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(_searchQueryProvider);
    final categoriesAsyncRaw = ref.watch(categoriesProvider);
    final categoriesAsync = categoriesAsyncRaw.whenData((list) =>
        list.map((m) => CategoryModel.fromMap(m)).toList()
          ..sort((a, b) => (a.sortOrder ?? 999).compareTo(b.sortOrder ?? 999)));
    // 🚀 select() يُعيد البناء فقط عند تغيّر هذه القيمة تحديداً — لا كامل الـ state
    final cartCount = ref.watch(cartCountProvider);
    final cartTotal = ref.watch(cartTotalProvider);
    final unreadCount = ref.watch(unreadCountProvider);

    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _handleRefresh,
              color: const Color(0xFF2ECC71),
              backgroundColor: context.bgHeader,
              strokeWidth: 2.5,
              displacement: 60,
              child: CustomScrollView(
                slivers: [
                  // ══ Header ══
                  SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: Row(
                          children: [
                            // ── الترحيب ──
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'مرحباً 👋',
                                    style:
                                        AppTextStyles.headlineMedium.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    'ماذا تريد اليوم؟',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ── زر الإشعارات ──
                            GestureDetector(
                              onTap: _openNotifications,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.07),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      unreadCount > 0
                                          ? Icons.notifications_rounded
                                          : Icons.notifications_outlined,
                                      color: unreadCount > 0
                                          ? AppColors.primary
                                          : Colors.grey[400],
                                      size: 22,
                                    ),
                                  ),
                                  if (unreadCount > 0)
                                    Positioned(
                                      top: -3,
                                      left: -3,
                                      child: AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        transitionBuilder: (child, anim) =>
                                            ScaleTransition(
                                                scale: anim, child: child),
                                        child: Container(
                                          key: ValueKey(unreadCount),
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                          constraints: const BoxConstraints(
                                              minWidth: 18, minHeight: 18),
                                          child: Text(
                                            unreadCount > 99
                                                ? '99+'
                                                : '$unreadCount',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 10),

                            // ── زر السلة ──
                            // 🚀 Consumer معزول للسلة فقط
                            Consumer(
                              builder: (_, ref, __) {
                                final cartCount = ref.watch(cartCountProvider);
                                return GestureDetector(
                                  onTap: _openCart,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.07),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.shopping_cart_rounded,
                                          color: AppColors.primary,
                                          size: 22,
                                        ),
                                      ),
                                      if (cartCount > 0)
                                        Positioned(
                                          top: -3,
                                          left: -3,
                                          child: AnimatedSwitcher(
                                            duration: const Duration(
                                                milliseconds: 300),
                                            transitionBuilder: (child, anim) =>
                                                ScaleTransition(
                                                    scale: anim, child: child),
                                            child: Container(
                                              key: ValueKey(cartCount),
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                              constraints: const BoxConstraints(
                                                  minWidth: 18, minHeight: 18),
                                              child: Text(
                                                '$cartCount',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w800,
                                                  fontFamily: 'Cairo',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ══ بطاقة السلة (تظهر عند وجود منتجات) ══
                  SliverToBoxAdapter(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      child: cartCount > 0
                          ? GestureDetector(
                              onTap: _openCart,
                              child: Container(
                                margin:
                                    const EdgeInsets.fromLTRB(20, 16, 20, 0),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  borderRadius: AppRadius.lgAll,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.3),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                        Icons.shopping_cart_checkout_rounded,
                                        color: Colors.white,
                                        size: 22),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          AnimatedSwitcher(
                                            duration: const Duration(
                                                milliseconds: 250),
                                            child: Text(
                                              key: ValueKey(cartCount),
                                              '$cartCount كرتون في السلة',
                                              style: AppTextStyles.labelMedium
                                                  .copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          AnimatedSwitcher(
                                            duration: const Duration(
                                                milliseconds: 250),
                                            child: Text(
                                              key: ValueKey(cartTotal),
                                              'الإجمالي: ${cartTotal.toStringAsFixed(0)} ر.ي',
                                              style: AppTextStyles.bodySmall
                                                  .copyWith(
                                                color: Colors.white
                                                    .withValues(alpha: 0.8),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 8),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: AppRadius.circleAll,
                                      ),
                                      child: Text(
                                        'إتمام الطلب',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),

                  // ══ خانة البحث ══
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: MerchantSearchBar(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        onClearAndExit: _clearAndExit,
                      ),
                    ),
                  ),

                  // ══ بانر الإشعارات إذا وُجدت ══
                  if (unreadCount > 0 && !_isSearching)
                    SliverToBoxAdapter(
                      child: GestureDetector(
                        onTap: _openNotifications,
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    AppColors.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.notifications_active_rounded,
                                size: 18, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'لديك $unreadCount إشعار جديد',
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary),
                              ),
                            ),
                            const Icon(Icons.arrow_back_ios_rounded,
                                size: 13, color: AppColors.primary),
                          ]),
                        ),
                      ),
                    ),

                  // ══ نتائج البحث أو الأصناف ══
                  if (_isSearching)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: SearchResultsView(query: searchQuery),
                      ),
                    )
                  else ...[
                    // عنوان الأصناف
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 20,
                              decoration: const BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                borderRadius: AppRadius.circleAll,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'الأصناف',
                              style: AppTextStyles.titleLarge.copyWith(
                                fontWeight: FontWeight.w800,
                                color: context.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            categoriesAsync.when(
                              data: (cats) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: AppRadius.circleAll,
                                ),
                                child: Text(
                                  '${cats.length} صنف',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // شبكة الأصناف
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: categoriesAsync.when(
                        loading: () => const SliverToBoxAdapter(
                          child: _CategoriesSkeleton(),
                        ),
                        error: (_, __) => SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text(
                                'تعذّر تحميل الأصناف',
                                style: AppTextStyles.bodyMedium
                                    .copyWith(color: Colors.grey[500]),
                              ),
                            ),
                          ),
                        ),
                        data: (categories) {
                          if (categories.isEmpty) {
                            return SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 60),
                                child: Column(
                                  children: [
                                    Icon(Icons.category_outlined,
                                        size: 64, color: Colors.grey[300]),
                                    const SizedBox(height: 12),
                                    Text(
                                      'لا توجد أصناف بعد',
                                      style: AppTextStyles.bodyMedium
                                          .copyWith(color: Colors.grey[400]),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return SliverGrid(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final cat = categories[index];
                                return CategoryCard(
                                  category: cat,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => BrandsScreen(
                                          categoryId: cat.id,
                                          categoryName: cat.name,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                              childCount: categories.length,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.85,
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════
// Skeleton تحميل الأصناف
// ══════════════════════════════════════════
class _CategoriesSkeleton extends StatefulWidget {
  const _CategoriesSkeleton();

  @override
  State<_CategoriesSkeleton> createState() => _CategoriesSkeletonState();
}

class _CategoriesSkeletonState extends State<_CategoriesSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: 9,
      itemBuilder: (_, __) => FadeTransition(
        opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_c),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: AppRadius.lgAll,
          ),
        ),
      ),
    );
  }
}
