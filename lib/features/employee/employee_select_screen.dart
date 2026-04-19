import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/app_database.dart';
import '../../state/providers.dart';

class EmployeeSelectScreen extends ConsumerWidget {
  const EmployeeSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(activeEmployeesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('klok — pointage'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-fab',
        icon: const Icon(Icons.admin_panel_settings),
        label: const Text('Administration'),
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        foregroundColor:
            Theme.of(context).colorScheme.onSecondaryContainer,
        onPressed: () => context.push('/admin'),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.endFloat,
      body: employees.when(
        data: (list) {
          if (list.isEmpty) return const _EmptyState();
          return LayoutBuilder(
            builder: (ctx, bc) {
              final cols = bc.maxWidth >= 1100
                  ? 4
                  : bc.maxWidth >= 700
                      ? 3
                      : 2;
              return GridView.builder(
                padding: const EdgeInsets.all(24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: 1.5,
                ),
                itemCount: list.length,
                itemBuilder: (ctx, i) =>
                    _EmployeeCard(employee: list[i]),
              );
            },
          );
        },
        error: (e, st) => Center(child: Text('Erreur : $e')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.employee});
  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(employee.color);
    final initials =
        '${employee.firstName[0]}${employee.lastName.isNotEmpty ? employee.lastName[0] : ''}'
            .toUpperCase();
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/clock/${employee.id}'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: color,
                foregroundColor: Colors.white,
                child: Text(
                  initials,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(employee.firstName,
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(employee.lastName,
                        style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.group_outlined, size: 96, color: Colors.black26),
          const SizedBox(height: 16),
          Text(
            'Aucun salarié enregistré',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text('Ajoutez les salariés depuis la page admin.'),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.lock_outline),
            label: const Text('Ouvrir la page admin'),
            onPressed: () => context.push('/admin'),
          ),
        ],
      ),
    );
  }
}

Color _parseColor(String hex) {
  final clean = hex.replaceAll('#', '');
  return Color(int.parse('FF$clean', radix: 16));
}
