import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radius.dart';
import '../../../../core/services/image_precache_service.dart';
import '../services/categories_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

class CategoryCard extends StatelessWidget {
  final CategoryModel category;
  final VoidCallback onTap;

  const CategoryCard({
    super.key,
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: context.borderColor),
          boxShadow: [
            BoxShadow(
              color: context.shadowColor,
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── صورة الصنف ──
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: context.bgInput,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child:
                      category.imageUrl != null && category.imageUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              cacheManager:
                                  ImagePrecacheService.instance.cacheManager,
                              imageUrl: category.imageUrl!,
                              fit: BoxFit.contain,
                              memCacheWidth: 160,
                              memCacheHeight: 160,
                              errorWidget: (_, __, ___) =>
                                  const _DefaultCategoryIcon(),
                              placeholder: (_, __) => _SkeletonBox(),
                            )
                          : const _DefaultCategoryIcon(),
                ),
              ),
            ),

            // ── خط فاصل أخضر رفيع ──
            Container(
              height: 2,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1B8E3D), Color(0xFF24B352)],
                ),
              ),
            ),

            // ── اسم الصنف ──
            Expanded(
              flex: 1,
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  category.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DefaultCategoryIcon extends StatelessWidget {
  const _DefaultCategoryIcon();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.category_rounded,
        color: AppColors.primary.withValues(alpha: 0.3),
        size: 40,
      ),
    );
  }
}

class _SkeletonBox extends StatefulWidget {
  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
