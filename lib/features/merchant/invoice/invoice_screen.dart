import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../orders/models/order_model.dart';
import 'package:gal/gal.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

Color _statusColorFromEnum(OrderStatus s) => switch (s) {
      OrderStatus.delivered => const Color(0xFF10B981),
      OrderStatus.pending => const Color(0xFFF59E0B),
      OrderStatus.accepted || OrderStatus.preparing => const Color(0xFF3B82F6),
      OrderStatus.onTheWay => const Color(0xFF8B5CF6),
      OrderStatus.cancelled || OrderStatus.rejected => const Color(0xFFEF4444),
      OrderStatus.returned ||
      OrderStatus.returnRequested =>
        const Color(0xFFEC4899),
    };

class InvoiceScreen extends StatefulWidget {
  final OrderModel order;
  const InvoiceScreen({super.key, required this.order});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _saving = false;
  final _repaintKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('order_items')
          .where('order_id', isEqualTo: widget.order.id)
          .get();
      if (mounted) {
        setState(() {
          _items = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّر تحميل تفاصيل الطلب، تحقق من الاتصال',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: StadiumBorder(),
          margin: EdgeInsets.all(16),
        ));
      }
    }
  }

  Future<void> _shareAsImage() async {
    setState(() => _saving = true);
    try {
      final repaintContext = _repaintKey.currentContext;
      if (repaintContext == null) return;
      final boundary =
          repaintContext.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || !boundary.attached) return;

      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(milliseconds: 600),
        onTimeout: () => null,
      );

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return;

      final bytes = byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
      final shortId = widget.order.id.length >= 8
          ? widget.order.id.substring(0, 8)
          : widget.order.id;
      final fileName = 'فاتورة_${widget.order.invoiceNumber ?? shortId}.png';
      final xFile =
          XFile.fromData(bytes, mimeType: 'image/png', name: fileName);
      await Share.shareXFiles([xFile], text: 'فاتورة سَلة');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّرت المشاركة، حاول مجدداً',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: StadiumBorder(),
          margin: EdgeInsets.all(16),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _downloadImage() async {
    setState(() => _saving = true);
    try {
      final ctx = _repaintKey.currentContext;
      if (ctx == null) return;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || !boundary.attached) return;

      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(milliseconds: 600),
        onTimeout: () => null,
      );

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return;

      final bytes = byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);

      await Gal.putImageBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم حفظ الصورة في المعرض ✅',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: StadiumBorder(),
          margin: EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّر التحميل، تحقق من صلاحية المعرض',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: StadiumBorder(),
          margin: EdgeInsets.all(16),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 استماع فوري لمستند الطلب في الفاتورة لظهور التوقيع وتحديث الحالة لحظياً
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.order.id)
          .snapshots(),
      builder: (context, snapshot) {
        final liveOrder = (snapshot.hasData &&
                snapshot.data!.exists &&
                snapshot.data!.data() != null)
            ? OrderModel.fromJson(
                {'id': snapshot.data!.id, ...snapshot.data!.data()!})
            : widget.order;

        final order = liveOrder;
        final date =
            '${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}';
        final time =
            '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';

        return Scaffold(
            backgroundColor: context.bgPage,
            body: SafeArea(
                child: Column(
              children: [
                // ── شريط علوي ──
                Container(
                  color: context.bgHeader,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.bgInput,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.arrow_back_ios_new_rounded,
                              size: 16, color: context.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('الفاتورة',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: context.textPrimary)),
                      ),
                      if (!_saving)
                        IconButton(
                          onPressed: _saving ? null : _downloadImage,
                          icon: const Icon(Icons.download_rounded,
                              color: AppColors.primary),
                          tooltip: 'تحميل كصورة',
                        ),
                      GestureDetector(
                        onTap: _saving ? null : _shareAsImage,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : const Row(
                                  children: [
                                    Icon(Icons.share_rounded,
                                        color: Colors.white, size: 16),
                                    SizedBox(width: 6),
                                    Text('مشاركة',
                                        style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white)),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── المحتوى ──
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary))
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                          child: RepaintBoundary(
                            key: _repaintKey,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 20,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  _InvoiceHeader(
                                      order: order, date: date, time: time),
                                  const Divider(height: 1),
                                  _MerchantInfo(order: order),
                                  const Divider(
                                      height: 1, color: Color(0xFFF0F0F0)),
                                  _ItemsTable(items: _items),
                                  const Divider(
                                      height: 1, color: Color(0xFFF0F0F0)),
                                  _TotalSection(order: order),

                                  // ── قسم التوقيع الرقمي المعتمد ──
                                  if (order.signatureUrl != null &&
                                      order.signatureUrl!.isNotEmpty) ...[
                                    const Divider(
                                        height: 1, color: Color(0xFFF0F0F0)),
                                    _SignatureSection(
                                        signatureUrl: order.signatureUrl!,
                                        signerName: order.storeName ??
                                            order.customerName ??
                                            'التاجر المستلم'),
                                  ],

                                  _InvoiceFooter(),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            )));
      },
    );
  }
}

// ════════════════════════════════════════════════════════
// رأس الفاتورة
// ════════════════════════════════════════════════════════
class _InvoiceHeader extends StatelessWidget {
  final OrderModel order;
  final String date;
  final String time;
  const _InvoiceHeader(
      {required this.order, required this.date, required this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F8EE), Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Text('سَلة',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('فاتورة',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A1A2E))),
                Text('المنصة الرقمية الأولى في اليمن',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: Colors.grey[500])),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  order.invoiceNumber ??
                      'INV-${order.id.length >= 8 ? order.id.substring(0, 8).toUpperCase() : order.id.toUpperCase()}',
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 6),
              Text('$date  •  $time',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: Colors.grey[500])),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// بيانات المتجر
