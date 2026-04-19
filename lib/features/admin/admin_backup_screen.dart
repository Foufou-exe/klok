import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/settings_repository.dart';
import '../../services/backup_service.dart';
import '../../state/providers.dart';

class AdminBackupScreen extends ConsumerStatefulWidget {
  const AdminBackupScreen({super.key});

  @override
  ConsumerState<AdminBackupScreen> createState() =>
      _AdminBackupScreenState();
}

class _AdminBackupScreenState extends ConsumerState<AdminBackupScreen> {
  bool _busy = false;
  String? _status;

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final svc = BackupService(ref.read(databaseProvider));
      final result = await svc.exportAll();
      await ref
          .read(settingsRepositoryProvider)
          .set(SettingsKeys.lastBackupAt, DateTime.now().toIso8601String());
      await svc.share(result);
      setState(() => _status = 'Sauvegarde exportée.');
    } catch (e) {
      setState(() => _status = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null) {
      setState(() => _status = 'Fichier illisible.');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final bytes = await File(path).readAsBytes();
      final svc = BackupService(ref.read(databaseProvider));
      final preview = svc.inspect(bytes);
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restaurer cette sauvegarde ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Exportée le ${DateFormat('dd/MM/yyyy HH:mm').format(preview.exportedAt.toLocal())}'),
              Text('Version app : ${preview.appVersion}'),
              Text('Schéma DB : v${preview.schemaVersion}'),
              const SizedBox(height: 8),
              Text('${preview.employeeCount} salariés'),
              Text('${preview.sessionCount} sessions'),
              Text('${preview.breakCount} pauses'),
              Text('${preview.settingCount} réglages'),
              const SizedBox(height: 16),
              const Text(
                '⚠ Toutes les données actuelles seront remplacées.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restaurer'),
            ),
          ],
        ),
      );
      if (ok != true) {
        setState(() => _status = 'Restauration annulée.');
        return;
      }
      await svc.restore(bytes);
      setState(() => _status = 'Sauvegarde restaurée.');
    } catch (e) {
      setState(() => _status = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastBackup = ref.watch(FutureProvider<String?>((ref) =>
        ref.watch(settingsRepositoryProvider).get(SettingsKeys.lastBackupAt)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sauvegarde'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/home'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dernière sauvegarde',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      lastBackup.when(
                        data: (v) => Text(v == null
                            ? 'Jamais'
                            : DateFormat('dd/MM/yyyy HH:mm')
                                .format(DateTime.parse(v).toLocal())),
                        loading: () => const Text('…'),
                        error: (_, _) => const Text('—'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.upload),
                label: const Text('Exporter la sauvegarde'),
                onPressed: _busy ? null : _export,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Importer une sauvegarde'),
                onPressed: _busy ? null : _import,
              ),
              const SizedBox(height: 24),
              if (_busy) const Center(child: CircularProgressIndicator()),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_status!,
                      style: Theme.of(context).textTheme.bodyLarge),
                ),
              const SizedBox(height: 16),
              const Text(
                'La sauvegarde contient tous les salariés, les sessions de travail, '
                'les pauses et les réglages. Partagez-la sur un drive ou une clé '
                'USB pour la conserver en lieu sûr.',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
