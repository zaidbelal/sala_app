import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart'; // تمت الإضافة من أجل kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_adaptive_colors.dart';
import '../../../../core/services/local_storage.dart';
import '../../orders/services/orders_service.dart';
import '../../cart/widgets/cart_floating_button.dart';
import '../../cart/providers/cart_provider.dart';
import '../../cart/models/cart_item_model.dart';
import 'tabs/home_tab.dart';
import 'tabs/history_tab.dart';
import 'tabs/orders_tab.dart';
import 'tabs/profile_tab.dart';
import '../../ledger/screens/ledger_tab.dart';
import '../../ledger/services/ledger_service.dart';
import 'package:sala/core/services/wal_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sala/core/services/app_cache.dart';

final _activeTabProvider = StateProvider<int>((ref) => 0);

class MerchantHomeScreen extends ConsumerStatefulWidget {
  const MerchantHomeScreen({super.key});

  @override
  ConsumerState<MerchantHomeScreen> createState() => _MerchantHomeScreenState();
}

class _MerchantHomeScreenState extends ConsumerState<MerchantHomeScreen> {
  late PageController _pageController;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySub;
  bool _isOffline = false;
  bool _justReconnected = false;
  Timer? _reconnectedTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    // 🚀 بدء مزامنة الطلبات المحفوظة حال فتح التطبيق لو كان الإنترنت متوفراً
    Connectivity().checkConnectivity().then((results) {
      if (!results.every((r) => r == ConnectivityResult.none)) {
        _syncPendingOrder();
        _syncPendingReturns();
        _syncPendingLedger(); // ✅ تشغيل مزامنة ديون الدفتر المسجلة أوفلاين
      }
    });
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (!mounted) return;

      if (!offline && _isOffline) {
        // عاد الاتصال
        setState(() {
          _isOffline = false;
          _justReconnected = true;
        });
        _reconnectedTimer?.cancel();
        _reconnectedTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _justReconnected = false);
        });
