import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:sala/core/constants/app_colors.dart';
import 'package:sala/core/services/local_storage.dart';
import '../widgets/new_order_sheet.dart';
import 'driver_order_detail_screen.dart';
import 'driver_stats_screen.dart';
import 'driver_history_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sala/core/services/realtime_hub.dart';
import 'package:sala/features/auth/login/services/auth_service.dart';
import 'package:sala/features/merchant/orders/services/orders_service.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import 'package:sala/core/widgets/signature_pad_dialog.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _sheetOpen = false;
  bool _isSyncingDeliveries = false;
  final db = FirebaseFirestore.instance;
  late final StreamSubscription<List<ConnectivityResult>>
      _driverConnectivitySub;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(driverNewOrderCallbackProvider.notifier).state =
          (id, data) => _onNewOrder(id, data);
      _syncPendingDeliveries();
    });

    // ✅ الاستماع لعودة الإنترنت لمزامنة تسليمات الأوفلاين تلقائياً بدون إعادة تشغيل التطبيق
    _driverConnectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      final hasNet = !results.every((r) => r == ConnectivityResult.none);
      if (hasNet && mounted) {
        _syncPendingDeliveries();
      }
    });
  }

  Future<void> _syncPendingDeliveries() async {
    if (_isSyncingDeliveries) return;
    _isSyncingDeliveries = true;
    try {
      final driverId = AppStorage.userId;
      if (driverId == null || driverId.isEmpty) return;
      final pending = AppStorage.getPendingDriverDeliveries(driverId);
      if (pending.isEmpty) return;

      for (final orderId in pending) {
        try {
          await OrdersService.deliverOrderByDriver(orderId: orderId);
          await AppStorage.removePendingDriverDelivery(orderId, driverId);
        } catch (e) {
          final err = e.toString().toLowerCase();
          // 🚀 إضافة deadline-exceeded لحماية الطلبات من الحذف عند ضعف الشبكة الشديد
          final isNetwork = err.contains('network') ||
              err.contains('timeout') ||
              err.contains('unavailable') ||
              err.contains('socket') ||
              err.contains('deadline-exceeded');

          // إذا كان الخطأ منطقياً (تم تسليمه مسبقاً، ملغي، محذوف، غير مصرح) نحذفه فوراً
          // أما إذا كان خطأ شبكة، نتركه في الطابور للمحاولة لاحقاً
          if (!isNetwork) {
            await AppStorage.removePendingDriverDelivery(orderId, driverId);
          }
        }
      }
    } finally {
      _isSyncingDeliveries = false;
    }
  }

  @override
  void dispose() {
    _driverConnectivitySub.cancel();
    _tabCtrl.dispose();
    ref.read(driverNewOrderCallbackProvider.notifier).state = null;
    super.dispose();
  }

