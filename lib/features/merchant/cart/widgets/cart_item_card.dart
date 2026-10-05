// ==================================================
// FILE: lib/features/merchant/cart/widgets/cart_item_card.dart
// ==================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_radius.dart';
import '../../../../../core/services/image_precache_service.dart';
import '../../../../../core/services/app_cache.dart';
import '../providers/cart_provider.dart';
import '../models/cart_item_model.dart';
import '../../products/services/products_service.dart';
import '../../products/widgets/product_details_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

class CartItemCard extends ConsumerWidget {
  final CartItem item;
  final VoidCallback? onDelete;

  const CartItemCard({super.key, required this.item, this.onDelete});

  ProductModel _resolveFullProduct() {
    final cached = AppCache.instance.getProducts();
    if (cached != null && cached.isNotEmpty) {
      final match = cached.firstWhere(
        (p) => p['id'] == item.product.id,
        orElse: () => <String, dynamic>{},
      );
      if (match.isNotEmpty) {
        return ProductModel.fromMap(match);
      }
    }
    return item.product;
  }

  void _openProductDetails(BuildContext context, ProductModel resolvedProduct) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductDetailsSheet(
        product: resolvedProduct,
        initialUnit: item.selectedUnit,
      ),
    );
  }

  Future<void> _showManualQtyDialog(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    int? selectedVal;
    await showDialog(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: '${item.quantity}');
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          backgroundColor: ctx.bgCard,
          title: Text(
            'تعديل الكمية (${item.product.name})',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ctx.textPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'أدخل الكمية المطلوبة مباشرة:',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: ctx.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
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
                  fillColor: ctx.bgInput,
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
                FocusScope.of(ctx).unfocus();
                Navigator.pop(ctx);
              },
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
                selectedVal = int.tryParse(ctrl.text.trim());
                FocusScope.of(ctx).unfocus();
                Navigator.pop(ctx);
              },
              child: const Text('تأكيد',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (selectedVal != null) {
      if (selectedVal! <= 0) {
        onDelete?.call();
      } else {
        ref.read(cartProvider.notifier).setQuantity(item, selectedVal!);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);
    final resolvedProduct = _resolveFullProduct();

    // 1. تحديد الصورة الأنسب (صورة الوحدة -> صورة المنتج الأساسية -> صورة الكاش)
    String? displayImage;
    if (item.selectedUnit?.imageUrl != null &&
        item.selectedUnit!.imageUrl!.trim().isNotEmpty) {
      displayImage = item.selectedUnit!.imageUrl!.trim();
    } else if (item.product.imageUrl != null &&
        item.product.imageUrl!.trim().isNotEmpty) {
      displayImage = item.product.imageUrl!.trim();
    } else if (resolvedProduct.imageUrl != null &&
        resolvedProduct.imageUrl!.trim().isNotEmpty) {
      displayImage = resolvedProduct.imageUrl!.trim();
    }

    // 2. حساب تفاصيل الكميات والحبات
    final int itemsPerUnit =
        item.selectedUnit?.qty ?? resolvedProduct.itemsPerCarton ?? 1;
    final int totalPieces = item.quantity * itemsPerUnit;
    final double? sizeMl = item.selectedUnit?.sizeMl ?? resolvedProduct.sizeMl;
    final currentLabel = item.unitLabel;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 1. صورة المنتج (تظهر دائماً وبشكل صحيح) ──
              GestureDetector(
                onTap: () => _openProductDetails(context, resolvedProduct),
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: context.bgInput,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(color: context.borderColor),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: displayImage != null && displayImage.isNotEmpty
                      ? CachedNetworkImage(
                          cacheManager:
                              ImagePrecacheService.instance.cacheManager,
                          imageUrl: displayImage,
                          fit: BoxFit.contain,
                          memCacheWidth: 200,
                          placeholder: (_, __) => Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.grey,
                            size: 32,
                          ),
                        )
                      : const Icon(
                          Icons.inventory_2_outlined,
                          color: Colors.grey,
                          size: 32,
                        ),
                ),
              ),

              const SizedBox(width: 12),

              // ── 2. بيانات المنتج والتسعير ──
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openProductDetails(context, resolvedProduct),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resolvedProduct.name,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),

                      // سطر السعر والوحدة
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color:
                                    AppColors.primary.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              currentLabel,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${item.unitPrice.toStringAsFixed(0)} ر.ي / $currentLabel',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: context.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // تفاصيل سعة الكرتون والحجم بالمل
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (itemsPerUnit > 1)
                            Text(
                              '($itemsPerUnit حبة في $currentLabel)',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10.5,
                                color: context.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (sizeMl != null && sizeMl > 0)
                            Text(
                              '• ${sizeMl.toStringAsFixed(0)} مل',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10.5,
                                color: context.textSecondary,
                              ),
                            ),
                          if (itemsPerUnit > 1)
                            Text(
                              '• الإجمالي: $totalPieces حبة',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10.5,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // الإجمالي وسلة الحذف
                      Row(
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              key: ValueKey(item.total),
                              '${item.total.toStringAsFixed(0)} ر.ي',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => onDelete?.call(),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.delete_outline_rounded,
                                  size: 18, color: Colors.red.shade400),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // ── 3. عداد الكمية (+ / -) ──
              Container(
                decoration: BoxDecoration(
                  color: context.bgInput,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: context.borderColor),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CountBtn(
                      icon: Icons.add_rounded,
                      color: AppColors.primary,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        notifier.incrementItem(item);
                      },
                    ),
                    GestureDetector(
                      onTap: () => _showManualQtyDialog(context, ref),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 8),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) =>
                              ScaleTransition(scale: anim, child: child),
                          child: Text(
                            key: ValueKey(item.quantity),
                            '${item.quantity}',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: context.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _CountBtn(
                      icon: Icons.remove_rounded,
                      color: item.quantity <= 1
                          ? Colors.red.shade400
                          : context.iconSecondary,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        if (item.quantity <= 1) {
                          onDelete?.call();
                        } else {
                          notifier.decrementItem(item);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── 4. شرائح خيارات الكميات المتاحة للمنتج (كرتون / نصف كرتون / حبة) ──
          if (resolvedProduct.units.length > 1) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: context.borderColor),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'الكميات المتاحة:',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: resolvedProduct.units.map((unit) {
                        final isSelected =
                            unit.label.trim() == currentLabel.trim();
                        return Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: ChoiceChip(
                            label: Text(
                              '${unit.label} (${unit.price.toStringAsFixed(0)} ر.ي)',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10.5,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : context.textPrimary,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: AppColors.primary,
                            backgroundColor: context.bgInput,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isSelected
                                    ? AppColors.primary
                                    : context.borderColor,
                              ),
                            ),
                            onSelected: (selected) {
                              if (selected && !isSelected) {
                                HapticFeedback.selectionClick();
                                notifier.changeItemUnit(item, unit);
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CountBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CountBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
