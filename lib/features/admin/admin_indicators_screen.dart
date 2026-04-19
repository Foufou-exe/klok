import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/time_math.dart';
import '../../data/db/app_database.dart';
import '../../state/providers.dart';

final _currentMonthSummaryProvider =
    FutureProvider.autoDispose<List<_EmployeeMonthSummary>>((ref) async {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month).toUtc();
  final to = DateTime(now.year, now.month + 1)
      .subtract(const Duration(seconds: 1))
      .toUtc();
  final employees =
      await ref.watch(employeeRepositoryProvider).watchActive().first;
  final sessionRepo = ref.watch(sessionRepositoryProvider);

  final result = <_EmployeeMonthSummary>[];
  for (final e in employees) {
    final sessions = await sessionRepo.sessionsInRange(e.id, from, to);
    final breaks = await sessionRepo
        .breaksForSessions(sessions.map((s) => s.id).toList());
    final byId = <int, List<Break>>{};
    for (final b in breaks) {
      byId.putIfAbsent(b.sessionId, () => []).add(b);
    }
    final joined = [
      for (final s in sessions)
        SessionWithBreaks(session: s, breaks: byId[s.id] ?? const []),
    ];
    final net = sumNet(joined);
    final pay = e.hourlyRateCents != null
        ? (net.inMinutes / 60.0) * (e.hourlyRateCents! / 100)
        : null;
    result.add(_EmployeeMonthSummary(
      employee: e,
      netDuration: net,
      sessionCount: sessions.length,
      grossPay: pay,
    ));
  }
  result.sort(
      (a, b) => b.netDuration.compareTo(a.netDuration));
  return result;
});

class _EmployeeMonthSummary {
  _EmployeeMonthSummary({
    required this.employee,
    required this.netDuration,
    required this.sessionCount,
    required this.grossPay,
  });

  final Employee employee;
  final Duration netDuration;
  final int sessionCount;
  final double? grossPay;
}

class AdminIndicatorsScreen extends ConsumerWidget {
  const AdminIndicatorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(_currentMonthSummaryProvider);
    final month = DateFormat('MMMM yyyy', 'fr_FR').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Indicateurs'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/home'),
        ),
      ),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (rows) {
          final total = rows.fold<Duration>(
              Duration.zero, (acc, r) => acc + r.netDuration);
          final totalPay = rows.fold<double>(
              0, (acc, r) => acc + (r.grossPay ?? 0));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mois en cours : $month',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text('Total heures : ${formatDuration(total)}'),
                      Text(
                        'Masse salariale brute estimée : '
                        '${NumberFormat.currency(locale: 'fr_FR', symbol: '€').format(totalPay)}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                const Center(child: Text('Aucune activité ce mois-ci.'))
              else
                ...rows.map((r) => Card(
                      child: ListTile(
                        title:
                            Text('${r.employee.firstName} ${r.employee.lastName}'),
                        subtitle: Text(
                            '${r.sessionCount} session(s) • ${formatDuration(r.netDuration)}'),
                        trailing: r.grossPay != null
                            ? Text(
                                NumberFormat.currency(
                                        locale: 'fr_FR', symbol: '€')
                                    .format(r.grossPay),
                                style:
                                    Theme.of(context).textTheme.titleMedium,
                              )
                            : null,
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}
