import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radius.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/services/image_precache_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import '../services/brands_service.dart';

class BrandCard extends StatefulWidget {
  final BrandModel brand;
  final VoidCallback onTap;

  const BrandCard({super.key, required this.brand, required this.onTap});

  @override
  State<BrandCard> createState() => _BrandCardState();
}

class _BrandCardState extends State<BrandCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnim = _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _controller.reverse();
  void _onTapUp(_) => _controller.forward();
  void _onTapCancel() => _controller.forward();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: AppRadius.xlAll,
            border: Border.all(color: context.borderColor),
            boxShadow: [
              BoxShadow(
                color: context.shadowColor,
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ══ الشعار ══
              Expanded(
                flex: 5,
                child: Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.bgInput,
                    borderRadius: AppRadius.lgAll,
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.lgAll,
                    child: widget.brand.logoUrl != null &&
                            widget.brand.logoUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            cacheManager:
                                ImagePrecacheService.instance.cacheManager,
                            imageUrl: widget.brand.logoUrl!,
                            fit: BoxFit.contain,
                            memCacheWidth: 240,
                            memCacheHeight: 240,
                            errorWidget: (_, __, ___) => const _DefaultLogo(),
                            placeholder: (_, __) => const _LogoSkeleton(),
                          )
                        : const _DefaultLogo(),
                  ),
                ),
              ),

              // ══ المعلومات ══
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.brand.name,
                        style: AppTextStyles.labelLarge.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.brand.description != null &&
                          widget.brand.description!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          widget.brand.description!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: context.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      // ── شريط الانتقال ──
                      Row(
                        children: [
                          Text(
                            'عرض المنتجات',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 12,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DefaultLogo extends StatelessWidget {
  const _DefaultLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.06),
      child: const Icon(
        Icons.storefront_rounded,
        color: AppColors.primary,
        size: 48,
      ),
    );
  }
}

class _LogoSkeleton extends StatefulWidget {
  const _LogoSkeleton();

  @override
  State<_LogoSkeleton> createState() => _LogoSkeletonState();
}

class _LogoSkeletonState extends State<_LogoSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_c),
      child: Container(color: Colors.grey[200]),
    );
  }
}
