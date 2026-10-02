import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart'; // تمت الإضافة من أجل kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_adaptive_colors.dart';
import '../../../../core/services/local_storage.dart';
import '../../../../core/services/app_cache.dart';
import '../../orders/services/orders_service.dart';
import '../../cart/widgets/cart_floating_button.dart';
import '../../products/services/products_service.dart';
import 'package:sala/core/models/product_unit.dart';
import '../../cart/providers/cart_provider.dart';
import 'tabs/home_tab.dart';
import 'tabs/history_tab.dart';
import 'tabs/orders_tab.dart';
import 'tabs/profile_tab.dart';

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
        _syncPendingReturns(); // 👈 تشغيل مزامنة المرتجعات
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

// 🚀 فور عودة الإنترنت: إرسال أي طلبات محفوظة في الهاتف
        _syncPendingOrder();
        _syncPendingReturns(); // 👈 تشغيل مزامنة المرتجعات
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
          // إرسال الطلب وإزالته فوراً من طابور التاجر الحالي
          await OrdersService.placeOrder(
            merchantId: currentUserId,
            items: List<Map<String, dynamic>>.from(pending['items']),
            expectedTotal:
                (pending['expectedTotal'] as num?)?.toDouble() ?? 0.0,
            notes: pending['notes'],
            extraData: pending['extraData'],
            orderId: orderId,
          );

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
          final bool isTransientIssue = errorMsg.contains('network') ||
              errorMsg.contains('timeout') ||
              errorMsg.contains('unavailable') ||
              errorMsg.contains('socket') ||
              errorMsg.contains('deadline-exceeded');

          if (isTransientIssue) {
            if (kDebugMode) {
              debugPrint(
                  '⚠️ تأجيل إرسال الطلب $orderId لحين استقرار الاتصال بالإنترنت');
            }
            continue;
          } else {
            // 🚀 استعادة الأصناف اعتماداً على بيانات المنتج الأصلية في الكاش لضمان تكامل الكائن
            final rawItems = pending['items'] as List<dynamic>? ?? [];
            final cartNotifier = ref.read(cartProvider.notifier);
            final cachedProducts = AppCache.instance.getProducts() ?? [];

            for (final raw in rawItems) {
              if (raw is Map) {
                final itemMap = Map<String, dynamic>.from(raw);
                final productId = itemMap['product_id']?.toString() ?? '';

                // البحث عن المنتج الأصلي بكافة بياناته وتصنيفاته
                final realProductMap = cachedProducts.firstWhere(
                  (p) => p['id'] == productId,
                  orElse: () => <String, dynamic>{},
                );

                final ProductModel p = realProductMap.isNotEmpty
                    ? ProductModel.fromMap(realProductMap)
                    : ProductModel(
                        id: productId,
                        name: itemMap['product_name']?.toString() ?? 'منتج',
                        price: (itemMap['price'] as num?)?.toDouble() ?? 0.0,
                        brandId: '',
                      );

                ProductUnit? unit;
                final unitLabel = itemMap['unit_label']?.toString();
                if (unitLabel != null && unitLabel.isNotEmpty) {
                  unit = p.units.cast<ProductUnit?>().firstWhere(
                        (u) => u?.label == unitLabel,
                        orElse: () => ProductUnit(
                          label: unitLabel,
                          qty: (itemMap['unit_qty'] as num?)?.toInt() ?? 1,
                          price: (itemMap['price'] as num?)?.toDouble() ?? 0.0,
                        ),
                      );
                }

                cartNotifier.addItem(
                  p,
                  (itemMap['quantity'] as num?)?.toInt() ?? 1,
                  unit: unit,
                );
              }
            }

            await cartNotifier.forceSave(); // حفظ السلة في القرص أولاً
            await AppStorage.removePendingOrder(
                orderId, currentUserId); // ثم مسح الطلب المعلق
            failCount++;
            if (kDebugMode) {
              debugPrint(
                  '❌ تعذر إرسال الطلب $orderId وتمت استعادة الأصناف للسلة بنجاح: $e');
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
          final isNetworkError = errorStr.contains('network') ||
              errorStr.contains('unavailable') ||
              errorStr.contains('timeout') ||
              errorStr.contains('socket');

          if (isNetworkError) {
            continue; // انترنت ضعيف؟ انتظر محاولة أخرى
          } else {
            // خطأ منطقي (مثل تم إرجاعه مسبقاً) نحذفه حتى لا يعلق
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

  @override
  Widget build(BuildContext context) {
    final activeTab = ref.watch(_activeTabProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: context.bgPage,
        body: Stack(
          children: [
            PageView(
              controller: _pageController,
              physics: const BouncingScrollPhysics(parent: PageScrollPhysics()),
              onPageChanged: (index) {
                ref.read(_activeTabProvider.notifier).state = index;
                HapticFeedback.selectionClick();
              },
              children: [
                const HomeTab(),
                const HistoryTab(),
                OrdersTab(
                  onNavigateToHistory: () {
                    _pageController.animateToPage(
                      1,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
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
                    onTap: () => _pageController.animateToPage(
                      0,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeInOut,
                    ),
                  ),
                  _NavItem(
                    icon: Icons.history_rounded,
                    iconOutlined: Icons.history_rounded,
                    label: 'السجل',
                    index: 1,
                    activeTab: activeTab,
                    onTap: () => _pageController.animateToPage(
                      1,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeInOut,
                    ),
                  ),
                  _NavItem(
                    icon: Icons.receipt_long_rounded,
                    iconOutlined: Icons.receipt_long_outlined,
                    label: 'الطلبات',
                    index: 2,
                    activeTab: activeTab,
                    onTap: () => _pageController.animateToPage(
                      2,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeInOut,
                    ),
                  ),
                  _NavItem(
                    icon: Icons.person_rounded,
                    iconOutlined: Icons.person_outline_rounded,
                    label: 'حسابي',
                    index: 3,
                    activeTab: activeTab,
                    onTap: () => _pageController.animateToPage(
                      3,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeInOut,
                    ),
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
