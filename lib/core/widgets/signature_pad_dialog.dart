import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../constants/app_colors.dart';

class DigitalSignatureDialog extends StatefulWidget {
  final String orderId;
  final String merchantName;

  const DigitalSignatureDialog({
    super.key,
    required this.orderId,
    required this.merchantName,
  });

  static Future<String?> show(BuildContext context,
      {required String orderId, required String merchantName}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          DigitalSignatureDialog(orderId: orderId, merchantName: merchantName),
    );
  }

  @override
  State<DigitalSignatureDialog> createState() => _DigitalSignatureDialogState();
}

class _DigitalSignatureDialogState extends State<DigitalSignatureDialog> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  bool _isSaving = false;

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentStroke = [details.localPosition];
      _strokes.add(_currentStroke);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentStroke.add(details.localPosition);
    });
  }

  void _clear() {
    HapticFeedback.lightImpact();
    setState(() {
      _strokes.clear();
      _currentStroke = [];
    });
  }

  Future<void> _saveSignature() async {
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى التوقيع أولاً في المربع المخصص',
              style: TextStyle(fontFamily: 'Cairo')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1. تحويل التوقيع إلى صورة PNG شفافة
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 400, 200));
      final painter = _SignaturePainter(strokes: _strokes);
      painter.paint(canvas, const Size(400, 200));
      final picture = recorder.endRecording();
      final img = await picture.toImage(400, 200);
      picture.dispose();
      final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();

      if (pngBytes == null) throw StateError('فشل معالجة التوقيع');
      final bytes = pngBytes.buffer.asUint8List();

      String? signatureUrl;
      // 2. محاولة الرفع السحابي أولاً، والتحول التلقائي لـ Base64 محلياً عند انقطاع الإنترنت
      try {
        final ref = FirebaseStorage.instance.ref().child('signatures').child(
            'order_${widget.orderId}_${DateTime.now().millisecondsSinceEpoch}.png');

        await ref
            .putData(bytes, SettableMetadata(contentType: 'image/png'))
            .timeout(const Duration(seconds: 4));

        signatureUrl = await ref.getDownloadURL();
      } catch (_) {
        // ✅ دعم العمل أوفلاين: تحويل التوقيع فوراً إلى Base64 Data URL لمنع تعطل السائق
        final base64String = base64Encode(bytes);
        signatureUrl = 'data:image/png;base64,$base64String';
      }

      // 3. تحديث الطلب في Firestore (يعمل أونلاين وأوفلاين معاً)
      unawaited(
        FirebaseFirestore.instance
            .collection('orders')
            .doc(widget.orderId)
            .update({
          'signature_url': signatureUrl,
          'signed_at': FieldValue.serverTimestamp(),
          'signed_by': widget.merchantName,
        }).catchError((_) {}),
      );

      if (mounted) {
        Navigator.of(context).pop(signatureUrl);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر الحفظ: $e',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: !_isSaving,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.draw_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'التوقيع الرقمي للاستلام',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.w800),
                    ),
                    Text(
                      widget.merchantName,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'اطلب من التاجر / المستلم التوقيع بإصبعه داخل المربع أدناه لتأكيد استلام الطلب رسمياً:',
                style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300, width: 1.5),
                ),
                child: GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CustomPaint(
                      painter: _SignaturePainter(strokes: _strokes),
                      size: const Size(double.infinity, 180),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: _isSaving ? null : _clear,
              icon: const Icon(Icons.cleaning_services_rounded,
                  size: 16, color: Colors.grey),
              label: const Text('مسح',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
            ),
            TextButton(
              onPressed: _isSaving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveSignature,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(_isSaving ? 'جاري الحفظ...' : 'اعتماد التوقيع',
                  style: const TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ));
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SignaturePainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.5;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      // ✅ دعم رسم النقاط المفردة الناتجة عن لمس الشاشة بدون سحب (مثل نقاط الحروف العربية)
      if (stroke.length == 1) {
        canvas.drawCircle(
          stroke.first,
          paint.strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
      } else {
        paint.style = PaintingStyle.stroke;
        for (int i = 0; i < stroke.length - 1; i++) {
          canvas.drawLine(stroke[i], stroke[i + 1], paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
