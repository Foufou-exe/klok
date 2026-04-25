// Onglet "Aperçu" de l'admin — variante Pastille (V2Dashboard).
//
// 3 zones de haut en bas :
//   1. En-tête (date + heure live)
//   2. Grid 1.4fr/1fr : "En poste maintenant" | "Cette semaine" (chiffre +
//      barres jour par jour)
//   3. Grid 3× : "Mois en cours" · "Moyenne équipe" · "Prochaine sauvegarde"
//
// On évite de dupliquer la logique : les totaux passent par les providers
// de `state/admin_stats.dart` pour que chaque widget se rafraîchisse quand
// une session change côté DB.
//
// Ref design : variants/v2-admin.jsx (fonction V2Dashboard).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/format.dart';
import '../../../data/db/app_database.dart';
import '../../../design/tokens.dart';
import '../../../state/admin_stats.dart';
import '../../../state/providers.dart';
import '../widgets/admin_card.dart';

class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key, required this.onOpenEmployee});

  final ValueChanged<Employee> onOpenEmployee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(tickerProvider).asData?.value ?? DateTime.now();
    // On évite LayoutBuilder ici : un ref.watch sur un StreamProvider à valeur
    // déjà en cache peut émettre synchroniquement pendant la phase de layout
    // et déclencher un !_debugDoingThisLayout. MediaQuery se résout au build
    // (avant layout), donc safe.
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(now: now),
          const SizedBox(height: 20),
          // Row 1 : En poste + Cette semaine
          // IntrinsicHeight nécessaire car on est dans un SingleChildScrollView
          // (hauteur non bornée) et on veut que les deux cards prennent la même
          // hauteur. Sans ça, le `crossAxisAlignment: stretch` du Row tente de
          // s'étirer à l'infini → "BoxConstraints forces an infinite height".
          wide
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 7,
                        child: _ActiveNowCard(onOpen: onOpenEmployee),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 5,
                        child: const _WeekCard(),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _ActiveNowCard(onOpen: onOpenEmployee),
                    const SizedBox(height: 16),
                    const _WeekCard(),
                  ],
                ),
          const SizedBox(height: 16),
          // Row 2 : 3 stat cards
          _StatRow(wide: wide),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(now);
    final timeLabel = formatHHmm(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Aperçu de la journée',
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
          '${_capitalize(dateLabel)} · $timeLabel',
          style: TextStyle(
            fontSize: 14,
            color: KlokTokens.inkSoft,
            fontFeatures: KlokTokens.tabularFigures,
          ),
        ),
      ],
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ─────────────────────────────────────────────────────────────
// "En poste maintenant" — liste live des actifs
// ─────────────────────────────────────────────────────────────
class _ActiveNowCard extends ConsumerWidget {
  const _ActiveNowCard({required this.onOpen});
  final ValueChanged<Employee> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamStatusProvider);
    final employees =
        ref.watch(activeEmployeesProvider).asData?.value ?? const [];
    final activeIds = team.byEmployee.keys.toSet();
    final active = employees.where((e) => activeIds.contains(e.id)).toList();

    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'En poste maintenant',
                style: TextStyle(
                  fontFamily: KlokTokens.fontDisplay,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: KlokTokens.ink,
                ),
              ),
              Text(
                '${active.length} sur ${employees.length}',
                style: TextStyle(fontSize: 13, color: KlokTokens.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (active.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Personne en service pour le moment.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: KlokTokens.inkSoft,
                ),
              ),
            )
          else
            for (int i = 0; i < active.length; i++) ...[
              _ActiveRow(
                employee: active[i],
                status: team.statusOf(active[i].id),
                onTap: () => onOpen(active[i]),
              ),
              if (i < active.length - 1) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _ActiveRow extends ConsumerWidget {
  const _ActiveRow({
    required this.employee,
    required this.status,
    required this.onTap,
  });

  final Employee employee;
  final EmployeeStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayTotalsProvider(employee.id));
    final color = _parseHexColor(employee.color);
    final isWorking = status.kind == EmployeeStatusKind.working;

    return Material(
      color: KlokTokens.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _CircleInitials(color: color, initials: _initialsOf(employee), size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${employee.firstName} ${employee.lastName}'.trim(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: KlokTokens.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'depuis ${status.since != null ? formatHHmm(status.since!) : '—'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: KlokTokens.inkSoft,
                        fontFeatures: KlokTokens.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                today.asData?.value != null
                    ? formatDuration(today.asData!.value.netDuration)
                    : '—',
                style: TextStyle(
                  fontFamily: KlokTokens.fontDisplay,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: KlokTokens.ink,
                  fontFeatures: KlokTokens.tabularFigures,
                ),
              ),
              const SizedBox(width: 10),
              _StatusChip(working: isWorking),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.working});
  final bool working;

  @override
  Widget build(BuildContext context) {
    final bg = working ? KlokTokens.successBg : KlokTokens.amberBg;
    final fg = working ? KlokTokens.success : KlokTokens.amber600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        working ? 'Service' : 'Pause',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// "Cette semaine" — chiffre + barres jour par jour
// ─────────────────────────────────────────────────────────────
class _WeekCard extends ConsumerWidget {
  const _WeekCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekTotal = ref.watch(currentWeekTotalProvider);
    final days = ref.watch(currentWeekDaysProvider);

    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cette semaine',
            style: TextStyle(
              fontFamily: KlokTokens.fontDisplay,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: KlokTokens.ink,
            ),
          ),
          const SizedBox(height: 14),
          // Chiffre géant bordeaux
          Text(
            weekTotal.asData?.value != null
                ? formatDuration(weekTotal.asData!.value)
                : '—',
            style: TextStyle(
              fontFamily: KlokTokens.fontDisplay,
              fontSize: 42,
              fontWeight: FontWeight.w500,
              letterSpacing: -1.2,
              color: KlokTokens.bordeaux,
              height: 1.0,
              fontFeatures: KlokTokens.tabularFigures,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Équipe entière · semaine en cours',
            style: TextStyle(fontSize: 12, color: KlokTokens.inkSoft),
          ),
          const SizedBox(height: 20),
          // Barres
          SizedBox(
            height: 110,
            child: days.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (list) => _WeekBars(days: list),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days});
  final List<WeekDayHours> days;

  @override
  Widget build(BuildContext context) {
    final maxH = days.fold<double>(
        0, (acc, d) => d.hours > acc ? d.hours : acc);
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++) ...[
                Expanded(
                  child: Container(
                    height: maxH == 0 ? 2 : (days[i].hours / maxH) * 90,
                    decoration: BoxDecoration(
                      color: days[i].isToday
                          ? KlokTokens.terra
                          : KlokTokens.amber.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                if (i < days.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: KlokTokens.border),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < days.length; i++) ...[
              Expanded(
                child: Center(
                  child: Text(
                    days[i].label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: days[i].isToday
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: days[i].isToday
                          ? KlokTokens.ink
                          : KlokTokens.inkSoft,
                    ),
                  ),
                ),
              ),
              if (i < days.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Stat row : 3 cartes de bas de page
// ─────────────────────────────────────────────────────────────
class _StatRow extends ConsumerWidget {
  const _StatRow({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthTotals = ref.watch(currentMonthTotalsProvider);
    final employees =
        ref.watch(activeEmployeesProvider).asData?.value ?? const [];
    final weekTotal = ref.watch(currentWeekTotalProvider);
    final lastBackup = ref.watch(lastBackupAtProvider);

    final monthValue = monthTotals.asData?.value;
    final monthLabel =
        monthValue != null ? formatDuration(monthValue.total) : '—';
    final monthSub = monthValue != null
        ? '${monthValue.daysWithActivity} jour${monthValue.daysWithActivity > 1 ? 's' : ''}'
        : '—';

    final averagePerPersonLabel = () {
      final w = weekTotal.asData?.value;
      if (w == null || employees.isEmpty) return '—';
      final perPerson = Duration(minutes: w.inMinutes ~/ employees.length);
      return formatDuration(perPerson);
    }();

    final backupLabel = () {
      final raw = lastBackup.asData?.value;
      if (raw == null) return 'Jamais';
      final parsed = DateTime.tryParse(raw)?.toLocal();
      if (parsed == null) return '—';
      final days = DateTime.now().difference(parsed).inDays;
      if (days <= 0) return "Aujourd'hui";
      if (days == 1) return 'Hier';
      return 'Il y a $days jours';
    }();
    final backupSub = () {
      final raw = lastBackup.asData?.value;
      if (raw == null) return 'à faire dès que possible';
      final parsed = DateTime.tryParse(raw)?.toLocal();
      if (parsed == null) return '—';
      return DateFormat('EEE dd/MM', 'fr_FR').format(parsed);
    }();

    final stats = [
      _Stat(label: 'Mois en cours', value: monthLabel, sub: monthSub),
      _Stat(
        label: 'Moyenne équipe',
        value: averagePerPersonLabel,
        sub: 'par personne / semaine',
      ),
      _Stat(
        label: 'Dernière sauvegarde',
        value: backupLabel,
        sub: backupSub,
      ),
    ];

    if (wide) {
      return Row(
        children: [
          for (int i = 0; i < stats.length; i++) ...[
            Expanded(child: _StatCard(stat: stats[i])),
            if (i < stats.length - 1) const SizedBox(width: 16),
          ],
        ],
      );
    }
    // Mode étroit : empilées, mais on force le stretch horizontal pour que
    // chaque card prenne toute la largeur disponible (sans ce stretch, la
    // Column se cale sur la largeur intrinsèque de la card, qui est faible).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < stats.length; i++) ...[
          _StatCard(stat: stats[i]),
          if (i < stats.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _Stat {
  _Stat({required this.label, required this.value, required this.sub});
  final String label;
  final String value;
  final String sub;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});
  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat.label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
              color: KlokTokens.inkSoft,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            stat.value,
            style: TextStyle(
              fontFamily: KlokTokens.fontDisplay,
              fontSize: 28,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.8,
              color: KlokTokens.ink,
              fontFeatures: KlokTokens.tabularFigures,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stat.sub,
            style: TextStyle(fontSize: 12, color: KlokTokens.inkSoft),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helpers partagés
// ─────────────────────────────────────────────────────────────
class _CircleInitials extends StatelessWidget {
  const _CircleInitials({
    required this.color,
    required this.initials,
    required this.size,
  });

  final Color color;
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontFamily: KlokTokens.fontDisplay,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.36,
            color: Colors.white,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

String _initialsOf(Employee e) {
  final f = e.firstName.isNotEmpty ? e.firstName[0] : '';
  final l = e.lastName.isNotEmpty ? e.lastName[0] : '';
  final out = '$f$l';
  return out.isEmpty ? '?' : out.toUpperCase();
}

Color _parseHexColor(String hex) {
  final clean = hex.replaceAll('#', '').trim();
  if (clean.length == 3) {
    final r = clean[0] * 2;
    final g = clean[1] * 2;
    final b = clean[2] * 2;
    return Color(int.parse('FF$r$g$b', radix: 16));
  }
  if (clean.length == 8) return Color(int.parse(clean, radix: 16));
  return Color(int.parse('FF$clean', radix: 16));
}
