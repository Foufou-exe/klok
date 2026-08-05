// Écran de pointage — variante Pastille (V2ClockScreen).
//
// Layout split 50/50 : card d'identité colorée à gauche (avatar + "Salut X !" +
// pill de statut + compteurs jour/semaine) et pile d'actions à droite, dont le
// contenu change suivant l'état :
//   • off     → gros bouton vert "Démarrer le service"
//   • working → bouton bordeaux "Terminer le service" + card "Démarrer pause"
//   • break   → bouton ambre "Reprendre le service"
//
// Responsive : on passe en colonne empilée si la largeur < 700 (portrait
// tablette / phone). Le haut reste le bandeau sticky avec horloge vivante
// et retour "Changer de salarié".
//
// Navigation : après action → /confirm/:id/:action (écran de remerciement).
// Ref design : variants/v2-pastille.jsx (fonction V2ClockScreen).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/time_math.dart';
import '../../data/db/app_database.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

class ClockScreen extends ConsumerWidget {
  const ClockScreen({super.key, required this.employeeId});

  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empAsync = ref.watch(employeeByIdProvider(employeeId));
    final clockAsync = ref.watch(clockStateProvider(employeeId));

    return Scaffold(
      backgroundColor: KlokTokens.bg,
      body: SafeArea(
        child: empAsync.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: KlokTokens.bordeaux),
          ),
          error: (e, _) => Center(child: Text('Erreur : $e')),
          data: (employee) => clockAsync.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: KlokTokens.bordeaux),
            ),
            error: (e, _) => Center(child: Text('Erreur : $e')),
            data: (state) => _ClockBody(employee: employee, state: state),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Body : top bar + split layout ou layout empilé
// ─────────────────────────────────────────────────────────────
class _ClockBody extends ConsumerWidget {
  const _ClockBody({required this.employee, required this.state});

  final Employee employee;
  final EmployeeClockState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (ctx, bc) {
        final w = bc.maxWidth;
        // Breakpoint choisi en pratique : en dessous de 700, les deux cartes
        // sont trop serrées côte à côte (48px padding + 24px gap).
        final stacked = w < 700;
        final horiz = w >= 900
            ? 48.0
            : w >= 600
            ? 32.0
            : 20.0;

        return Column(
          children: [
            _TopBar(horiz: horiz),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(horiz, 8, horiz, horiz),
                child: stacked
                    ? _StackedLayout(employee: employee, state: state)
                    : _SplitLayout(employee: employee, state: state),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SplitLayout extends StatelessWidget {
  const _SplitLayout({required this.employee, required this.state});
  final Employee employee;
  final EmployeeClockState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _IdentityCard(employee: employee, state: state),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: _ActionColumn(employee: employee, state: state),
        ),
      ],
    );
  }
}

class _StackedLayout extends StatelessWidget {
  const _StackedLayout({required this.employee, required this.state});
  final Employee employee;
  final EmployeeClockState state;

  @override
  Widget build(BuildContext context) {
    // En stacked on scroll pour laisser passer les claviers / formats réduits.
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          SizedBox(
            // Garde la card d'identité suffisamment haute pour rester lisible.
            height: 280,
            child: _IdentityCard(employee: employee, state: state),
          ),
          const SizedBox(height: 14),
          _ActionColumn(employee: employee, state: state),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Top bar : "Changer de salarié" + horloge live
// ─────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar({required this.horiz});
  final double horiz;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horiz, 16, horiz, 8),
      child: Row(
        children: [
          InkWell(
            onTap: () => context.go('/'),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left, size: 18, color: KlokTokens.inkSoft),
                  const SizedBox(width: 4),
                  Text(
                    'Changer de salarié',
                    style: TextStyle(
                      fontSize: 14,
                      color: KlokTokens.inkSoft,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          const _LiveClockSmall(),
        ],
      ),
    );
  }
}

