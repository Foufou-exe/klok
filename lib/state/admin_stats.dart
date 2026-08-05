// Providers analytiques réservés aux écrans admin — calculent à la volée les
// heures par jour / semaine / mois à partir des sessions déjà en DB.
//
// On évite de cacher des totaux : la DB reste source de vérité, et les
// providers.family permettent à Flutter de reforger quand une session se
// ferme. Ces providers sont `autoDispose` : on les libère quand on quitte
// l'onglet admin (pas besoin de les garder chauds en mode salarié).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/time_math.dart';
import '../data/db/app_database.dart';
import 'providers.dart';

/// Tuple interne qui agrège tous les chiffres utiles d'un salarié sur
/// une période donnée (typiquement "jour" ou "semaine").
class EmployeeRangeTotals {
  EmployeeRangeTotals({
    required this.netDuration,
    required this.sessionCount,
    required this.grossPay,
  });

  final Duration netDuration;
  final int sessionCount;
  // Peut être null si pas de taux horaire défini.
  final double? grossPay;
}

/// Calcule les totaux (heures nettes + nb sessions + paie brute) d'un
/// salarié sur une période. Les `from`/`to` sont attendus en **UTC**.
Future<EmployeeRangeTotals> _computeTotals(
  SessionRepository repo,
  Employee employee,
  DateTime from,
  DateTime to,
) async {
  final sessions = await repo.sessionsInRange(employee.id, from, to);
  final breaks = await repo.breaksForSessions(
    sessions.map((s) => s.id).toList(),
  );
  final joined = [
    for (final s in sessions)
      SessionWithBreaks(
        session: s,
        breaks: breaks.where((b) => b.sessionId == s.id).toList(),
      ),
  ];
  final net = sumNet(joined);
  final pay = employee.hourlyRateCents != null
      ? (net.inMinutes / 60.0) * (employee.hourlyRateCents! / 100)
      : null;
  return EmployeeRangeTotals(
    netDuration: net,
    sessionCount: sessions.length,
    grossPay: pay,
  );
}

/// Totaux "aujourd'hui" pour un salarié donné, en local timezone.
final todayTotalsProvider = FutureProvider.autoDispose
    .family<EmployeeRangeTotals, int>((ref, employeeId) async {
      // Dépend du tick pour se rafraîchir toutes les secondes tant qu'une
      // session ouverte existe — évite un compteur figé à "3h 12m".
      ref.watch(tickerProvider);
      final employee = await ref.watch(employeeByIdProvider(employeeId).future);
      final repo = ref.watch(sessionRepositoryProvider);

      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day).toUtc();
      final dayEnd = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(const Duration(days: 1)).toUtc();
      return _computeTotals(repo, employee, dayStart, dayEnd);
    });

/// Totaux de la semaine courante (lundi 00:00 local → maintenant).
final weekTotalsProvider = FutureProvider.autoDispose
    .family<EmployeeRangeTotals, int>((ref, employeeId) async {
      ref.watch(tickerProvider);
      final employee = await ref.watch(employeeByIdProvider(employeeId).future);
      final repo = ref.watch(sessionRepositoryProvider);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final weekStart = today.subtract(Duration(days: now.weekday - 1)).toUtc();
      final weekEnd = today.add(const Duration(days: 1)).toUtc();
      return _computeTotals(repo, employee, weekStart, weekEnd);
    });

/// Totaux du mois courant.
final monthTotalsProvider = FutureProvider.autoDispose
    .family<EmployeeRangeTotals, int>((ref, employeeId) async {
      ref.watch(tickerProvider);
      final employee = await ref.watch(employeeByIdProvider(employeeId).future);
      final repo = ref.watch(sessionRepositoryProvider);

      final now = DateTime.now();
      final start = DateTime(now.year, now.month).toUtc();
      final end = DateTime(now.year, now.month + 1).toUtc();
      return _computeTotals(repo, employee, start, end);
    });

/// Totaux jour par jour sur la semaine en cours (pour le graphe Dashboard).
/// Index 0 = lundi, 6 = dimanche.
class WeekDayHours {
  WeekDayHours({
    required this.label,
    required this.hours,
    required this.isToday,
  });
  final String label;
  final double hours;
  final bool isToday;
}

final currentWeekDaysProvider = FutureProvider.autoDispose<List<WeekDayHours>>((
  ref,
) async {
  ref.watch(tickerProvider);
  final employees = await ref.watch(activeEmployeesProvider.future);
  final repo = ref.watch(sessionRepositoryProvider);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(Duration(days: now.weekday - 1));
  final result = <WeekDayHours>[];
  const labels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

  for (var i = 0; i < 7; i++) {
    final dayStart = weekStart.add(Duration(days: i)).toUtc();
    final dayEnd = weekStart.add(Duration(days: i + 1)).toUtc();
    Duration total = Duration.zero;
    for (final e in employees) {
      final sessions = await repo.sessionsInRange(e.id, dayStart, dayEnd);
      final breaks = await repo.breaksForSessions(
        sessions.map((s) => s.id).toList(),
      );
      final joined = [
        for (final s in sessions)
          SessionWithBreaks(
            session: s,
            breaks: breaks.where((b) => b.sessionId == s.id).toList(),
          ),
      ];
      total += sumNet(joined);
    }
    result.add(
      WeekDayHours(
        label: labels[i],
        hours: total.inMinutes / 60.0,
        isToday: i == (now.weekday - 1),
      ),
    );
  }
  return result;
});

/// Somme des heures de tous les salariés actifs sur la semaine en cours.
final currentWeekTotalProvider = FutureProvider.autoDispose<Duration>((
  ref,
) async {
  final days = await ref.watch(currentWeekDaysProvider.future);
  var total = 0.0;
  for (final d in days) {
    total += d.hours;
  }
  final minutes = (total * 60).round();
  return Duration(minutes: minutes);
});

/// Heures totales de l'équipe sur le mois courant + nombre de jours couverts.
class MonthTotalsSummary {
  MonthTotalsSummary({required this.total, required this.daysWithActivity});
  final Duration total;
  final int daysWithActivity;
}

final currentMonthTotalsProvider =
    FutureProvider.autoDispose<MonthTotalsSummary>((ref) async {
      ref.watch(tickerProvider);
      final employees = await ref.watch(activeEmployeesProvider.future);
      final repo = ref.watch(sessionRepositoryProvider);

      final now = DateTime.now();
      final start = DateTime(now.year, now.month).toUtc();
      final end = DateTime(now.year, now.month + 1).toUtc();

      Duration total = Duration.zero;
      final daySet = <String>{};
      for (final e in employees) {
        final sessions = await repo.sessionsInRange(e.id, start, end);
        final breaks = await repo.breaksForSessions(
          sessions.map((s) => s.id).toList(),
        );
        for (final s in sessions) {
          final d = s.startedAt.toLocal();
          daySet.add('${d.year}-${d.month}-${d.day}');
        }
        final joined = [
          for (final s in sessions)
            SessionWithBreaks(
              session: s,
              breaks: breaks.where((b) => b.sessionId == s.id).toList(),
            ),
        ];
        total += sumNet(joined);
      }
      return MonthTotalsSummary(total: total, daysWithActivity: daySet.length);
    });
