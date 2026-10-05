import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../features/admin/services/admin_service.dart';
import 'image_precache_service.dart';

enum PaperSize { mm58, mm80 }

class ThermalPrinterService {
  ThermalPrinterService._();
  static final instance = ThermalPrinterService._();
  static bool _isCapturing = false;
  static Future<Uint8List?> capturePngFromKey(GlobalKey key) async {
    if (_isCapturing) return null;
    _isCapturing = true;
    try {
      final context = key.currentContext;
      if (context == null) return null;
      final boundary = context.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || !boundary.attached) return null;

      // انتظار اكتمال إطار الرسم بأمان في Release Mode بدون استدعاء debugNeedsPaint المحظورة
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(milliseconds: 600),
        onTimeout: () => null,
      );
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return null;
      return byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
    } catch (e) {
      debugPrint('Thermal capture error: $e');
      return null;
    } finally {
      _isCapturing = false;
    }
  }
}

/// ويدجت الفاتورة المصممة باحترافية عالية وبأعلى درجات التباين للطباعة الحرارية (58mm / 80mm)
class ThermalReceiptWidget extends StatelessWidget {
  final AdminOrder order;
  final List<Map<String, dynamic>> items;
  final String? signatureUrl;
  final PaperSize paperSize;

  const ThermalReceiptWidget({
    super.key,
    required this.order,
    required this.items,
    this.signatureUrl,
    this.paperSize = PaperSize.mm58,
  });

  @override
  Widget build(BuildContext context) {
    final width = paperSize == PaperSize.mm58 ? 384.0 : 576.0;
    final shortId = order.orderNumber ??
        (order.id.length >= 8
            ? order.id.substring(0, 8).toUpperCase()
            : order.id.toUpperCase());

    final dateStr =
        '${order.createdAt.year}/${order.createdAt.month.toString().padLeft(2, '0')}/${order.createdAt.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';

    final totalQuantity = items.fold<int>(
      0,
      (sum, item) {
        final totalQty = (item['quantity'] as num?)?.toInt() ?? 1;
        final returnedQty = (item['returned_quantity'] as num?)?.toInt() ?? 0;
        return sum + (totalQty - returnedQty).clamp(0, totalQty);
      },
    );
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── ترويسة الفاتورة ──
          Center(
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'سَـــــلَّـــــة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'منصة توزيع الجملة والتجزئة - صنعاء',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const Text(
                  'فاتورة تسليم مبيعات رسمية',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          const _DashedLine(thickness: 1.5),

          // ── بيانات الفاتورة والعميل ──
          _ReceiptRow(label: 'رقم الفاتورة:', value: '#$shortId', bold: true),
          _ReceiptRow(label: 'تاريخ ووقت الطلب:', value: '$dateStr  $timeStr'),

          if (order.storeName != null && order.storeName!.trim().isNotEmpty)
            _ReceiptRow(
              label: 'المتجر / البقالة:',
              value: order.storeName!.trim(),
              bold: true,
            ),

          // طباعة اسم التاجر بوضوح
          _ReceiptRow(
            label: 'اسم التاجر (العميل):',
            value: order.merchantName.trim(),
            bold: true,
          ),

          if (order.phoneNumber != null && order.phoneNumber!.trim().isNotEmpty)
            _ReceiptRow(
              label: 'رقم هاتف العميل:',
              value: order.phoneNumber!.trim(),
            ),

          _ReceiptRow(
            label: 'طريقة الدفع:',
            value: order.paymentMethod == 'cash'
                ? 'نقداً عند الاستلام (كاش)'
                : 'دفع آجل',
            bold: true,
          ),

          const _DashedLine(thickness: 1.5),

          // ── رأس جدول الأصناف ──
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.black, width: 1.2),
                bottom: BorderSide(color: Colors.black, width: 1.2),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    'الصنف',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      color: Colors.black,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'الكمية والوحدة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      color: Colors.black,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'السعر',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      color: Colors.black,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'الإجمالي',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ...items.map((item) {
            final rawName = item['product_name'] ?? 'منتج';
            final rawUnit =
                (item['unit_label'] ?? item['unit'])?.toString().trim() ?? '';
            final unitLabel = rawUnit.isNotEmpty ? rawUnit : 'كرتون';
            final totalQty = (item['quantity'] as num?)?.toInt() ?? 1;
            final returnedQty =
                (item['returned_quantity'] as num?)?.toInt() ?? 0;
            final netQty = (totalQty - returnedQty).clamp(0, totalQty);
            final price = (item['price'] as num?)?.toDouble() ?? 0.0;
            final total = netQty * price;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rawName,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                            height: 1.3,
                          ),
                        ),
                        if (returnedQty > 0)
                          Text(
                            'مرتجع: $returnedQty',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // عرض الكمية الصافية الفعلية
                  Expanded(
                    flex: 3,
                    child: Text(
                      '$netQty $unitLabel',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      price.toStringAsFixed(0),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      total.toStringAsFixed(0),
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const _DashedLine(thickness: 1.5),

          // ── إحصائيات الكمية والأصناف ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'عدد الأصناف: ${items.length}',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              Text(
                'إجمالي الكمية: $totalQuantity',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // ── المربع البارز للمبلغ الإجمالي ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 2.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'المبلغ الصافي المطلوب:',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
                Text(
                  '${order.total.toStringAsFixed(0)} ر.ي',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── خانة التوقيع الرقمي إن وُجد ──
          if (signatureUrl != null && signatureUrl!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  Text(
                    'توقيع المستلم المعتمد (${order.merchantName}):',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  signatureUrl!.startsWith('data:image')
                      ? Builder(
                          builder: (_) {
                            try {
                              final raw = signatureUrl!.split(',').last.trim();
                              final bytes = base64Decode(raw);
                              return Image.memory(
                                bytes,
                                height: 50,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              );
                            } catch (_) {
                              return const SizedBox.shrink();
                            }
                          },
                        )
                      : CachedNetworkImage(
                          imageUrl: signatureUrl!,
                          cacheManager:
                              ImagePrecacheService.instance.cacheManager,
                          height: 50,
                          fit: BoxFit.contain,
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                          placeholder: (_, __) => const SizedBox(
                            height: 50,
                            width: 50,
                            child: Center(
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.5),
                            ),
                          ),
                        ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // ── رمز QR Code للفحص السريع ──
          Center(
            child: Column(
              children: [
                QrImageView(
                  data:
                      'SALA_INV:$shortId|TOTAL:${order.total}|MERCHANT:${order.merchantName}|DATE:${order.createdAt.toIso8601String()}',
                  version: QrVersions.auto,
                  size: paperSize == PaperSize.mm58 ? 95.0 : 120.0,
                ),
                const SizedBox(height: 6),
                const Text(
                  'شكراً لتعاملكم معنا وثقتكم بنا!',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
                // رقم خدمة العملاء المحدث
                const Text(
                  'خدمة العملاء والشكاوى: 777692369',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _ReceiptRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// خط فاصل متقطع احترافي متكيف تماماً مع عرض الفاتورة
class _DashedLine extends StatelessWidget {
  final double thickness;
  const _DashedLine({this.thickness = 1.0});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rawWidth = constraints.maxWidth;
        final boxWidth = rawWidth.isFinite ? rawWidth : 384.0;
        const dashWidth = 4.0;
        const dashSpace = 3.0;
        final dashCount =
            (boxWidth / (dashWidth + dashSpace)).floor().clamp(1, 150);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(dashCount, (_) {
              return SizedBox(
                width: dashWidth,
                height: thickness,
                child: const DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