// ══ استقبال طلب جديد من RealtimeHub مع طابور معالجة متسلسل ══
  final List<Map<String, dynamic>> _newOrderQueue = [];

  void _onNewOrder(String orderId, Map<String, dynamic> data) {
    if (!mounted) return;
    _newOrderQueue.add({'id': orderId, 'data': data});
    if (!_sheetOpen) {
      _processNextOrderInQueue();
    }
  }

  Future<void> _processNextOrderInQueue() async {
    if (!mounted || _newOrderQueue.isEmpty || _sheetOpen) return;
    _sheetOpen = true;
    final next = _newOrderQueue.removeAt(0);
    final orderId = next['id'] as String;
    final data = next['data'] as Map<String, dynamic>;

    try {
      final accepted = await NewOrderSheet.show(
        context,
        orderId: orderId,
        data: data,
      );

      if (accepted == true && mounted) {
        await _acceptOrder(orderId, data);
      }
    } finally {
      _sheetOpen = false;
    }

    if (mounted && _newOrderQueue.isNotEmpty) {
      _processNextOrderInQueue();
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmedOrders = ref.watch(realtimeConfirmedOrdersProvider);
    final driverId = AppStorage.userId ?? '';
    final pendingDeliveries =
        AppStorage.getPendingDriverDeliveries(driverId).toSet();
    final shippedOrders = ref
        .watch(realtimeMyShippedOrdersProvider)
        .where((o) => !pendingDeliveries.contains(o['id']?.toString()))
        .toList();

    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(shippedOrders.length),
            _buildTabBar(confirmedOrders.length, shippedOrders.length),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _OrdersListFromProvider(
                    orders: confirmedOrders,
                    emptyIcon: Icons.inbox_outlined,
                    emptyText: 'لا توجد طلبات جاهزة للاستلام',
                    status: 'confirmed',
                    onAction: _handleAction,
                    onTap: _openDetail,
                  ),
                  _OrdersListFromProvider(
                    orders: shippedOrders,
                    emptyIcon: Icons.check_circle_outline_rounded,
                    emptyText: 'لا توجد طلبات قيد التوصيل',
                    status: 'shipped',
                    onAction: _handleAction,
                    onTap: _openDetail,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══ الهيدر ══
  Widget _buildHeader(int activeCount) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF1B8E3D), Color(0xFF25C25A)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── أيقونة المندوب ──
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delivery_dining_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),

          // ── الاسم والحالة ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مرحباً ${AppStorage.userName ?? 'المندوب'} 👋',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF69F0AE),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      activeCount > 0
                          ? '$activeCount طلب قيد التوصيل'
                          : 'جاهز للتوصيل',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── أزرار الهيدر ──
          Row(
            children: [
              // زر سجل الرحلات
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DriverHistoryScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.history_rounded,
                      color: Colors.white, size: 19),
                ),
              ),
              // زر الإحصائيات
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DriverStatsScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.bar_chart_rounded,
                      color: Colors.white, size: 19),
                ),
              ),
              // زر الخروج
              GestureDetector(
                onTap: _confirmLogout,
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.logout_rounded,
                      color: Colors.white, size: 19),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══ TabBar ══
  Widget _buildTabBar(int confirmedCount, int shippedCount) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabCtrl,
        labelStyle: const TextStyle(
            fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontFamily: 'Cairo', fontSize: 13),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey,
        indicator: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        padding: const EdgeInsets.all(4),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('📦 جاهزة للاستلام'),
                if (confirmedCount > 0) ...[
                  const SizedBox(width: 6),
                  _Badge(count: confirmedCount, color: Colors.orange),
                ],
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🚚 قيد التوصيل'),
                if (shippedCount > 0) ...[
                  const SizedBox(width: 6),
                  _Badge(count: shippedCount, color: Colors.blue),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══ فتح تفاصيل الطلب ══
  void _openDetail(String orderId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverOrderDetailScreen(
          orderId: orderId,
          data: data,
          onAction: _handleAction,
        ),
      ),
    );
  }

