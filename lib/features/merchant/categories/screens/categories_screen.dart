import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../services/categories_service.dart';
import '../widgets/category_card.dart';
import '../../widgets/categories_skeleton.dart';
import '../../brands/screens/brands_screen.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import '../../../../core/services/catalog_service.dart'; // 🚀 ربط نظام الكاش

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 🚀 توجيه الاستعلام عبر الـ RAM Cache الفوري وتقليل فواتير فايربيز
    final categoriesAsyncRaw = ref.watch(categoriesProvider);
    final categoriesAsync = categoriesAsyncRaw.whenData((list) =>
        list.map((m) => CategoryModel.fromMap(m)).toList()
          ..sort((a, b) => (a.sortOrder ?? 999).compareTo(b.sortOrder ?? 999)));

    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(categoriesProvider);
            await ref.read(categoriesProvider.future);
          },
          child: CustomScrollView(
            slivers: [
              // ══ Header ══
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Row(
                    children: [
                      Text(
                        'الأصناف',
                        style: AppTextStyles.headlineMedium,
                      ),
                      const Spacer(),
                      categoriesAsync.when(
                        data: (cats) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
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

              // ══ Grid ══
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: categoriesAsync.when(
                  loading: () => const SliverToBoxAdapter(
                    child: CategoriesSkeleton(),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                    child: _ErrorState(
                      onRetry: () => ref.invalidate(categoriesProvider),
                    ),
                  ),
                  data: (categories) {
                    if (categories.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: _EmptyState(),
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
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
          Icon(Icons.category_outlined, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'لا توجد أصناف بعد',
            style: AppTextStyles.titleMedium.copyWith(color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          Text(
            'سيتم إضافة الأصناف من قِبل المدير',
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
          Icon(Icons.wifi_off_rounded, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'تعذّر تحميل الأصناف',
            style: AppTextStyles.titleMedium.copyWith(color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            label: Text(
              'إعادة المحاولة',
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
