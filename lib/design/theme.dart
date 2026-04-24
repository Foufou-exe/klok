// Klok — thème Material 3 version Pastille.
//
// Enveloppe les tokens en un `ThemeData` exploitable partout. Le principe :
// tout composant Material (bouton, card, app bar) doit déjà avoir la bonne
// gueule sans qu'on ait à le restyler, grâce aux sous-thèmes ci-dessous.

import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildKlokTheme() {
  final scheme = ColorScheme(
    brightness: Brightness.light,
    // Rôles primaires — bordeaux pour les actions structurantes de l'app
    // (admin, export, boutons de l'écran salarié avec fort signal).
    primary: KlokTokens.bordeaux,
    onPrimary: Colors.white,
    primaryContainer: KlokTokens.bordeaux900,
    onPrimaryContainer: Colors.white,
    // Secondaire — amber/terra pour les pauses / actions chaudes.
    secondary: KlokTokens.amber,
    onSecondary: Colors.white,
    secondaryContainer: KlokTokens.amberBg,
    onSecondaryContainer: KlokTokens.amber600,
    // Tertiaire — terra pour les accents graphiques.
    tertiary: KlokTokens.terra,
    onTertiary: Colors.white,
    // Erreur — danger (rouge chaud).
    error: KlokTokens.danger,
    onError: Colors.white,
    // Surfaces — carton crème.
    surface: KlokTokens.card,
    onSurface: KlokTokens.ink,
    surfaceContainerLowest: KlokTokens.bg,
    surfaceContainerLow: KlokTokens.bgDeep,
    surfaceContainer: KlokTokens.card,
    surfaceContainerHigh: KlokTokens.card,
    surfaceContainerHighest: KlokTokens.cream100,
    onSurfaceVariant: KlokTokens.inkSoft,
    outline: KlokTokens.border,
    outlineVariant: KlokTokens.muted,
    // Shadow/inverse/scrim — laissés par défaut (Material saura faire).
    shadow: const Color(0xFF3C2814),
    scrim: const Color(0xAA000000),
    inverseSurface: KlokTokens.ink,
    onInverseSurface: KlokTokens.cream100,
    inversePrimary: KlokTokens.amber,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: KlokTokens.bg,
    canvasColor: KlokTokens.bg,
    fontFamily: KlokTokens.fontText,
    textTheme: _buildTextTheme(),
    primaryTextTheme: _buildTextTheme(),

    // AppBar : neutre, intégrée au fond crème (pas de barre qui tranche).
    appBarTheme: AppBarTheme(
      backgroundColor: KlokTokens.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: KlokTokens.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: KlokTokens.fontDisplay,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: KlokTokens.ink,
        letterSpacing: -0.3,
      ),
    ),

    // Boutons remplis — grand tap target tablette + radius généreux.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: KlokTokens.bordeaux,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        minimumSize: const Size(88, 56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KlokTokens.radiusMd),
        ),
        textStyle: const TextStyle(
          fontFamily: KlokTokens.fontDisplay,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: KlokTokens.card,
        foregroundColor: KlokTokens.ink,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KlokTokens.radiusMd),
          side: BorderSide(color: KlokTokens.border),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: KlokTokens.ink,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KlokTokens.radiusMd),
        ),
        side: BorderSide(color: KlokTokens.border),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: KlokTokens.inkSoft,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),

    // Cards — blanches sur fond crème, ombre sépia douce.
    cardTheme: CardThemeData(
      color: KlokTokens.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KlokTokens.radiusLg),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: KlokTokens.border,
      thickness: 1,
      space: 1,
    ),

    // Inputs — grands, doux, lisibles debout derrière un bar.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KlokTokens.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KlokTokens.radiusMd),
        borderSide: BorderSide(color: KlokTokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KlokTokens.radiusMd),
        borderSide: BorderSide(color: KlokTokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KlokTokens.radiusMd),
        borderSide: BorderSide(color: KlokTokens.bordeaux, width: 2),
      ),
      labelStyle: TextStyle(color: KlokTokens.inkSoft),
      hintStyle: TextStyle(color: KlokTokens.muted),
    ),

    iconTheme: IconThemeData(color: KlokTokens.inkSoft, size: 20),
    splashFactory: InkSparkle.splashFactory,
  );
}

TextTheme _buildTextTheme() {
  const display = KlokTokens.fontDisplay;
  const text = KlokTokens.fontText;
  final ink = KlokTokens.ink;
  final inkSoft = KlokTokens.inkSoft;

  return TextTheme(
    // Gros titres écran (ex. "Bon service !", "Salut Marie")
    displayLarge: TextStyle(
      fontFamily: display,
      fontSize: 56,
      fontWeight: FontWeight.w500,
      letterSpacing: -1.5,
      color: ink,
      height: 1.05,
    ),
    displayMedium: TextStyle(
      fontFamily: display,
      fontSize: 42,
      fontWeight: FontWeight.w500,
      letterSpacing: -1.2,
      color: ink,
      height: 1.0,
    ),
    displaySmall: TextStyle(
      fontFamily: display,
      fontSize: 34,
      fontWeight: FontWeight.w500,
      letterSpacing: -1.0,
      color: ink,
    ),
    // Titres de section (admin)
    headlineLarge: TextStyle(
      fontFamily: display,
      fontSize: 32,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.8,
      color: ink,
    ),
    headlineMedium: TextStyle(
      fontFamily: display,
      fontSize: 28,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.8,
      color: ink,
    ),
    headlineSmall: TextStyle(
      fontFamily: display,
      fontSize: 22,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
      color: ink,
    ),
    // Titres de carte / boutons
    titleLarge: TextStyle(
      fontFamily: display,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontFamily: text,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    titleSmall: TextStyle(
      fontFamily: text,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    // Corps
    bodyLarge: TextStyle(
      fontFamily: text,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: ink,
    ),
    bodyMedium: TextStyle(
      fontFamily: text,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: ink,
    ),
    bodySmall: TextStyle(
      fontFamily: text,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: inkSoft,
    ),
    // Labels
    labelLarge: TextStyle(
      fontFamily: text,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: ink,
    ),
    labelMedium: TextStyle(
      fontFamily: text,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: inkSoft,
    ),
    labelSmall: TextStyle(
      fontFamily: text,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: inkSoft,
    ),
  );
}

/// Style pour les chiffres monospacés (horloges, totaux). Appliquer par-dessus
/// un style existant : `Theme.of(ctx).textTheme.displayLarge!.merge(klokNum)`.
const TextStyle klokNum = TextStyle(
  fontFeatures: KlokTokens.tabularFigures,
  fontVariations: <FontVariation>[FontVariation('wght', 500)],
);