// ══ تأكيد تسجيل الخروج ══
  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('تسجيل الخروج',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
        content: const Text('هل تريد تسجيل الخروج؟',
            style: TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.grey))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('خروج', style: TextStyle(fontFamily: 'Cairo'))),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await ref.read(authServiceProvider).signOut();
    } catch (_) {}

    if (mounted) {
      context.go('/login');
    }
  }

  // ══ معالجة الإجراء (استلام / تسليم) ══
  // ══════════════════════════════════════════
  // مستمع الطلبات الجديدة الفورية
  // ══════════════════════════════════════════
  /// قبول الطلب مباشرة من الشيت (بدون تأكيد إضافي)
  Future<void> _acceptOrder(String orderId, Map<String, dynamic> data) async {
    if (!mounted) return;

    final driverId = AppStorage.userId;
    if (driverId == null || driverId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('خطأ: السائق غير مسجل الدخول بشكل صحيح',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    BuildContext? dialogContext;
    bool dialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return const PopScope(
          canPop: false,
          child: Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
        );
      },
    );

    void closeLoadingDialog() {
      if (dialogOpen) {
        dialogOpen = false;
        if (dialogContext != null && Navigator.canPop(dialogContext!)) {
          Navigator.of(dialogContext!).pop();
        }
      }
    }

    try {
      await OrdersService.assignOrderToDriver(
        orderId: orderId,
        driverId: driverId,
        driverName: AppStorage.userName ?? 'مندوب سلة',
      ).timeout(const Duration(seconds: 10));

      closeLoadingDialog();
      HapticFeedback.mediumImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('✅ تم قبول الطلب — أنت في الطريق!',
                  style: TextStyle(fontFamily: 'Cairo')),
            ]),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        Future.delayed(
            const Duration(milliseconds: 300), () => _tabCtrl.animateTo(1));
      }
    } catch (e) {
      closeLoadingDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e
                  .toString()
                  .replaceAll('Exception: ', '')
                  .replaceAll('StateError: ', ''),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  // ══════════════════════════════════════════
  // (الكود الأصلي يبدأ من هنا)
  // ══════════════════════════════════════════
  bool _isHandlingAction = false;

  Future<bool> _handleAction(
      String orderId, String action, String merchantName) async {
    if (_isHandlingAction) return false;
    _isHandlingAction = true;

    try {
      final isPickup = action == 'pick_up';
      final actionLabel = isPickup ? 'استلام من المستودع' : 'تأكيد التسليم';
      final actionColor = isPickup ? Colors.blue : AppColors.primary;
      final confirmMsg = isPickup
          ? 'هل استلمت طلب "$merchantName" من المستودع وأنت في الطريق؟'
          : 'هل تم تسليم طلب "$merchantName" للعميل بنجاح؟';

      final confirm = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPickup
                      ? Icons.inventory_rounded
                      : Icons.check_circle_rounded,
                  color: actionColor,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                actionLabel,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                confirmMsg,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  color: Color(0xFF888888),
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey[300]!),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('إلغاء',
                          style: TextStyle(
                              fontFamily: 'Cairo', color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: Icon(
                          isPickup
                              ? Icons.inventory_rounded
                              : Icons.check_rounded,
                          size: 18),
                      label: Text(actionLabel,
                          style: const TextStyle(fontFamily: 'Cairo')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: actionColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      if (confirm != true || !mounted) return false;

      // ── في حالة التسليم: نطلب التوقيع أولاً قبل أي مؤشر تحميل لمنع الـ Deadlock ──
      if (!isPickup) {
        final currentOrders = ref.read(realtimeMyShippedOrdersProvider);
        final orderMap = currentOrders.firstWhere(
          (o) => o['id'] == orderId,
          orElse: () => <String, dynamic>{},
        );
        String? signatureUrl = orderMap['signature_url'] as String?;

        if (signatureUrl == null || signatureUrl.isEmpty) {
          signatureUrl = await DigitalSignatureDialog.show(
            context,
            orderId: orderId,
            merchantName: merchantName,
          );
        }

        if (signatureUrl == null || signatureUrl.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    '⚠️ تم إلغاء العملية: يجب توقيع التاجر لتأكيد التسليم'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return false;
        }
      }

      // ── إظهار شاشة الانتظار بأمان بعد إغلاق كافة النوافذ ──
      BuildContext? dialogCtx;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) {
          dialogCtx = c;
          return const PopScope(
            canPop: false,
            child: Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
          );
        },
      );

      void dismissDialog() {
        if (dialogCtx != null && Navigator.canPop(dialogCtx!)) {
          Navigator.of(dialogCtx!).pop();
          dialogCtx = null;
        }
      }

      try {
        if (isPickup) {
          await OrdersService.assignOrderToDriver(orderId: orderId)
              .timeout(const Duration(seconds: 10));
        } else {
          final netResults = await Connectivity().checkConnectivity().timeout(
              const Duration(seconds: 2),
              onTimeout: () => [ConnectivityResult.none]);
          final bool isOffline =
              netResults.every((r) => r == ConnectivityResult.none);

          if (isOffline) {
            // حفظ التسليم في الطابور المحلي أولاً وتجنب الكتابة المباشرة غير المتزامنة مع الأرباح
            await AppStorage.savePendingDriverDelivery(orderId);
          } else {
            try {
              await OrdersService.deliverOrderByDriver(orderId: orderId)
                  .timeout(const Duration(seconds: 10));
            } catch (err) {
              final errStr = err.toString().toLowerCase();
              final bool isNetworkIssue = errStr.contains('network') ||
                  errStr.contains('timeout') ||
                  errStr.contains('unavailable') ||
                  errStr.contains('socket');

              if (isNetworkIssue) {
                await AppStorage.savePendingDriverDelivery(orderId);
              } else {
                dismissDialog();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        err
                            .toString()
                            .replaceAll('Exception: ', '')
                            .replaceAll('StateError: ', ''),
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return false;
              }
            }
          }
        }

        dismissDialog();
        HapticFeedback.mediumImpact();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                      isPickup
                          ? Icons.inventory_rounded
                          : Icons.celebration_rounded,
                      color: Colors.white,
                      size: 18),
                  const SizedBox(width: 8),
                  Text(
                    isPickup
                        ? '✅ تم استلام الطلب من المستودع'
                        : '🎉 تم تأكيد التسليم بنجاح',
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ],
              ),
              backgroundColor: actionColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );

          if (isPickup) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) _tabCtrl.animateTo(1);
            });
          }
        }
        return true;
      } catch (e) {
        dismissDialog();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e
                    .toString()
                    .replaceAll('Exception: ', '')
                    .replaceAll('StateError: ', ''),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }
    } finally {
      _isHandlingAction = false;
    }
  }
}

