import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/app_cache.dart';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart' hide Source;

/// مشغل صوت البيب التجاري الفوري بصوت مرتفع واستجابة فورية بدون تأخير (0ms)
class SupermarketSoundHelper {
  SupermarketSoundHelper._();
  static AudioPlayer? _audioPlayer;

  static Future<void> playSupermarketBeep() async {
    HapticFeedback.mediumImpact();
    try {
      _audioPlayer ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      await _audioPlayer!.stop();
      await _audioPlayer!.setVolume(1.0);
      await _audioPlayer!.play(
        AssetSource('sounds/beep.mp3'),
        mode: PlayerMode.lowLatency,
      );
    } catch (_) {
      try {
        SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }

  static void playRetryFeedback() {
    HapticFeedback.selectionClick();
  }

  /// ✅ تحرير فوري ودائم لموارد الأجهزة والصوت في نظام التشغيل
  static Future<void> releasePlayer() async {
    if (_audioPlayer != null) {
      try {
        await _audioPlayer!.stop();
        await _audioPlayer!.dispose();
      } catch (_) {}
      _audioPlayer = null;
    }
  }
}

class BarcodeTools {
  BarcodeTools._();
  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  static int _checkDigit(String body) {
    var sum = 0;
    for (var i = 0; i < body.length; i++) {
      final d = body.codeUnitAt(body.length - 1 - i) - 48;
      sum += (i % 2 == 0) ? d * 3 : d;
    }
    return (10 - sum % 10) % 10;
  }

  static bool isValidGtin(String s) {
    if (!_digitsOnly.hasMatch(s)) return false;
    if (![8, 12, 13, 14].contains(s.length)) return false;
    return _checkDigit(s.substring(0, s.length - 1)) ==
        s.codeUnitAt(s.length - 1) - 48;
  }

  static String? _upcEtoA(String e) {
    if (e.length != 8 || !_digitsOnly.hasMatch(e)) return null;
    final n = e[0], d = e.substring(1, 7), chk = e[7], d6 = d[5];
    String body;
    switch (d6) {
      case '0':
      case '1':
      case '2':
        body = '${d.substring(0, 2)}${d6}0000${d.substring(2, 5)}';
        break;
      case '3':
        body = '${d.substring(0, 3)}00000${d.substring(3, 5)}';
        break;
      case '4':
        body = '${d.substring(0, 4)}00000${d[4]}';
        break;
      default:
        body = '${d.substring(0, 5)}0000$d6';
    }
    return '$n$body$chk';
  }

  /// توليد كافة الصيغ المكافئة المحتملة للباركود الواحد عالمياً ومحلياً
  static List<String> variants(String raw) {
    final c = BarcodeScannerScreen.cleanBarcode(raw);
    final out = <String>{};
    if (c.isEmpty) return const [];
    out.add(c);
    if (!_digitsOnly.hasMatch(c)) return out.toList();

    final s = c.replaceFirst(RegExp(r'^0+'), '');
    if (s.isEmpty) return out.toList();
    out.add(s);
    for (final len in const [13, 12, 14, 8]) {
      if (s.length <= len) out.add(s.padLeft(len, '0'));
    }
    out
      ..add('0$s')
      ..add('00$s');

    final a = _upcEtoA(c);
    if (a != null) {
      out
        ..add(a)
        ..add(a.padLeft(13, '0'));
    }
    if (c.length == 14 && isValidGtin(c)) {
      final body12 = c.substring(1, 13);
      final inner13 = '$body12${_checkDigit(body12)}';
      out
        ..add(inner13)
        ..add(inner13.replaceFirst(RegExp(r'^0+'), ''));
    }
    return out.where((e) => e.isNotEmpty).toList();
  }
}

enum _LookupStatus { found, notFound }

class _LookupResult {
  final _LookupStatus status;
  final Map<String, dynamic>? product;
  const _LookupResult(this.status, [this.product]);
}

class BarcodeScannerScreen extends StatefulWidget {
  final bool returnCodeOnly;
  final bool findProductMode;
  final bool continuousMode;
  final void Function(Map<String, dynamic> product)? onProductScanned;

  const BarcodeScannerScreen({
    super.key,
    this.returnCodeOnly = false,
    this.findProductMode = false,
    this.continuousMode = false,
    this.onProductScanned,
  });

  static Future<Map<String, dynamic>?> scanProduct(BuildContext context) {
    return Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(findProductMode: true),
      ),
    );
  }

