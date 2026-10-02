import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_adaptive_colors.dart';

class ReturnInvoiceModel {
  final String id;
  final String orderId;
  final String productName;
  final int quantity;
  final double refundAmount;
  final String reason;
  final String? rejectionReason;
  final String status;
  final String storeName;
  final String? signatureUrl;
  final DateTime createdAt;

  const ReturnInvoiceModel({
    required this.id,
    required this.orderId,
    required this.productName,
    required this.quantity,
    required this.refundAmount,
    required this.reason,
    this.rejectionReason,
    required this.status,
    required this.storeName,
    this.signatureUrl,
    required this.createdAt,
  });

  factory ReturnInvoiceModel.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v != null && v.toString().isNotEmpty) {
        try {
          return DateTime.parse(v.toString());
        } catch (_) {}
      }
      return DateTime.now();
    }

    return ReturnInvoiceModel(
      id: map['id']?.toString() ?? '',
      orderId: map['order_id']?.toString() ?? '',
      productName: map['product_name']?.toString() ?? 'منتج',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      refundAmount: (map['refund_amount'] as num?)?.toDouble() ?? 0.0,
      reason: map['reason']?.toString() ?? '',
      rejectionReason: map['rejection_reason']?.toString() ??
          map['reject_reason']?.toString(),
      status: map['status']?.toString() ?? 'accepted',
      storeName: map['store_name']?.toString() ?? '',
      signatureUrl: map['signature_url']?.toString(),
      createdAt: parseDate(map['created_at']),
    );
  }
}

class ReturnInvoiceScreen extends StatefulWidget {
  final ReturnInvoiceModel returnItem;
  const ReturnInvoiceScreen({super.key, required this.returnItem});

  @override
  State<ReturnInvoiceScreen> createState() => _ReturnInvoiceScreenState();
}

