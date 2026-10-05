import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../providers/cart_provider.dart';
import '../screens/cart_screen.dart';

class CartFloatingButton extends ConsumerStatefulWidget {
  const CartFloatingButton({super.key});

  @override
  ConsumerState<CartFloatingButton> createState() => _CartFloatingButtonState();
}

class _CartFloatingButtonState extends ConsumerState<CartFloatingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  int _prevCount = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _pulse = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(cartCountProvider);
    final total = ref.watch(cartTotalProvider);

    // نبض عند إضافة منتج جديد
    if (count > _prevCount) {
      _prevCount = count;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pulseCtrl.forward().then((_) => _pulseCtrl.reverse());
      });
    } else {
      _prevCount = count;
    }

    if (count == 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CartScreen(),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.shopping_cart_rounded,
                    color: Colors.white, size: 24),
                Positioned(
                  top: -6,
                  right: -6,
                  child: ScaleTransition(
                    scale: _pulse,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            const Text('السلة',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const Spacer(),
            Text('${total.toStringAsFixed(0)} ر.ي',
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }
}
