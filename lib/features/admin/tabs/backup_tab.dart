// Onglet "Sauvegarde" — variante Pastille.
//
// Deux cartes côte à côte :
//   • Exporter tout → sérialise toute la DB en JSON, écrit un fichier dans le
//     répertoire temporaire, puis ouvre le partage natif (share_plus). On
//     stamp `SettingsKeys.lastBackupAt` au passage pour faire vivre la pastille
//     "Dernière sauvegarde · il y a N jours" du dashboard.
//   • Restaurer → file_picker pour choisir un .json klok, lecture du payload,
//     vérif checksum, dialog de prévisualisation, puis remplace l'intégralité
//     de la DB en transaction. Stratégie volontairement simple : on remplace
//     tout, pas de merge — c'est la garantie que ce qui est dans le fichier
//     se retrouve à l'identique en DB.
//
// Ref design : variants/v2-admin.jsx (fonction V2Backup).

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../design/tokens.dart';
import '../../../services/backup_service.dart';
import '../../../state/providers.dart';
import '../widgets/admin_card.dart';

class BackupTab extends ConsumerWidget {
  const BackupTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sauvegarde',
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
            'Fichier unique portable · hors-ligne',
            style: TextStyle(fontSize: 14, color: KlokTokens.inkSoft),
          ),
          const SizedBox(height: 20),
          // MediaQuery au lieu de LayoutBuilder : évite la re-entrance layout
          // déclenchée par un ConsumerWidget enfant (lastBackupAtProvider) qui
          // émettrait pendant la pose du LayoutBuilder.
          Builder(
            builder: (ctx) {
              final wide = MediaQuery.sizeOf(ctx).width >= 900;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Expanded(child: _ExportCard()),
                    SizedBox(width: 16),
                    Expanded(child: _RestoreCard()),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  _ExportCard(),
                  SizedBox(height: 16),
                  _RestoreCard(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Carte "Exporter tout"
// ─────────────────────────────────────────────────────────────
class _ExportCard extends ConsumerWidget {
  const _ExportCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastBackupAtProvider).asData?.value;
    final now = DateTime.now();
    final filename =
        'klok-backup-${DateFormat('yyyy-MM-dd').format(now)}.zip';

    String lastLabel;
    if (last == null) {
      lastLabel = 'Aucune sauvegarde enregistrée';
    } else {
      final parsed = DateTime.tryParse(last)?.toLocal();
      lastLabel = parsed != null
          ? DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR').format(parsed)
          : '—';
    }

    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconBadge(
                icon: Icons.file_download_outlined,
                bg: KlokTokens.successBg,
                fg: KlokTokens.success,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Exporter tout',
                      style: TextStyle(
                        fontFamily: KlokTokens.fontDisplay,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: KlokTokens.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Salariés · sessions · pauses · réglages',
                      style: TextStyle(
                          fontSize: 13, color: KlokTokens.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KlokTokens.bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  style: TextStyle(
                    fontFamily: KlokTokens.fontMono,
                    fontSize: 12,
                    color: KlokTokens.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Contenu généré à l\'instant',
                  style: TextStyle(
                    fontSize: 12,
                    color: KlokTokens.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PrimaryDark(
            label: 'Exporter maintenant',
            onTap: () => _triggerExport(context, ref),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Dernière : ',
                style:
                    TextStyle(fontSize: 12, color: KlokTokens.inkSoft),
              ),
              Expanded(
                child: Text(
                  lastLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: KlokTokens.ink,
                    fontFeatures: KlokTokens.tabularFigures,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _triggerExport(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final backup = ref.read(backupServiceProvider);
      final result = await backup.exportAll();
      // On stamp la date dès que le fichier est écrit (avant share) — comme
      // ça même si l'utilisateur annule la sheet de partage on a quand même
      // une trace que l'export s'est fait localement.
      await ref.read(settingsRepositoryProvider).set(
            SettingsKeys.lastBackupAt,
            DateTime.now().toUtc().toIso8601String(),
          );
      await backup.share(result);
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Échec de l'export : $e")),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Carte "Restaurer"
// ─────────────────────────────────────────────────────────────
class _RestoreCard extends ConsumerWidget {
  const _RestoreCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconBadge(
                icon: Icons.file_upload_outlined,
                bg: KlokTokens.amberBg,
                fg: KlokTokens.amber,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Restaurer',
                      style: TextStyle(
                        fontFamily: KlokTokens.fontDisplay,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: KlokTokens.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Remplace les données actuelles',
                      style: TextStyle(
                          fontSize: 13, color: KlokTokens.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _DashedDropzone(
            onBrowse: () => _pickAndRestore(context, ref),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KlokTokens.amberBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: KlokTokens.ink,
                ),
                children: [
                  const TextSpan(
                    text: 'Attention',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' — la restauration '),
                  const TextSpan(
                    text: 'remplace tout',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                      text: '. Un aperçu s\'affichera avant confirmation.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Restore : pick le fichier → vérifie le checksum → preview → restore
// ─────────────────────────────────────────────────────────────
Future<void> _pickAndRestore(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  // file_picker 11.x : `pickFiles` est une méthode statique sur la classe
  // FilePicker (avant : FilePicker.platform.pickFiles).
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    // Note : sur Android, le filtre extension n'est pas garanti par toutes
    // les implémentations, mais on récupère un .json klok dans la majorité
    // des cas. La validation se fait quand même via inspect() côté service.
    allowedExtensions: const ['json'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return;

  // `withData: true` sert sur web ; sur mobile on a souvent path mais pas
  // bytes, donc on retombe sur File.readAsBytes si nécessaire.
  Uint8List? bytes = picked.files.single.bytes;
  if (bytes == null) {
    final path = picked.files.single.path;
    if (path == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Impossible de lire le fichier.')),
      );
      return;
    }
    bytes = await File(path).readAsBytes();
  }

  final backup = ref.read(backupServiceProvider);
  RestorePreview preview;
  try {
    preview = backup.inspect(bytes);
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Sauvegarde invalide : $e')),
    );
    return;
  }

  if (!context.mounted) return;
  final confirm = await _showRestorePreview(context, preview);
  if (confirm != true) return;

  try {
    await backup.restore(bytes);
    // Invalider explicitement les providers qui dépendent de settings/PIN —
    // le routeur peut nous renvoyer en onboarding sinon (si le fichier n'a
    // pas de PIN, peu probable mais robuste).
    ref.invalidate(hasAdminPinProvider);
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Échec de la restauration : $e')),
    );
    return;
  }

  if (!context.mounted) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        'Restauration OK · ${preview.employeeCount} salariés, '
        '${preview.sessionCount} sessions importés.',
      ),
    ),
  );
}

Future<bool?> _showRestorePreview(
    BuildContext context, RestorePreview p) async {
  final stamp = DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR')
      .format(p.exportedAt.toLocal());
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Restaurer cette sauvegarde ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Exportée le $stamp'),
          const SizedBox(height: 6),
          Text('Version klok : ${p.appVersion}'),
          const SizedBox(height: 12),
          Text('Contenu du fichier :',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: KlokTokens.ink,
              )),
          const SizedBox(height: 4),
          Text('• ${p.employeeCount} salariés'),
          Text('• ${p.sessionCount} sessions de travail'),
          Text('• ${p.breakCount} pauses'),
          Text('• ${p.settingCount} réglages'),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: KlokTokens.amberBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "⚠️  Toutes les données actuelles seront écrasées. Action "
              'irréversible (sauf si tu as fait une autre sauvegarde avant).',
              style: TextStyle(fontSize: 12, color: KlokTokens.ink),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: KlokTokens.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Tout remplacer'),
        ),
      ],
    ),
  );
}

class _DashedDropzone extends StatelessWidget {
  const _DashedDropzone({required this.onBrowse});
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: KlokTokens.border, radius: 12),
      child: Container(
        decoration: BoxDecoration(
          color: KlokTokens.bg,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(
          children: [
            Text.rich(
              TextSpan(
                style:
                    TextStyle(fontSize: 13, color: KlokTokens.inkSoft),
                children: [
                  const TextSpan(text: 'Dépose un fichier '),
                  TextSpan(
                    text: '.zip',
                    style: TextStyle(
                      fontFamily: KlokTokens.fontMono,
                      color: KlokTokens.ink,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Material(
              color: KlokTokens.card,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: onBrowse,
                borderRadius: BorderRadius.circular(8),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: KlokTokens.border),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  child: Text(
                    'Parcourir',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: KlokTokens.ink,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Simple dashed border painter — Flutter n'a pas d'équivalent natif à
// `border-style: dashed`, donc on peint le tracé autour du container.
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(rrect);
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final len =
            (dist + dash < metric.length) ? dash : metric.length - dist;
        canvas.drawPath(metric.extractPath(dist, dist + len), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

// ─────────────────────────────────────────────────────────────
// Widgets partagés
// ─────────────────────────────────────────────────────────────
class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.bg,
    required this.fg,
  });

  final IconData icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: fg),
    );
  }
}

class _PrimaryDark extends StatelessWidget {
  const _PrimaryDark({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KlokTokens.ink,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
