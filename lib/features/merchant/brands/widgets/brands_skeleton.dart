import 'package:flutter/material.dart';
import '../../../../core/constants/app_radius.dart';

class BrandsSkeleton extends StatefulWidget {
  const BrandsSkeleton({super.key});

  @override
  State<BrandsSkeleton> createState() => _BrandsSkeletonState();
}

class _BrandsSkeletonState extends State<BrandsSkeleton>
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

  Widget _skeletonBox(double w, double h) => FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 0.9).animate(_c),
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: AppRadius.smAll,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.78,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => FadeTransition(
        opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_c),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: AppRadius.xlAll,
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: AppRadius.lgAll,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _skeletonBox(100, 12),
              const SizedBox(height: 6),
              _skeletonBox(70, 10),
              const SizedBox(height: 6),
              _skeletonBox(85, 10),
            ],
          ),
        ),
      ),
    );
  }
}
