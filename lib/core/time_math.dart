import '../data/db/app_database.dart';

/// Au-delà de cette durée, une session est presque sûrement un oubli de
/// pointage de sortie plutôt qu'un vrai service. Un service de bar/restaurant
/// long (double coupure, soirée d'événement) dépasse rarement 12 h ; une
/// session de 14 h ou de 30 h vient d'un salarié parti sans clôturer.
///
/// On ne corrige pas automatiquement : on signale, et le patron tranche depuis
/// l'espace admin. Corriger d'office fausserait la paie sans laisser de trace.
const Duration kMaxPlausibleSessionDuration = Duration(hours: 12);

class SessionWithBreaks {
  SessionWithBreaks({required this.session, required this.breaks});

  final WorkSession session;
  final List<Break> breaks;

  bool get isOpen => session.endedAt == null;

  /// Une session encore ouverte est mesurée jusqu'à maintenant.
  Duration get grossDuration {
    final end = session.endedAt ?? DateTime.now().toUtc();
    return end.difference(session.startedAt);
  }

  Duration get breakDuration {
    var total = Duration.zero;
    for (final b in breaks) {
      final end = b.endedAt ?? DateTime.now().toUtc();
      total += end.difference(b.startedAt);
    }
    return total;
  }

  Duration get netDuration {
    final gross = grossDuration;
    final breaks = breakDuration;
    final net = gross - breaks;
    return net.isNegative ? Duration.zero : net;
  }

  /// Horloge système reculée entre le pointage d'entrée et celui de sortie.
  bool get hasNegativeDuration => grossDuration.isNegative;

  /// Session close anormalement longue : sortie pointée bien trop tard.
  bool get isImplausiblyLong =>
      !isOpen && grossDuration > kMaxPlausibleSessionDuration;

  /// Session toujours ouverte au-delà d'un service plausible : le salarié est
  /// parti sans pointer sa sortie et le compteur tourne encore. Distinguée de
  /// [isImplausiblyLong] car elle appelle une autre action côté patron —
  /// clôturer la session, pas corriger une heure.
  bool get isStaleOpenSession =>
      isOpen && grossDuration > kMaxPlausibleSessionDuration;

  /// Cumul des pauses supérieur au temps de présence — saisie incohérente.
  bool get hasBreakOverflow =>
      !grossDuration.isNegative && breakDuration > grossDuration;

  bool get hasTimeAnomaly =>
      hasNegativeDuration ||
      isImplausiblyLong ||
      isStaleOpenSession ||
      hasBreakOverflow;

  /// Libellé court de l'anomalie, à afficher à côté de la durée. `null` si la
  /// session est saine.
  String? get anomalyLabel {
    if (hasNegativeDuration) return 'Horloge incohérente';
    if (isStaleOpenSession) return 'Sortie non pointée';
    if (isImplausiblyLong) return 'Durée inhabituelle';
    if (hasBreakOverflow) return 'Pauses > présence';
    return null;
  }
}

Duration sumNet(Iterable<SessionWithBreaks> sessions) {
  return sessions.fold(Duration.zero, (acc, s) => acc + s.netDuration);
}

/// Regroupe par jour **local** de début de session.
///
/// Une session à cheval sur minuit (service de nuit : 22 h → 2 h) est comptée
/// entièrement sur son jour de début. C'est la convention de paie usuelle — la
/// nuit du vendredi appartient au vendredi — et elle évite de scinder une
/// session en deux lignes sur la fiche de paie.
Map<DateTime, List<SessionWithBreaks>> groupByLocalDay(
  Iterable<SessionWithBreaks> items,
) {
  final map = <DateTime, List<SessionWithBreaks>>{};
  for (final item in items) {
    final local = item.session.startedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    map.putIfAbsent(day, () => []).add(item);
  }
  return map;
}
