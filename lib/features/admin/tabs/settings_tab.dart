// Onglet "Réglages" — variante Pastille.
//
// 6 cartes (grille 2×3 en paysage, 1 colonne en portrait) :
//   • Code PIN admin · modifier (relance le flow PIN gate en mode création)
//   • Établissement · modifier (édite `bar.name` via dialog)
//   • Logo · importer (file_picker → copie le fichier dans appDocs)
//   • Rappel sauvegarde · jamais / hebdo / mensuel (radio dans dialog)
//   • Mode kiosque · informationnel (le vrai lock-task mode demande de
//     l'Android natif, hors scope ici — on documente l'état au patron)
//   • Mises à jour · informationnel (pas de serveur de MAJ → on stamp la
//     date du dernier check manuel pour mémoire)
//
// On watch les providers correspondants pour que les sous-titres reflètent
// l'état courant en live (logo importé, freq du rappel, version, etc.).
//
// Ref design : variants/v2-admin.jsx (fonction V2Settings).

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/version.dart';
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
    final logoPath = ref.watch(logoPathProvider).asData?.value;
    final reminderFreq = ref.watch(backupReminderFreqProvider).asData?.value;
    final lastUpdateCheck =
        ref.watch(lastUpdateCheckAtProvider).asData?.value;

    final reminder = _BackupReminderFreq.parse(reminderFreq);

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
        sub: logoPath == null || logoPath.isEmpty
            ? 'Aucun logo importé'
            : 'Importé : ${p.basename(logoPath)}',
        actionLabel: logoPath == null || logoPath.isEmpty
            ? 'Importer'
            : 'Remplacer',
        onTap: () => _importLogo(context, ref),
        // Si un logo est déjà là, on offre une action secondaire "Retirer" via
        // un long press (geste avancé, pas de bouton car on tient à 2 actions
        // max sur la carte). Documenté pour le patron dans le snackbar.
        onSecondaryTap: logoPath == null || logoPath.isEmpty
            ? null
            : () => _removeLogo(context, ref, logoPath),
      ),
      _SettingItem(
        title: 'Rappel sauvegarde',
        sub: reminder.label,
        actionLabel: 'Modifier',
        onTap: () => _editReminder(context, ref, reminder),
      ),
      _SettingItem(
        title: 'Mode kiosque',
        sub: 'Plein écran salarié · admin verrouillé par PIN',
        actionLabel: 'Actif',
        badge: true,
      ),
      _SettingItem(
        title: 'Mises à jour',
        sub: lastUpdateCheck == null
            ? 'Version $kAppVersion · jamais vérifié'
            : 'Version $kAppVersion · ${_formatRelativeDate(lastUpdateCheck)}',
        actionLabel: 'Vérifier',
        onTap: () => _checkUpdates(context, ref),
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

  // ── Établissement ────────────────────────────────────────────
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

  // ── PIN ──────────────────────────────────────────────────────
  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    // Reverrouiller et renvoyer vers l'écran PinGate qui gérera la saisie
    // (deux étapes, identique à la création initiale).
    final settings = ref.read(settingsRepositoryProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Modifier le PIN'),
        content: const Text(
            "Tu vas être renvoyé à l'écran de déverrouillage pour redéfinir un nouveau PIN."),
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

  // ── Logo ─────────────────────────────────────────────────────
  Future<void> _importLogo(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final src = picked.files.single.path;
    if (src == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Impossible de lire le fichier choisi.')),
      );
      return;
    }
    try {
      // On copie le fichier dans appDocs/logo.<ext> pour qu'il survive aux
      // nettoyages de cache et qu'on n'ait pas à redemander à chaque MAJ.
      final docs = await getApplicationDocumentsDirectory();
      final ext = p.extension(src).toLowerCase();
      // Nom déterministe : si le patron remplace, l'ancien est écrasé.
      final dst = File(p.join(docs.path, 'klok_logo$ext'));
      // On nettoie les anciens fichiers logo.* d'autres extensions au passage.
      for (final entity in docs.listSync()) {
        if (entity is File &&
            p.basenameWithoutExtension(entity.path) == 'klok_logo' &&
            entity.path != dst.path) {
          await entity.delete();
        }
      }
      await File(src).copy(dst.path);
      await ref
          .read(settingsRepositoryProvider)
          .set(SettingsKeys.logoPath, dst.path);
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Logo importé.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Échec de l'import : $e")),
      );
    }
  }

  Future<void> _removeLogo(
      BuildContext context, WidgetRef ref, String currentPath) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final f = File(currentPath);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Ignoré : si le fichier n'existe plus, le retrait du setting suffit.
    }
    await ref.read(settingsRepositoryProvider).delete(SettingsKeys.logoPath);
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Logo retiré.')),
    );
  }

  // ── Rappel sauvegarde ────────────────────────────────────────
  Future<void> _editReminder(
    BuildContext context,
    WidgetRef ref,
    _BackupReminderFreq current,
  ) async {
    final selected = await showDialog<_BackupReminderFreq>(
      context: context,
      builder: (ctx) {
        var pending = current;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Rappel de sauvegarde'),
            // Flutter 3.32+ a deprecated groupValue/onChanged sur chaque
            // RadioListTile au profit d'un ancêtre RadioGroup<T> qui gère le
            // group value en un seul endroit.
            content: RadioGroup<_BackupReminderFreq>(
              groupValue: pending,
              onChanged: (v) {
                if (v != null) setLocal(() => pending = v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final freq in _BackupReminderFreq.values)
                    RadioListTile<_BackupReminderFreq>(
                      value: freq,
                      title: Text(freq.label),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Le rappel s\'affiche sous forme de bandeau sur l\'admin '
                    'quand la dernière sauvegarde dépasse l\'intervalle. Pas '
                    'de notif système (Klok ne demande aucune permission).',
                    style: TextStyle(
                      fontSize: 12,
                      color: KlokTokens.muted,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, pending),
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    await ref
        .read(settingsRepositoryProvider)
        .set(SettingsKeys.backupReminderFreq, selected.key);
  }

  // ── Mises à jour ─────────────────────────────────────────────
  Future<void> _checkUpdates(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    // Klok n'a pas de serveur de MAJ : on ne peut donc pas vraiment vérifier.
    // On stamp la date du check manuel — utile si plus tard on branche un
    // canal privé (Firebase App Distribution) on saura quand l'utilisateur a
    // ouvert ce dialog la dernière fois.
    await ref.read(settingsRepositoryProvider).set(
          SettingsKeys.lastUpdateCheckAt,
          DateTime.now().toUtc().toIso8601String(),
        );
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mises à jour'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version installée : $kAppVersion'),
            const SizedBox(height: 10),
            Text(
              "Klok est 100 % hors-ligne — il n'y a pas de canal automatique "
              "de mise à jour. Pour passer à une nouvelle version, ton "
              "installateur te fournira un APK signé à transférer "
              "manuellement.",
              style: TextStyle(fontSize: 13, color: KlokTokens.inkSoft),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    messenger.showSnackBar(
      const SnackBar(content: Text('Vérification notée.')),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Modèles & helpers
// ─────────────────────────────────────────────────────────────

enum _BackupReminderFreq {
  none(key: 'none', label: 'Aucun rappel'),
  weekly(key: 'weekly', label: 'Hebdomadaire · lundi'),
  monthly(key: 'monthly', label: 'Mensuel · 1er du mois');

  const _BackupReminderFreq({required this.key, required this.label});
  final String key;
  final String label;

  static _BackupReminderFreq parse(String? raw) {
    for (final f in _BackupReminderFreq.values) {
      if (f.key == raw) return f;
    }
    // Default : weekly. Cohérent avec ce que disait la sub-card avant
    // qu'on câble le réglage.
    return _BackupReminderFreq.weekly;
  }
}

String _formatRelativeDate(String iso) {
  final parsed = DateTime.tryParse(iso)?.toLocal();
  if (parsed == null) return 'jamais vérifié';
  final days = DateTime.now().difference(parsed).inDays;
  if (days <= 0) return "vérifié aujourd'hui";
  if (days == 1) return 'vérifié hier';
  if (days < 30) return 'vérifié il y a $days jours';
  return 'vérifié le ${DateFormat('dd/MM/yyyy').format(parsed)}';
}

class _SettingItem {
  _SettingItem({
    required this.title,
    required this.sub,
    required this.actionLabel,
    this.onTap,
    this.onSecondaryTap,
    this.badge = false,
  });

  final String title;
  final String sub;
  final String actionLabel;
  final VoidCallback? onTap;
  // Action secondaire optionnelle, exposée via long-press sur le bouton.
  // Utilisé p. ex. pour "Retirer le logo" sans ajouter une 2e CTA visible.
  final VoidCallback? onSecondaryTap;
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
            _OutlineButton(
              label: item.actionLabel,
              onTap: item.onTap,
              onLongPress: item.onSecondaryTap,
            ),
        ],
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.label,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KlokTokens.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
