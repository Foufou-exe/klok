// Onglet "Export paie" — variante Pastille.
//
// 2 colonnes :
//   • gauche : choix de la période (3 boutons) + chips salariés + CTA
//     "Générer N PDF" bordeaux.
//   • droite : aperçu A4 scale réduit (placeholder fidèle au design).
//
// Le pipeline PDF est branché : à chaque clic sur "Générer", on calcule les
// totaux jour-par-jour pour les salariés cochés via `PayrollPdfService`,
// on produit un PDF A4 par salarié dans le répertoire temporaire, puis on
// ouvre le share sheet natif (mail / Drive / clé USB...). Pas de réseau.
//
// Ref design : variants/v2-admin.jsx (fonction V2Export).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/db/app_database.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../design/tokens.dart';
import '../../../services/payroll_pdf_service.dart';
import '../../../state/providers.dart';
import '../widgets/admin_card.dart';

enum _Period { currentMonth, previousMonth, custom }

class ExportTab extends ConsumerStatefulWidget {
  const ExportTab({super.key});

  @override
  ConsumerState<ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends ConsumerState<ExportTab> {
  _Period _period = _Period.currentMonth;
  final Set<int> _selected = <int>{};
  bool _initialized = false;
  bool _generating = false;

  (DateTime, DateTime) _range() {
    final now = DateTime.now();
    switch (_period) {
      case _Period.currentMonth:
        return (
          DateTime(now.year, now.month),
          DateTime(now.year, now.month + 1).subtract(const Duration(days: 1)),
        );
      case _Period.previousMonth:
        return (
          DateTime(now.year, now.month - 1),
          DateTime(now.year, now.month).subtract(const Duration(days: 1)),
        );
      case _Period.custom:
        // Placeholder : 30 derniers jours (picker réel plus tard).
        return (
          now.subtract(const Duration(days: 29)),
          now,
        );
    }
  }

  /// Génère un PDF A4 par salarié coché et ouvre la sheet de partage.
  Future<void> _generateAndShare(List<Employee> allEmployees) async {
    if (_selected.isEmpty || _generating) return;
    setState(() => _generating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final (from, to) = _range();
      final selectedEmployees = allEmployees
          .where((e) => _selected.contains(e.id))
          .toList();

      final pdf = ref.read(payrollPdfServiceProvider);
      final settings = ref.read(settingsRepositoryProvider);
      final establishment =
          (await settings.get(SettingsKeys.barName))?.trim() ?? 'Klok';
      final ownerFirst =
          (await settings.get(SettingsKeys.ownerFirstName))?.trim() ?? '';
      final ownerLast =
          (await settings.get(SettingsKeys.ownerLastName))?.trim() ?? '';
      var ownerName = [ownerFirst, ownerLast]
          .where((s) => s.isNotEmpty)
          .join(' ');
      if (ownerName.isEmpty) {
        ownerName =
            (await settings.get(SettingsKeys.ownerLegacyName))?.trim() ?? '';
      }

      final bundle = <PayrollData>[];
      for (final e in selectedEmployees) {
        final data = await pdf.compute(employee: e, from: from, to: to);
        bundle.add(data);
      }
      final n = await pdf.generateAndShare(
        bundle: bundle,
        establishmentName: establishment,
        ownerName: ownerName.isEmpty ? null : ownerName,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('$n PDF généré${n > 1 ? 's' : ''} et partagé${n > 1 ? 's' : ''}.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Échec de l'export PDF : $e")),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees =
        ref.watch(activeEmployeesProvider).asData?.value ?? const [];
    // Par défaut, tout le monde est coché au premier build.
    if (!_initialized && employees.isNotEmpty) {
      _initialized = true;
      _selected.addAll(employees.map((e) => e.id));
    }

    final (from, to) = _range();
    final rangeLabel =
        '${DateFormat('dd/MM/yyyy').format(from)} → ${DateFormat('dd/MM/yyyy').format(to)}';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(),
          const SizedBox(height: 20),
          // MediaQuery au lieu de LayoutBuilder : on évite la re-entrance layout.
          Builder(
            builder: (ctx) {
              final wide = MediaQuery.sizeOf(ctx).width >= 900;
              final left = _LeftColumn(
                period: _period,
                onPeriod: (p) => setState(() => _period = p),
                rangeLabel: rangeLabel,
                employees: employees,
                selected: _selected,
                onToggle: (id) => setState(() {
                  if (_selected.contains(id)) {
                    _selected.remove(id);
                  } else {
                    _selected.add(id);
                  }
                }),
                onGenerate: _generating
                    ? null
                    : () => _generateAndShare(employees),
                generating: _generating,
              );
              final right = _RightColumn(
                rangeLabel: rangeLabel,
                employees: employees
                    .where((e) => _selected.contains(e.id))
                    .toList(),
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: left),
                    const SizedBox(width: 16),
                    Expanded(child: right),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  left,
                  const SizedBox(height: 16),
                  right,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Export paie',
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
          'Génère un PDF par salarié pour la compta',
          style: TextStyle(fontSize: 14, color: KlokTokens.inkSoft),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Colonne gauche : période + chips + CTA
// ─────────────────────────────────────────────────────────────
class _LeftColumn extends StatelessWidget {
  const _LeftColumn({
    required this.period,
    required this.onPeriod,
    required this.rangeLabel,
    required this.employees,
    required this.selected,
    required this.onToggle,
    required this.onGenerate,
    required this.generating,
  });

  final _Period period;
  final ValueChanged<_Period> onPeriod;
  final String rangeLabel;
  final List<Employee> employees;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  // Nullable : on désactive le bouton tant qu'une génération est en cours.
  final VoidCallback? onGenerate;
  final bool generating;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Période',
            style: TextStyle(
              fontFamily: KlokTokens.fontDisplay,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: KlokTokens.ink,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _PeriodPill(
                label: 'Mois en cours',
                active: period == _Period.currentMonth,
                onTap: () => onPeriod(_Period.currentMonth),
              ),
              const SizedBox(width: 8),
              _PeriodPill(
                label: 'Mois précédent',
                active: period == _Period.previousMonth,
                onTap: () => onPeriod(_Period.previousMonth),
              ),
              const SizedBox(width: 8),
              _PeriodPill(
                label: 'Personnalisé',
                active: period == _Period.custom,
                onTap: () => onPeriod(_Period.custom),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: KlokTokens.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PLAGE RETENUE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.7,
                    color: KlokTokens.inkSoft,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rangeLabel,
                  style: TextStyle(
                    fontFamily: KlokTokens.fontDisplay,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: KlokTokens.ink,
                    fontFeatures: KlokTokens.tabularFigures,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Salariés (${selected.length}/${employees.length})',
            style: TextStyle(
              fontFamily: KlokTokens.fontDisplay,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: KlokTokens.ink,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in employees)
                _EmployeeChip(
                  employee: e,
                  selected: selected.contains(e.id),
                  onTap: () => onToggle(e.id),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _GenerateButton(
            count: selected.length,
            // Désactivé si pas de sélection OU si on génère déjà — évite les
            // doubles clics qui produiraient deux salves de PDF.
            enabled: selected.isNotEmpty && onGenerate != null,
            generating: generating,
            onTap: onGenerate,
          ),
        ],
      ),
    );
  }
}

class _PeriodPill extends StatelessWidget {
  const _PeriodPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: active ? KlokTokens.ink : KlokTokens.bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: active ? Colors.white : KlokTokens.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmployeeChip extends StatelessWidget {
  const _EmployeeChip({
    required this.employee,
    required this.selected,
    required this.onTap,
  });

  final Employee employee;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _parseHexColor(employee.color);
    return Material(
      color: selected ? color : KlokTokens.bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: selected
                ? null
                : Border.all(
                    color: KlokTokens.border,
                    style: BorderStyle.solid,
                  ),
          ),
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.25)
                      : KlokTokens.card,
                ),
                child: Center(
                  child: Text(
                    _initialsOf(employee),
                    style: TextStyle(
                      fontFamily: KlokTokens.fontDisplay,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : KlokTokens.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${employee.firstName} ${employee.lastName}'.trim(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: selected ? Colors.white : KlokTokens.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenerateButton extends StatelessWidget {
  const _GenerateButton({
    required this.count,
    required this.enabled,
    required this.generating,
    required this.onTap,
  });

  final int count;
  final bool enabled;
  final bool generating;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final clickable = enabled && !generating;
    final bg = clickable ? KlokTokens.bordeaux : KlokTokens.border;
    final fg = clickable ? Colors.white : KlokTokens.muted;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: clickable ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Center(
            child: generating
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Génération en cours...',
                        style: TextStyle(
                          fontFamily: KlokTokens.fontDisplay,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Générer $count PDF · partager',
                    style: TextStyle(
                      fontFamily: KlokTokens.fontDisplay,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: fg,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Colonne droite : aperçu A4
// ─────────────────────────────────────────────────────────────
class _RightColumn extends ConsumerWidget {
  const _RightColumn({required this.rangeLabel, required this.employees});

  final String rangeLabel;
  final List<Employee> employees;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = employees.isEmpty
        ? null
        : employees.first; // Aperçu du 1er salarié sélectionné
    final barName = ref.watch(barNameProvider).asData?.value ?? 'Klok';
    final today = DateFormat('dd/MM/yyyy').format(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'APERÇU',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.7,
            color: KlokTokens.inkSoft,
          ),
        ),
        const SizedBox(height: 10),
        AspectRatio(
          aspectRatio: 210 / 297,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x243C2814),
                  offset: Offset(0, 8),
                  blurRadius: 28,
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
            child: _PdfPreview(
              employee: preview,
              barName: barName,
              rangeLabel: rangeLabel,
              today: today,
            ),
          ),
        ),
      ],
    );
  }
}

class _PdfPreview extends StatelessWidget {
  const _PdfPreview({
    required this.employee,
    required this.barName,
    required this.rangeLabel,
    required this.today,
  });

  final Employee? employee;
  final String barName;
  final String rangeLabel;
  final String today;

  @override
  Widget build(BuildContext context) {
    final name = employee != null
        ? '${employee!.firstName} ${employee!.lastName}'.trim()
        : 'Aucun salarié sélectionné';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header PDF
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: KlokTokens.border),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontFamily: KlokTokens.fontDisplay,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                          color: KlokTokens.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rangeLabel,
                        style: TextStyle(
                          fontSize: 9,
                          color: KlokTokens.inkSoft,
                          fontFeatures: KlokTokens.tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      barName,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: KlokTokens.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Édité le $today',
                      style: TextStyle(
                        fontSize: 9,
                        color: KlokTokens.inkSoft,
                        fontFeatures: KlokTokens.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // KPI row
        Row(
          children: [
            for (final kv in const [
              ['Jours', '—'],
              ['Heures', '—'],
              ['Pauses', '—'],
            ]) ...[
              Expanded(child: _PdfKpi(label: kv[0], value: kv[1])),
              if (kv != const ['Pauses', '—']) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'DÉTAIL',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: KlokTokens.inkSoft,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Center(
            child: Text(
              'Le détail journalier sera généré\nà partir des sessions en base.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: KlokTokens.inkSoft,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PdfKpi extends StatelessWidget {
  const _PdfKpi({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: KlokTokens.bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: KlokTokens.inkSoft,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: KlokTokens.fontDisplay,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KlokTokens.ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────
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
