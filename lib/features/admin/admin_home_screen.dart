import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/admin_session.dart';

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () {
            ref.read(adminUnlockedProvider.notifier).lock();
            context.go('/');
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Verrouiller',
            icon: const Icon(Icons.lock),
            onPressed: () {
              ref.read(adminUnlockedProvider.notifier).lock();
              context.go('/');
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, bc) {
          final cols = bc.maxWidth >= 900 ? 3 : 2;
          return GridView.count(
            padding: const EdgeInsets.all(24),
            crossAxisCount: cols,
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            childAspectRatio: 1.4,
            children: [
              _Tile(
                icon: Icons.group,
                label: 'Salariés',
                onTap: () => context.push('/admin/employees'),
              ),
              _Tile(
                icon: Icons.bar_chart,
                label: 'Indicateurs',
                onTap: () => context.push('/admin/indicators'),
              ),
              _Tile(
                icon: Icons.picture_as_pdf,
                label: 'Export PDF',
                onTap: () => context.push('/admin/export'),
              ),
              _Tile(
                icon: Icons.save_alt,
                label: 'Sauvegarde',
                onTap: () => context.push('/admin/backup'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 64,
                  color: Theme.of(context).colorScheme.onPrimaryContainer),
              const SizedBox(height: 12),
              Text(label,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer)),
            ],
          ),
        ),
      ),
    );
  }
}
