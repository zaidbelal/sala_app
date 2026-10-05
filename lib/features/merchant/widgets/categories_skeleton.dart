import 'package:flutter/material.dart';
import '../../../../core/constants/app_radius.dart';

class CategoriesSkeleton extends StatefulWidget {
  final int itemCount;

  const CategoriesSkeleton({
    super.key,
    this.itemCount = 9,
  });

  @override
  State<CategoriesSkeleton> createState() => _CategoriesSkeletonState();
}

class _CategoriesSkeletonState extends State<CategoriesSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: widget.itemCount,
          itemBuilder: (_, index) {
            // تأخير متتالي لكل بطاقة
            final delay = (index % 3) * 0.1;
            final opacity = (_animation.value - delay).clamp(0.2, 1.0);

            return Opacity(
              opacity: opacity,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppRadius.lgAll,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // دائرة الأيقونة
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // سطر النص
                    Container(
                      width: 50,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 5),
                    // سطر نص أصغر
                    Container(
                      width: 32,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
