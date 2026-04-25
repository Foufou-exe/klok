// Onglet "Réglages" — variante Pastille.
//
// Grille 2×3 (ou 1 colonne en portrait) de cartes :
//   • Code PIN admin · modifier
//   • Établissement · modifier (change `bar.name` dans les settings)
//   • Logo · importer (TODO: pas encore câblé)
//   • Rappel sauvegarde · hebdo (TODO: UI only)
//   • Mode kiosque · actif (badge vert)
//   • Mises à jour · version + check
//
// On watch `barNameProvider`, `hasAdminPinProvider`, `lastBackupAtProvider`
// pour refléter l'état courant. Le renommage de l'établissement déclenche
// un dialog simple avec un champ texte.
//
// Ref design : variants/v2-admin.jsx (fonction V2Settings).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../design/tokens.dart';
import '../../../state/admin_session.dart';
import '../../../state/providers.dart';
import '../widgets/admin_card.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPin = ref.watch(hasAdminPinProvider).asData?.value ?? true;
    final barName = ref.watch(barNameProvider).asData?.value ?? 'Non défini';

    final items = <_SettingItem>[
      _SettingItem(
        title: 'Code PIN admin',
        sub: hasPin
            ? '8 chiffres · verrou actif'
            : 'Aucun PIN · à configurer',
        actionLabel: 'Modifier',
        onTap: () => _changePin(context, ref),
      ),
      _SettingItem(
        title: 'Établissement',
        sub: barName.isEmpty ? 'Non défini' : barName,
        actionLabel: 'Modifier',
        onTap: () => _editBarName(context, ref, barName),
      ),
      _SettingItem(
        title: 'Logo',
        sub: 'Aucun logo importé',
        actionLabel: 'Importer',
        onTap: () => _notImplemented(context, 'Import de logo'),
      ),
      _SettingItem(
        title: 'Rappel sauvegarde',
        sub: 'Hebdomadaire · lundi',
        actionLabel: 'Modifier',
        onTap: () => _notImplemented(context, 'Réglage du rappel'),
      ),
      _SettingItem(
        title: 'Mode kiosque',
        sub: 'Verrouille Klok au démarrage',
        actionLabel: 'Actif',
        badge: true,
      ),
      _SettingItem(
        title: 'Mises à jour',
        sub: 'Version 0.1.0 · à jour',
        actionLabel: 'Vérifier',
        onTap: () => _notImplemented(context, 'Vérification des MAJ'),
      ),
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Réglages',
            style: TextStyle(
              fontFamily: KlokTokens.fontDisplay,
              fontSize: 28,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.8,
              color: KlokTokens.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Configuration de l'app",
            style: TextStyle(fontSize: 14, color: KlokTokens.inkSoft),
          ),
          const SizedBox(height: 20),
          // MediaQuery au lieu de LayoutBuilder : évite la re-entrance layout
          // si un provider parent émet une valeur pendant la pose.
          Builder(
            builder: (ctx) {
              final cols = MediaQuery.sizeOf(ctx).width >= 900 ? 2 : 1;
              return _Grid(
                cols: cols,
                gap: 12,
                children: [for (final it in items) _SettingCard(item: it)],
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────
  Future<void> _editBarName(
      BuildContext context, WidgetRef ref, String current) async {
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Nom de l'établissement"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Ex : Le Comptoir d'Alphonse",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await ref.read(settingsRepositoryProvider).set(
          SettingsKeys.barName,
          result,
        );
  }

  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    // Reverrouiller et renvoyer vers l'écran PinGate qui gérera la saisie
    // (deux étapes, identique à la création initiale).
    final settings = ref.read(settingsRepositoryProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Modifier le PIN'),
        content: const Text(
            'Tu vas être renvoyé à l\'écran de déverrouillage pour redéfinir un nouveau PIN.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // On vide le hash pour déclencher le flux de création à la prochaine
    // ouverture de /admin.
    await settings.delete(SettingsKeys.pinHash);
    await settings.delete(SettingsKeys.pinSalt);
    // Invalide les providers concernés et quitte l'admin.
    ref.invalidate(hasAdminPinProvider);
    ref.read(adminUnlockedProvider.notifier).lock();
    if (!context.mounted) return;
    Navigator.of(context).maybePop();
  }

  void _notImplemented(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label : à câbler dans une future version.')),
    );
  }
}

class _SettingItem {
  _SettingItem({
    required this.title,
    required this.sub,
    required this.actionLabel,
    this.onTap,
    this.badge = false,
  });

  final String title;
  final String sub;
  final String actionLabel;
  final VoidCallback? onTap;
  final bool badge;
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.item});
  final _SettingItem item;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontFamily: KlokTokens.fontDisplay,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: KlokTokens.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: KlokTokens.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (item.badge)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: KlokTokens.successBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                item.actionLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: KlokTokens.success,
                ),
              ),
            )
          else
            _OutlineButton(label: item.actionLabel, onTap: item.onTap),
        ],
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KlokTokens.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KlokTokens.border),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KlokTokens.ink,
            ),
          ),
        ),
      ),
    );
  }
}

// Grille responsive — copie de celle du team_tab (volontairement locale
// pour garder l'onglet autonome).
class _Grid extends StatelessWidget {
  const _Grid({
    required this.cols,
    required this.gap,
    required this.children,
  });

  final int cols;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      final row = <Widget>[];
      for (var j = 0; j < cols; j++) {
        final idx = i + j;
        if (idx < children.length) {
          row.add(Expanded(child: children[idx]));
        } else {
          row.add(const Expanded(child: SizedBox.shrink()));
        }
        if (j < cols - 1) row.add(SizedBox(width: gap));
      }
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: row,
        ),
      ));
      if (i + cols < children.length) rows.add(SizedBox(height: gap));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}
