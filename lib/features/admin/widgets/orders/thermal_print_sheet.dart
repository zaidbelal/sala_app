import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/thermal_printer_service.dart';
import '../../../../core/services/image_precache_service.dart';
import '../../services/admin_service.dart';

class ThermalPrintPreviewSheet extends StatefulWidget {
  final AdminOrder order;
  final List<Map<String, dynamic>> items;
  final String? signatureUrl;

  const ThermalPrintPreviewSheet({
    super.key,
    required this.order,
    required this.items,
    this.signatureUrl,
  });

  static void show(
    BuildContext context, {
    required AdminOrder order,
    required List<Map<String, dynamic>> items,
    String? signatureUrl,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ThermalPrintPreviewSheet(
        order: order,
        items: items,
        signatureUrl: signatureUrl,
      ),
    );
  }

  @override
  State<ThermalPrintPreviewSheet> createState() =>
      _ThermalPrintPreviewSheetState();
}

class _ThermalPrintPreviewSheetState extends State<ThermalPrintPreviewSheet> {
  final GlobalKey _receiptKey = GlobalKey();
  bool _isProcessing = false;
  PaperSize _paperSize = PaperSize.mm58;

  @override
  void initState() {
    super.initState();
    // تحميل التوقيع مسبقاً عبر مدير كاش التطبيق الموحد لمنع ظهور علامة التحميل في الفاتورة
    if (widget.signatureUrl != null &&
        widget.signatureUrl!.startsWith('http')) {
      ImagePrecacheService.instance.cacheManager
          .getSingleFile(widget.signatureUrl!)
          .then((_) {
        if (mounted) setState(() {});
      }).catchError((_) {});
    }
  }

  Future<void> _shareToThermalPrinterApp() async {
    setState(() => _isProcessing = true);
    final bytes = await ThermalPrinterService.capturePngFromKey(_receiptKey);
    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر إنشاء صورة الفاتورة للطباعة، حاول مجدداً',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final xFile = XFile.fromData(
      bytes,
      mimeType: 'image/png',
      name: 'receipt_${widget.order.id}.png',
    );

    // إرسال الصورة فوراً إلى تطبيقات الطابعات الحرارية عبر البلوتوث (مثل RawBT أو طباعة النظام)
    await Share.shareXFiles([xFile], text: 'طباعة فاتورة حرارية');
  }

  Future<void> _saveToGallery() async {
    setState(() => _isProcessing = true);
    final bytes = await ThermalPrinterService.capturePngFromKey(_receiptKey);
    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (bytes != null) {
      try {
        await Gal.putImageBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حفظ الإيصال الحراري في المعرض بنجاح ✅',
                  style: TextStyle(fontFamily: 'Cairo')),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر الحفظ في المعرض، تحقق من الصلاحيات',
                  style: TextStyle(fontFamily: 'Cairo')),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.print_rounded,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'معاينة الطباعة الحرارية',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 15,
                        fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // أزرار مقاس الورق بتصميم مضغوط وأنيق
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () =>
                            setState(() => _paperSize = PaperSize.mm58),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _paperSize == PaperSize.mm58
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '58mm',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _paperSize == PaperSize.mm58
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _paperSize = PaperSize.mm80),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _paperSize == PaperSize.mm80
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '80mm',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _paperSize == PaperSize.mm80
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // معاينة الإيصال
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: RepaintBoundary(
                  key: _receiptKey,
                  child: Material(
                    elevation: 6,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    child: ThermalReceiptWidget(
                      order: widget.order,
                      items: widget.items,
                      signatureUrl: widget.signatureUrl,
                      paperSize: _paperSize,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // أزرار التحكم والطباعة
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -2))
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _saveToGallery,
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('حفظ كصورة',
                        style: TextStyle(
                            fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _shareToThermalPrinterApp,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.bluetooth_connected_rounded),
                    label: const Text('إرسال للطابعة الحرارية 🖨️',
                        style: TextStyle(
                            fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
