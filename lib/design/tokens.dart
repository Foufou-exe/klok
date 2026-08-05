// Klok — design tokens (variante Pastille).
//
// Les couleurs sources viennent de la réf Claude Design en `oklch()`. Flutter
// ne parse pas l'espace OKLCH nativement, donc on convertit en sRGB une fois
// au chargement de la classe (static final → calculé au premier accès).
// Référence : `Klok.html` / `variants/v2-pastille.jsx` dans le dossier design.

import 'dart:math' as math;
import 'package:flutter/material.dart';

class KlokTokens {
  KlokTokens._();

  // ---------- Neutres (crème chaud) ----------
  static final Color cream50 = _oklch(0.985, 0.008, 75);
  static final Color cream100 = _oklch(0.97, 0.015, 70);
  static final Color cream200 = _oklch(0.94, 0.02, 68);
  static final Color cream300 = _oklch(0.88, 0.025, 65);
  static final Color cream400 = _oklch(0.75, 0.03, 60);

  // ---------- Encre (texte) ----------
  static final Color ink = _oklch(0.22, 0.04, 30); // V2 principal
  static final Color inkSoft = _oklch(0.45, 0.04, 40); // V2 secondaire
  static final Color ink600 = _oklch(0.42, 0.04, 40);
  static final Color ink800 = _oklch(0.28, 0.05, 30);
  static final Color ink900 = _oklch(0.18, 0.04, 30);

  // ---------- Surfaces (variante Pastille) ----------
  static final Color bg = _oklch(0.97, 0.02, 72);
  static final Color bgDeep = _oklch(0.94, 0.025, 70);
  static const Color card = Color(0xFFFFFFFF);
  static final Color muted = _oklch(0.72, 0.03, 60);
  static final Color border = _oklch(0.9, 0.02, 65);

  // ---------- Accents chauds ----------
  static final Color amber = _oklch(0.72, 0.15, 65);
  static final Color amber600 = _oklch(0.68, 0.17, 60);
  static final Color amberBg = _oklch(0.95, 0.05, 75);
  static final Color terra = _oklch(0.6, 0.16, 38);
  static final Color terra700 = _oklch(0.48, 0.14, 35);
  static final Color bordeaux = _oklch(0.42, 0.13, 25);
  static final Color bordeaux900 = _oklch(0.25, 0.08, 25);

  // ---------- Sémantique ----------
  static final Color success = _oklch(0.6, 0.13, 150);
  static final Color successBg = _oklch(0.94, 0.04, 150);
  static final Color warn = _oklch(0.75, 0.14, 75);
  static final Color danger = _oklch(0.58, 0.18, 25);

  // ---------- Rayons ----------
  static const double radiusSm = 8;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusXl = 28;
  static const double radiusPill = 999;

  // ---------- Ombres (teinte sépia — accord avec le fond crème) ----------
  // Opacités hex sur couleur sépia #3C2814 : 0F=6%, 0A=4%, 14=8%, 1F=12%, 19=10%.
  static const List<BoxShadow> shadowSm = <BoxShadow>[
    BoxShadow(color: Color(0x0F3C2814), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0A3C2814), offset: Offset(0, 1), blurRadius: 3),
  ];
  static const List<BoxShadow> shadowMd = <BoxShadow>[
    BoxShadow(color: Color(0x143C2814), offset: Offset(0, 2), blurRadius: 6),
    BoxShadow(color: Color(0x0F3C2814), offset: Offset(0, 6), blurRadius: 20),
  ];
  static const List<BoxShadow> shadowLg = <BoxShadow>[
    BoxShadow(color: Color(0x1F3C2814), offset: Offset(0, 4), blurRadius: 12),
    BoxShadow(color: Color(0x193C2814), offset: Offset(0, 16), blurRadius: 40),
  ];

  // ---------- Typographie ----------
  static const String fontDisplay = 'InterTight';
  static const String fontText = 'Inter';
  static const String fontMono = 'JetBrainsMono';

  /// `FontFeature`s pour les chiffres proportionnels type "horloge" :
  /// tnum bloque la chasse des chiffres pour éviter le sautillement.
  static const List<FontFeature> tabularFigures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];
}

// ─────────────────────────────────────────────────────────────
// Helpers de conversion OKLCH → sRGB.
// Transformée de Björn Ottosson (https://bottosson.github.io/posts/oklab/).
// ─────────────────────────────────────────────────────────────

Color _oklch(double l, double c, double hDeg) {
  // OKLCH → OKLab (polar → cartesian)
  final hRad = hDeg * math.pi / 180.0;
  final a = c * math.cos(hRad);
  final b = c * math.sin(hRad);

  // OKLab → LMS' (linéaire, avant cube)
  final lPrime = l + 0.3963377774 * a + 0.2158037573 * b;
  final mPrime = l - 0.1055613458 * a - 0.0638541728 * b;
  final sPrime = l - 0.0894841775 * a - 1.2914855480 * b;

  final lCube = lPrime * lPrime * lPrime;
  final mCube = mPrime * mPrime * mPrime;
  final sCube = sPrime * sPrime * sPrime;

  // LMS → linear sRGB
  final r = 4.0767416621 * lCube - 3.3077115913 * mCube + 0.2309699292 * sCube;
  final g = -1.2684380046 * lCube + 2.6097574011 * mCube - 0.3413193965 * sCube;
  final bl =
      -0.0041960863 * lCube - 0.7034186147 * mCube + 1.7076147010 * sCube;

  return Color.fromRGBO(
    (_gammaEncode(r) * 255).round().clamp(0, 255),
    (_gammaEncode(g) * 255).round().clamp(0, 255),
    (_gammaEncode(bl) * 255).round().clamp(0, 255),
    1,
  );
}

double _gammaEncode(double linear) {
  if (linear <= 0) return 0;
  if (linear >= 1) return 1;
  if (linear <= 0.0031308) return 12.92 * linear;
  return 1.055 * math.pow(linear, 1 / 2.4).toDouble() - 0.055;
}
