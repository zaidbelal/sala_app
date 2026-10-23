import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radius.dart';
import '../../cart/providers/cart_provider.dart';
import '../services/products_service.dart';
import 'package:sala/core/models/product_unit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/services/image_precache_service.dart';

class ProductDetailsSheet extends ConsumerStatefulWidget {
  final ProductModel product;
  final ProductUnit? initialUnit;
  const ProductDetailsSheet(
      {super.key, required this.product, this.initialUnit});

  @override
  ConsumerState<ProductDetailsSheet> createState() =>
      _ProductDetailsSheetState();
}

class _ProductDetailsSheetState extends ConsumerState<ProductDetailsSheet> {
  int _qty = 1;
  ProductUnit? _selectedUnit;

  @override
  void initState() {
    super.initState();
    _selectedUnit = widget.initialUnit ??
        (widget.product.units.isNotEmpty ? widget.product.units.first : null);
  }

  double get _currentPrice => _selectedUnit?.price ?? widget.product.price;

  String get _currentUnitLabel => _selectedUnit?.label ?? 'كرتون';

  String? get _currentImageUrl {
    if (_selectedUnit?.imageUrl != null &&
        _selectedUnit!.imageUrl!.trim().isNotEmpty) {
      return _selectedUnit!.imageUrl!.trim();
    }
    if (_selectedUnit == null || _selectedUnit!.label == 'كرتون') {
      return widget.product.imageUrl;
    }
    return null;
  }

  String get _currentSizeDisplay {
    if (widget.product.sizeText != null &&
        widget.product.sizeText!.trim().isNotEmpty) {
      return widget.product.sizeText!.trim();
    }
    final s = _selectedUnit?.sizeMl ?? widget.product.sizeMl;
    if (s != null) {
      return s % 1 == 0 ? '${s.toInt()} مل' : '$s مل';
    }
    return '—';
  }

  int? get _currentItems => _selectedUnit?.qty ?? widget.product.itemsPerCarton;

  DateTime? get _currentExpiry {
    if (_selectedUnit?.expiryDate != null) {
      return _selectedUnit!.expiryDate;
    }
    return DateTime.tryParse(widget.product.expiryDate ?? '');
  }

  DateTime? get _currentProduction {
    if (_selectedUnit?.productionDate != null) {
      return _selectedUnit!.productionDate;
    }
    return DateTime.tryParse(widget.product.productionDate ?? '');
  }

  bool get _hasImage {
    return _currentImageUrl != null && _currentImageUrl!.isNotEmpty;
  }

  String _formatDate(String? date) {
    if (date == null || date.isEmpty) return '—';
    try {
      final dt = DateTime.parse(date);
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return date.replaceAll('-', '/');
    }
  }

  bool get _isExpiringSoon {
    final expiry = _currentExpiry;
    if (expiry == null) return false;
    return expiry.isBefore(DateTime.now().add(const Duration(days: 30)));
  }

