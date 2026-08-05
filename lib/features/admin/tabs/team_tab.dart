// Onglet "Équipe" de l'admin — variante Pastille.
//
// Deux modes dans un seul widget :
//   • Grille de salariés (quand `detail == null`) : cartes avec pastille,
//     statut live, et totaux jour/semaine.
//   • Vue détail (quand `detail != null`) : header gros + 4 stat cards +
//     historique des 12 derniers jours.
//
// On choisit volontairement de ne pas router /admin/employee/:id : le shell
// admin garde son propre état (activeTab + detail), ce qui simplifie les
// transitions et évite un rebuild du header.
//
// Ref design : variants/v2-admin.jsx (fonctions V2Team + V2Detail).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/format.dart';
import '../../../core/time_math.dart';
import '../../../data/db/app_database.dart';
import '../../../design/tokens.dart';
import '../../../state/admin_stats.dart';
import '../../../state/providers.dart';
import '../widgets/add_employee_modal.dart';
import '../widgets/admin_card.dart';

class TeamTab extends ConsumerWidget {
  const TeamTab({
    super.key,
    required this.detail,
    required this.onOpen,
    required this.onBack,
  });

  final Employee? detail;
  final ValueChanged<Employee> onOpen;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (detail != null) {
      return _TeamDetail(employee: detail!, onBack: onBack);
    }
    return _TeamGrid(onOpen: onOpen);
  }
}

// ─────────────────────────────────────────────────────────────
// Vue liste : grille 3 colonnes (2 en portrait) avec + Ajouter
// ─────────────────────────────────────────────────────────────
class _TeamGrid extends ConsumerWidget {
  const _TeamGrid({required this.onOpen});
  final ValueChanged<Employee> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees =
        ref.watch(activeEmployeesProvider).asData?.value ?? const [];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Équipe',
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
                      '${employees.length} salarié${employees.length > 1 ? 's' : ''} actif${employees.length > 1 ? 's' : ''}',
                      style:
                          TextStyle(fontSize: 14, color: KlokTokens.inkSoft),
                    ),
                  ],
                ),
              ),
              _AddButton(onTap: () => _openAddModal(context)),
            ],
          ),
          const SizedBox(height: 20),
          // MediaQuery au lieu de LayoutBuilder : on évite la re-entrance layout
          // déclenchée par les ConsumerWidgets enfants qui watchent des streams.
          Builder(
            builder: (ctx) {
              final w = MediaQuery.sizeOf(ctx).width;
              final cols = w >= 900 ? 3 : (w >= 560 ? 2 : 1);
              return _Grid(
                cols: cols,
                gap: 14,
                children: [
                  for (final e in employees)
                    _TeamCard(employee: e, onTap: () => onOpen(e)),
                ],
              );
            },
          ),
          if (employees.isEmpty) ...[
            const SizedBox(height: 40),
            Center(
              child: Text(
                'Aucun salarié pour le moment.\nAjoute quelqu\'un pour commencer.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: KlokTokens.inkSoft),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openAddModal(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const AddEmployeeModal(),
    );
  }
}

// Grille responsive sans dépendre de GridView (on garde l'alignement haut
// des cartes et la hauteur auto).
class _Grid extends StatelessWidget {
  const _Grid({
    required this.cols,
    required this.gap,
    required this.children,
  });

  final int cols;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      final row = <Widget>[];
      for (var j = 0; j < cols; j++) {
        final idx = i + j;
        if (idx < children.length) {
          row.add(Expanded(child: children[idx]));
        } else {
          row.add(const Expanded(child: SizedBox.shrink()));
        }
        if (j < cols - 1) row.add(SizedBox(width: gap));
      }
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: row,
        ),
      ));
      if (i + cols < children.length) rows.add(SizedBox(height: gap));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _TeamCard extends ConsumerWidget {
  const _TeamCard({required this.employee, required this.onTap});

  final Employee employee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamStatusProvider);
    final status = team.statusOf(employee.id);
    final today = ref.watch(todayTotalsProvider(employee.id));
    final week = ref.watch(weekTotalsProvider(employee.id));

    return Material(
      color: KlokTokens.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: KlokTokens.card,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D3C2814),
                offset: Offset(0, 1),
                blurRadius: 3,
              ),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CircleInitials(
                    color: _parseHexColor(employee.color),
                    initials: _initialsOf(employee),
                    size: 52,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${employee.firstName} ${employee.lastName}'.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: KlokTokens.fontDisplay,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: KlokTokens.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          employee.hourlyRateCents != null
                              ? '${(employee.hourlyRateCents! / 100).toStringAsFixed(2)} €/h'
                              : 'Salarié',
                          style: TextStyle(
                              fontSize: 12, color: KlokTokens.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _StatusBadge(kind: status.kind),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _CornerMetric(
                      label: "Aujourd'hui",
                      value: today.asData?.value != null
                          ? formatDuration(today.asData!.value.netDuration)
                          : '—',
                    ),
                  ),
                  Expanded(
                    child: _CornerMetric(
                      label: 'Semaine',
                      value: week.asData?.value != null
                          ? formatDuration(week.asData!.value.netDuration)
                          : '—',
                      alignRight: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.kind});
  final EmployeeStatusKind kind;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    switch (kind) {
      case EmployeeStatusKind.working:
        bg = KlokTokens.successBg;
        fg = KlokTokens.success;
        label = '● En service';
      case EmployeeStatusKind.onBreak:
        bg = KlokTokens.amberBg;
        fg = KlokTokens.amber600;
        label = '● En pause';
      case EmployeeStatusKind.off:
        bg = KlokTokens.bg;
        fg = KlokTokens.muted;
        label = '○ Hors service';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg),
      ),
    );
  }
}

