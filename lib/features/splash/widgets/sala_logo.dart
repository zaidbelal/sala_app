import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../core/constants/app_colors.dart';

class SalaLogo extends StatelessWidget {
  final double size;
  final Color color;

  const SalaLogo({
    super.key,
    this.size = 100,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BasketPainter(color: color),
      ),
    );
  }
}

class _BasketPainter extends CustomPainter {
  final Color color;

  _BasketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── الألوان ──
    final paintFill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final paintStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.045
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final paintLight = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.030
      ..strokeCap = StrokeCap.round;

    // ══════════════════════════════════════
    // 1. المقبض (Handle)
    // ══════════════════════════════════════
    final handleRect = Rect.fromCenter(
      center: Offset(w * 0.50, h * 0.28),
      width: w * 0.44,
      height: h * 0.34,
    );
    final handlePath = Path()..addArc(handleRect, math.pi, math.pi);

    canvas.drawPath(handlePath, paintStroke);

    // ══════════════════════════════════════
    // 2. جسم السلة (Body)
    // ══════════════════════════════════════
    final bodyTop = h * 0.42;
    final bodyBottom = h * 0.88;
    final bodyLeft = w * 0.10;
    final bodyRight = w * 0.90;

    // الشكل الخارجي للسلة (شبه منحرف منحنى)
    final bodyPath = Path();
    bodyPath.moveTo(w * 0.16, bodyTop);
    bodyPath.lineTo(w * 0.84, bodyTop);
    bodyPath.quadraticBezierTo(
        bodyRight, bodyTop + h * 0.02, bodyRight, bodyTop + h * 0.06);
    bodyPath.lineTo(w * 0.92, bodyBottom - h * 0.06);
    bodyPath.quadraticBezierTo(
        bodyRight - w * 0.04, bodyBottom, w * 0.78, bodyBottom);
    bodyPath.lineTo(w * 0.22, bodyBottom);
    bodyPath.quadraticBezierTo(
        bodyLeft + w * 0.04, bodyBottom, bodyLeft, bodyBottom - h * 0.06);
    bodyPath.lineTo(bodyLeft, bodyTop + h * 0.06);
    bodyPath.quadraticBezierTo(bodyLeft, bodyTop + h * 0.02, w * 0.16, bodyTop);
    bodyPath.close();

    canvas.drawPath(bodyPath, paintFill);

    // ══════════════════════════════════════
    // 3. خطوط النسيج الأفقية
    // ══════════════════════════════════════
    const lines = 4;

    final spacing = (bodyBottom - bodyTop) / (lines + 1);

    for (int i = 1; i <= lines; i++) {
      final y = bodyTop + spacing * i;
      final shrink = (i / lines) * w * 0.05;

      canvas.drawLine(
        Offset(bodyLeft + shrink + w * 0.04, y),
        Offset(bodyRight - shrink - w * 0.04, y),
        paintLight,
      );
    }

    // ══════════════════════════════════════
    // 4. خطوط النسيج العمودية
    // ══════════════════════════════════════
    const vLines = 5;
    final vSpacing = (bodyRight - bodyLeft) / (vLines + 1);

    for (int i = 1; i <= vLines; i++) {
      final x = bodyLeft + vSpacing * i;
      canvas.drawLine(
        Offset(x, bodyTop + h * 0.04),
        Offset(x, bodyBottom - h * 0.04),
        paintLight,
      );
    }

    // ══════════════════════════════════════
    // 5. الحافة العلوية للسلة
    // ══════════════════════════════════════
    final rimPaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final rimPath = Path();
    rimPath.moveTo(w * 0.10, bodyTop);
    rimPath.lineTo(w * 0.90, bodyTop);
    rimPath.lineTo(w * 0.90, bodyTop + h * 0.07);
    rimPath.lineTo(w * 0.10, bodyTop + h * 0.07);
    rimPath.close();

    canvas.drawPath(rimPath, rimPaint);

    // ══════════════════════════════════════
    // 6. بريق علوي للعمق
    // ══════════════════════════════════════
    final glowPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.20),
          Colors.white.withValues(alpha: 0.00),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, bodyTop, w, h * 0.25))
      ..style = PaintingStyle.fill;

    final glowPath = Path();
    glowPath.moveTo(w * 0.10, bodyTop);
    glowPath.lineTo(w * 0.90, bodyTop);
    glowPath.lineTo(w * 0.90, bodyTop + h * 0.25);
    glowPath.lineTo(w * 0.10, bodyTop + h * 0.25);
    glowPath.close();

    canvas.drawPath(glowPath, glowPaint);
  }

  @override
  bool shouldRepaint(_BasketPainter oldDelegate) => oldDelegate.color != color;
}
