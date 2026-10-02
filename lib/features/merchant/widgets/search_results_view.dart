// ==================================================
// FILE: lib/features/merchant/widgets/search_results_view.dart
// ==================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/app_radius.dart';
import '../../../../core/services/image_precache_service.dart';
import '../search/services/search_service.dart';
import '../brands/screens/brands_screen.dart';
import '../products/screens/products_screen.dart';
import '../products/widgets/product_details_sheet.dart';
import '../products/services/products_service.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

class SearchResultsView extends ConsumerWidget {
  final String query;
  const SearchResultsView({super.key, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) return const SizedBox.shrink();

    final resultsAsync = ref.watch(searchResultsProvider(query));

    return resultsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2.5,
          ),
        ),
      ),
      error: (e, _) => const _EmptyState(message: 'حدث خطأ، تحقق من اتصالك'),
      data: (result) {
        if (result.isEmpty) {
          return _EmptyState(message: 'لا توجد نتائج لـ "$query"');
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ══ 1. المنتجات أولاً ══
            if (result.products.isNotEmpty) ...[
              _SectionHeader(
                title: 'المنتجات (${result.products.length})',
                icon: Icons.inventory_2_rounded,
                color: AppColors.primary,
              ),
              ...result.products.map((p) => _ResultTile(
                    title: p['name'] ?? '',
                    query: query,
                    subtitle: p['price'] != null ? '${p['price']} ر.ي' : null,
                    imageUrl: p['image_url'] as String?,
                    fallbackIcon: Icons.shopping_bag_rounded,
                    iconColor: AppColors.primary,
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => ProductDetailsSheet(
                          product: ProductModel.fromMap({
                            'id': p['id']?.toString() ?? '',
                            ...p,
                          }),
                        ),
                      );
                    },
                  )),
              const _Divider(),
            ],

            // ══ 2. الشركات ثانياً ══
            if (result.brands.isNotEmpty) ...[
              _SectionHeader(
                title: 'الشركات (${result.brands.length})',
                icon: Icons.business_rounded,
                color: const Color(0xFF3B82F6),
              ),
              ...result.brands.map((b) => _ResultTile(
                    title: b['name'] ?? '',
                    query: query,
                    subtitle: 'عرض منتجات الشركة',
                    imageUrl: b['logo_url'] as String?,
                    fallbackIcon: Icons.storefront_rounded,
                    iconColor: const Color(0xFF3B82F6),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductsScreen(
                            brandId: b['id'].toString(),
                            brandName: b['name'] ?? '',
                          ),
                        ),
                      );
                    },
                  )),
              const _Divider(),
            ],

            // ══ 3. الأصناف ثالثاً ══
            if (result.categories.isNotEmpty) ...[
              _SectionHeader(
                title: 'الأصناف (${result.categories.length})',
                icon: Icons.category_rounded,
                color: Colors.orange,
              ),
              ...result.categories.map((c) => _ResultTile(
                    title: c['name'] ?? '',
                    query: query,
                    subtitle: 'تصفح شركات هذا الصنف',
                    imageUrl: c['image_url'] as String?,
                    fallbackIcon: Icons.grid_view_rounded,
                    iconColor: Colors.orange,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BrandsScreen(
                            categoryId: c['id'].toString(),
                            categoryName: c['name'] ?? '',
                          ),
                        ),
                      );
                    },
                  )),
            ],
          ],
        );
      },
    );
  }
}

// ══ عنصر النتيجة مع دعم صور الأوفلاين ══
class _ResultTile extends StatelessWidget {
  final String title;
  final String query;
  final String? subtitle;
  final String? imageUrl;
  final IconData fallbackIcon;
  final Color iconColor;
  final VoidCallback onTap;

  const _ResultTile({
    required this.title,
    required this.query,
    this.subtitle,
    this.imageUrl,
    required this.fallbackIcon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              // ── الصورة مع مدير الكاش الداعم للأوفلاين ──
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 48,
                  height: 48,
                  color: context.bgInput,
                  child: imageUrl != null && imageUrl!.trim().isNotEmpty
                      ? CachedNetworkImage(
                          cacheManager: ImagePrecacheService.instance
                              .cacheManager, // 👈 الحفظ في القرص للأوفلاين
                          imageUrl: imageUrl!.trim(),
                          fit: BoxFit.cover,
                          memCacheWidth: 120,
                          memCacheHeight: 120,
                          placeholder: (_, __) => _FallbackIcon(
                              icon: fallbackIcon, color: iconColor),
                          errorWidget: (_, __, ___) => _FallbackIcon(
                              icon: fallbackIcon, color: iconColor),
                        )
                      : _FallbackIcon(icon: fallbackIcon, color: iconColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HighlightedText(text: title, query: query),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: context.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 13,
                color: context.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _FallbackIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(color: context.borderColor, thickness: 1),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  const _HighlightedText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(
        text,
        style: AppTextStyles.bodyMedium.copyWith(
          color: context.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w900,
        ),
      ));
      start = index + query.length;
    }

    return RichText(
      text: TextSpan(
        style: AppTextStyles.bodyMedium.copyWith(
          color: context.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        children: spans,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.search_off_rounded,
                size: 56, color: context.iconSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