// ══════════════════════════════════════════
// قائمة الطلبات
// ══════════════════════════════════════════
// ══ قائمة الطلبات من Provider (بدون Stream مستقل) ══
class _OrdersListFromProvider extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final IconData emptyIcon;
  final String emptyText;
  final String status;
  final Future<void> Function(String, String, String) onAction;
  final void Function(String, Map<String, dynamic>) onTap;

  const _OrdersListFromProvider({
    required this.orders,
    required this.emptyIcon,
    required this.emptyText,
    required this.status,
    required this.onAction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final docs = orders;

    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(emptyIcon,
                  size: 40, color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 16),
            Text(
              emptyText,
              style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 15, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Text(
              status == 'confirmed'
                  ? 'ستظهر الطلبات هنا فور تأكيدها'
                  : 'الطلبات التي استلمتها ستظهر هنا',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    // ترتيب محلي آمن يدعم Timestamp و DateTime بدون رمي استثناء
    final sorted = List<Map<String, dynamic>>.from(docs)
      ..sort((a, b) {
        DateTime? parse(dynamic v) {
          if (v is Timestamp) return v.toDate();
          if (v is DateTime) return v;
          if (v is String) return DateTime.tryParse(v);
          return null;
        }

        final aTime = parse(a['created_at']);
        final bTime = parse(b['created_at']);
        if (aTime == null || bTime == null) return 0;
        return aTime.compareTo(bTime);
      });
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final data = sorted[index];
        final orderId = data['id'] as String? ?? '';
        return _DriverOrderCard(
          orderId: orderId,
          data: data,
          onAction: onAction,
          onTap: onTap,
        );
      },
    );
  }
}

