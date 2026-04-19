import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/session_repository.dart';
import '../../state/providers.dart';

class ClockScreen extends ConsumerWidget {
  const ClockScreen({super.key, required this.employeeId});

  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empAsync = ref.watch(employeeByIdProvider(employeeId));
    final clockAsync = ref.watch(clockStateProvider(employeeId));
    ref.watch(tickerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: empAsync.maybeWhen(
          data: (e) => Text('${e.firstName} ${e.lastName}'),
          orElse: () => const Text('Pointage'),
        ),
      ),
      body: clockAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (state) => _ClockBody(
          employeeId: employeeId,
          state: state,
          employee: empAsync.value,
        ),
      ),
    );
  }
}

class _ClockBody extends ConsumerWidget {
  const _ClockBody({
    required this.employeeId,
    required this.state,
    required this.employee,
  });

  final int employeeId;
  final EmployeeClockState state;
  final Employee? employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = state.isIdle
        ? 'Hors service'
        : state.isOnBreak
            ? 'En pause'
            : 'En activité';
    final color = state.isIdle
        ? Colors.grey.shade600
        : state.isOnBreak
            ? Colors.orange.shade700
            : Colors.green.shade700;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .headlineLarge
                    ?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 40),
          if (state.openSession != null)
            _SessionInfo(state: state)
          else
            const Center(
              child: Text(
                'Appuyez sur Commencer pour démarrer votre activité.',
                style: TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 48),
          _ActionButtons(employeeId: employeeId, state: state),
        ],
      ),
    );
  }
}

class _SessionInfo extends ConsumerWidget {
  const _SessionInfo({required this.state});

  final EmployeeClockState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = state.openSession!;
    final now = DateTime.now().toUtc();
    final gross = now.difference(session.startedAt);
    final breakDuration = state.openBreak != null
        ? now.difference(state.openBreak!.startedAt)
        : Duration.zero;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _Line(
              label: 'Début',
              value: formatHHmm(session.startedAt),
            ),
            const SizedBox(height: 12),
            _Line(
              label: 'Durée',
              value: formatDuration(gross),
            ),
            if (state.openBreak != null) ...[
              const Divider(height: 32),
              _Line(
                label: 'Pause en cours',
                value: formatDuration(breakDuration),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w400)),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
  }
}

class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.employeeId, required this.state});

  final int employeeId;
  final EmployeeClockState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(sessionRepositoryProvider);

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e')),
          );
        }
      }
    }

    if (state.isIdle) {
      return FilledButton.icon(
        icon: const Icon(Icons.play_arrow, size: 32),
        label: const Text('Commencer'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.green.shade700,
          minimumSize: const Size.fromHeight(96),
        ),
        onPressed: () => run(() => repo.startSession(employeeId)),
      );
    }

    if (state.isOnBreak) {
      return FilledButton.icon(
        icon: const Icon(Icons.play_arrow, size: 32),
        label: const Text('Reprendre'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.green.shade700,
          minimumSize: const Size.fromHeight(96),
        ),
        onPressed: () => run(() => repo.endBreak(state.openBreak!.id)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.pause, size: 32),
          label: const Text('Prendre une pause'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
            minimumSize: const Size.fromHeight(96),
          ),
          onPressed: () =>
              run(() => repo.startBreak(state.openSession!.id)),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.stop, size: 28),
          label: const Text('Terminer l\'activité'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade700,
            minimumSize: const Size.fromHeight(80),
            side: BorderSide(color: Colors.red.shade700, width: 2),
            textStyle:
                const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Terminer l\'activité ?'),
                content: const Text(
                    'Confirmez-vous la fin de votre service ?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Annuler'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Terminer'),
                  ),
                ],
              ),
            );
            if (ok == true) {
              await run(() => repo.endSession(state.openSession!.id));
              if (context.mounted) context.go('/');
            }
          },
        ),
      ],
    );
  }
}