// 🚀 فور عودة الإنترنت: مزامنة الطلبات والمرتجعات وديون الدفتر
        _syncPendingOrder();
        _syncPendingReturns();
        _syncPendingLedger(); // ✅ مزامنة حركات الدفتر فور عودة الإنترنت
      } else if (offline) {
        setState(() {
          _isOffline = true;
          _justReconnected = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _connectivitySub.cancel();
    _reconnectedTimer?.cancel();
    super.dispose();
  }

  Future<void> retry() async {
    final results = await Connectivity().checkConnectivity();
    if (!mounted) return;
    final offline = results.every((r) => r == ConnectivityResult.none);
    if (!offline) {
      setState(() {
        _isOffline = false;
        _justReconnected = true;
      });
      _reconnectedTimer?.cancel();
      _reconnectedTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _justReconnected = false);
      });

      // مزامنة الطلبات في حال ضغط المستخدم على إعاد المحاولة ونجح الاتصال
      _syncPendingOrder();
      _syncPendingReturns(); // 👈 تشغيل مزامنة المرتجعات
      _syncPendingLedger();
    } else {
      // اهتزاز خفيف للإشارة أن النت لا يزال منقطعاً
      HapticFeedback.heavyImpact();
    }
  }

  bool _isSyncing = false;

  Future<void> _syncPendingOrder() async {
    if (_isSyncing) return;
    final currentUserId = AppStorage.userId;
    if (currentUserId == null || currentUserId.isEmpty) return;

    final pendingQueue = AppStorage.getPendingOrders(currentUserId);
    if (pendingQueue.isEmpty) return;

    _isSyncing = true;

    int successCount = 0;
    int failCount = 0;

    try {
      for (final pending in pendingQueue) {
        final orderId = pending['orderId']?.toString() ?? '';
        final orderMerchantId = pending['merchantId']?.toString() ?? '';

        // منع إرسال طلبات تعود لمستخدم آخر
        if (orderMerchantId != currentUserId) {
          await AppStorage.removePendingOrder(orderId, orderMerchantId);
          continue;
        }

        try {
          // إرسال الطلب وإزالته فوراً وتأكيد الـ WAL
          await OrdersService.placeOrder(
            merchantId: currentUserId,
            items: List<Map<String, dynamic>>.from(pending['items']),
            expectedTotal:
                (pending['expectedTotal'] as num?)?.toDouble() ?? 0.0,
            notes: pending['notes'],
            extraData: pending['extraData'],
            orderId: orderId,
          );

          await WalService.instance.markCommitted(orderId);
          await AppStorage.removePendingOrder(orderId, currentUserId);
          successCount++;
        } catch (e) {
          // إذا كان الطلب مسجلاً بالفعل في السيرفر (Idempotent Success) نحذفه بنجاح
          if (e.toString().contains('already-exists') ||
              e.toString().contains('تم إنشاء الطلب مسبقاً')) {
            await AppStorage.removePendingOrder(orderId, currentUserId);
            successCount++;
            continue;
          }
          final errorMsg = e.toString().toLowerCase();
          final bool isStockOrProductIssue =
              errorMsg.contains('product_unavailable') ||
                  errorMsg.contains('out_of_stock') ||
                  errorMsg.contains('صنف') ||
                  errorMsg.contains('غير متوفر');

          final bool isTransientIssue = !isStockOrProductIssue &&
              (errorMsg.contains('network') ||
                  errorMsg.contains('timeout') ||
                  errorMsg.contains('socket') ||
                  errorMsg.contains('deadline-exceeded') ||
                  errorMsg.contains('unauthenticated') ||
                  errorMsg.contains('تسجيل الدخول') ||
                  errorMsg.contains('جلسة التاجر غير صالحة') ||
                  errorMsg.contains('user-not-found') ||
                  errorMsg.contains('permission-denied') ||
                  (errorMsg.contains('unavailable') &&
                      !errorMsg.contains('product')));

          if (isTransientIssue) {
            if (kDebugMode) {
              debugPrint(
                  '⚠️ تأجيل إرسال الطلب $orderId لحين استقرار الجلسة والاتصال بالإنترنت');
            }
            continue;
          } else {
            await WalService.instance.markAborted(orderId);
            // التحقق المباشر من السيرفر لضمان عدم إعادة أصناف محذوفة إلى السلة
            List<Map<String, dynamic>> availableProducts = [];
            try {
              final snap = await FirebaseFirestore.instance
                  .collection('products')
                  .where('is_deleted', isEqualTo: false)
                  .where('is_active', isEqualTo: true)
                  .limit(500)
                  .get(const GetOptions(source: Source.server));
              availableProducts =
                  snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
            } catch (_) {
              availableProducts = AppCache.instance.getProducts() ?? [];
            }

            final activeProductMap = {
              for (final p in availableProducts)
                if (p['is_deleted'] != true && p['is_active'] != false)
                  p['id'].toString(): p
            };

            final cartMap = <String, dynamic>{};
            final errorStr = e.toString();

            for (final item in pending['items']) {
              final productId = item['product_id']?.toString() ?? '';
              final productName = item['product_name']?.toString() ?? '';

              final isExplicitlyFailed = (productId.isNotEmpty &&
                      errorStr.contains(productId)) ||
                  (productName.isNotEmpty && errorStr.contains(productName));
              final liveProduct = activeProductMap[productId];

              // إذا كان المنتج محذوفاً أو غير متوفر في الكاتالوج الفعّال لا يُعاد للسلة مطلقاً
              if (isExplicitlyFailed || liveProduct == null) {
                continue;
              }

              final unitLabel = item['unit_label']?.toString().trim();
              final cartKey = (unitLabel == null ||
                      unitLabel.isEmpty ||
                      unitLabel == 'كرتون')
                  ? productId
                  : '${productId}__$unitLabel';

              cartMap[cartKey] = {
                'product': {
                  'id': productId,
                  'name': liveProduct['name'] ?? item['product_name'],
                  'price': item['price'],
                  'brand_id': liveProduct['brand_id'] ?? '',
                  'brandId': liveProduct['brand_id'] ?? '',
                  'image_url': liveProduct['image_url'],
                  'size_ml': liveProduct['size_ml'],
                  'items_per_carton': liveProduct['items_per_carton'],
                },
                'quantity': item['quantity'],
                'snapshot_at': DateTime.now().millisecondsSinceEpoch,
                if (unitLabel != null && unitLabel.isNotEmpty)
                  'selectedUnit': {
                    'label': unitLabel,
                    'qty': item['unit_qty'] ?? 1,
                    'price': item['price'],
                  },
              };
            }
            if (cartMap.isNotEmpty) {
              // 🔒 دمج كافة العناصر المعادة أولاً برمجياً ثم حفظها مرة واحدة لمنع تداخل عمليات الكتابة على القرص
              final notifier = ref.read(cartProvider.notifier);
              for (final entry in cartMap.entries) {
                final oldItem =
                    CartItem.fromJson(entry.value as Map<String, dynamic>);
                notifier.addItem(
                  oldItem.product,
                  oldItem.quantity,
                  unit: oldItem.selectedUnit,
                );
              }
              await notifier.forceSave();
            }
            await AppStorage.removePendingOrder(orderId, currentUserId);
            failCount++;
            if (kDebugMode) {
              debugPrint(
                  '❌ تمت معالجة الطلب المعلق المتعثر $orderId بنجاح: $e');
            }
          }
        }
      }
    } finally {
      _isSyncing = false;
    }
    if (!mounted) return;

    if (successCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  successCount == 1
                      ? 'تم إرسال طلبك المعلق بنجاح ✅'
                      : 'تم إرسال $successCount طلبات معلقة بنجاح ✅',
                  style: const TextStyle(fontFamily: 'Cairo'))),
        ]),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ));
    }

    if (failCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Expanded(
            child: Text(
                'تعذر إرسال $failCount طلب معلق بسبب تغير في المخزون أو الأسعار. نرجو إعادة الطلب.',
                style: const TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w700))),
      ])));
    }
  }

  bool _isSyncingReturns = false;

  Future<void> _syncPendingReturns() async {
    if (_isSyncingReturns) return;
    final currentUserId = AppStorage.userId;
    if (currentUserId == null || currentUserId.isEmpty) return;

    final pendingReturns = AppStorage.getPendingReturns(currentUserId);
    if (pendingReturns.isEmpty) return;

    _isSyncingReturns = true;
    int successCount = 0;

    try {
      for (final pending in pendingReturns) {
        final orderId = pending['orderId']?.toString() ?? '';
        final merchantId = pending['merchantId']?.toString() ?? '';

        if (merchantId != currentUserId) {
          await AppStorage.removePendingReturn(orderId, merchantId);
          continue;
        }

        try {
          await OrdersService.submitReturns(
            orderId: orderId,
            itemsToReturn:
                List<Map<String, dynamic>>.from(pending['itemsToReturn']),
            merchantId: merchantId,
            storeName: pending['storeName'],
            contact: pending['contact'],
            latitude: (pending['latitude'] as num?)?.toDouble(),
            longitude: (pending['longitude'] as num?)?.toDouble(),
            reason: pending['reason'],
          );

          await AppStorage.removePendingReturn(orderId, merchantId);
          successCount++;
        } catch (e) {
          final errorStr = e.toString().toLowerCase();
          final isTransientIssue = errorStr.contains('network') ||
              errorStr.contains('unavailable') ||
              errorStr.contains('timeout') ||
              errorStr.contains('socket') ||
              errorStr.contains('deadline-exceeded') ||
              errorStr.contains('جلسة التاجر غير صالحة') ||
              errorStr.contains('user-not-found');

          if (isTransientIssue) {
            continue; // تأجيل المزامنة لحين جاهزية الجلسة والإنترنت
          } else {
            // خطأ منطقي نهائي من السيرفر فقط
            await AppStorage.removePendingReturn(orderId, merchantId);
          }
        }
      }

      if (successCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.assignment_return_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text('تم إرسال طلبات الإرجاع المعلقة بنجاح ✅',
                    style: const TextStyle(fontFamily: 'Cairo'))),
          ]),
          backgroundColor: const Color(0xFFEA580C),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      _isSyncingReturns = false;
    }
  }

  bool _isSyncingLedger = false;

  Future<void> _syncPendingLedger() async {
    if (_isSyncingLedger) return;
    final currentUserId = AppStorage.userId;
    if (currentUserId == null || currentUserId.isEmpty) return;

    _isSyncingLedger = true;
    try {
      final syncedCount =
          await LedgerService.instance.syncPendingLedgerQueue(currentUserId);

      if (syncedCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'تمت مزامنة $syncedCount حركات ديون مع السيرفر بنجاح 📒✅',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          ]),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      _isSyncingLedger = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = ref.watch(_activeTabProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness:
            context.isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness:
            context.isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: context.bgPage,
        body: Stack(
          children: [
            IndexedStack(
              index: activeTab,
              children: [
                const HomeTab(),
                const HistoryTab(),
                OrdersTab(
                  onNavigateToHistory: () {
                    ref.read(_activeTabProvider.notifier).state = 1;
                  },
                ),
                const LedgerTab(),
                const ProfileTab(),
              ],
            ),
            // ── مؤشر الإنترنت العائم والأنيق ──
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: SafeArea(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: (_isOffline || _justReconnected) ? 1.0 : 0.0,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _isOffline
                              ? Colors.black.withValues(alpha: 0.75)
                              : Colors.green.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isOffline
                                  ? Icons.cloud_off_rounded
                                  : Icons.cloud_done_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isOffline ? 'وضع عدم الاتصال' : 'عاد الاتصال ✅',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: CartFloatingButton(),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: context.bgHeader,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  _NavItem(
                    icon: Icons.home_rounded,
                    iconOutlined: Icons.home_outlined,
                    label: 'الرئيسية',
                    index: 0,
                    activeTab: activeTab,
                    onTap: () =>
                        ref.read(_activeTabProvider.notifier).state = 0,
                  ),
                  _NavItem(
                    icon: Icons.history_rounded,
                    iconOutlined: Icons.history_rounded,
                    label: 'السجل',
                    index: 1,
                    activeTab: activeTab,
                    onTap: () =>
                        ref.read(_activeTabProvider.notifier).state = 1,
                  ),
                  _NavItem(
                    icon: Icons.receipt_long_rounded,
                    iconOutlined: Icons.receipt_long_outlined,
                    label: 'الطلبات',
                    index: 2,
                    activeTab: activeTab,
                    onTap: () =>
                        ref.read(_activeTabProvider.notifier).state = 2,
                  ),
                  _NavItem(
                    icon: Icons.menu_book_rounded,
                    iconOutlined: Icons.menu_book_outlined,
                    label: 'الدفتر',
                    index: 3,
                    activeTab: activeTab,
                    onTap: () =>
                        ref.read(_activeTabProvider.notifier).state = 3,
                  ),
                  _NavItem(
                    icon: Icons.person_rounded,
                    iconOutlined: Icons.person_outline_rounded,
                    label: 'حسابي',
                    index: 4,
                    activeTab: activeTab,
                    onTap: () =>
                        ref.read(_activeTabProvider.notifier).state = 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════
// عنصر التنقل
// ══════════════════════════════════════════
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData iconOutlined;
  final String label;
  final int index;
  final int activeTab;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.iconOutlined,
    required this.label,
    required this.index,
    required this.activeTab,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == activeTab;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                isActive ? icon : iconOutlined,
                size: 24,
                color: isActive ? AppColors.primary : const Color(0xFFAAAAAA),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Cairo',
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? AppColors.primary : const Color(0xFFAAAAAA),
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
