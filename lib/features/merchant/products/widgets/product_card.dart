import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_adaptive_colors.dart';
import '../../../../core/services/image_precache_service.dart';
import '../services/products_service.dart';
import '../../cart/providers/cart_provider.dart';
import 'package:sala/core/models/product_unit.dart';
import 'product_details_sheet.dart';

class ProductCard extends ConsumerStatefulWidget {
  final ProductModel product;
  const ProductCard({super.key, required this.product});

  @override
  ConsumerState<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<ProductCard> {
  late PageController _pageController;
  int _currentIndex = 0;
  int _qty = 1;
  static const int _kInitialPage = 1000;

  List<ProductUnit> get _units {
    if (widget.product.units.isNotEmpty) {
      return widget.product.units;
    }
    return [
      ProductUnit(
        label: 'كرتون',
        qty: widget.product.itemsPerCarton ?? 1,
        price: widget.product.price,
        imageUrl: widget.product.imageUrl,
        sizeMl: widget.product.sizeMl,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    final units = _units;
    final initialPage =
        units.length > 1 ? _kInitialPage - (_kInitialPage % units.length) : 0;
    _pageController = PageController(initialPage: initialPage);
  }

  @override
  void didUpdateWidget(covariant ProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id ||
        oldWidget.product.units.length != widget.product.units.length) {
      final units = _units;
      setState(() {
        _currentIndex = 0;
        _qty = 1;
      });
      if (_pageController.hasClients) {
        final initialPage = units.length > 1
            ? _kInitialPage - (_kInitialPage % units.length)
            : 0;
        _pageController.jumpToPage(initialPage);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _showManualQtyDialog(ProductUnit unit) async {
    HapticFeedback.mediumImpact();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => _ManualQtyDialog(
        initialQty: _qty,
        unitLabel: unit.label,
      ),
    );

    if (result != null && result > 0 && mounted) {
      setState(() => _qty = result);
    }
  }

  void _addToCart(ProductUnit unit) {
    HapticFeedback.mediumImpact();

    ref.read(cartProvider.notifier).addItem(
          widget.product,
          _qty,
          unit: unit,
        );

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ تمت إضافة $_qty ${unit.label} من (${widget.product.name}) إلى السلة',
          style: const TextStyle(fontFamily: 'Cairo'),
          textAlign: TextAlign.right,
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final units = _units;
    final hasMultipleUnits = units.length > 1;
    final currentUnit = units[_currentIndex % units.length];

    final cartKey = (currentUnit.label.trim() == 'كرتون')
        ? widget.product.id
        : '${widget.product.id}__${currentUnit.label.trim()}';

    final cartQty = ref.watch(
      cartProvider.select((c) => c[cartKey]?.quantity ?? 0),
    );

    final total = currentUnit.price * _qty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── ترويسة البطاقة: اسم المنتج ──
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.product.name,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasMultipleUnits) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.swipe_rounded,
                            size: 12, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          currentUnit.label,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 10),

            // ── منطقة التمرير اللانهائي بين الكميات ──
            SizedBox(
              height: 86,
              child: PageView.builder(
                controller: _pageController,
                physics: hasMultipleUnits
                    ? const BouncingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _currentIndex =
                        (index % units.length + units.length) % units.length;
                    _qty = 1;
                  });
                },
                itemBuilder: (context, index) {
                  final safeIndex =
                      (index % units.length + units.length) % units.length;
                  final unit = units[safeIndex];
                  final unitImageUrl = (unit.imageUrl != null &&
                          unit.imageUrl!.trim().isNotEmpty)
                      ? unit.imageUrl!.trim()
                      : widget.product.imageUrl;

                  return Row(
                    children: [
                      // 1. الإجمالي
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'الإجمالي',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: context.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${total.toStringAsFixed(0)} ر.ي',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: context.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 2. سعر الوحدة
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'سعر ${unit.label}',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: context.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${unit.price.toStringAsFixed(0)} ر.ي',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 10),

                      // 3. صورة المنتج/الوحدة (نقر الصورة يفتح التفاصيل)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => ProductDetailsSheet(
                              product: widget.product,
                              initialUnit: unit,
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 76,
                            height: 76,
                            color: context.bgInput,
                            child: unitImageUrl != null &&
                                    unitImageUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    cacheManager: ImagePrecacheService
                                        .instance.cacheManager,
                                    imageUrl: unitImageUrl,
                                    fit: BoxFit.contain,
                                    memCacheWidth: 200,
                                    placeholder: (_, __) => const Center(
                                      child: Icon(Icons.inventory_2_outlined,
                                          color: Colors.grey, size: 28),
                                    ),
                                    errorWidget: (_, __, ___) => const Center(
                                      child: Icon(Icons.inventory_2_outlined,
                                          color: AppColors.primary, size: 28),
                                    ),
                                  )
                                : const Center(
                                    child: Icon(Icons.inventory_2_outlined,
                                        color: AppColors.primary, size: 28),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // ── مؤشرات النقاط عند وجود أكثر من كمية ──
            if (hasMultipleUnits) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(units.length, (i) {
                  final isActive = i == (_currentIndex % units.length);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: isActive ? 16 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color:
                          isActive ? AppColors.primary : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ],

            const SizedBox(height: 12),

            // ── عداد الكمية (تم عكس أماكن + و - ودعم النقر المزدوج لإدخال الرقم) ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (cartQty > 0) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.shopping_cart_rounded,
                            size: 16, color: AppColors.primary),
                        Positioned(
                          top: -7,
                          right: -7,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                                color: Colors.red, shape: BoxShape.circle),
                            child: Text(
                              '$cartQty',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                ],

                // 1. زر النقصان (-) انتقل إلى اليمين
                GestureDetector(
                  onTap: () {
                    if (_qty > 1) {
                      HapticFeedback.lightImpact();
                      setState(() => _qty--);
                    }
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: context.bgInput,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Icon(
                      Icons.remove_rounded,
                      color:
                          _qty > 1 ? context.textPrimary : Colors.grey.shade400,
                      size: 20,
                    ),
                  ),
                ),

                // 2. رقم الكمية (نقر مزدوج لفتح لوحة المفاتيح وكتابة الرقم يدوياً)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => _showManualQtyDialog(currentUnit),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Text(
                      '$_qty',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                ),

                // 3. زر الزيادة (+) انتقل إلى اليسار
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _qty++);
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── زر إضافة للسلة ──
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () => _addToCart(currentUnit),
                icon: const Icon(Icons.shopping_cart_outlined, size: 19),
                label: Text(
                  'إضافة للسلة (${currentUnit.label})',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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

// ══════════════════════════════════════════════════════
// نافذة إدخال الكمية اليدوية الآمنة والخالية من الأخطاء
// ══════════════════════════════════════════════════════
class _ManualQtyDialog extends StatefulWidget {
  final int initialQty;
  final String unitLabel;

  const _ManualQtyDialog({
    required this.initialQty,
    required this.unitLabel,
  });

  @override
  State<_ManualQtyDialog> createState() => _ManualQtyDialogState();
}

class _ManualQtyDialogState extends State<_ManualQtyDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialQty}');
  }

  @override
  void dispose() {
    _controller.dispose(); // يُحذف بأمان تام فقط بعد إغلاق النافذة بالكامل
    super.dispose();
  }

  void _submit() {
    final val = int.tryParse(_controller.text.trim());
    FocusScope.of(context).unfocus(); // إغلاق الكيبورد بسلاسة قبل الخروج
    Navigator.pop(context, (val != null && val > 0) ? val : null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: context.bgCard,
      title: Text(
        'تحديد الكمية (${widget.unitLabel})',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: context.textPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'أدخل عدد الكراتين / الحبات المطلوبة مباشرة:',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: context.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: context.bgInput,
              hintText: '1',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.pop(context);
          },
          child: const Text(
            'إلغاء',
            style: TextStyle(fontFamily: 'Cairo', color: Colors.grey),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _submit,
          child: const Text(
            'تأكيد',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
