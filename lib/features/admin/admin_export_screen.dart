import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../data/db/app_database.dart';
import '../../services/pdf_export_service.dart';
import '../../state/providers.dart';

class AdminExportScreen extends ConsumerStatefulWidget {
  const AdminExportScreen({super.key});

  @override
  ConsumerState<AdminExportScreen> createState() => _AdminExportScreenState();
}

class _AdminExportScreenState extends ConsumerState<AdminExportScreen> {
  Employee? _selected;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _busy = false;

  DateTime get _from => DateTime(_month.year, _month.month).toUtc();
  DateTime get _to => DateTime(_month.year, _month.month + 1)
      .subtract(const Duration(seconds: 1))
      .toUtc();

  Future<void> _export() async {
    final emp = _selected;
    if (emp == null) return;
    setState(() => _busy = true);
    try {
      final sessions = await ref
          .read(sessionRepositoryProvider)
          .sessionsInRange(emp.id, _from, _to);
      final breaks = await ref
          .read(sessionRepositoryProvider)
          .breaksForSessions(sessions.map((s) => s.id).toList());
      final pdf = await PdfExportService().buildPayroll(PayrollReport(
        employee: emp,
        from: _from,
        to: _to,
        sessions: sessions,
        breaks: breaks,
      ));
      final fileName =
          'klok_${emp.lastName}_${emp.firstName}_${DateFormat('yyyy-MM').format(_month)}.pdf';
      await Printing.sharePdf(bytes: pdf, filename: fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    final emp = _selected;
    if (emp == null) return;
    setState(() => _busy = true);
    try {
      final sessions = await ref
          .read(sessionRepositoryProvider)
          .sessionsInRange(emp.id, _from, _to);
      final breaks = await ref
          .read(sessionRepositoryProvider)
          .breaksForSessions(sessions.map((s) => s.id).toList());
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Aperçu')),
            body: PdfPreview(
              build: (_) => PdfExportService().buildPayroll(PayrollReport(
                employee: emp,
                from: _from,
                to: _to,
                sessions: sessions,
                breaks: breaks,
              )),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(allEmployeesProvider);
    final monthLabel =
        DateFormat('MMMM yyyy', 'fr_FR').format(_month);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export PDF'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/home'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              employees.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Erreur : $e'),
                data: (list) => DropdownButtonFormField<Employee>(
                  initialValue: _selected,
                  decoration: const InputDecoration(
                    labelText: 'Salarié',
                    border: OutlineInputBorder(),
                  ),
                  items: list
                      .map((e) => DropdownMenuItem(
                            value: e,
                            child: Text('${e.firstName} ${e.lastName}'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selected = v),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() => _month = DateTime(
                        _month.year, _month.month - 1)),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        monthLabel,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _month = DateTime(
                        _month.year, _month.month + 1)),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Du ${DateFormat('dd/MM/yyyy').format(_from.toLocal())} '
                'au ${DateFormat('dd/MM/yyyy').format(_to.toLocal())}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.visibility),
                label: const Text('Aperçu'),
                onPressed: _selected == null || _busy ? null : _preview,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.share),
                label: const Text('Exporter & partager'),
                onPressed: _selected == null || _busy ? null : _export,
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
