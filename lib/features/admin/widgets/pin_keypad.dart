// Pavé numérique partagé pour la saisie de PIN.
//
// Utilisé à deux endroits :
//   • `admin_gate_screen.dart` (entrée + création quand on perd le PIN)
//   • `klok_onboarding.dart` (étape 3 — création initiale du PIN patron)
//
// L'ordre des chiffres est paramétrable via `PinKeypad.digits`. On garde un
// ordre standard 1..9, 0 pour l'onboarding (familier) et un ordre aléatoire
// pour la gate admin (anti shoulder-surfing : un voisin qui aperçoit la
// position des touches frappées ne peut pas reconstituer le code).
//
// Le shuffle est fait UNE seule fois par instance (cf. `_PinEntryState`) :
// remélanger à chaque touche serait insupportable côté UX.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../design/tokens.dart';

/// Liste 0..9 dans l'ordre standard (1,2,3,4,5,6,7,8,9,0). Le slot d'index 9
/// correspond à la case du milieu de la dernière ligne (par convention "0").
const kStandardKeypadDigits = <String>[
  '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
];

/// Renvoie une copie mélangée des chiffres 0..9 — utiliser pour la gate admin.
List<String> randomKeypadDigits([Random? rng]) {
  final r = rng ?? Random.secure();
  final list = List<String>.of(kStandardKeypadDigits);
  list.shuffle(r);
  return list;
}

/// Affiche N points alignés horizontalement ; les `filled` premiers sont
/// pleins, le reste est vide. Quand `error` est vrai, on les colore en rouge
/// et on applique un shake horizontal piloté par l'animation `shake`.
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.length,
    required this.filled,
    required this.error,
    required this.shake,
  });

  final int length;
  final int filled;
  final bool error;
  final Animation<double> shake;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shake,
      builder: (ctx, child) {
        // Courbe sinusoïdale amortie → oscillation "non-non" de ~8 px.
        final t = shake.value;
        final dx = t == 0
            ? 0.0
            : 8 * (1 - t) * (t * 20).remainder(2) - 8 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(length, (i) {
          final isFilled = i < filled;
          final color = error ? KlokTokens.danger : KlokTokens.bordeaux;
          // 8 dots à 16px + spacing 5 ≈ 233px : tient même sur un téléphone.
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isFilled ? color : Colors.transparent,
                border: Border.all(
                  color: isFilled ? color : KlokTokens.border,
                  width: 1.5,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Pavé numérique 4×3.
///
/// Layout fixe :
///   Row 1 : digits[0] digits[1] digits[2]
///   Row 2 : digits[3] digits[4] digits[5]
///   Row 3 : digits[6] digits[7] digits[8]
///   Row 4 : (vide)    digits[9] (backspace)
///
/// `digits` doit contenir exactement 10 chaînes. Pour l'ordre standard utiliser
/// `kStandardKeypadDigits`, pour un ordre aléatoire utiliser
/// `randomKeypadDigits()`.
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.digits,
    required this.onDigit,
    required this.onBackspace,
  });

  final List<String> digits;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    assert(digits.length == 10, 'PinKeypad expects exactly 10 digits');
    return SizedBox(
      width: 72 * 3 + 10 * 2,
      child: Column(
        children: [
          _row([digits[0], digits[1], digits[2]]),
          const SizedBox(height: 10),
          _row([digits[3], digits[4], digits[5]]),
          const SizedBox(height: 10),
          _row([digits[6], digits[7], digits[8]]),
          const SizedBox(height: 10),
          _row(['', digits[9], 'back']),
        ],
      ),
    );
  }

  Widget _row(List<String> items) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (items[i] == '')
            const SizedBox(width: 72, height: 72)
          else if (items[i] == 'back')
            _KeyBackspace(onTap: onBackspace)
          else
            _KeyDigit(value: items[i], onTap: () => onDigit(items[i])),
          if (i < items.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _KeyDigit extends StatelessWidget {
  const _KeyDigit({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KlokTokens.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: KlokTokens.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: KlokTokens.border),
          ),
          width: 72,
          height: 72,
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: KlokTokens.fontDisplay,
                fontSize: 26,
                fontWeight: FontWeight.w400,
                color: KlokTokens.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyBackspace extends StatelessWidget {
  const _KeyBackspace({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: KlokTokens.border),
          ),
          width: 72,
          height: 72,
          child: Icon(
            Icons.backspace_outlined,
            size: 20,
            color: KlokTokens.inkSoft,
          ),
        ),
      ),
    );
  }
}
