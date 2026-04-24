// Carte blanche sur fond crème — brique de base de l'admin Pastille.
// Équivalent de la fonction React V2Card : ombre sépia très douce, coins
// bien arrondis. On la centralise pour garder une densité visuelle stable
// sur tous les onglets.

import 'package:flutter/material.dart';

import '../../../design/tokens.dart';

class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = 18,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final border = BorderRadius.circular(radius);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: KlokTokens.card,
        borderRadius: border,
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D3C2814), // ~5% sepia
            offset: Offset(0, 1),
            blurRadius: 3,
          ),
          BoxShadow(
            color: Color(0x0A3C2814), // ~4%
            offset: Offset(0, 2),
            blurRadius: 12,
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (clip) {
      return ClipRRect(borderRadius: border, child: content);
    }
    return content;
  }
}
