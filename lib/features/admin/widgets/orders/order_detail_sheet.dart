import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/widgets/app_map.dart';
import '../../../../../core/widgets/signature_pad_dialog.dart';
import '../../services/admin_service.dart';
import 'order_widgets.dart';
import 'return_sheet.dart';
import 'thermal_print_sheet.dart';
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sala/core/services/local_storage.dart';

class OrderDetailSheet extends ConsumerStatefulWidget {
  final AdminOrder order;
  final VoidCallback onStatusChanged;
  const OrderDetailSheet(
      {super.key, required this.order, required this.onStatusChanged});

  @override
  ConsumerState<OrderDetailSheet> createState() => _OrderDetailSheetState();
}

class _OrderDetailSheetState extends ConsumerState<OrderDetailSheet> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _returns = [];
  bool _itemsLoading = true;
  bool _returnsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final service = ref.read(adminServiceProvider);
    final results = await Future.wait([
      service.getOrderItems(widget.order.id),
      service.getOrderReturns(widget.order.id),
    ]);
    if (mounted) {
      setState(() {
        _items = results[0];
        _itemsLoading = false;
        _returns = results[1];
        _returnsLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 استماع فوري ومباشر للأدمن لمتابعة توقيع السائق وتغيير الحالة لحظياً
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.order.id)
          .snapshots(),
      builder: (context, snapshot) {
        final currentOrderData = (snapshot.hasData &&
                snapshot.data!.exists &&
                snapshot.data!.data() != null)
            ? AdminOrder.fromMap(
                {'id': snapshot.data!.id, ...snapshot.data!.data()!})
            : widget.order;

        final order = currentOrderData;
        final color = OrderStatusHelper.color(order.status);
        final label = OrderStatusHelper.label(order.status);

        return DraggableScrollableSheet(
            initialChildSize: 0.88,
            maxChildSize: 0.96,
            minChildSize: 0.5,
            builder: (_, scrollCtrl) => Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F7FA),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      // مقبض
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2)),
                      ),
                      // رأس الشيت
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  order.storeName ?? order.merchantName,
                                  style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1A1A2E)),
                                ),
                                if (order.orderNumber != null)
                                  Text('رقم الطلب: ${order.orderNumber}',
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 12,
                                          color: Colors.grey[500])),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: color.withValues(alpha: 0.25)),
                            ),
                            child: Text(label,
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: color)),
                          ),
                        ]),
                      ),
                      // المحتوى
                      Expanded(
                        child: ListView(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          children: [
                            // ── معلومات التاجر ──
                            OrderSection(
                              title: 'معلومات التاجر',
                              icon: Icons.person_rounded,
                              child: Column(children: [
                                OrderInfoRow(
                                    label: 'الاسم', value: order.merchantName),
                                if (order.storeName != null)
                                  OrderInfoRow(
                                      label: 'المتجر', value: order.storeName!),
                                if (order.phoneNumber != null)
                                  OrderInfoRow(
                                      label: 'الهاتف',
                                      value: order.phoneNumber!,
                                      icon: Icons.phone_rounded,
                                      iconColor: AppColors.primary),
                                if (order.latitude != null &&
                                    order.longitude != null)
                                  _LocationRow(
                                    latitude: order.latitude!,
                                    longitude: order.longitude!,
                                    merchantName:
                                        order.storeName ?? order.merchantName,
                                  ),
                              ]),
                            ),
                            const SizedBox(height: 12),

                            // ── تفاصيل الطلب ──
                            OrderSection(
                              title: 'تفاصيل الطلب',
                              icon: Icons.receipt_rounded,
                              child: Column(children: [
                                OrderInfoRow(
                                    label: 'الدفع',
                                    value: OrderStatusHelper.payment(
                                        order.paymentMethod)),
                                OrderInfoRow(
                                    label: 'المجموع',
                                    value:
                                        '${order.total.toStringAsFixed(0)} ر.ي'),
                                OrderInfoRow(
                                  label: 'التاريخ',
                                  value:
                                      '${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}  ${order.createdAt.hour}:${order.createdAt.minute.toString().padLeft(2, '0')}',
                                ),
                                if (order.notes != null &&
                                    order.notes!.isNotEmpty)
                                  OrderInfoRow(
                                      label: 'ملاحظات',
                                      value: order.notes!,
                                      icon: Icons.notes_rounded,
                                      iconColor: Colors.orange),
                              ]),
                            ),
                            const SizedBox(height: 12),

                            // ── كارت التوقيع الرقمي المعتمد للمدير فور وصوله ──
                            if (order.signatureUrl != null &&
                                order.signatureUrl!.isNotEmpty) ...[
                              OrderSection(
                                title: 'توقيع المستلم المعتمد ✓',
                                icon: Icons.draw_rounded,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'تم توقيع الفاتورة من قِبل:\n${order.storeName ?? order.merchantName}',
                                        style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Container(
                                      height: 60,
                                      width: 120,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: order.signatureUrl!
                                                .startsWith('data:image')
                                            ? Builder(
                                                builder: (_) {
                                                  try {
                                                    final raw = order
                                                        .signatureUrl!
                                                        .split(',')
                                                        .last
                                                        .trim();
                                                    final bytes =
                                                        base64Decode(raw);
                                                    return Image.memory(
                                                      bytes,
                                                      fit: BoxFit.contain,
                                                      errorBuilder:
                                                          (_, __, ___) =>
                                                              const SizedBox
                                                                  .shrink(),
                                                    );
                                                  } catch (_) {
                                                    return const SizedBox
                                                        .shrink();
                                                  }
                                                },
                                              )
                                            : Image.network(
                                                order.signatureUrl!,
                                                fit: BoxFit.contain,
                                                errorBuilder: (_, __, ___) =>
                                                    const SizedBox.shrink(),
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],

                            // ── المنتجات ──
                            OrderSection(
                              title: 'المنتجات',
                              icon: Icons.inventory_2_rounded,
                              child: _itemsLoading
                                  ? const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Center(
                                          child: CircularProgressIndicator(
                                              color: AppColors.primary,
                                              strokeWidth: 2)),
                                    )
                                  : _items.isEmpty
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Center(
                                            child: Text('لا توجد منتجات',
                                                style: TextStyle(
                                                    fontFamily: 'Cairo',
                                                    color: Colors.grey)),
                                          ),
                                        )
                                      : Column(
                                          children:
                                              _items.asMap().entries.map((e) {
                                            final i = e.key;
                                            final item = e.value;
                                            final rawName =
                                                item['product_name'] ?? 'منتج';
                                            final unitLabel = item['unit_label']
                                                    ?.toString()
                                                    .trim() ??
                                                'كرتون';
                                            final name = unitLabel.isNotEmpty
                                                ? '$rawName ($unitLabel)'
                                                : rawName;
                                            final totalQty =
                                                (item['quantity'] as num?)
                                                        ?.toInt() ??
                                                    0;
                                            final returnedQty =
                                                (item['returned_quantity']
                                                            as num?)
                                                        ?.toInt() ??
                                                    0;
                                            final netQty =
                                                (totalQty - returnedQty)
                                                    .clamp(0, totalQty);
                                            final price =
                                                (item['price'] as num?)
                                                        ?.toDouble() ??
                                                    0;
                                            final subtotal = netQty * price;

                                            return Column(children: [
                                              if (i > 0)
                                                const Divider(height: 1),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 10),
                                                child: Row(children: [
                                                  Container(
                                                    width: 36,
                                                    height: 36,
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primary
                                                          .withValues(
                                                              alpha: 0.08),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                    child: Center(
                                                      child: Text('$netQty',
                                                          style: const TextStyle(
                                                              fontFamily:
                                                                  'Cairo',
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: AppColors
                                                                  .primary)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(name,
                                                            style: const TextStyle(
                                                                fontFamily:
                                                                    'Cairo',
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700)),
                                                        Row(
                                                          children: [
                                                            Text(
                                                                '${price.toStringAsFixed(0)} ر.ي / $unitLabel',
                                                                style: TextStyle(
                                                                    fontFamily:
                                                                        'Cairo',
                                                                    fontSize:
                                                                        11,
                                                                    color: Colors
                                                                            .grey[
                                                                        500])),
                                                            if (returnedQty >
                                                                0) ...[
                                                              const SizedBox(
                                                                  width: 6),
                                                              Text(
                                                                '(مرتجع: $returnedQty)',
                                                                style: const TextStyle(
                                                                    fontFamily:
                                                                        'Cairo',
                                                                    fontSize:
                                                                        11,
                                                                    color: Colors
                                                                        .red,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700),
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.end,
                                                    children: [
                                                      Text(
                                                          '${subtotal.toStringAsFixed(0)} ر.ي',
                                                          style: TextStyle(
                                                              fontFamily:
                                                                  'Cairo',
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: Colors
                                                                  .grey[800])),
                                                      if (returnedQty > 0)
                                                        const Text(
                                                          'الصافي',
                                                          style: TextStyle(
                                                              fontFamily:
                                                                  'Cairo',
                                                              fontSize: 9,
                                                              color:
                                                                  Colors.grey),
                                                        ),
                                                    ],
                                                  ),
                                                ]),
                                              ),
                                            ]);
                                          }).toList(),
                                        ),
                            ),
                            const SizedBox(height: 12),

                            // ── طلبات الإرجاع ──
                            if (_returnsLoading)
                              const Center(
                                  child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                    color: AppColors.primary, strokeWidth: 2),
                              ))
                            else if (_returns.isNotEmpty)
                              OrderSection(
                                title: 'طلبات الإرجاع (${_returns.length})',
                                icon: Icons.assignment_return_rounded,
                                child: Column(
                                  children:
                                      _returns.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final item = entry.value;

                                    final productName = item['product_name']
                                                ?.toString()
                                                .trim()
                                                .isNotEmpty ==
                                            true
                                        ? item['product_name'].toString()
                                        : 'منتج غير معروف';

                                    final quantity =
                                        (item['quantity'] as num?)?.toInt() ??
                                            0;

                                    final status =
                                        item['status']?.toString() ?? 'pending';

                                    final reason =
                                        item['reason']?.toString().trim() ?? '';

                                    return Column(
                                      children: [
                                        if (index > 0) const Divider(height: 1),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Icon(
                                                Icons.assignment_return_rounded,
                                                size: 20,
                                                color: AppColors.primary,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      productName,
                                                      style: const TextStyle(
                                                        fontFamily: 'Cairo',
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      'الكمية: $quantity',
                                                      style: TextStyle(
                                                        fontFamily: 'Cairo',
                                                        fontSize: 11,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                    if (reason.isNotEmpty) ...[
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        'السبب: $reason',
                                                        style: TextStyle(
                                                          fontFamily: 'Cairo',
                                                          fontSize: 11,
                                                          color:
                                                              Colors.grey[600],
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                status == 'accepted'
                                                    ? 'مقبول'
                                                    : status == 'rejected'
                                                        ? 'مرفوض'
                                                        : 'قيد المراجعة',
                                                style: const TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),

                            const SizedBox(height: 16),

                            // ── أزرار الحالة والإجراءات ──
                            _ActionButtons(
                              order: order,
                              items: _items,
                              returns: _returns,
                              onDone: () {
                                widget.onStatusChanged();
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ));
      },
    );
  }
}

// ══════════════════════════════════════════
// زر وعرض موقع التوصيل بنفس خريطة التاجر الموحدة
// ══════════════════════════════════════════
class _LocationRow extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String merchantName;

  const _LocationRow({
    required this.latitude,
    required this.longitude,
    required this.merchantName,
  });

  void _openMap(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.location_on_rounded,
                      color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'موقع $merchantName',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AppMap(
                initialLocation: LatLng(latitude, longitude),
                defaultCenter: LatLng(latitude, longitude),
                initialZoom: 16.5,
                title: 'موقع التوصيل',
                markerLabel: 'موقع التوصيل: $merchantName',
                allowPick: false,
                showSearch: true,
                showCurrentLocation: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        onTap: () => _openMap(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'موقع التوصيل',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      'اضغط لعرض موقع المحل بدقة على الخريطة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'عرض الخريطة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── أزرار الإجراءات والطباعة والتوقيع ──
class _ActionButtons extends ConsumerWidget {
  final AdminOrder order;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> returns;
  final VoidCallback onDone;

  const _ActionButtons({
    required this.order,
    required this.items,
    this.returns = const [],
    required this.onDone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(adminServiceProvider);

    Future<void> changeStatus(String newStatus) async {
      try {
        await service.updateOrderStatus(order.id, newStatus);
        if (context.mounted) {
          onDone();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم تحديث حالة الطلب',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: StadiumBorder(),
            margin: EdgeInsets.all(16),
          ));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString(),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: const StadiumBorder(),
            margin: const EdgeInsets.all(16),
          ));
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // ── زر طباعة الفاتورة الحرارية (ESC/POS Bluetooth) ──
            _ActionBtn(
              label: 'طباعة إيصال حراري 🖨️',
              icon: Icons.print_rounded,
              color: const Color(0xFF0F172A),
              onTap: () {
                ThermalPrintPreviewSheet.show(
                  context,
                  order: order,
                  items: items,
                  signatureUrl: order.signatureUrl,
                );
              },
            ),

            // ── زر التوقيع الرقمي للمستلم ──
            _ActionBtn(
              label: 'أخذ توقيع المستلم ✍️',
              icon: Icons.draw_rounded,
              color: const Color(0xFF6366F1),
              onTap: () async {
                final signatureUrl = await DigitalSignatureDialog.show(
                  context,
                  orderId: order.id,
                  merchantName: order.storeName ?? order.merchantName,
                );
                if (signatureUrl != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('✅ تم حفظ التوقيع الرقمي بنجاح في الفاتورة'),
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),

            // ── أزرار تغيير الحالة ──
            if (order.status == 'pending') ...[
              _ActionBtn(
                  label: 'قبول الطلب',
                  icon: Icons.check_circle_rounded,
                  color: AppColors.primary,
                  onTap: () => changeStatus('confirmed')),
              _ActionBtn(
                  label: 'رفض الطلب',
                  icon: Icons.cancel_rounded,
                  color: Colors.red,
                  onTap: () => changeStatus('cancelled')),
            ],
            if (order.status == 'confirmed' || order.status == 'pending') ...[
              _ActionBtn(
                label: 'تأكيد التسليم مباشرة (المدير)',
                icon: Icons.done_all_rounded,
                color: AppColors.primary,
                onTap: () => changeStatus('delivered'),
              ),
              _ActionBtn(
                label: 'بدء التوصيل بنفسك',
                icon: Icons.local_shipping_rounded,
                color: Colors.blue,
                onTap: () async {
                  final adminUid = AppStorage.userId ?? '';
                  final adminName = AppStorage.userName ?? 'الإدارة';
                  try {
                    await service.updateOrderStatus(
                      order.id,
                      'shipped',
                      driverId: adminUid,
                      driverName: adminName,
                    );
                    if (context.mounted) {
                      onDone();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم استلام الطلب وبدء التوصيل بنجاح 🚚',
                              style: TextStyle(fontFamily: 'Cairo')),
                          backgroundColor: AppColors.primary,
                          behavior: SnackBarBehavior.floating,
                          shape: StadiumBorder(),
                          margin: EdgeInsets.all(16),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e.toString(),
                              style: const TextStyle(
                                  fontFamily: 'Cairo', fontSize: 11)),
                          backgroundColor: Colors.red,
                          behavior: SnackBarBehavior.floating,
                          shape: const StadiumBorder(),
                          margin: const EdgeInsets.all(16),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
            if (order.status == 'shipped')
              _ActionBtn(
                  label: 'تأكيد التسليم',
                  icon: Icons.done_all_rounded,
                  color: AppColors.primary,
                  onTap: () => changeStatus('delivered')),
            if (order.status == 'return_requested') ...[
              _ActionBtn(
                label: 'قبول المرتجع وتسويته ✓',
                icon: Icons.assignment_turned_in_rounded,
                color: const Color(0xFFEA580C),
                onTap: () async {
                  try {
                    final pendingReturns =
                        returns.where((r) => r['status'] == 'pending').toList();
                    if (pendingReturns.isEmpty) {
                      await service.updateOrderStatus(order.id, 'returned');
                    } else {
                      for (final ret in pendingReturns) {
                        await service.updateReturnStatus(
                            ret['id']?.toString() ?? '', 'accepted');
                      }
                    }
                    if (context.mounted) {
                      onDone();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'تم قبول المرتجع وتسويته واستعادة المخزون بنجاح ✓',
                            style: TextStyle(fontFamily: 'Cairo')),
                        backgroundColor: Color(0xFFEA580C),
                        behavior: SnackBarBehavior.floating,
                        shape: StadiumBorder(),
                        margin: EdgeInsets.all(16),
                      ));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(e.toString(),
                            style: const TextStyle(
                                fontFamily: 'Cairo', fontSize: 11)),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                        shape: const StadiumBorder(),
                        margin: EdgeInsets.all(16),
                      ));
                    }
                  }
                },
              ),
              _ActionBtn(
                label: 'رفض طلب الإرجاع ✗',
                icon: Icons.cancel_rounded,
                color: Colors.red,
                onTap: () async {
                  try {
                    final pendingReturns =
                        returns.where((r) => r['status'] == 'pending').toList();
                    if (pendingReturns.isEmpty) {
                      await service.updateOrderStatus(order.id, 'delivered');
                    } else {
                      for (final ret in pendingReturns) {
                        await service.updateReturnStatus(
                            ret['id']?.toString() ?? '', 'rejected',
                            rejectionReason: 'تم الرفض من الإدارة');
                      }
                    }
                    if (context.mounted) {
                      onDone();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('تم رفض طلب الإرجاع',
                            style: TextStyle(fontFamily: 'Cairo')),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                        shape: StadiumBorder(),
                        margin: EdgeInsets.all(16),
                      ));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(e.toString(),
                            style: const TextStyle(
                                fontFamily: 'Cairo', fontSize: 11)),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                        shape: const StadiumBorder(),
                        margin: EdgeInsets.all(16),
                      ));
                    }
                  }
                },
              ),
            ],
            if (order.status == 'delivered')
              _ActionBtn(
                  label: 'تسجيل ارجاع',
                  icon: Icons.assignment_return_rounded,
                  color: const Color(0xFFEA580C),
                  onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => ReturnSheet(
                          order: order,
                          service: service,
                          onDone: onDone,
                        ),
                      )),
          ],
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ],
        ),
      ),
    );
  }
}
