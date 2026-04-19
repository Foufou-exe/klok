import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/db/app_database.dart';
import '../../state/providers.dart';

class AdminEmployeesScreen extends ConsumerWidget {
  const AdminEmployeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(allEmployeesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salariés'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/home'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('Ajouter'),
        onPressed: () => _openEditor(context, ref),
      ),
      body: employees.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Aucun salarié.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final e = list[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _parseColor(e.color),
                    foregroundColor: Colors.white,
                    child: Text(e.firstName[0].toUpperCase()),
                  ),
                  title: Text('${e.firstName} ${e.lastName}'),
                  subtitle: Text(
                    'Taux horaire : ${formatMoneyCents(e.hourlyRateCents)}'
                    '${e.archived ? ' • Archivé' : ''}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      final repo = ref.read(employeeRepositoryProvider);
                      if (v == 'edit') {
                        _openEditor(context, ref, existing: e);
                      } else if (v == 'archive') {
                        await repo.archive(e.id);
                      } else if (v == 'unarchive') {
                        await repo.unarchive(e.id);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                      if (!e.archived)
                        const PopupMenuItem(
                            value: 'archive', child: Text('Archiver')),
                      if (e.archived)
                        const PopupMenuItem(
                            value: 'unarchive', child: Text('Désarchiver')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openEditor(BuildContext context, WidgetRef ref, {Employee? existing}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _EmployeeEditor(existing: existing),
    );
  }
}

class _EmployeeEditor extends ConsumerStatefulWidget {
  const _EmployeeEditor({this.existing});

  final Employee? existing;

  @override
  ConsumerState<_EmployeeEditor> createState() => _EmployeeEditorState();
}

class _EmployeeEditorState extends ConsumerState<_EmployeeEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _rate;
  late String _color;

  static const _palette = [
    '#3B82F6', '#22C55E', '#EF4444', '#F59E0B',
    '#8B5CF6', '#EC4899', '#14B8A6', '#64748B',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _first = TextEditingController(text: e?.firstName ?? '');
    _last = TextEditingController(text: e?.lastName ?? '');
    _rate = TextEditingController(
      text: e?.hourlyRateCents != null
          ? (e!.hourlyRateCents! / 100).toStringAsFixed(2)
          : '',
    );
    _color = e?.color ?? _palette.first;
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final repo = ref.read(employeeRepositoryProvider);
    final rateText = _rate.text.replaceAll(',', '.').trim();
    final cents = rateText.isEmpty
        ? null
        : (double.parse(rateText) * 100).round();

    if (widget.existing == null) {
      await repo.create(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        color: _color,
        hourlyRateCents: cents,
      );
    } else {
      await repo.update(
        widget.existing!.copyWith(
          firstName: _first.text.trim(),
          lastName: _last.text.trim(),
          color: _color,
          hourlyRateCents: Value(cents),
        ),
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nouveau salarié' : 'Modifier'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _first,
                decoration: const InputDecoration(labelText: 'Prénom'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _last,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rate,
                decoration: const InputDecoration(
                  labelText: 'Taux horaire (€)',
                  hintText: 'ex: 12.50 — optionnel',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = double.tryParse(v.replaceAll(',', '.'));
                  if (n == null || n < 0) return 'Montant invalide';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Couleur',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _palette)
                    GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _parseColor(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c == _color ? Colors.black : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}

Color _parseColor(String hex) {
  final clean = hex.replaceAll('#', '');
  return Color(int.parse('FF$clean', radix: 16));
}