class _ReturnInvoiceScreenState extends State<ReturnInvoiceScreen> {
  final _repaintKey = GlobalKey();
  bool _saving = false;
  Future<void> _shareAsImage() async {
    setState(() => _saving = true);
    try {
      final context = _repaintKey.currentContext;
      if (context == null) return;
      final boundary = context.findRenderObject() as RenderRepaintBoundary?;
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
      final shortId = widget.returnItem.id.length >= 6
          ? widget.returnItem.id.substring(0, 6).toUpperCase()
          : widget.returnItem.id.toUpperCase();
      final fileName = 'فاتورة_مرتجع_$shortId.png';
      final xFile =
          XFile.fromData(bytes, mimeType: 'image/png', name: fileName);
      await Share.shareXFiles([xFile], text: 'فاتورة إرجاع سَلة');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّرت المشاركة، حاول مجدداً',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
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
          content: Text('تم حفظ فاتورة المرتجع في المعرض ✅',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّر الحفظ، تحقق من صلاحيات المعرض',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.returnItem;
    final date =
        '${item.createdAt.day}/${item.createdAt.month}/${item.createdAt.year}';
    final time =
        '${item.createdAt.hour.toString().padLeft(2, '0')}:${item.createdAt.minute.toString().padLeft(2, '0')}';
    final shortRetId = item.id.length >= 6
        ? item.id.substring(0, 6).toUpperCase()
        : item.id.toUpperCase();
    final shortOrderId = item.orderId.length >= 6
        ? item.orderId.substring(0, 6).toUpperCase()
        : item.orderId.toUpperCase();
    final unitPrice = item.quantity > 0
        ? item.refundAmount / item.quantity
        : item.refundAmount;

    return Scaffold(
      backgroundColor: context.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            // ── الشريط العلوي ──
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
                    child: Text(
                      'فاتورة إرجاع',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: context.textPrimary),
                    ),
                  ),
                  if (!_saving)
                    IconButton(
                      onPressed: _downloadImage,
                      icon: const Icon(Icons.download_rounded,
                          color: Color(0xFFEA580C)),
                      tooltip: 'تحميل',
                    ),
                  GestureDetector(
                    onTap: _saving ? null : _shareAsImage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEA580C),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFEA580C).withValues(alpha: 0.3),
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

            // ── جسم الفاتورة ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                child: RepaintBoundary(
                  key: _repaintKey,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ترويسة فاتورة المرتجع
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFFFF7ED), Colors.white],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(22)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEA580C),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFEA580C)
                                          .withValues(alpha: 0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Icon(Icons.assignment_return_rounded,
                                      color: Colors.white, size: 28),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('فاتورة إرجاع',
                                        style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 22,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF1A1A2E))),
                                    Text('سند مرتجع رسمي • سَلة',
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEA580C)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'RET-$shortRetId',
                                      style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFEA580C)),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text('مرجع الطلب: #$shortOrderId',
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w600)),
                                  Text('$date  •  $time',
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10,
                                          color: Colors.grey[500])),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // تفاصيل المتجر والحالة
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  const Icon(Icons.storefront_rounded,
                                      size: 20, color: Color(0xFFEA580C)),
                                  const SizedBox(height: 4),
                                  Text('المتجر',
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10,
                                          color: Colors.grey[500])),
                                  Text(
                                      item.storeName.isNotEmpty
                                          ? item.storeName
                                          : 'متجر التاجر',
                                      style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800)),
                                ],
                              ),
                              Column(
                                children: [
                                  Icon(
                                    item.status == 'accepted'
                                        ? Icons.check_circle_rounded
                                        : item.status == 'rejected'
                                            ? Icons.cancel_rounded
                                            : Icons.hourglass_top_rounded,
                                    size: 20,
                                    color: item.status == 'accepted'
                                        ? Colors.green
                                        : item.status == 'rejected'
                                            ? Colors.red
                                            : Colors.orange,
                                  ),
                                  const SizedBox(height: 4),
                                  Text('حالة الإرجاع',
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10,
                                          color: Colors.grey[500])),
                                  Text(
                                    item.status == 'accepted'
                                        ? 'مرتجع مقبول ✓'
                                        : item.status == 'rejected'
                                            ? 'تم الرفض ✗'
                                            : 'قيد المراجعة ⏳',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: item.status == 'accepted'
                                          ? Colors.green
                                          : item.status == 'rejected'
                                              ? Colors.red
                                              : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // جدول الأصناف المرتجعة
                        Container(
                          color:
                              const Color(0xFFEA580C).withValues(alpha: 0.06),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          child: const Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text('الصنف المرتجع',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFEA580C))),
                              ),
                              SizedBox(
                                width: 55,
                                child: Text('الكمية',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFEA580C))),
                              ),
                              SizedBox(
                                width: 75,
                                child: Text('السعر',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFEA580C))),
                              ),
                              SizedBox(
                                width: 85,
                                child: Text('المسترد',
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFEA580C))),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          color: const Color(0xFFFFFBF7),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  item.productName,
                                  style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(
                                          0xFF1A1A2E)), // لون داكن صريح لمنع البهتان
                                ),
                              ),
                              SizedBox(
                                width: 55,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEA580C)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text('${item.quantity}',
                                        style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFEA580C))),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 75,
                                child: Text(
                                  '${unitPrice.toStringAsFixed(0)} ر.ي',
                                  textAlign: TextAlign.center,
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      color: Colors.grey[700]),
                                ),
                              ),
                              SizedBox(
                                width: 85,
                                child: Text(
                                  '${item.refundAmount.toStringAsFixed(0)} ر.ي',
                                  textAlign: TextAlign.end,
                                  textDirection: TextDirection.rtl,
                                  style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFEA580C)),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // سبب الإرجاع
                        if (item.reason.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color:
                                        Colors.orange.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.info_outline_rounded,
                                          size: 14, color: Colors.orange),
                                      SizedBox(width: 6),
                                      Text('سبب الإرجاع المسجل:',
                                          style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: Colors.orange,
                                              fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(item.reason,
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 12,
                                          color: Colors.grey[800],
                                          height: 1.5)),
                                ],
                              ),
                            ),
                          ),

                        // سبب الرفض من الإدارة (إن وُجد)
                        if (item.status == 'rejected' &&
                            item.rejectionReason != null &&
                            item.rejectionReason!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF5F5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.red.withValues(alpha: 0.35)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.cancel_rounded,
                                          size: 15, color: Colors.red),
                                      SizedBox(width: 6),
                                      Text('سبب رفض الطلب من الإدارة:',
                                          style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: Colors.red,
                                              fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(item.rejectionReason!,
                                      style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 12,
                                          color: Color(0xFF991B1B),
                                          fontWeight: FontWeight.w700,
                                          height: 1.5)),
                                ],
                              ),
                            ),
                          ),
                        // إجمالي المبلغ المسترد
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFEA580C)
                                      .withValues(alpha: 0.08),
                                  const Color(0xFFEA580C)
                                      .withValues(alpha: 0.03),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFFEA580C)
                                      .withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('إجمالي القيمة المستردة للتاجر',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1A1A2E))),
                                Text(
                                  '${item.refundAmount.toStringAsFixed(0)} ر.ي',
                                  textDirection: TextDirection.rtl,
                                  style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFEA580C)),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // التوقيع الرقمي للمرتجع إن وُجد
                        if (item.signatureUrl != null &&
                            item.signatureUrl!.isNotEmpty) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'توقيع معتمد المرتجع:',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFEA580C)),
                                ),
                                Container(
                                  height: 50,
                                  width: 110,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: item.signatureUrl!
                                          .startsWith('data:image')
                                      ? Builder(
                                          builder: (_) {
                                            try {
                                              final raw = item.signatureUrl!
                                                  .split(',')
                                                  .last
                                                  .trim();
                                              final bytes = base64Decode(raw);
                                              return Image.memory(
                                                bytes,
                                                fit: BoxFit.contain,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(
                                                        Icons.draw_rounded,
                                                        color: Colors.grey),
                                              );
                                            } catch (_) {
                                              return const Icon(
                                                  Icons.draw_rounded,
                                                  color: Colors.grey);
                                            }
                                          },
                                        )
                                      : Image.network(
                                          item.signatureUrl!,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(Icons.draw_rounded,
                                                  color: Colors.grey),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // تذييل الفاتورة
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(22)),
                          ),
                          child: Column(
                            children: [
                              Text(
                                item.status == 'accepted'
                                    ? 'تمت تسوية هذا المرتجع وإضافته لحسابكم'
                                    : 'طلب الإرجاع قيد مراجعة الإدارة',
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFEA580C)),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                  'سَلة — المنصة الرقمية الأولى في اليمن',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 10,
                                      color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
