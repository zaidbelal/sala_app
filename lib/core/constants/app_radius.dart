import 'package:flutter/material.dart';

class AppRadius {
  AppRadius._();

  // ── القيم الأساسية ──
  static const double none = 0.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
  static const double circle = 100.0;

  // ── BorderRadius الجاهزة ──
  static const BorderRadius noneAll = BorderRadius.all(Radius.circular(none));
  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius xxlAll = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius xxxlAll = BorderRadius.all(Radius.circular(xxxl));
  static const BorderRadius circleAll =
      BorderRadius.all(Radius.circular(circle));

  // ── للبطاقات (cards) ──
  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius cardLarge = BorderRadius.all(Radius.circular(xxl));

  // ── للأزرار ──
  static const BorderRadius button = BorderRadius.all(Radius.circular(md));
  static const BorderRadius buttonRound =
      BorderRadius.all(Radius.circular(circle));

  // ── لحقول الإدخال ──
  static const BorderRadius input = BorderRadius.all(Radius.circular(md));

  // ── للصور ──
  static const BorderRadius image = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius imageSmall = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius avatar = BorderRadius.all(Radius.circular(circle));

  // ── للـ Bottom Sheet ──
  static const BorderRadius bottomSheet = BorderRadius.only(
    topLeft: Radius.circular(xxl),
    topRight: Radius.circular(xxl),
  );

  // ── للـ Snackbar ──
  static const BorderRadius snackbar = BorderRadius.all(Radius.circular(md));

  // ── للـ Chip ──
  static const BorderRadius chip = BorderRadius.all(Radius.circular(circle));

  // ── للـ Badge ──
  static const BorderRadius badge = BorderRadius.all(Radius.circular(circle));

  // ── أعلى فقط ──
  static const BorderRadius topOnly = BorderRadius.only(
    topLeft: Radius.circular(lg),
    topRight: Radius.circular(lg),
  );

  // ── أسفل فقط ──
  static const BorderRadius bottomOnly = BorderRadius.only(
    bottomLeft: Radius.circular(lg),
    bottomRight: Radius.circular(lg),
  );

  // ── RRadius مباشرة ──
  static const Radius rXS = Radius.circular(xs);
  static const Radius rSM = Radius.circular(sm);
  static const Radius rMD = Radius.circular(md);
  static const Radius rLG = Radius.circular(lg);
  static const Radius rXL = Radius.circular(xl);
  static const Radius rCircle = Radius.circular(circle);
}
