import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../cart/providers/cart_provider.dart';
import 'package:sala/core/constants/app_colors.dart';
import 'package:sala/core/constants/app_radius.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import 'package:sala/core/models/product_unit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../products/services/products_service.dart';
import 'package:sala/core/services/app_cache.dart';
import 'package:sala/core/services/catalog_service.dart';

class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key});

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _searchCtrl = TextEditingController();
  List<ProductModel> _products = [];
  List<ProductModel> _filtered = [];
  bool _loading = true;
  String? _error;
  Timer? _filterDebounce;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 250), _filter);
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 1. القراءة من كاش الهاتف المحلي أولاً
      List<Map<String, dynamic>> productsData =
          AppCache.instance.getProducts() ?? [];

      // 2. إذا لم يكن متوفراً بالكاش، نجلبه عبر مزود الكتالوج الكامل والآمن
      if (productsData.isEmpty) {
        final fetched = await ref.read(productsProvider(null).future);
        productsData = List<Map<String, dynamic>>.from(fetched);
      }

      if (!mounted) return;

      final list = productsData
          .where((p) => p['is_active'] != false && p['is_deleted'] != true)
          .map((p) => ProductModel.fromMap(Map<String, dynamic>.from(p)))
          .toList();

      setState(() {
        _products = list;
        _filtered = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تحميل المنتجات، تحقق من الاتصال بالإنترنت';
        _loading = false;
      });
    }
  }

  void _filter() {
    // دالة مساعدة لتوحيد الحروف العربية تجاهل (الهمزات، التاء المربوطة، الياء)
    String normalize(String text) {
      return text
          .replaceAll(RegExp(r'[أإآ]'), 'ا')
          .replaceAll('ة', 'ه')
          .replaceAll('ى', 'ي')
          .toLowerCase()
          .trim();
    }

    final q = normalize(_searchCtrl.text);

    setState(() {
      _filtered = q.isEmpty
          ? _products
          : _products.where((p) {
              final productName = normalize(p.name);
              // دعم البحث المتقدم (حتى لو كان جزء من الكلمة في الوسط)
              return productName.contains(q);
            }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: context.bgCard, // ✅ دارك مود
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(children: [
        // ── مقبض ──
        const SizedBox(height: 12),
        Container(
          width: 44,
          height: 4,
          decoration: BoxDecoration(
            color: context.borderColor, // ✅ دارك مود
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // ── رأس الشيت ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: context.bgInput, // ✅ دارك مود
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: context.textPrimary, // ✅ دارك مود
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'إضافة منتج',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary, // ✅ دارك مود
                ),
              ),
              const Spacer(),
              const SizedBox(width: 36),
            ],
          ),
        ),
        // ── خانة البحث ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: TextField(
            controller: _searchCtrl,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              color: context.textPrimary, // ✅ دارك مود
            ),
            decoration: InputDecoration(
              hintText: 'ابحث عن منتج...',
              hintStyle: TextStyle(
                fontFamily: 'Cairo',
                color: context.textHint, // ✅ دارك مود
                fontSize: 14,
              ),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: AppColors.primary),
              filled: true,
              fillColor: context.bgInput, // ✅ دارك مود
              border: const OutlineInputBorder(
                borderRadius: AppRadius.lgAll,
                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: AppRadius.lgAll,
                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.lgAll,
                borderSide:
                    BorderSide(color: context.borderColor), // ✅ دارك مود
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        // ── المحتوى ──
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _error != null
                  ? _ErrorState(error: _error!, onRetry: _fetchProducts)
                  : _filtered.isEmpty
                      ? _EmptyState(hasSearch: _searchCtrl.text.isNotEmpty)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => _ProductTile(
                              key: ValueKey(_filtered[i].id),
                              product: _filtered[i],
                              onAdd: (qty, unit) {
                                ref
                                    .read(cartProvider.notifier)
                                    .addItem(_filtered[i], qty, unit: unit);

                                HapticFeedback.lightImpact();
                              }),
                        ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════
// صف المنتج
// ════════════════════════════════════════
class _ProductTile extends StatefulWidget {
  final ProductModel product;
  final void Function(int qty, ProductUnit? unit) onAdd;
  const _ProductTile({super.key, required this.product, required this.onAdd});

  @override
  State<_ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends State<_ProductTile> {
  int _qty = 1;
  bool _added = false;
  ProductUnit? _selectedUnit;

  @override
  void initState() {
    super.initState();
    _initUnit();
  }

  @override
  void didUpdateWidget(covariant _ProductTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id) {
      _initUnit();
    }
  }

  void _initUnit() {
    _qty = 1;
    _selectedUnit =
        widget.product.units.isNotEmpty ? widget.product.units.first : null;
  }

  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _showManualQtyDialog() {
    HapticFeedback.mediumImpact();
    final controller = TextEditingController(text: '$_qty');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: context.bgCard,
        title: Text(
          'تحديد الكمية (${_selectedUnit?.label ?? "كرتون"})',
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
              'أدخل الكمية المطلوبة للمنتج (${widget.product.name}):',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: context.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              if (val != null && val > 0) {
                setState(() => _qty = val);
              }
              Navigator.pop(ctx);
            },
            child: const Text('تأكيد',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _add() {
    widget.onAdd(_qty, _selectedUnit);
    if (!mounted) return;
    setState(() => _added = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _added = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgCard, // ✅ دارك مود
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: context.borderColor), // ✅ دارك مود
        boxShadow: [
          BoxShadow(
            color: context.shadowColor.withValues(alpha: 0.06),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        children: [
          // صورة/أيقونة الكمية المختارة تلقائياً (كرتون أو حبة)
          Builder(
            builder: (context) {
              final activeImg = (_selectedUnit?.imageUrl != null &&
                      _selectedUnit!.imageUrl!.trim().isNotEmpty)
                  ? _selectedUnit!.imageUrl!.trim()
                  : (_selectedUnit == null || _selectedUnit!.label == 'كرتون'
                      ? widget.product.imageUrl
                      : null);

              return Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: AppRadius.mdAll,
                ),
                child: activeImg != null && activeImg.isNotEmpty
                    ? ClipRRect(
                        borderRadius: AppRadius.mdAll,
                        child: CachedNetworkImage(
                          imageUrl: activeImg,
                          fit: BoxFit.cover,
                          memCacheWidth: 200,
                          errorWidget: (_, __, ___) => const Icon(
                              Icons.inventory_2_outlined,
                              color: AppColors.primary,
                              size: 24),
                        ),
                      )
                    : const Icon(Icons.inventory_2_outlined,
                        color: AppColors.primary, size: 24),
              );
            },
          ),
          const SizedBox(width: 10),
          // الاسم والسعر
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.product.name,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary, // ✅ دارك مود
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _selectedUnit != null
                      ? '${_selectedUnit!.price.toStringAsFixed(0)} ر.ي / ${_selectedUnit!.label}'
                      : '${widget.product.price.toStringAsFixed(0)} ر.ي',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // ── اختيار الوحدة إن وُجدت ──
                if (widget.product.units.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: widget.product.units.map((unit) {
                        final isSelected = _selectedUnit?.label == unit.label;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedUnit = unit),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            margin: const EdgeInsetsDirectional.only(end: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.primary.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              unit.label,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // التحكم بالكمية (يدعم النقر المزدوج لكتابة الرقم يدوياً)
          Row(
            children: [
              _QtyBtn(
                icon: Icons.remove_rounded,
                onTap: () => setState(() {
                  if (_qty > 1) _qty--;
                }),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: _showManualQtyDialog,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    '$_qty',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: context.textPrimary, // ✅ دارك مود
                    ),
                  ),
                ),
              ),
              _QtyBtn(
                icon: Icons.add_rounded,
                onTap: () => setState(() => _qty++),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // زر الإضافة
          GestureDetector(
            onTap: _added ? null : _add,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _added ? Colors.green : AppColors.primary,
                borderRadius: AppRadius.mdAll,
              ),
              child: Icon(
                _added ? Icons.check_rounded : Icons.add_shopping_cart_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════
// زر الكمية
// ════════════════════════════════════════
class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: context.bgInput, // ✅ دارك مود
          borderRadius: AppRadius.smAll,
        ),
        child: Icon(
          icon,
          size: 16,
          color: context.textPrimary, // ✅ دارك مود
        ),
      ),
    );
  }
}

// ════════════════════════════════════════
// حالة الخطأ
// ════════════════════════════════════════
class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 60, color: context.iconSecondary),
            const SizedBox(height: 16),
            Text(
              'فشل تحميل المنتجات',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.textPrimary, // ✅ دارك مود
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                color: context.textSecondary, // ✅ دارك مود
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة',
                  style: TextStyle(fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape:
                    const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════
// قائمة فارغة
// ════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  const _EmptyState({required this.hasSearch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasSearch ? Icons.search_off_rounded : Icons.inventory_2_outlined,
            size: 60,
            color: context.iconSecondary, // ✅ دارك مود
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch ? 'لا نتائج للبحث' : 'لا توجد منتجات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.textSecondary, // ✅ دارك مود
            ),
          ),
        ],
      ),
    );
  }
}