// ════════════════════════════════════════════════════════
class _MerchantInfo extends StatelessWidget {
  final OrderModel order;
  const _MerchantInfo({required this.order});

  String _payLabel(String? m) => switch (m) {
        'cash' => 'نقداً',
        'credit' => 'آجل',
        'transfer' => 'تحويل',
        _ => m ?? '---',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: _InfoItem(
              icon: Icons.store_rounded,
              label: 'اسم المتجر',
              value: order.storeName ?? '---',
            ),
          ),
          Expanded(
            child: _InfoItem(
              icon: Icons.payments_rounded,
              label: 'الدفع',
              value: _payLabel(order.paymentMethod),
            ),
          ),
          Expanded(
            child: _InfoItem(
              icon: Icons.verified_rounded,
              label: 'الحالة',
              value: order.status.label,
              valueColor: _statusColorFromEnum(order.status),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                fontFamily: 'Cairo', fontSize: 10, color: Colors.grey[500])),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: valueColor ?? const Color(0xFF1A1A2E))),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════
// جدول المنتجات
// ════════════════════════════════════════════════════════
class _ItemsTable extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _ItemsTable({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text('لا توجد تفاصيل منتجات',
            style: TextStyle(fontFamily: 'Cairo', color: Colors.grey[400])),
      );
    }
    return Column(
      children: [
        Container(
          color: AppColors.primary.withValues(alpha: 0.06),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: const Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('المنتج',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
              SizedBox(
                width: 55,
                child: Text('الكمية',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
              SizedBox(
                width: 80,
                child: Text('السعر',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
              SizedBox(
                width: 90,
                child: Text('الإجمالي',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
            ],
          ),
        ),
        ...items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final totalQty = (item['quantity'] as num?)?.toInt() ?? 1;
          final returnedQty = (item['returned_quantity'] as num?)?.toInt() ?? 0;
          final netQty = (totalQty - returnedQty).clamp(0, totalQty);
          final price = (item['unit_price'] ?? item['price'] ?? 0) as num;
          final netTotal = netQty * price.toDouble();
          final isFullyReturned = netQty == 0 && returnedQty > 0;

          return Container(
            color: i.isEven ? Colors.white : const Color(0xFFFAFFFB),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Builder(
                    builder: (context) {
                      final rawName =
                          item['product_name'] ?? item['name'] ?? '---';
                      final unit = item['unit_label']?.toString().trim() ?? '';
                      final displayName = unit.isNotEmpty
                          ? '$rawName ($unit)'
                          : '$rawName (كرتون)';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isFullyReturned
                                  ? Colors.grey[400]
                                  : const Color(0xFF1A1A2E),
                              decoration: isFullyReturned
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          if (returnedQty > 0)
                            Text(
                              'مرتجع: $returnedQty ${unit.isNotEmpty ? unit : "كرتون"}',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFEA580C),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 55,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isFullyReturned
                            ? Colors.grey.withValues(alpha: 0.12)
                            : AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('$netQty',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: isFullyReturned
                                  ? Colors.grey
                                  : AppColors.primary)),
                    ),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    '${price.toStringAsFixed(0)} ر.ي',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF424242)),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    '${netTotal.toStringAsFixed(0)} ر.ي',
                    textAlign: TextAlign.end,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: isFullyReturned
                            ? Colors.grey
                            : const Color(0xFF1A1A2E)),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════
// الإجمالي
// ════════════════════════════════════════════════════════
class _TotalSection extends StatelessWidget {
  final OrderModel order;
  const _TotalSection({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: order.notes != null && order.notes!.isNotEmpty
                ? Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.sticky_note_2_rounded,
                              size: 14, color: Colors.orange),
                          SizedBox(width: 4),
                          Text('ملاحظات',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 4),
                        Text(order.notes!,
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Colors.grey[700])),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.08),
                  AppColors.primary.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('إجمالي الفاتورة',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text(
                  '${order.total.toStringAsFixed(0)} ر.ي',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// قسم التوقيع الرقمي داخل الفاتورة
// ════════════════════════════════════════════════════════
class _SignatureSection extends StatelessWidget {
  final String signatureUrl;
  final String signerName;
  const _SignatureSection(
      {required this.signatureUrl, required this.signerName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.verified_user_rounded,
                      size: 16, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text(
                    'التوقيع الرقمي للاستلام:',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'المستلم: $signerName',
                style: const TextStyle(
                    fontFamily: 'Cairo', fontSize: 10.5, color: Colors.grey),
              ),
            ],
          ),
          Container(
            height: 55,
            width: 120,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: signatureUrl.startsWith('data:image')
                  ? Builder(
                      builder: (_) {
                        try {
                          final raw = signatureUrl.split(',').last.trim();
                          final bytes = base64Decode(raw);
                          return Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Center(
                              child:
                                  Icon(Icons.draw_rounded, color: Colors.grey),
                            ),
                          );
                        } catch (_) {
                          return const Center(
                            child: Icon(Icons.draw_rounded, color: Colors.grey),
                          );
                        }
                      },
                    )
                  : Image.network(
                      signatureUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.draw_rounded, color: Colors.grey),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// ذيل الفاتورة
// ════════════════════════════════════════════════════════
class _InvoiceFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Divider(
              color: AppColors.primary.withValues(alpha: 0.15), thickness: 1),
          const SizedBox(height: 8),
          const Text('شكراً لتعاملكم معنا',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
          const SizedBox(height: 2),
          Text('سَلة — المنصة الرقمية الأولى في اليمن',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 11, color: Colors.grey[500])),
        ],
      ),
    );
  }
}
