import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/app_radius.dart';
import '../services/brands_service.dart';
import '../widgets/brand_card.dart';
import '../widgets/brands_skeleton.dart';
import '../../products/screens/products_screen.dart';
import 'package:sala/core/services/image_precache_service.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

class BrandsScreen extends ConsumerWidget {
  final String categoryId;
  final String categoryName;

  const BrandsScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<List<BrandModel>>>(
      brandsStreamProvider(categoryId),
      (previous, next) {
        next.whenData((brands) {
          if (brands.isNotEmpty) {
            ImagePrecacheService.instance.prewarmBrands(
              brands.map((b) => {'logo_url': b.logoUrl}).toList(),
            );
          }
        });
      },
    );

    final brandsAsync = ref.watch(brandsStreamProvider(categoryId));

    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async =>
              ref.invalidate(brandsStreamProvider(categoryId)),
          child: CustomScrollView(
            slivers: [
              // ══ AppBar مخصص ══
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
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
                          onTap: () => Navigator.of(context).pop(),
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              categoryName,
                              style: AppTextStyles.headlineSmall.copyWith(
                                fontWeight: FontWeight.w800,
                                color: context
                                    .textPrimary, // 👈 تم إضافة اللون المتكيف هنا
                              ),
                            ),
                            brandsAsync.when(
                              data: (brands) => Text(
                                '${brands.length} شركة متاحة',
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
                      // عداد الشركات
                      brandsAsync.when(
                        data: (brands) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: const BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: AppRadius.circleAll,
                          ),
                          child: Text(
                            '${brands.length}',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: context.bgCard,
                              fontWeight: FontWeight.w700,
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

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ══ Grid الشركات ══
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: brandsAsync.when(
                  loading: () => const SliverToBoxAdapter(
                    child: BrandsSkeleton(),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                    child: _ErrorState(
                      onRetry: () =>
                          ref.invalidate(brandsStreamProvider(categoryId)),
                    ),
                  ),
                  data: (brands) {
                    if (brands.isEmpty) {
                      return const SliverToBoxAdapter(child: _EmptyState());
                    }

                    return SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final brand = brands[index];
                          return BrandCard(
                            brand: brand,
                            onTap: () {
                              // 🚀 استخدام MaterialPageRoute ليسمح بتفعيل السحب من اليمين للرجوع
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ProductsScreen(
                                    brandId: brand.id,
                                    brandName: brand.name,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        childCount: brands.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 0.78,
                      ),
                    );
                  },
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 30)),
            ],
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
              Icons.storefront_outlined,
              size: 52,
              color: AppColors.primary.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'لا توجد شركات في هذا الصنف',
            style: AppTextStyles.titleMedium.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'سيتم إضافة الشركات قريباً',
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
            'تعذّر تحميل الشركات',
            style: AppTextStyles.titleMedium.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}