  static Future<String?> scan(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(returnCodeOnly: true),
      ),
    );
  }

  /// تنظيف وتوحيد الباركود بدقة مطلقة
  static String cleanBarcode(String raw) {
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
      '۰': '0',
      '۱': '1',
      '۲': '2',
      '۳': '3',
      '۴': '4',
      '۵': '5',
      '۶': '6',
      '۷': '7',
      '۸': '8',
      '۹': '9',
    };
    var text = raw.trim();
    arabicDigits.forEach((ar, en) => text = text.replaceAll(ar, en));
    text = text.replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F\s-]'), '');
    return text.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '').trim();
  }

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final AnimationController _laserAnimCtrl;
  late final Animation<double> _laserPosition;

  bool _isProcessingMatch = false;
  bool _isTorchOn = false;
  double _zoomScale = 0.0;
  String? _cameraError;

  // 🚀 محرك الاستمرار الدائم بالمسح دون توقف حتى إيجاد السلعة
  final Map<String, DateTime> _unmatchedCodesCooldown = {};
  String? _statusBannerText;
  Color _statusBannerColor = AppColors.primary;
  Timer? _statusBannerTimer;
  int _continuousScanCount = 0;

  Offset? _focusPoint;
  bool _showFocusCircle = false;
  Timer? _focusResetTimer;

  @override
  void initState() {
    super.initState();

    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.unrestricted,
      detectionTimeoutMs: 60,
      facing: CameraFacing.back,
      torchEnabled: false,
      returnImage: false,
      autoStart: true,
      cameraResolution: const Size(1920, 1080),
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.itf,
        BarcodeFormat.codabar,
        BarcodeFormat.dataMatrix,
        BarcodeFormat.qrCode,
        BarcodeFormat.pdf417,
        BarcodeFormat.aztec,
      ],
    );

    _laserAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);

    _laserPosition = Tween<double>(begin: 0.05, end: 0.95).animate(
      CurvedAnimation(parent: _laserAnimCtrl, curve: Curves.easeInOut),
    );

    BarcodeIndexManager.instance.ensureInitialized();
    unawaited(_startCamera());
  }

  @override
  void dispose() {
    _statusBannerTimer?.cancel();
    _focusResetTimer?.cancel();
    _laserAnimCtrl.dispose();
    _controller.dispose();
    SupermarketSoundHelper
        .releasePlayer(); // 🔒 إغلاق وتفريغ المشغل الصوتي فوراً
    super.dispose();
  }

  Future<void> _onTapToFocus(TapUpDetails details) async {
    final p = details.localPosition;
    final size = MediaQuery.of(context).size;
    setState(() {
      _focusPoint = p;
      _showFocusCircle = true;
    });
    HapticFeedback.selectionClick();
    _focusResetTimer?.cancel();
    _focusResetTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _showFocusCircle = false);
    });
    try {
      await (_controller as dynamic)
          .setFocusPoint(Offset(p.dx / size.width, p.dy / size.height));
    } catch (_) {}
  }

  Future<void> _startCamera() async {
    try {
      await _controller.start();
      if (mounted && _cameraError != null) setState(() => _cameraError = null);
    } on MobileScannerException catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = e.errorCode == MobileScannerErrorCode.permissionDenied
            ? 'لم يتم منح إذن الكاميرا.\nفعّله من إعدادات الهاتف ثم أعد المحاولة.'
            : 'تعذّر تشغيل الكاميرا. أعد المحاولة.';
      });
    } catch (_) {
      if (mounted) setState(() => _cameraError = 'تعذّر تشغيل الكاميرا.');
    }
  }

  Future<void> _stopCamera() async {
    try {
      await _controller.stop();
    } catch (_) {}
  }

  Barcode? _pickBest(BarcodeCapture capture) {
    final list = capture.barcodes
        .where((b) => (b.rawValue ?? '').trim().isNotEmpty)
        .toList();
    if (list.isEmpty) return null;
    if (list.length == 1) return list.first;
    final size = capture.size;
    if (size.width <= 0 || size.height <= 0) return list.first;

    double dist(Barcode b) {
      final c = b.corners;
      if (c.isEmpty) return double.infinity;
      var sx = 0.0, sy = 0.0;
      for (final p in c) {
        sx += p.dx;
        sy += p.dy;
      }
      final cx = sx / c.length / size.width - 0.5;
      final cy = sy / c.length / size.height - 0.5;
      return math.sqrt(cx * cx + cy * cy);
    }

    list.sort((a, b) => dist(a).compareTo(dist(b)));
    return list.first;
  }

  // ── النواة المركزية: مسح مستمر ذكي لا يغلق الكاميرا ولا يتوقف عند الفشل ──
  void _onDetect(BarcodeCapture capture) {
    if (!mounted || _isProcessingMatch) return;
    final b = _pickBest(capture);
    final raw = b?.rawValue;
    if (b == null || raw == null) return;

    final code = BarcodeScannerScreen.cleanBarcode(raw);
    if (code.length < 3) return;

    // إذا تم مسح نفس الكود غير المطابق قبل أقل من 750ms نترك الكاميرا تبحث عن كود آخر فوراً دون تجميد
    final now = DateTime.now();
    _pruneUnmatchedCodes(now, protectedCode: code);
    final lastFailedAt = _unmatchedCodesCooldown[code];
    if (lastFailedAt != null &&
        now.difference(lastFailedAt).inMilliseconds < 750) {
      return;
    }

    unawaited(_processScannedCode(code));
  }

  void _pruneUnmatchedCodes(DateTime now, {required String protectedCode}) {
    _unmatchedCodesCooldown.removeWhere(
      (_, failedAt) =>
          now.difference(failedAt) >= const Duration(milliseconds: 750),
    );
    if (_unmatchedCodesCooldown.length < 128) return;

    final oldest = _unmatchedCodesCooldown.entries
        .where((entry) => entry.key != protectedCode)
        .reduce(
          (a, b) => a.value.isBefore(b.value) ? a : b,
        );
    _unmatchedCodesCooldown.remove(oldest.key);
  }

  Future<void> _processScannedCode(String code) async {
    if (_isProcessingMatch) return;

    if (widget.returnCodeOnly) {
      _isProcessingMatch = true;
      SupermarketSoundHelper.playSupermarketBeep();
      await _stopCamera();
      if (mounted) Navigator.of(context).pop(code);
      return;
    }

    _isProcessingMatch = true;
    final result = await _lookup(code);
    if (!mounted) return;

    if (result.status == _LookupStatus.found && result.product != null) {
      final product = result.product!;
      SupermarketSoundHelper.playSupermarketBeep();
      _unmatchedCodesCooldown.clear();

      if (widget.continuousMode) {
        _continuousScanCount++;
        try {
          widget.onProductScanned?.call(product);
        } catch (_) {}

        _setLiveStatus(
          '✅ تمت إضافة: ${product['name'] ?? 'سلعة'} (#$_continuousScanCount)',
          AppColors.primary,
        );

        // تبريد لحظي 280ms فقط لمنع التقاط نفس السلعة الممسوحة مرتين في نفس الإطار
        await Future.delayed(const Duration(milliseconds: 280));
        _isProcessingMatch = false;
      } else {
        await _stopCamera();
        if (mounted) Navigator.of(context).pop(product);
      }
    } else {
      // 🚀 لم يجد شيئاً: لا نتوقف! نعطي تغذية راجعة خفيفة ونستمر بالمسح فوراً حتى يجد
      SupermarketSoundHelper.playRetryFeedback();
      _unmatchedCodesCooldown[code] = DateTime.now();

      _setLiveStatus(
        '🔍 جاري البحث... ($code غير مسجل) استمر بالمسح',
        Colors.orange.shade800,
      );

      // تحرير فوري لمعالج الكاميرا للالتقاط من زاوية أفضل أو التقاط منتج آخر
      await Future.delayed(const Duration(milliseconds: 120));
      _isProcessingMatch = false;
    }
  }

  void _setLiveStatus(String text, Color color) {
    if (!mounted) return;
    setState(() {
      _statusBannerText = text;
      _statusBannerColor = color;
    });
    _statusBannerTimer?.cancel();
    _statusBannerTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _statusBannerText = null);
      }
    });
  }

  Future<_LookupResult> _lookup(String code) async {
    final index = BarcodeIndexManager.instance;

    // 1. فحص فوري بذاكرة الهاتف RAM (0ms)
    var matched = index.find(code);
    if (matched != null) return _LookupResult(_LookupStatus.found, matched);

    // 2. فحص كاش المنتجات الشامل وتحديث الفهرس
    if (index.rebuildIfStale()) {
      matched = index.find(code);
      if (matched != null) return _LookupResult(_LookupStatus.found, matched);
    }

    // 3. فحص سحابي سريع مع جميع احتمالات الأصفار والـ GTIN
    final vars = BarcodeTools.variants(code).take(25).toList();
    final col = FirebaseFirestore.instance.collection('products');
    Map<String, dynamic>? hit;

    try {
      hit = await _queryFast(col.where('all_barcodes', arrayContainsAny: vars));
      if (hit == null) {
        hit = await _queryFast(col.where('barcode', whereIn: vars));
      }
    } catch (_) {}

    if (hit != null) {
      index.indexProduct(hit);
      return _LookupResult(_LookupStatus.found, hit);
    }

    return const _LookupResult(_LookupStatus.notFound);
  }

  Future<Map<String, dynamic>?> _queryFast(
      Query<Map<String, dynamic>> q) async {
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await q
          .limit(3)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      snap = await q.limit(3).get(const GetOptions(source: Source.cache));
    }
    for (final d in snap.docs) {
      final data = d.data();
      if (data['is_deleted'] == true || data['is_active'] == false) continue;
      return {'id': d.id, ...data};
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final double boxWidth = screenSize.width * 0.86;
    final double boxHeight = screenSize.height * 0.30;

    final scanWindowRect = Rect.fromCenter(
      center: Offset(screenSize.width / 2, screenSize.height * 0.42),
      width: boxWidth,
      height: boxHeight,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 🚀 الكاميرا الحرة المباشرة مع معالج onDetect المنقح بالكامل
          GestureDetector(
            onTapUp: _onTapToFocus,
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          ),

          // تعتيم بؤري يركز العدسة
          CustomPaint(
            size: Size.infinite,
            painter: _ScannerOverlayPainter(
              scanWindow: scanWindowRect,
              borderRadius: 22,
            ),
          ),

          // دائرة التركيز اليدوي عند النقر باللمس
          if (_showFocusCircle && _focusPoint != null)
            Positioned(
              left: _focusPoint!.dx - 30,
              top: _focusPoint!.dy - 30,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF00FF66), width: 2),
                ),
              ),
            ),

          // إطار الاستهداف الليزري المتطور
          Positioned(
            left: scanWindowRect.left,
            top: scanWindowRect.top,
            child: Container(
              width: boxWidth,
              height: boxHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Stack(
                children: [
                  const _CornerDecorations(),
                  AnimatedBuilder(
                    animation: _laserPosition,
                    builder: (context, _) {
                      return Positioned(
                        top: _laserPosition.value * (boxHeight - 10),
                        left: 10,
                        right: 10,
                        child: Container(
                          height: 3.5,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: const LinearGradient(
                              colors: [
                                Colors.transparent,
                                Color(0xFF00FF66),
                                Colors.white,
                                Color(0xFF00FF66),
                                Colors.transparent,
                              ],
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0xFF00FF66),
                                blurRadius: 14,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 🚀 شريط الحالة الديناميكي الحي المستمر (Smart Continuous HUD)
          Positioned(
            top: scanWindowRect.bottom + 20,
            left: 20,
            right: 20,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _statusBannerText != null
                  ? Container(
                      key: ValueKey(_statusBannerText),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _statusBannerColor.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        _statusBannerText!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : Column(
                      key: const ValueKey('default_guidance'),
                      children: [
                        Text(
                          widget.continuousMode
                              ? '⚡ المسح التلقائي المستمر نشط: مرر السلع بدون توقف'
                              : 'وجّه الكاميرا نحو باركود الصنف وسيتعرف عليه فوراً',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 8),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '💡 الماسح لا يتوقف إذا لم يجد السلعة ويستمر بالبحث الذاتي',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: Color(0xFF00FF66),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          // شريط التحكم العلوي المدمج
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      onPressed: () async {
                        await _stopCamera();
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 24),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      widget.continuousMode
                          ? '🛒 كاشير سريع ($_continuousScanCount ممسوح)'
                          : '⚡ ماسح باركود فائق السرعة',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          tooltip: 'تقريب',
                          onPressed: () async {
                            _zoomScale =
                                _zoomScale >= 0.5 ? 0.0 : _zoomScale + 0.25;
                            await _controller.setZoomScale(_zoomScale);
                            setState(() {});
                          },
                          icon: Icon(
                            _zoomScale > 0
                                ? Icons.zoom_in_rounded
                                : Icons.zoom_out_rounded,
                            color: _zoomScale > 0
                                ? const Color(0xFF00FF66)
                                : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          tooltip: 'الكشاف',
                          onPressed: () async {
                            await _controller.toggleTorch();
                            setState(() => _isTorchOn = !_isTorchOn);
                          },
                          icon: Icon(
                            _isTorchOn
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                            color:
                                _isTorchOn ? Colors.amberAccent : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerDecorations extends StatelessWidget {
  const _CornerDecorations();

  @override
  Widget build(BuildContext context) {
    const double length = 28.0;
    const double thickness = 4.0;
    const Color cornerColor = Color(0xFF00FF66);

    return Stack(
      children: [
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            width: length,
            height: length,
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: cornerColor, width: thickness),
                right: BorderSide(color: cornerColor, width: thickness),
              ),
              borderRadius: BorderRadius.only(topRight: Radius.circular(20)),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          child: Container(
            width: length,
            height: length,
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: cornerColor, width: thickness),
                left: BorderSide(color: cornerColor, width: thickness),
              ),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20)),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: length,
            height: length,
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: cornerColor, width: thickness),
                right: BorderSide(color: cornerColor, width: thickness),
              ),
              borderRadius: BorderRadius.only(bottomRight: Radius.circular(20)),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          child: Container(
            width: length,
            height: length,
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: cornerColor, width: thickness),
                left: BorderSide(color: cornerColor, width: thickness),
              ),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20)),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Rect scanWindow;
  final double borderRadius;
  _ScannerOverlayPainter({
    required this.scanWindow,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(scanWindow, Radius.circular(borderRadius)),
      );
    final overlayPath =
        Path.combine(PathOperation.difference, backgroundPath, cutoutPath);
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.65);
    canvas.drawPath(overlayPath, paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) =>
      oldDelegate.scanWindow != scanWindow;
}

// ══════════════════════════════════════════════════════
// مدير الفهرسة الموحد فائق السرعة بالذاكرة العشوائية
// ══════════════════════════════════════════════════════
class BarcodeIndexManager {
  BarcodeIndexManager._();
  static final instance = BarcodeIndexManager._();
  final Map<String, Map<String, dynamic>> _index = {};
  DateTime? _lastRebuildTime;

  void ensureInitialized() {
    if (_index.isEmpty) rebuildIndex();
  }

  bool rebuildIfStale() {
    final now = DateTime.now();
    if (_lastRebuildTime == null ||
        now.difference(_lastRebuildTime!).inMinutes > 5) {
      rebuildIndex();
      return true;
    }
    return false;
  }

  void rebuildIndex() {
    _index.clear();
    final allProducts = AppCache.instance.getAllCachedProducts();
    for (final p in allProducts) {
      indexProduct(p);
    }
    _lastRebuildTime = DateTime.now();
  }

  void indexProduct(Map<String, dynamic> product) {
    if (product['is_deleted'] == true || product['is_active'] == false) return;

    void addVar(String raw) {
      final c = BarcodeScannerScreen.cleanBarcode(raw);
      if (c.isEmpty) return;
      final stripped = c.replaceFirst(RegExp(r'^0+'), '');
      _index[c] = product;
      if (stripped.isNotEmpty) {
        _index[stripped] = product;
        _index['0$stripped'] = product;
        _index['00$stripped'] = product;
      }
    }

    if (product['barcode'] != null) addVar(product['barcode'].toString());

    if (product['all_barcodes'] is List) {
      for (final b in product['all_barcodes']) {
        if (b != null) addVar(b.toString());
      }
    }

    if (product['units'] is List) {
      for (final u in product['units']) {
        if (u is Map && u['barcode'] != null) {
          addVar(u['barcode'].toString());
        }
      }
    }
  }

  Map<String, dynamic>? find(String rawCode) {
    ensureInitialized();
    final clean = BarcodeScannerScreen.cleanBarcode(rawCode);
    final stripped = clean.replaceFirst(RegExp(r'^0+'), '');
    return _index[clean] ??
        _index[stripped] ??
        _index['0$stripped'] ??
        _index['00$stripped'];
  }
}
