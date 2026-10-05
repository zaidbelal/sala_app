import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/app_cache.dart';
import '../products/services/products_service.dart';
import '../products/widgets/product_details_sheet.dart';
import 'package:sala/core/models/product_unit.dart';
import '../../../../core/services/notification_service.dart';

class BarcodeScannerScreen extends StatefulWidget {
  final bool returnCodeOnly;

  const BarcodeScannerScreen({
    super.key,
    this.returnCodeOnly = false,
  });

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
  }

  /// فتح الكاميرا لمسح الباركود وإرجاع الرقم الملتقط كـ String
  static Future<String?> scan(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(returnCodeOnly: true),
      ),
    );
  }

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    returnImage: false,
  );
  bool _isProcessing = false;
  bool _isTorchOn = false;
  double _zoomScale = 0.0;
  bool _showHelpPrompt = false;
  Timer? _scanTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _startHelpTimer();
  }

  void _startHelpTimer() {
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isProcessing) {
        setState(() => _showHelpPrompt = true);
      }
    });
  }

  @override
  void dispose() {
    _scanTimeoutTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String _cleanBarcode(String raw) {
    const arabicDigits = {
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
    };
    var text = raw.trim();
    arabicDigits.forEach((ar, en) => text = text.replaceAll(ar, en));
    return text.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
  }

  Future<void> _handleBarcode(String rawCode) async {
    if (_isProcessing) return;
    final code = _cleanBarcode(rawCode);
    if (code.isEmpty) return;

    setState(() => _isProcessing = true);
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);

    // إذا كان الغرض هو التقاط الباركود لنموذج إضافة/تعديل المنتج
    if (widget.returnCodeOnly) {
      Navigator.of(context).pop(code);
      return;
    }

    ProductModel? matchedProduct;
    ProductUnit? matchedUnit;

    // ── 1. فحص فوري في كاش الهاتف المحلي (0ms) ──
    final cached = AppCache.instance.getProducts();
    if (cached != null && cached.isNotEmpty) {
      for (final p in cached) {
        final productBarcode = p['barcode']?.toString().trim();
        if (productBarcode != null && _cleanBarcode(productBarcode) == code) {
          matchedProduct = ProductModel.fromMap(p);
          break;
        }

        final units = p['units'];
        if (units is List) {
          for (final u in units) {
            if (u is Map) {
              final unitBarcode = u['barcode']?.toString().trim();
              if (unitBarcode != null && _cleanBarcode(unitBarcode) == code) {
                matchedProduct = ProductModel.fromMap(p);
                matchedUnit = ProductUnit.fromMap(Map<String, dynamic>.from(u));
                break;
              }
            }
          }
        }
        if (matchedProduct != null) break;
      }
    }
// ── 2. في حال لم يتواجد في الكاش، استعلام سحابي مباشر متوافق 100% بدون اشتراط فهرس مركب ──
    if (matchedProduct == null) {
      try {
        final querySnap = await FirebaseFirestore.instance
            .collection('products')
            .where('barcode', isEqualTo: code)
            .limit(5)
            .get(const GetOptions(source: Source.serverAndCache));

        final validDocs =
            querySnap.docs.where((d) => d.data()['is_deleted'] != true);
        if (validDocs.isNotEmpty) {
          final doc = validDocs.first;
          matchedProduct = ProductModel.fromMap({'id': doc.id, ...doc.data()});
        }
      } catch (_) {}
    }
    if (!mounted) return;

    if (matchedProduct != null) {
      final rootContext = NotificationService.navigatorKey.currentContext;
      Navigator.of(context).pop();
      if (rootContext != null) {
        showModalBottomSheet(
          context: rootContext,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => ProductDetailsSheet(
            product: matchedProduct!,
            initialUnit: matchedUnit,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '⚠️ لم يتم العثور على منتج مرتبط بهذا الباركود ($code)',
            style: const TextStyle(fontFamily: 'Cairo'),
            textAlign: TextAlign.center,
          ),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 1800));
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // نافذة إدخال الباركود يدوياً (للتجربة على المحاكي أو إذا كان الباركود تالفاً)
  void _showManualInputDialog() {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'كتابة الباركود يدوياً',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: TextField(
          controller: textCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: 'أدخل رقم الباركود...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final val = textCtrl.text.trim();
              Navigator.pop(ctx);
              if (val.isNotEmpty) _handleBarcode(val);
            },
            child: const Text('بحث', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── كاميرا قراءة الباركود ──
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              for (final b in barcodes) {
                final val = b.rawValue;
                if (val != null && val.isNotEmpty) {
                  _handleBarcode(val);
                  break;
                }
              }
            },
          ),

          // ── واجهة المستخدم التفاعلية ──
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 28),
                      ),
                      const Text(
                        'مسح باركود المنتج',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'إدخال يدوي',
                            onPressed: _showManualInputDialog,
                            icon: const Icon(Icons.keyboard_alt_outlined,
                                color: Colors.white, size: 24),
                          ),
                          // زر التكبير 2x لحل مشكلة عدم وضوح الباركود عن قرب
                          IconButton(
                            tooltip: 'تقريب الكاميرا',
                            onPressed: () async {
                              final newZoom = _zoomScale == 0.0 ? 0.35 : 0.0;
                              await _controller.setZoomScale(newZoom);
                              setState(() => _zoomScale = newZoom);
                            },
                            icon: Icon(
                              _zoomScale > 0
                                  ? Icons.zoom_out_rounded
                                  : Icons.zoom_in_rounded,
                              color: _zoomScale > 0
                                  ? AppColors.primary
                                  : Colors.white,
                              size: 24,
                            ),
                          ),
                          IconButton(
                            tooltip: 'تشغيل الكشاف',
                            onPressed: () async {
                              await _controller.toggleTorch();
                              setState(() => _isTorchOn = !_isTorchOn);
                            },
                            icon: Icon(
                              _isTorchOn
                                  ? Icons.flash_on_rounded
                                  : Icons.flash_off_rounded,
                              color: _isTorchOn ? Colors.amber : Colors.white,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // مربع التركيز مع إضاءة خضراء
                Center(
                  child: Container(
                    width: 270,
                    height: 190,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primary, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 240,
                          height: 2,
                          color: Colors.redAccent.withValues(alpha: 0.8),
                        ),
                        if (_isProcessing)
                          const CircularProgressIndicator(
                              color: AppColors.primary),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // شريط التوجيه الذكي الذي يظهر مساعدة فورية إذا تعثرت الكاميرا في المسح
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _showHelpPrompt
                      ? GestureDetector(
                          onTap: _showManualInputDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            margin: const EdgeInsets.only(
                                bottom: 30, left: 20, right: 20),
                            decoration: BoxDecoration(
                              color:
                                  Colors.amber.shade900.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black45,
                                    blurRadius: 10,
                                    offset: Offset(0, 3)),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit_note_rounded,
                                    color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'الباركود تالف أو غير واضح؟ اضغط للكتابة يدوياً ✍️',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          margin: const EdgeInsets.only(bottom: 30),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'وجّه الكاميرا نحو باركود الصنف أو الكرتون',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
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
