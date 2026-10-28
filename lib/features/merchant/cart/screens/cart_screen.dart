import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_radius.dart';
import '../../cart/providers/cart_provider.dart';
import '../widgets/cart_item_card.dart';
import '../widgets/quick_add_sheet.dart';
import 'checkout_screen.dart';
import '../../../../../core/services/local_storage.dart';
import '../../../../../core/services/connectivity_service.dart';
import '../models/cart_item_model.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  double get _minOrder => AppConfig.minOrderValue;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncCartPrices();
    });
  }

  Future<void> _syncCartPrices() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;
    final bool hasInternet = await ConnectivityHelper.hasActiveInternet();
    // 🛡️ حماية السلة: منع التحقق الجزئي أوفلاين لحماية أصناف التاجر من الحذف الخاطئ
    if (!hasInternet) return;

    final cartProductIds =
        cart.values.map((e) => e.product.id).toSet().toList();
    List<Map<String, dynamic>> latestProducts = [];

    try {
      final chunks = <List<String>>[];
      for (var i = 0; i < cartProductIds.length; i += 30) {
        chunks.add(cartProductIds.sublist(i,
            i + 30 > cartProductIds.length ? cartProductIds.length : i + 30));
      }
      final successfullyQueriedIds = <String>{};
      for (final chunk in chunks) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('products')
              .where(FieldPath.documentId, whereIn: chunk)
              .get(const GetOptions(source: Source.server));
          latestProducts
              .addAll(snap.docs.map((d) => {'id': d.id, ...d.data()}));
          successfullyQueriedIds.addAll(chunk);
        } catch (_) {
          // في حال فشل أي Chunk شبكياً، لا نعتبر منتجاته محذوفة ونحفظها للمحاولة القادمة
        }
      }
      if (successfullyQueriedIds.isEmpty) return;

      final hasChanges =
          ref.read(cartProvider.notifier).validateAndUpdatePrices(
                latestProducts,
                queriedBatchIds: successfullyQueriedIds,
              );

      if (hasChanges && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '⚠️ تم تحديث سلتك واستبعاد الأصناف التي لم تعد متوفرة ومطابقة أحدث الأسعار',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      return;
    }
  }

  void _handleDelete(CartItem item) {
    final deletedItem = item;
    ref.read(cartProvider.notifier).removeItem(item.cartKey);
    HapticFeedback.lightImpact();

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('تم حذف ${deletedItem.product.name}',
            style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.grey[800],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'تراجع',
          textColor: Colors.white,
          onPressed: () {
            ref.read(cartProvider.notifier).addItem(
                  deletedItem.product,
                  deletedItem.quantity,
                  unit: deletedItem.selectedUnit,
                );
          },
        ),
      ),
    );
  }

  void _openQuickAdd() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QuickAddSheet(),
    );
  }

  void _goToCheckout() {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    final uid = AppStorage.userId;

    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('يرجى تسجيل الدخول أولاً',
            style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(merchantId: uid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final items = cart.values.toList();
    final total = ref.watch(cartTotalProvider);
    final count = ref.watch(cartCountProvider);
    final progress = (total / _minOrder).clamp(0.0, 1.0);
    final belowMin = total < _minOrder;

    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, count),
            Expanded(
              child: cart.isEmpty
                  ? const _EmptyCart()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => CartItemCard(
                        item: items[i],
                        onDelete: () => _handleDelete(items[i]),
                      ),
                    ),
            ),
            if (cart.isNotEmpty) _buildBottom(total, belowMin, progress),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    return Container(
      color: context.bgHeader,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.bgPage,
                borderRadius: AppRadius.mdAll,
              ),
              child: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('سلتي',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 20,
                      fontWeight: FontWeight.w900)),
              Text(
                count == 0 ? 'فارغة' : '$count صنف',
                style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: _openQuickAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: AppRadius.circleAll,
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text('إضافة',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottom(double total, bool belowMin, double progress) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: context.bgCard,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('الإجمالي',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 15, color: Colors.grey)),
              Text(
                '${total.toStringAsFixed(0)} ر.ي',
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary),
              ),
            ],
          ),
          if (belowMin) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الحد الأدنى للطلب',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: Colors.grey[500]),
                ),
                Text(
                  '${((_minOrder - total) <= 0 ? 0 : (_minOrder - total).ceil())} ر.ي متبقي',
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.orange),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: Colors.grey[200],
                color: Colors.orange,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: belowMin ? null : _goToCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape:
                    const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_bag_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('إتمام الطلب',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.shopping_cart_outlined,
                size: 55, color: Colors.grey[300]),
          ),
          const SizedBox(height: 20),
          Text('السلة فارغة',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[400])),
          const SizedBox(height: 8),
          Text('اضغط + إضافة لتبدأ طلبك',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 13, color: Colors.grey[400])),
        ],
      ),
    );
  }
}
