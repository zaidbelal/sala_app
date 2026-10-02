import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_radius.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../orders/services/orders_service.dart';
import '../../orders/screens/order_status_screen.dart';
import '../providers/cart_provider.dart';
import 'location_picker_screen.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../../core/services/local_storage.dart'; // 🚀 ضروري جداً للوصول إلى AppStorage
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sala/features/auth/login/services/auth_service.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  final String merchantId;
  const CheckoutScreen({super.key, required this.merchantId});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  LatLng? _location;
  String _paymentMethod = 'cash';
  bool _isLoading = false;
  String?
      _orderIdempotencyKey; // ✅ مفتاح التثبيت لمنع تكرار إنشاء الطلب عند إعادة المحاولة

  @override
  void initState() {
    super.initState();
    _prefillMerchantDetails();
  }

  Future<void> _prefillMerchantDetails() async {
    final localName = AppStorage.userName ?? '';
    final localPhone = AppStorage.userPhone ?? '';
    if (localName.isNotEmpty && _nameCtrl.text.isEmpty) {
      _nameCtrl.text = localName;
    }
    if (localPhone.isNotEmpty && _contactCtrl.text.isEmpty) {
      _contactCtrl.text = localPhone.replaceFirst('+967', '0');
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(widget.merchantId)
          .get();
      if (!mounted || !doc.exists || doc.data() == null) return;
      final data = doc.data()!;

      setState(() {
        if (_storeCtrl.text.isEmpty) {
          _storeCtrl.text = data['store_name']?.toString() ?? '';
        }
        if (_nameCtrl.text.isEmpty) {
          _nameCtrl.text = data['full_name']?.toString() ?? '';
        }
        if (_contactCtrl.text.isEmpty) {
          final phone = data['phone_number']?.toString() ?? '';
          _contactCtrl.text = phone.replaceFirst('+967', '0');
        }
        if (_location == null) {
          final lat = (data['latitude'] as num?)?.toDouble();
          final lng = (data['longitude'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            _location = LatLng(lat, lng);
          }
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CheckoutScreen] failed to prefill profile data: $e');
      }
    }
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );
    if (result != null) setState(() => _location = result);
  }

  // ─── يعرض dialog تحميل فوق كل شيء ───
  BuildContext? _loadingDialogContext;

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (dialogCtx) {
        _loadingDialogContext = dialogCtx;
        return PopScope(
          canPop: false,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 30),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text('جاري إرسال الطلب...',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.none,
                          color: dialogCtx.textPrimary)),
                  const SizedBox(height: 6),
                  Text('يرجى الانتظار',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          decoration: TextDecoration.none,
                          color: Colors.grey[500])),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isPlacingOrder = false;

  Future<void> _placeOrder() async {
    if (_isPlacingOrder) return;
    _isPlacingOrder = true;
    try {
      await _placeOrderInternal();
    } finally {
      if (mounted) {
        setState(() => _isPlacingOrder = false);
      } else {
        _isPlacingOrder = false;
      }
    }
  }

  Future<void> _placeOrderInternal() async {
    // ── 1. التحقق من السلة ──
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      _showError('السلة فارغة، أضف منتجات أولاً');
      return;
    }
    if (cart.length > AppConfig.maxOrderItems) {
      _showError(
          'عذراً، لا يمكن أن يحتوي الطلب الواحد على أكثر من ${AppConfig.maxOrderItems} صنفاً مختلفاً. يرجى تقسيم الطلب.');
      return;
    }
    // ── 2. التحقق من الحد الأدنى للطلب ──
    const double minOrderLimit = AppConfig.minOrderValue;
    final total = ref.read(cartTotalProvider);
    if (total < minOrderLimit) {
      _showError(
          'الحد الأدنى للطلب هو ${minOrderLimit.toStringAsFixed(0)} ر.ي');
      return;
    }

    // ── 3. فحص طريقة الدفع ──
    if (_paymentMethod == 'deferred') {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.schedule_rounded,
              color: Colors.orange, size: 40),
          title: const Text('قريباً',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
          content: const Text(
            'سيتم العمل بنظام الدفع الآجل قريباً\nالتطبيق يعمل حالياً بالدفع النقدي فقط',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _paymentMethod = 'cash');
              },
              child: const Text('التحويل للدفع النقدي',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      return;
    }

    // ── 4. التحقق الصارم من كافة المدخلات والموقع قبل إظهار أي نافذة لمنع الـ Deadlock ──
    if (!_formKey.currentState!.validate()) return;

    if (_location == null) {
      _showError('يرجى تحديد موقع التوصيل');
      return;
    }
    final cleanContact = _contactCtrl.text.trim();
    if (cleanContact.isEmpty || cleanContact.length < 9) {
      _showError('يرجى إدخال رقم هاتف صحيح للتواصل (9 أرقام على الأقل)');
      return;
    }

    final String normalizedPhone;
    try {
      normalizedPhone = AuthService.formatPhone(cleanContact);
    } catch (e) {
      _showError('صيغة رقم الهاتف غير صحيحة، تأكد من إدخال 9 أرقام تبدأ بـ 7');
      return;
    }

    // ── 5. إغلاق لوحة المفاتيح وبدء حالة التحميل ──
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    HapticFeedback.heavyImpact();

    _showLoadingDialog();

    final String merchantId = widget.merchantId;
    final List<Map<String, dynamic>> itemsList = cart.values
        .map((e) => <String, dynamic>{
              'product_id': e.product.id,
              'product_name': e.product.name,
              'quantity': e.quantity,
              'price': e.unitPrice,
              if (e.selectedUnit != null) ...{
                'unit_label': e.selectedUnit!.label,
                'unit_qty': e.selectedUnit!.qty,
              },
            })
        .toList();

    final String? notesString =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    final Map<String, dynamic> extraDataMap = {
      'store_name': _storeCtrl.text.trim(),
      'customer_name': _nameCtrl.text.trim(),
      'merchant_name': _nameCtrl.text.trim(),
      'contact': normalizedPhone,
      'phone_number': normalizedPhone,
      'delivery_address': _storeCtrl.text.trim(),
      'latitude': _location!.latitude,
      'longitude': _location!.longitude,
      'payment_method': _paymentMethod,
    };
    _orderIdempotencyKey ??=
        FirebaseFirestore.instance.collection('orders').doc().id;
    final String generatedOrderId = _orderIdempotencyKey!;

    final orderData = {
      'orderId': generatedOrderId,
      'merchantId': merchantId,
      'expectedTotal': total,
      'items': itemsList,
      'notes': notesString,
      'extraData': extraDataMap,
    };

    void safeDismissLoading() {
      if (_loadingDialogContext != null &&
          Navigator.canPop(_loadingDialogContext!)) {
        Navigator.of(_loadingDialogContext!).pop();
        _loadingDialogContext = null;
      }
    }

    bool isOffline = false;
    try {
      final netResults = await Connectivity().checkConnectivity();
      isOffline = netResults.every((r) => r == ConnectivityResult.none);
    } catch (_) {
      isOffline = false;
    }
    if (isOffline) {
      await AppStorage.savePendingOrder(orderData);
      ref.read(cartProvider.notifier).clear();
      _orderIdempotencyKey = null;

      if (!mounted) return;
      safeDismissLoading();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [
          Icon(Icons.cloud_done_rounded, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Expanded(
              child: Text(
                  'أنت غير متصل بالإنترنت، تم حفظ طلبك بأمان وسيتم إرساله تلقائياً فور عودة الشبكة 📡',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.w700))),
        ]),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ));

      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      return;
    }

    try {
      final order = await OrdersService.placeOrder(
        merchantId: merchantId,
        items: itemsList,
        expectedTotal: total,
        notes: notesString,
        extraData: extraDataMap,
        orderId: generatedOrderId,
      ).timeout(const Duration(seconds: 30));
      _orderIdempotencyKey = null;
      ref.read(cartProvider.notifier).clear();

      if (!mounted) return;
      safeDismissLoading();

      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => OrderStatusScreen(order: order),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
            child: child,
          ),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      safeDismissLoading();

      final errorStr = e.toString().toLowerCase();
      final isNetworkError = errorStr.contains('network') ||
          errorStr.contains('unavailable') ||
          errorStr.contains('unknown') ||
          errorStr.contains('timeout') ||
          errorStr.contains('socket') ||
          errorStr.contains('deadline-exceeded');

      if (isNetworkError) {
        await AppStorage.savePendingOrder(orderData);
        ref.read(cartProvider.notifier).clear();
        _orderIdempotencyKey = null;

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.cloud_done_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
                child: Text(
                    'تعذر الاتصال بالخادم، تم حفظ طلبك وسيتم إرساله تلقائياً فور توفر الشبكة 📡',
                    style: TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.w700))),
          ]),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ));

        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        return;
      }
      HapticFeedback.vibrate();
      _orderIdempotencyKey = null;
      final cleanError = e
          .toString()
          .replaceAll('Exception: ', '')
          .replaceAll('StateError: ', '')
          .replaceAll('ArgumentError: ', '');

      _showError(cleanError.isNotEmpty
          ? cleanError
          : 'فشل إرسال الطلب، تأكد من صحة البيانات والمخزون');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(fontFamily: 'Cairo'))),
      ]),
      backgroundColor: Colors.red[700],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);

    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header ───
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: context.bgCard,
                        borderRadius: AppRadius.mdAll,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.07),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child:
                          const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تأكيد الطلب',
                          style: AppTextStyles.headlineMedium.copyWith(
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          )),
                      Text(
                        '${cart.length} منتج — ${total.toStringAsFixed(0)} ر.ي',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle(
                          title: 'بيانات العميل', icon: Icons.person_rounded),
                      const SizedBox(height: 12),
                      _FormField(
                        controller: _storeCtrl,
                        label: 'اسم البقالة / المحل',
                        hint: 'مثال: بقالة النور',
                        icon: Icons.storefront_rounded,
                      ),
                      const SizedBox(height: 12),
                      _FormField(
                        controller: _nameCtrl,
                        label: 'اسم العميل',
                        hint: 'الاسم الكامل',
                        icon: Icons.badge_rounded,
                      ),
                      const SizedBox(height: 12),
                      _FormField(
                        controller: _contactCtrl,
                        label: 'رقم التواصل',
                        hint: '7XXXXXXXX',
                        icon: Icons.phone_rounded,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'مطلوب';
                          if (v.length < 9) return 'رقم غير صحيح';
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      const _SectionTitle(
                          title: 'موقع التوصيل',
                          icon: Icons.location_on_rounded),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _pickLocation,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.bgCard,
                            borderRadius: AppRadius.lgAll,
                            border: Border.all(
                              color: _location == null
                                  ? context.borderColor
                                  : AppColors.primary,
                              width: _location == null ? 1 : 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: context.shadowColor,
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _location == null
                                      ? const Color(0xFFF0F0F0)
                                      : AppColors.primary
                                          .withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _location == null
                                      ? Icons.add_location_rounded
                                      : Icons.location_on_rounded,
                                  color: _location == null
                                      ? Colors.grey[400]
                                      : AppColors.primary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _location == null
                                          ? 'تحديد موقع التوصيل'
                                          : 'تم تحديد الموقع ✓',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: _location == null
                                            ? Colors.grey[600]
                                            : AppColors.primary,
                                      ),
                                    ),
                                    Text(
                                      _location == null
                                          ? 'GPS أو اختيار يدوي على الخريطة *'
                                          : '${_location!.latitude.toStringAsFixed(4)}, ${_location!.longitude.toStringAsFixed(4)}',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios_rounded,
                                  size: 14, color: context.textHint),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const _SectionTitle(
                          title: 'ملاحظات (اختياري)',
                          icon: Icons.notes_rounded),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: context.bgCard,
                          borderRadius: AppRadius.lgAll,
                          boxShadow: [
                            BoxShadow(
                              color: context.shadowColor,
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _notesCtrl,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14,
                              color: context.textPrimary),
                          decoration: InputDecoration(
                            hintText:
                                'مثال: أرسل بعد العصر\nالتوصيل للباب الخلفي',
                            hintStyle: TextStyle(
                                fontFamily: 'Cairo',
                                color: context.textHint,
                                fontSize: 13),
                            border: const OutlineInputBorder(
                              borderRadius: AppRadius.lgAll,
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                          maxLines: 3,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const _SectionTitle(
                          title: 'طريقة الدفع', icon: Icons.payments_rounded),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber[50],
                          borderRadius: AppRadius.mdAll,
                          border: Border.all(color: Colors.amber[200]!),
                        ),
                        child: Row(children: [
                          Icon(Icons.info_outline_rounded,
                              size: 15, color: Colors.amber[800]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'التطبيق يعمل بالدفع النقدي فقط',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: Colors.amber[900]),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 10),
                      _PaymentOption(
                        value: 'cash',
                        groupValue: _paymentMethod,
                        label: 'نقداً عند الاستلام',
                        subtitle: 'ادفع عند وصول الطلب',
                        icon: Icons.payments_outlined,
                        onChanged: (v) => setState(() => _paymentMethod = v!),
                      ),
                      const SizedBox(height: 8),
                      Opacity(
                        opacity: 0.45,
                        child: AbsorbPointer(
                          child: _PaymentOption(
                            value: 'deferred',
                            groupValue: _paymentMethod,
                            label: 'الدفع الآجل (قريباً)',
                            subtitle: 'سيتوفر في تحديث قادم',
                            icon: Icons.schedule_rounded,
                            onChanged: (_) {},
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),

            // ─── Bottom Bar ───
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: BoxDecoration(
                color: context.bgCard,
                boxShadow: [
                  BoxShadow(
                    color: context.shadowColor,
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        side: BorderSide(color: context.borderColor),
                        shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll),
                      ),
                      child: const Text('إلغاء',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w600,
                              color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _placeOrder,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send_rounded, size: 20),
                                SizedBox(width: 8),
                                Text('إتمام الطلب',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800)),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════
class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: AppColors.primary),
      const SizedBox(width: 8),
      Text(
        title,
        style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: context.textPrimary),
      ),
    ]);
  }
}

