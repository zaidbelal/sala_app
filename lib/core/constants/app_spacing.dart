import 'package:flutter/material.dart';

class AppSpacing {
  AppSpacing._();

  // ── القيم الأساسية ──
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
  static const double huge = 48.0;
  static const double giant = 64.0;

  // ── Padding الأكثر استخداماً ──
  static const EdgeInsets paddingXS = EdgeInsets.all(xs);
  static const EdgeInsets paddingSM = EdgeInsets.all(sm);
  static const EdgeInsets paddingMD = EdgeInsets.all(md);
  static const EdgeInsets paddingLG = EdgeInsets.all(lg);
  static const EdgeInsets paddingXL = EdgeInsets.all(xl);
  static const EdgeInsets paddingXXL = EdgeInsets.all(xxl);

  // ── Padding أفقي ──
  static const EdgeInsets horizontalXS = EdgeInsets.symmetric(horizontal: xs);
  static const EdgeInsets horizontalSM = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets horizontalMD = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets horizontalLG = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets horizontalXL = EdgeInsets.symmetric(horizontal: xl);
  static const EdgeInsets horizontalXXL = EdgeInsets.symmetric(horizontal: xxl);

  // ── Padding عمودي ──
  static const EdgeInsets verticalXS = EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets verticalSM = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets verticalMD = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets verticalLG = EdgeInsets.symmetric(vertical: lg);
  static const EdgeInsets verticalXL = EdgeInsets.symmetric(vertical: xl);
  static const EdgeInsets verticalXXL = EdgeInsets.symmetric(vertical: xxl);

  // ── Padding الشاشات (page padding) ──
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: lg,
  );

  static const EdgeInsets pageHorizontal = EdgeInsets.symmetric(
    horizontal: lg,
  );

  static const EdgeInsets cardPadding = EdgeInsets.all(lg);

  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );

  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: xxl,
    vertical: md,
  );

  static const EdgeInsets inputPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );

  static const EdgeInsets chipPadding = EdgeInsets.symmetric(
    horizontal: md,
    vertical: xs,
  );

  // ── SizedBox الجاهزة (استخدمها مباشرة) ──
  static const Widget gapXS = SizedBox(height: xs, width: xs);
  static const Widget gapSM = SizedBox(height: sm, width: sm);
  static const Widget gapMD = SizedBox(height: md, width: md);
  static const Widget gapLG = SizedBox(height: lg, width: lg);
  static const Widget gapXL = SizedBox(height: xl, width: xl);
  static const Widget gapXXL = SizedBox(height: xxl, width: xxl);
  static const Widget gapXXXL = SizedBox(height: xxxl, width: xxxl);

  static const Widget hXS = SizedBox(height: xs);
  static const Widget hSM = SizedBox(height: sm);
  static const Widget hMD = SizedBox(height: md);
  static const Widget hLG = SizedBox(height: lg);
  static const Widget hXL = SizedBox(height: xl);
  static const Widget hXXL = SizedBox(height: xxl);
  static const Widget hXXXL = SizedBox(height: xxxl);
  static const Widget hHuge = SizedBox(height: huge);

  static const Widget wXS = SizedBox(width: xs);
  static const Widget wSM = SizedBox(width: sm);
  static const Widget wMD = SizedBox(width: md);
  static const Widget wLG = SizedBox(width: lg);
  static const Widget wXL = SizedBox(width: xl);
  static const Widget wXXL = SizedBox(width: xxl);
  static const Widget wXXXL = SizedBox(width: xxxl);
}