// ══════════════════════════════════════════
// بطاقة الطلب للسائق
// ══════════════════════════════════════════
class _DriverOrderCard extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> data;
  final Future<void> Function(String, String, String) onAction;
  final void Function(String, Map<String, dynamic>) onTap;

  const _DriverOrderCard({
    required this.orderId,
    required this.data,
    required this.onAction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final merchantName =
        data['merchant_name'] ?? data['customer_name'] ?? 'غير معروف';
    final storeName = data['store_name'] as String?;
    final phone = (data['phone_number'] ?? data['contact']) as String?;
    final address = (data['delivery_address'] ?? data['store_name']) as String?;
    final total = (data['total_amount'] as num?)?.toDouble() ??
        (data['total'] as num?)?.toDouble() ??
        0.0;
    final status = data['status'] as String? ?? '';
    final isConfirmed = status == 'confirmed' || status == 'pending';
    final orderNum = data['order_number'] ?? data['invoice_number'] ?? '';
    final notes = data['notes'] as String?;
    final itemsCount = (data['items_count'] as num?)?.toInt() ?? 0;

    // ── وقت الإنشاء ──
    String timeAgo = '';
    if (data['created_at'] is Timestamp) {
      final dt = (data['created_at'] as Timestamp).toDate();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) {
        timeAgo = 'منذ ${diff.inMinutes} دقيقة';
      } else if (diff.inHours < 24) {
        timeAgo = 'منذ ${diff.inHours} ساعة';
      } else {
        timeAgo = 'منذ ${diff.inDays} يوم';
      }
    }

    return GestureDetector(
      onTap: () => onTap(orderId, data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isConfirmed
                ? Colors.blue.withValues(alpha: 0.2)
                : AppColors.primary.withValues(alpha: 0.2),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: context.shadowColor,
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── شريط الحالة العلوي ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isConfirmed
                    ? Colors.blue.withValues(alpha: 0.06)
                    : AppColors.primary.withValues(alpha: 0.06),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(
                    isConfirmed
                        ? Icons.inventory_2_rounded
                        : Icons.local_shipping_rounded,
                    size: 14,
                    color: isConfirmed ? Colors.blue : AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isConfirmed ? 'جاهز للاستلام' : 'قيد التوصيل',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isConfirmed ? Colors.blue : AppColors.primary,
                    ),
                  ),
                  const Spacer(),
                  if (timeAgo.isNotEmpty)
                    Text(
                      timeAgo,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          color: Colors.grey),
                    ),
                ],
              ),
            ),

            // ── محتوى البطاقة ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── اسم التاجر والمبلغ ──
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              merchantName,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimary,
                              ),
                            ),
                            if (storeName != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                storeName,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${total.toStringAsFixed(0)} ر.ي',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color:
                                  isConfirmed ? Colors.blue : AppColors.primary,
                            ),
                          ),
                          if (orderNum.isNotEmpty)
                            Text(
                              '#$orderNum',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  // ── العنوان ──
                  if (address != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on_rounded,
                            color: Colors.orange, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            address,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: context.textSecondary,
                              height: 1.5,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                  // ── رقم الهاتف ──
                  if (phone != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.phone_rounded,
                            color: Color(0xFF1B8E3D), size: 15),
                        const SizedBox(width: 6),
                        Text(
                          phone,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Color(0xFF1B8E3D),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        // ── زر اتصال سريع ──
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: phone));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('تم نسخ الرقم',
                                    style: TextStyle(fontFamily: 'Cairo')),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B8E3D)
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.copy_rounded,
                                    size: 12, color: Color(0xFF1B8E3D)),
                                SizedBox(width: 3),
                                Text('نسخ',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 10,
                                        color: Color(0xFF1B8E3D),
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // ── ملاحظات ──
                  if (notes != null && notes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.sticky_note_2_outlined,
                              size: 13, color: Colors.amber),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              notes,
                              style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: Color(0xFF92400E)),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── معلومات إضافية ──
                  if (itemsCount > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 13, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          '$itemsCount صنف',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),
                ],
              ),
            ),

            // ── زر السحب للتأكيد ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _SwipeActionButton(
                label: isConfirmed
                    ? '← اسحب لتأكيد الاستلام'
                    : '← اسحب لتأكيد التسليم',
                color: isConfirmed ? Colors.blue : AppColors.primary,
                icon: isConfirmed
                    ? Icons.inventory_rounded
                    : Icons.check_circle_rounded,
                onConfirmed: () => onAction(
                  orderId,
                  isConfirmed ? 'pick_up' : 'deliver',
                  merchantName,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════
// بادج العدد
// ══════════════════════════════════════════
class _Badge extends StatelessWidget {
  final int count;
  final Color color;
  const _Badge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// زر السحب لتأكيد الإجراء
// ══════════════════════════════════════════════════════════
class _SwipeActionButton extends StatefulWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onConfirmed;

  const _SwipeActionButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.onConfirmed,
  });

  @override
  State<_SwipeActionButton> createState() => _SwipeActionButtonState();
}

class _SwipeActionButtonState extends State<_SwipeActionButton> {
  double _dragX = 0;
  bool _confirmed = false;
  static const double _maxDrag = 220;
  static const double _threshold = 0.75;

  void _onDragUpdate(DragUpdateDetails d) {
    if (_confirmed) return;
    setState(() {
      _dragX = (_dragX - d.delta.dx).clamp(0, _maxDrag);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_confirmed) return;
    if (_dragX / _maxDrag >= _threshold) {
      setState(() => _confirmed = true);
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 300), widget.onConfirmed);
    } else {
      setState(() => _dragX = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragX / _maxDrag).clamp(0.0, 1.0);

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.color.withValues(alpha: 0.3)),
      ),
      child: Stack(
        children: [
          // شريط التقدم
          AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            width: _dragX + 52,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          // النص المركزي
          Center(
            child: AnimatedOpacity(
              opacity: 1 - progress,
              duration: const Duration(milliseconds: 100),
              child: Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: widget.color,
                ),
              ),
            ),
          ),
          // المقبض القابل للسحب (من اليمين للشمال)
          Positioned(
            right: _dragX,
            top: 4,
            child: GestureDetector(
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _confirmed ? Colors.green : widget.color,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  _confirmed ? Icons.check_rounded : widget.icon,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