class _CornerMetric extends StatelessWidget {
  const _CornerMetric({
    required this.label,
    required this.value,
    this.alignRight = false,
  });

  final String label;
  final String value;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final cross =
        alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: cross,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: KlokTokens.inkSoft),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontFamily: KlokTokens.fontDisplay,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: KlokTokens.ink,
            fontFeatures: KlokTokens.tabularFigures,
          ),
        ),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KlokTokens.ink,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            '+ Ajouter un salarié',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Vue détail : header + 4 stats + historique
// ─────────────────────────────────────────────────────────────
class _TeamDetail extends ConsumerWidget {
  const _TeamDetail({required this.employee, required this.onBack});

  final Employee employee;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayTotalsProvider(employee.id));
    final month = ref.watch(monthTotalsProvider(employee.id));

    final monthTotal = month.asData?.value;
    final monthDuration =
        monthTotal != null ? formatDuration(monthTotal.netDuration) : '—';
    final monthDays = monthTotal?.sessionCount.toString() ?? '—';
    final averageDay = () {
      final m = monthTotal;
      if (m == null || m.sessionCount == 0) return '—';
      final avg = Duration(minutes: m.netDuration.inMinutes ~/ m.sessionCount);
      return formatDuration(avg);
    }();
    final todayLabel = today.asData?.value != null
        ? formatDuration(today.asData!.value.netDuration)
        : '—';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BackLink(onTap: onBack),
          const SizedBox(height: 14),
          // Header card
          AdminCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                _CircleInitials(
                  color: _parseHexColor(employee.color),
                  initials: _initialsOf(employee),
                  size: 76,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${employee.firstName} ${employee.lastName}'.trim(),
                        style: TextStyle(
                          fontFamily: KlokTokens.fontDisplay,
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          color: KlokTokens.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        employee.hourlyRateCents != null
                            ? '${(employee.hourlyRateCents! / 100).toStringAsFixed(2)} €/h · embauché en ${DateFormat('MMMM yyyy', 'fr_FR').format(employee.createdAt.toLocal())}'
                            : 'Salarié · embauché en ${DateFormat('MMMM yyyy', 'fr_FR').format(employee.createdAt.toLocal())}',
                        style:
                            TextStyle(fontSize: 14, color: KlokTokens.inkSoft),
                      ),
                    ],
                  ),
                ),
                // Actions sur la fiche salarié : éditer (ouvre la modale en
                // mode update), archiver (soft delete — la fiche est masquée
                // mais l'historique reste pour la compta), export PDF
                // (renvoie l'utilisateur vers l'onglet dédié).
                _IconActionButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Modifier',
                  onTap: () => _editEmployee(context, employee),
                ),
                const SizedBox(width: 8),
                _IconActionButton(
                  icon: Icons.archive_outlined,
                  tooltip: 'Archiver',
                  onTap: () => _confirmArchive(context, ref, employee, onBack),
                ),
                const SizedBox(width: 8),
                _ExportPdfButton(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'L\'export PDF se fait depuis l\'onglet "Export paie".'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 4 stat cards — MediaQuery plutôt que LayoutBuilder.
          Builder(
            builder: (ctx) {
              final w = MediaQuery.sizeOf(ctx).width;
              final cols = w >= 900 ? 4 : (w >= 560 ? 2 : 1);
              return _Grid(
                cols: cols,
                gap: 12,
                children: [
                  _MiniStat(
                    label: 'Total mois',
                    value: monthDuration,
                    color: KlokTokens.bordeaux,
                  ),
                  _MiniStat(
                    label: 'Jours travaillés',
                    value: monthDays,
                    color: KlokTokens.ink,
                  ),
                  _MiniStat(
                    label: 'Moyenne / jour',
                    value: averageDay,
                    color: KlokTokens.ink,
                  ),
                  _MiniStat(
                    label: "Aujourd'hui",
                    value: todayLabel,
                    color: KlokTokens.success,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          // Historique
          _HistoryTable(employeeId: employee.id),
        ],
      ),
    );
  }
}

class _BackLink extends StatelessWidget {
  const _BackLink({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_left, size: 18, color: KlokTokens.inkSoft),
                const SizedBox(width: 4),
                Text(
                  'Retour équipe',
                  style: TextStyle(
                    fontSize: 13,
                    color: KlokTokens.inkSoft,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExportPdfButton extends StatelessWidget {
  const _ExportPdfButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KlokTokens.bordeaux,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            'Exporter PDF',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Petit bouton carré avec une icône — utilisé pour Modifier / Archiver sur
/// la fiche détail. On reste cohérent avec le bouton Quitter du header admin
/// (même bordure, même radius).
class _IconActionButton extends StatelessWidget {
  const _IconActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: KlokTokens.card,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: KlokTokens.border),
            ),
            width: 38,
            height: 38,
            child: Icon(icon, size: 18, color: KlokTokens.inkSoft),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Actions globales sur le détail d'un salarié (édition / archivage)
// ─────────────────────────────────────────────────────────────
Future<void> _editEmployee(BuildContext context, Employee e) async {
  await showDialog<void>(
    context: context,
    builder: (_) => AddEmployeeModal(existing: e),
  );
}

/// Demande confirmation puis archive le salarié (soft delete : préserve
/// l'historique de pointage pour la compta). On revient ensuite sur la
/// liste équipe — sans le bouton "Annuler" la sortie ne déchargerait pas
/// le détail puisqu'on supprime de l'index actif.
Future<void> _confirmArchive(
  BuildContext context,
  WidgetRef ref,
  Employee e,
  VoidCallback onBack,
) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Archiver ce salarié ?'),
      content: Text(
        '${e.firstName} ${e.lastName} sera retiré de la liste active. '
        "L'historique de ses pointages reste conservé pour la compta. "
        'Tu pourras le restaurer plus tard depuis la sauvegarde.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: KlokTokens.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Archiver'),
        ),
      ],
    ),
  );
  if (confirm != true) return;
  await ref.read(employeeRepositoryProvider).archive(e.id);
  if (!context.mounted) return;
  onBack();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('${e.firstName} ${e.lastName} archivé'),
    ),
  );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
              color: KlokTokens.inkSoft,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: KlokTokens.fontDisplay,
              fontSize: 24,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.6,
              color: color,
              fontFeatures: KlokTokens.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Historique — 12 derniers jours (day aggregated)