class _LiveClockSmall extends ConsumerWidget {
  const _LiveClockSmall();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(tickerProvider).asData?.value ?? DateTime.now();
    return Text(
      formatHHmm(now),
      style: TextStyle(
        fontFamily: KlokTokens.fontDisplay,
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: KlokTokens.ink,
        fontFeatures: KlokTokens.tabularFigures,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Identity card (gauche) — fond coloré à la couleur du salarié
// ─────────────────────────────────────────────────────────────
class _IdentityCard extends ConsumerWidget {
  const _IdentityCard({required this.employee, required this.state});

  final Employee employee;
  final EmployeeClockState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // On tick pour afficher la durée qui coule sur la pill de statut.
    ref.watch(tickerProvider);
    final color = _parseHexColor(employee.color);
    final initials = _initialsOf(employee);

    // Calcule les compteurs du jour et de la semaine à partir des sessions
    // déjà en DB (en lecture directe via repo, pas un FutureProvider, pour
    // garder ce widget simple — on le rafraîchit sur chaque tick via le watch).
    final repo = ref.watch(sessionRepositoryProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Cercle décoratif bottom-right — simule overflow: hidden + circle.
            Positioned(
              right: -80,
              bottom: -80,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 36, 32, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mini-avatar
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontFamily: KlokTokens.fontDisplay,
                          fontWeight: FontWeight.w600,
                          fontSize: 28,
                          letterSpacing: -0.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // "Salut {prenom} !"
                  Text(
                    'Salut\n${employee.firstName} !',
                    style: const TextStyle(
                      fontFamily: KlokTokens.fontDisplay,
                      fontSize: 38,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -1,
                      height: 1.05,
                      color: Colors.white,
                    ),
                  ),
                  if (employee.lastName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      employee.lastName,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Pill de statut
                  _StatusPill(state: state),
                  // Compteurs (seulement si une session est en cours).
                  if (!state.isIdle) ...[
                    const SizedBox(height: 18),
                    _DayWeekCounters(employee: employee, repo: repo),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends ConsumerWidget {
  const _StatusPill({required this.state});
  final EmployeeClockState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now().toUtc();
    String label;
    if (state.isIdle) {
      label = "Pas encore pointé aujourd'hui";
    } else if (state.isOnBreak) {
      final d = now.difference(state.openBreak!.startedAt);
      label = 'En pause depuis ${_shortDur(d)}';
    } else {
      final d = now.difference(state.openSession!.startedAt);
      label = 'En service depuis ${_shortDur(d)}';
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayWeekCounters extends StatefulWidget {
  const _DayWeekCounters({required this.employee, required this.repo});
  final Employee employee;
  final SessionRepository repo;

  @override
  State<_DayWeekCounters> createState() => _DayWeekCountersState();
}

class _DayWeekCountersState extends State<_DayWeekCounters> {
  Duration _today = Duration.zero;
  Duration _week = Duration.zero;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toUtc();
    // Lundi = 1 en Dart.
    final weekStartLocal = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final weekStart = weekStartLocal.toUtc();
    final endOfRange = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1)).toUtc();

    // Jour
    final sessionsToday = await widget.repo.sessionsInRange(
      widget.employee.id,
      startOfDay,
      endOfRange,
    );
    final breaksToday = await widget.repo.breaksForSessions(
      sessionsToday.map((s) => s.id).toList(),
    );
    final todayTotal = sumNet([
      for (final s in sessionsToday)
        SessionWithBreaks(
          session: s,
          breaks: breaksToday.where((b) => b.sessionId == s.id).toList(),
        ),
    ]);

    // Semaine
    final sessionsWeek = await widget.repo.sessionsInRange(
      widget.employee.id,
      weekStart,
      endOfRange,
    );
    final breaksWeek = await widget.repo.breaksForSessions(
      sessionsWeek.map((s) => s.id).toList(),
    );
    final weekTotal = sumNet([
      for (final s in sessionsWeek)
        SessionWithBreaks(
          session: s,
          breaks: breaksWeek.where((b) => b.sessionId == s.id).toList(),
        ),
    ]);

    if (!mounted) return;
    setState(() {
      _today = todayTotal;
      _week = weekTotal;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Text(
        "Aujourd'hui : — · Semaine : —",
        style: TextStyle(
          fontFamily: KlokTokens.fontDisplay,
          fontSize: 14,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      );
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: KlokTokens.fontDisplay,
          fontSize: 14,
          color: Colors.white.withValues(alpha: 0.85),
        ),
        children: [
          const TextSpan(text: "Aujourd'hui : "),
          TextSpan(
            text: formatDuration(_today),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontFeatures: KlokTokens.tabularFigures,
            ),
          ),
          const TextSpan(text: ' · Semaine : '),
          TextSpan(
            text: formatDuration(_week),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontFeatures: KlokTokens.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Action column (droite) — boutons variant par état
// ─────────────────────────────────────────────────────────────
class _ActionColumn extends ConsumerWidget {
  const _ActionColumn({required this.employee, required this.state});
  final Employee employee;
  final EmployeeClockState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(sessionRepositoryProvider);

    Future<void> doAction(String action) async {
      try {
        switch (action) {
          case 'start':
            await repo.startSession(employee.id);
            break;
          case 'end':
            await repo.endSession(state.openSession!.id);
            break;
          case 'break-start':
            await repo.startBreak(state.openSession!.id);
            break;
          case 'break-end':
            await repo.endBreak(state.openBreak!.id);
            break;
        }
        if (!context.mounted) return;
        // Redirige sur l'écran de confirmation (2,5s auto-dismiss).
        context.go('/confirm/${employee.id}/$action');
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.isIdle)
          _HeroAction(
            label: 'Démarrer',
            label2: 'le service',
            sub: 'Ça sera noté à ${formatHHmm(DateTime.now())}',
            bg: KlokTokens.success,
            onTap: () => doAction('start'),
            overline: 'ACTION',
          )
        else if (state.isOnBreak)
          _HeroAction(
            label: 'Reprendre',
            label2: 'le service',
            sub: _breakDurationSub(state.openBreak),
            bg: KlokTokens.amber,
            onTap: () => doAction('break-end'),
          )
        else ...[
          // En service — deux actions, la principale d'abord.
          _PrimaryAction(
            label: 'Terminer le service',
            sub: 'Tu rentres ? Bonne soirée.',
            onTap: () => _confirmEndSession(context, () => doAction('end')),
          ),
          const SizedBox(height: 14),
          _SecondaryAction(
            label: 'Démarrer une pause',
            sub: 'Café, cigarette, repas…',
            onTap: () => doAction('break-start'),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmEndSession(
    BuildContext context,
    VoidCallback onConfirm,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KlokTokens.radiusLg),
        ),
        title: Text(
          "Terminer le service ?",
          style: TextStyle(
            fontFamily: KlokTokens.fontDisplay,
            fontWeight: FontWeight.w600,
            color: KlokTokens.ink,
          ),
        ),
        content: Text(
          'Confirme la fin de ton service.',
          style: TextStyle(color: KlokTokens.inkSoft),
        ),
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
    if (ok == true) onConfirm();
  }
}

/// Gros bouton "hero" (fond coloré) pour l'action principale quand elle est
/// unique : démarrer ou reprendre.
class _HeroAction extends StatelessWidget {
  const _HeroAction({
    required this.label,
    required this.label2,
    required this.sub,
    required this.bg,
    required this.onTap,
    this.overline,
  });

  final String label;
  final String label2;
  final String sub;
  final Color bg;
  final VoidCallback onTap;
  final String? overline;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: bg.withValues(alpha: 0.3),
                offset: const Offset(0, 8),
                blurRadius: 24,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 36, 28, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (overline != null) ...[
                  Text(
                    overline!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.6,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  '$label\n$label2',
                  style: const TextStyle(
                    fontFamily: KlokTokens.fontDisplay,
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.6,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.9),
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

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.sub,
    required this.onTap,
  });
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KlokTokens.bordeaux,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: KlokTokens.bordeaux,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x263C2814),
                offset: Offset(0, 6),
                blurRadius: 20,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: KlokTokens.fontDisplay,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.9),
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

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.label,
    required this.sub,
    required this.onTap,
  });
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KlokTokens.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: KlokTokens.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: KlokTokens.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: KlokTokens.fontDisplay,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                    color: KlokTokens.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  style: TextStyle(fontSize: 13, color: KlokTokens.inkSoft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helpers locaux
// ─────────────────────────────────────────────────────────────

String _shortDur(Duration d) {
  final total = d.inMinutes;
  if (total < 1) return "moins d'une minute";
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '${h}h';
  return '${h}h${m.toString().padLeft(2, '0')}';
}

String _breakDurationSub(Break? b) {
  if (b == null) return '';
  final mins = DateTime.now().toUtc().difference(b.startedAt).inMinutes;
  if (mins < 1) return 'Pause en cours';
  return 'Pause de $mins minute${mins > 1 ? 's' : ''}';
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
