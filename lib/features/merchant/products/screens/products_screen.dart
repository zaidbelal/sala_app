import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radius.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../cart/providers/cart_provider.dart';
import '../../cart/screens/cart_screen.dart';
import '../widgets/product_card.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import 'package:sala/features/merchant/products/services/products_service.dart';

class ProductsScreen extends ConsumerWidget {
  final String brandId;
  final String brandName;

  const ProductsScreen({
    super.key,
    required this.brandId,
    required this.brandName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // جلب منتجات الشركة الصحيحة عبر المعرّف الخاص بها brand_id
    final productsAsync = ref.watch(productsStreamProvider(brandId));

    final cart = ref.watch(cartProvider);
    final cartCount = cart.values.fold(0, (s, i) => s + i.quantity);
    final cartTotal = cart.values.fold(0.0, (s, i) => s + i.total);

    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(productsStreamProvider(brandId));
          },
          child: CustomScrollView(
            // 🚀 تفعيل التمرير المرن والكامل حتى في حالة عدد المنتجات القليل
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              // ══ Header ══
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 14, 16, 0),
                  child: Row(
                    children: [
                      // زر الرجوع
                      Material(
                        color: context.bgCard,
                        shape: const CircleBorder(),
                        elevation: 2,
                        shadowColor: Colors.black12,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).pop();
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 18,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // اسم الشركة وعدد المنتجات
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              brandName,
                              style: AppTextStyles.headlineSmall.copyWith(
                                fontWeight: FontWeight.w800,
                                color: context.textPrimary,
                              ),
                            ),
                            productsAsync.when(
                              data: (p) => Text(
                                '${p.length} منتج متاح',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.grey[500],
                                ),
                              ),
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),

                      // أيقونة السلة مع العداد
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CartScreen(),
                            ),
                          );
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
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
                                top: -5,
                                left: -5,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(
                                          scale: anim, child: child),
                                  child: Container(
                                    key: ValueKey(cartCount),
                                    padding: const EdgeInsets.all(5),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '$cartCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ══ شريط السلة المتحرك ══
              SliverToBoxAdapter(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  child: cartCount > 0
                      ? Container(
                          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: AppRadius.lgAll,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.primary.withValues(alpha: 0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.shopping_cart_checkout_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Text(
                                  key: ValueKey(cartCount),
                                  '$cartCount كرتون في السلة',
                                  style: AppTextStyles.labelMedium.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Text(
                                  key: ValueKey(cartTotal),
                                  '${cartTotal.toStringAsFixed(0)} ر.ي',
                                  style: AppTextStyles.labelLarge.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.mediumImpact();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const CartScreen(),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    borderRadius: AppRadius.circleAll,
                                  ),
                                  child: Text(
                                    'تأكيد ←',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // ══ قائمة المنتجات ══
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: productsAsync.when(
                  loading: () => const SliverToBoxAdapter(
                    child: _ProductsSkeleton(),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                    child: _ErrorState(
                      onRetry: () {
                        ref.invalidate(
                          productsStreamProvider(brandId),
                        );
                      },
                    ),
                  ),
                  data: (products) {
                    if (products.isEmpty) {
                      return const SliverToBoxAdapter(child: _EmptyState());
                    }
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: RepaintBoundary(
                            child: ProductCard(
                              key: ValueKey('product_${products[index].id}'),
                              product: products[index],
                            ),
                          ),
                        ),
                        childCount: products.length,
                        addRepaintBoundaries: true,
                        addSemanticIndexes: false,
                      ),
                    );
                  },
                ),
              ),
// 🚀 مسافة أمان سفلية كافية لرفع آخر منتج وزر السلة بالكامل فوق شريط أندرويد
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════
// Skeleton Loading
// ══════════════════════════════════════════
class _ProductsSkeleton extends StatefulWidget {
  const _ProductsSkeleton();

  @override
  State<_ProductsSkeleton> createState() => _ProductsSkeletonState();
}

class _ProductsSkeletonState extends State<_ProductsSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.35, end: 0.9).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        4,
        (i) => FadeTransition(
          opacity: _anim,
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            height: 130,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: AppRadius.xlAll,
            ),
            child: Row(
              children: [
                Container(
                  width: 110,
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: AppRadius.lgAll,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            height: 14,
                            width: 120,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: AppRadius.smAll,
                            )),
                        const SizedBox(height: 8),
                        Container(
                            height: 10,
                            width: 80,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: AppRadius.smAll,
                            )),
                        const Spacer(),
                        Container(
                            height: 34,
                            width: 160,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: AppRadius.mdAll,
                            )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 52,
              color: AppColors.primary.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'لا توجد منتجات بعد',
            style: AppTextStyles.titleMedium.copyWith(
              color: Colors.grey[600],
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'سيتم إضافة المنتجات من قِبل المدير',
            style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.wifi_off_rounded,
              size: 52,
              color: Colors.red.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'تعذّر تحميل المنتجات',
            style: AppTextStyles.titleMedium.copyWith(
              color: Colors.grey[600],
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'تحقق من اتصالك بالإنترنت',
            style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[400]),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
              shape: const StadiumBorder(),
              elevation: 0,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text(
              'إعادة المحاولة',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