// ─────────────────────────────────────────────────────────────
class _HistoryTable extends ConsumerWidget {
  const _HistoryTable({required this.employeeId});
  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Recalculé à chaque tick pour que la ligne "en cours" reste à jour.
    ref.watch(tickerProvider);
    final history = ref.watch(_employeeHistoryProvider(employeeId));

    return AdminCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: KlokTokens.border),
              ),
            ),
            child: _HistoryRow(
              date: 'Date',
              start: 'Début',
              end: 'Fin',
              breaks: 'Pauses',
              total: 'Total',
              isHeader: true,
            ),
          ),
          history.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Erreur : $e'),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Aucune session pour le moment.',
                    style: TextStyle(color: KlokTokens.inkSoft),
                  ),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    Container(
                      color: rows[i].current
                          ? KlokTokens.successBg
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 11),
                      child: _HistoryRow(
                        date: rows[i].date,
                        start: rows[i].start,
                        end: rows[i].end,
                        breaks: rows[i].breaks,
                        total: rows[i].total,
                        muted: rows[i].isOff,
                        currentEnd: rows[i].current && rows[i].rawEnd == null,
                        anomaly: rows[i].anomaly,
                      ),
                    ),
                    if (i < rows.length - 1)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: KlokTokens.border,
                      ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.date,
    required this.start,
    required this.end,
    required this.breaks,
    required this.total,
    this.isHeader = false,
    this.muted = false,
    this.currentEnd = false,
    this.anomaly,
  });

  final String date;
  final String start;
  final String end;
  final String breaks;
  final String total;
  final bool isHeader;
  final bool muted;
  final bool currentEnd;
  final String? anomaly;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: isHeader ? 11 : 13,
      fontWeight: isHeader ? FontWeight.w600 : FontWeight.w400,
      letterSpacing: isHeader ? 0.6 : 0,
      color: isHeader
          ? KlokTokens.inkSoft
          : (muted ? KlokTokens.muted : KlokTokens.ink),
      fontFeatures: KlokTokens.tabularFigures,
    );
    final endWidget = (currentEnd && !isHeader)
        ? Text(
            'en cours',
            style: baseStyle.copyWith(
              color: KlokTokens.success,
              fontWeight: FontWeight.w500,
            ),
          )
        : Text(end, style: baseStyle);

    Widget cell(String text, {TextAlign align = TextAlign.left}) =>
        Text(text, style: baseStyle, textAlign: align);
    final label = anomaly;
    return Row(
      children: [
        Expanded(
          child: label == null || isHeader
              ? Text(isHeader ? date.toUpperCase() : date, style: baseStyle)
              : Row(
                  children: [
                    Flexible(child: Text(date, style: baseStyle)),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: label,
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: KlokTokens.warn,
                      ),
                    ),
                  ],
                ),
        ),
        Expanded(child: cell(isHeader ? start.toUpperCase() : start)),
        Expanded(child: endWidget),
        Expanded(child: cell(isHeader ? breaks.toUpperCase() : breaks)),
        Expanded(
          child: Text(
            isHeader ? total.toUpperCase() : total,
            textAlign: TextAlign.right,
            style: baseStyle.copyWith(
              fontWeight: isHeader ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Provider local : historique 12 jours par salarié.
// On agrège au niveau du jour local en regroupant les sessions chevauchant
// le même jour (rare dans un bar, mais on gère : on prend le 1er start et
// le dernier end du jour).
// ─────────────────────────────────────────────────────────────
class _HistoryRowData {
  _HistoryRowData({
    required this.date,
    required this.start,
    required this.end,
    required this.breaks,
    required this.total,
    required this.isOff,
    required this.current,
    this.rawEnd,
    this.anomaly,
  });

  final String date;
  final String start;
  final String end;
  final String breaks;
  final String total;
  final bool isOff;
  final bool current;
  final DateTime? rawEnd;

  /// Libellé d'anomalie du jour (`SessionWithBreaks.anomalyLabel`), `null` si
  /// la journée est saine. Les heures restent affichées telles quelles : on
  /// signale au patron, on ne corrige pas à sa place.
  final String? anomaly;
}

final _employeeHistoryProvider = FutureProvider.autoDispose
    .family<List<_HistoryRowData>, int>((ref, employeeId) async {
  ref.watch(tickerProvider);
  final repo = ref.watch(sessionRepositoryProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final from = today.subtract(const Duration(days: 11)).toUtc();
  final to = today.add(const Duration(days: 1)).toUtc();

  final sessions = await repo.sessionsInRange(employeeId, from, to);
  final breaks =
      await repo.breaksForSessions(sessions.map((s) => s.id).toList());

  // Regrouper les sessions par jour local
  final byDay = <DateTime, List<SessionWithBreaks>>{};
  for (final s in sessions) {
    final local = s.startedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final joined = SessionWithBreaks(
      session: s,
      breaks: breaks.where((b) => b.sessionId == s.id).toList(),
    );
    byDay.putIfAbsent(day, () => []).add(joined);
  }

  final rows = <_HistoryRowData>[];
  for (var i = 0; i < 12; i++) {
    final day = today.subtract(Duration(days: i));
    final dayLabel = DateFormat('EEE dd/MM', 'fr_FR').format(day);
    final items = byDay[day];
    final isToday = i == 0;

    if (items == null || items.isEmpty) {
      rows.add(_HistoryRowData(
        date: dayLabel,
        start: '—',
        end: '—',
        breaks: '—',
        total: '—',
        isOff: true,
        current: isToday,
      ));
      continue;
    }

    items.sort(
        (a, b) => a.session.startedAt.compareTo(b.session.startedAt));
    final firstStart = items.first.session.startedAt.toLocal();
    DateTime? lastEnd;
    var hasOpen = false;
    for (final it in items) {
      if (it.session.endedAt == null) {
        hasOpen = true;
      } else {
        final end = it.session.endedAt!.toLocal();
        if (lastEnd == null || end.isAfter(lastEnd)) lastEnd = end;
      }
    }
    final netTotal = sumNet(items);
    final breakTotal = items.fold<Duration>(
      Duration.zero,
      (acc, it) => acc + it.breakDuration,
    );

    // Première anomalie rencontrée sur la journée — suffisant pour attirer
    // l'œil, le détail se lit sur la ligne concernée.
    final anomaly = items
        .map((it) => it.anomalyLabel)
        .firstWhere((label) => label != null, orElse: () => null);

    rows.add(_HistoryRowData(
      date: dayLabel,
      start: formatHHmm(firstStart),
      end: lastEnd != null ? formatHHmm(lastEnd) : '—',
      breaks: breakTotal.inMinutes > 0
          ? '${breakTotal.inMinutes} min'
          : '—',
      total: formatDuration(netTotal),
      isOff: false,
      current: hasOpen,
      rawEnd: lastEnd,
      anomaly: anomaly,
    ));
  }
  return rows;
});

// ─────────────────────────────────────────────────────────────
// Helpers partagés avec dashboard_tab.dart
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