  void _addToCart() {
    HapticFeedback.mediumImpact();

    ref.read(cartProvider.notifier).addItem(
          widget.product,
          _qty,
          unit: _selectedUnit,
        );

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ تمت إضافة ${widget.product.name} - $_currentUnitLabel للسلة',
          style: const TextStyle(fontFamily: 'Cairo'),
          textAlign: TextAlign.right,
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final total = _currentPrice * _qty;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // مقبض السحب
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // صورة + اسم + سعر
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFB),
                          borderRadius: AppRadius.lgAll,
                          border: Border.all(color: Colors.grey.shade100),
                        ),
                        child: ClipRRect(
                          borderRadius: AppRadius.lgAll,
                          child: _hasImage
                              ? CachedNetworkImage(
                                  cacheManager: ImagePrecacheService
                                      .instance.cacheManager,
                                  imageUrl: _currentImageUrl!,
                                  fit: BoxFit.contain,
                                  placeholder: (_, __) => const Icon(
                                    Icons.shopping_bag_outlined,
                                    color: Colors.grey,
                                    size: 40,
                                  ),
                                  errorWidget: (_, __, ___) => const Icon(
                                    Icons.shopping_bag_outlined,
                                    color: AppColors.primary,
                                    size: 40,
                                  ),
                                )
                              : const Icon(
                                  Icons.shopping_bag_outlined,
                                  color: AppColors.primary,
                                  size: 40,
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── اسم المنتج واضح وبارز باللون الأسود دائماً ──
                            Text(
                              '${product.name} - $_currentUnitLabel',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            if (product.description != null &&
                                product.description!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                product.description!,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: AppRadius.circleAll,
                              ),
                              child: Text(
                                '${_currentPrice.toStringAsFixed(0)} ر.ي / $_currentUnitLabel',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── اختيار الوحدة ──
                  if (product.units.isNotEmpty) ...[
                    const Text(
                      'اختر الوحدة المطلوبة:',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: product.units.map((unit) {
                        final selected = _selectedUnit?.label == unit.label;

                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedUnit = unit;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  selected ? AppColors.primary : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary
                                    : Colors.grey.shade300,
                                width: selected ? 1.5 : 1,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      )
                                    ]
                                  : [],
                            ),
                            child: Text(
                              unit.label,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color:
                                    selected ? Colors.white : Colors.grey[700],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],
// ── بطاقة التفاصيل مع عرض الباركود بوضوح ──
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFB),
                      borderRadius: AppRadius.lgAll,
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        // عرض باركود المنتج أو الوحدة المحددة مع رسمة الباركود التخطيطية
                        if ((_selectedUnit?.barcode ?? product.barcode) !=
                                null &&
                            (_selectedUnit?.barcode ?? product.barcode)!
                                .isNotEmpty) ...[
                          _InfoTile(
                            icon: Icons.qr_code_2_rounded,
                            label: 'الباركود الدولي',
                            value: (_selectedUnit?.barcode ?? product.barcode)!,
                            valueColor: AppColors.primary,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: _BarcodeVisualBox(
                              barcode:
                                  (_selectedUnit?.barcode ?? product.barcode)!,
                            ),
                          ),
                          _divider(),
                        ],
                        _InfoTile(
                          icon: Icons.straighten_rounded,
                          label: 'الحجم',
                          value: _currentSizeDisplay,
                        ),
                        _divider(),
                        _InfoTile(
                          icon: Icons.inventory_2_rounded,
                          label: 'عدد الحبات / كرتون',
                          value: _currentItems != null
                              ? '$_currentItems حبة'
                              : '—',
                        ),
                        _divider(),
                        _InfoTile(
                          icon: Icons.layers_rounded,
                          label: 'المخزون',
                          value:
                              '${product.stock % 1 == 0 ? product.stock.toInt() : product.stock.toStringAsFixed(2)} كرتون',
                        ),
                        _divider(),
                        _InfoTile(
                          icon: Icons.calendar_month_rounded,
                          label: 'تاريخ الإنتاج',
                          value: _currentProduction == null
                              ? '—'
                              : _formatDate(
                                  _currentProduction!.toIso8601String(),
                                ),
                        ),
                        _divider(),
                        _InfoTile(
                          icon: Icons.event_busy_rounded,
                          label: 'تاريخ الانتهاء',
                          value: _currentExpiry == null
                              ? '—'
                              : _formatDate(
                                  _currentExpiry!.toIso8601String(),
                                ),
                          valueColor: _isExpiringSoon ? Colors.red : null,
                          badge: _isExpiringSoon ? 'ينتهي قريباً' : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // اختيار الكمية
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _QtyBtn(
                        icon: Icons.remove_rounded,
                        onTap: () {
                          if (_qty > 1) setState(() => _qty--);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) =>
                              ScaleTransition(scale: anim, child: child),
                          child: Text(
                            '$_qty',
                            key: ValueKey(_qty),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                        ),
                      ),
                      _QtyBtn(
                        icon: Icons.add_rounded,
                        onTap: () => setState(() => _qty++),
                        filled: true,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // زر الإضافة للسلة
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, MediaQuery.of(context).padding.bottom + 16),
            child: GestureDetector(
              onTap: _addToCart,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: AppRadius.lgAll,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.shopping_cart_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        key: ValueKey(_qty),
                        total > 0
                            ? 'إضافة $_qty $_currentUnitLabel — ${total.toStringAsFixed(0)} ر.ي'
                            : 'إضافة للسلة',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.grey.shade200);
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final String? badge;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF555555),
              )),
          const Spacer(),
          if (badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(badge!,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  )),
            ),
            const SizedBox(width: 8),
          ],
          Text(value,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: valueColor ?? const Color(0xFF1A1A2E),
              )),
        ],
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  const _QtyBtn({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: filled
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.1),
          borderRadius: AppRadius.mdAll,
        ),
        child: Icon(
          icon,
          size: 22,
          color: filled ? Colors.white : AppColors.primary,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// مجسم رسمة الباركود الحقيقي التخطيطي ليظهر تحت الرقم
// ══════════════════════════════════════════════════════════════
class _BarcodeVisualBox extends StatelessWidget {
  final String barcode;
  const _BarcodeVisualBox({required this.barcode});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // خطوط الباركود التخطيطية الحقيقية
          CustomPaint(
            size: const Size(double.infinity, 48),
            painter: _BarcodePainter(code: barcode),
          ),
          const SizedBox(height: 6),
          // الرقم مطبوعاً أسفل الخطوط بتباعد واضح كالملصق التجاري
          Text(
            barcode.split('').join('  '),
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  final String code;
  _BarcodePainter({required this.code});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    final width = size.width;
    final height = size.height;

    // توليد خطوط الباركود المتناسقة بناءً على رقم الباركود
    final hashValues = code.codeUnits;
    const totalBars = 55;
    final barUnitWidth = width / totalBars;

    for (int i = 0; i < totalBars; i++) {
      // خطوط بداية ونهاية ووسط مميزة كأي باركود عالمي
      final isGuard = (i < 3) || (i > totalBars - 4) || (i >= 26 && i <= 28);
      final charVal = hashValues[i % hashValues.length];
      final isBlack = isGuard || ((charVal + i * 7) % 3 != 0);

      if (isBlack) {
        final barHeight = isGuard ? height : height * 0.88;
        canvas.drawRect(
          Rect.fromLTWH(i * barUnitWidth, 0, barUnitWidth * 0.78, barHeight),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
