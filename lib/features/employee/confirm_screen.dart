// Écran de confirmation — variante Pastille (V2ConfirmScreen).
//
// Affiche une grosse pastille colorée avec les initiales, un message de type
// "Bon service !" et l'heure à laquelle l'action vient d'être effectuée.
// Auto-dismiss après 2,5 s : on retourne à l'écran de sélection.
//
// L'action est encodée dans l'URL (/confirm/:id/:action) pour survivre à un
// hot-reload / changement d'orientation — ainsi, même si quelque chose est
// secoué, on retombe bien sur le bon message.
//
// Ref design : variants/v2-pastille.jsx (fonction V2ConfirmScreen).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/db/app_database.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

enum ConfirmAction { start, end, breakStart, breakEnd }

ConfirmAction? _parseAction(String raw) {
  switch (raw) {
    case 'start':
      return ConfirmAction.start;
    case 'end':
      return ConfirmAction.end;
    case 'break-start':
      return ConfirmAction.breakStart;
    case 'break-end':
      return ConfirmAction.breakEnd;
  }
  return null;
}

class ConfirmScreen extends ConsumerStatefulWidget {
  const ConfirmScreen({
    super.key,
    required this.employeeId,
    required this.action,
  });

  final int employeeId;
  final String action;

  @override
  ConsumerState<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends ConsumerState<ConfirmScreen> {
  Timer? _timer;
  late final DateTime _at;

  @override
  void initState() {
    super.initState();
    _at = DateTime.now();
    _timer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      context.go('/');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final empAsync = ref.watch(employeeByIdProvider(widget.employeeId));
    final action = _parseAction(widget.action);

    return Scaffold(
      backgroundColor: KlokTokens.bg,
      body: GestureDetector(
        // Tap n'importe où → on skip le délai.
        onTap: () => context.go('/'),
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          child: empAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Center(child: Text('Erreur : $e')),
            data: (employee) => action == null
                ? const _FallbackUnknownAction()
                : _ConfirmBody(
                    employee: employee,
                    action: action,
                    at: _at,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmBody extends StatelessWidget {
  const _ConfirmBody({
    required this.employee,
    required this.action,
    required this.at,
  });

  final Employee employee;
  final ConfirmAction action;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final msg = _messageFor(action);
    final color = msg.color;
    final initials = _initialsOf(employee);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Dégradé radial autour de la pastille — teinte la couleur de l'action
        // (vert/bordeaux/ambre) vers transparent.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.7,
                colors: [
                  color.withValues(alpha: 0.13),
                  color.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Grosse pastille
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    offset: const Offset(0, 20),
                    blurRadius: 60,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontFamily: KlokTokens.fontDisplay,
                    fontWeight: FontWeight.w500,
                    fontSize: 56,
                    letterSpacing: -2,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            // Titre "Bon service !" etc.
            Text(
              msg.title,
              style: TextStyle(
                fontFamily: KlokTokens.fontDisplay,
                fontSize: 52,
                fontWeight: FontWeight.w500,
                letterSpacing: -1.5,
                color: KlokTokens.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // "Démarré à 14:23"
            Text(
              '${msg.sub} ${formatHHmm(at)}',
              style: TextStyle(
                fontSize: 18,
                color: KlokTokens.inkSoft,
                fontFeatures: KlokTokens.tabularFigures,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FallbackUnknownAction extends StatelessWidget {
  const _FallbackUnknownAction();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 56, color: KlokTokens.muted),
          const SizedBox(height: 16),
          Text('Action inconnue', style: TextStyle(color: KlokTokens.inkSoft)),
        ],
      ),
    );
  }
}

class _Msg {
  const _Msg(this.title, this.sub, this.color);
  final String title;
  final String sub;
  final Color color;
}

_Msg _messageFor(ConfirmAction a) {
  switch (a) {
    case ConfirmAction.start:
      return _Msg('Bon service !', 'Démarré à', KlokTokens.success);
    case ConfirmAction.end:
      return _Msg('Bonne soirée !', 'Terminé à', KlokTokens.bordeaux);
    case ConfirmAction.breakStart:
      return _Msg('Bonne pause !', 'Pause à', KlokTokens.amber);
    case ConfirmAction.breakEnd:
      return _Msg("C'est reparti !", 'Repris à', KlokTokens.success);
  }
}

String _initialsOf(Employee e) {
  final f = e.firstName.isNotEmpty ? e.firstName[0] : '';
  final l = e.lastName.isNotEmpty ? e.lastName[0] : '';
  final out = '$f$l';
  return out.isEmpty ? '?' : out.toUpperCase();
}