// ════════════════════════════════
class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      textDirection: TextDirection.rtl,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 14,
        color: context.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      validator: validator ??
          (v) {
            if (v == null || v.trim().isEmpty) return 'هذا الحقل مطلوب';
            return null;
          },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
            fontFamily: 'Cairo', color: context.textSecondary, fontSize: 13),
        hintStyle: TextStyle(
            fontFamily: 'Cairo', color: context.textHint, fontSize: 13),
        prefixIcon: Icon(icon, color: context.iconSecondary, size: 20),
        filled: true,
        fillColor: context.bgInput,
        border: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Color(0xFFEEEEEE)),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Color(0xFFEEEEEE)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Colors.red),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final String value;
  final String groupValue;
  final String label;
  final String subtitle;
  final IconData icon;
  final ValueChanged<String?> onChanged;

  const _PaymentOption({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : context.bgCard, // 👈 متكيف تلقائياً مع خلفية الوضع الداكن
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: isSelected ? AppColors.primary : context.borderColor,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : context.bgInput,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 18,
                  color:
                      isSelected ? AppColors.primary : context.iconSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isSelected
                              ? AppColors.primary
                              : context.textPrimary)), // 👈 نص أبيض وواضح
                  Text(subtitle,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color:
                              context.textSecondary)), // 👈 نص ثانوي رمادي فاتح
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected ? AppColors.primary : context.borderColor,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      size: 13, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
