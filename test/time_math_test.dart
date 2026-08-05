import 'package:flutter_test/flutter_test.dart';

import 'package:klok/core/time_math.dart';
import 'package:klok/data/db/app_database.dart';

/// `time_math` produit les heures qui finissent sur les fiches de paie. C'est
/// du calcul pur, donc testable sans base : on fabrique les lignes à la main.
SessionWithBreaks build({
  required DateTime startedAt,
  DateTime? endedAt,
  List<(DateTime, DateTime?)> breaks = const [],
}) {
  return SessionWithBreaks(
    session: WorkSession(
      id: 1,
      employeeId: 1,
      startedAt: startedAt,
      endedAt: endedAt,
    ),
    breaks: [
      for (final (i, b) in breaks.indexed)
        Break(id: i + 1, sessionId: 1, startedAt: b.$1, endedAt: b.$2),
    ],
  );
}

void main() {
  group('durées', () {
    test('net = brut - pauses', () {
      final s = build(
        startedAt: DateTime.utc(2026, 5, 12, 9),
        endedAt: DateTime.utc(2026, 5, 12, 17),
        breaks: [(DateTime.utc(2026, 5, 12, 12), DateTime.utc(2026, 5, 12, 13))],
      );
      expect(s.grossDuration, const Duration(hours: 8));
      expect(s.breakDuration, const Duration(hours: 1));
      expect(s.netDuration, const Duration(hours: 7));
    });

    test('plusieurs pauses se cumulent', () {
      final s = build(
        startedAt: DateTime.utc(2026, 5, 12, 9),
        endedAt: DateTime.utc(2026, 5, 12, 17),
        breaks: [
          (DateTime.utc(2026, 5, 12, 11), DateTime.utc(2026, 5, 12, 11, 15)),
          (DateTime.utc(2026, 5, 12, 14), DateTime.utc(2026, 5, 12, 14, 45)),
        ],
      );
      expect(s.breakDuration, const Duration(hours: 1));
      expect(s.netDuration, const Duration(hours: 7));
    });

    test('le net est clampé à zéro, jamais négatif', () {
      // Pauses plus longues que la présence : saisie incohérente.
      final s = build(
        startedAt: DateTime.utc(2026, 5, 12, 9),
        endedAt: DateTime.utc(2026, 5, 12, 10),
        breaks: [(DateTime.utc(2026, 5, 12, 9), DateTime.utc(2026, 5, 12, 12))],
      );
      expect(s.netDuration, Duration.zero);
      expect(s.hasBreakOverflow, isTrue);
      expect(s.hasTimeAnomaly, isTrue);
    });

    test('sumNet additionne les sessions', () {
      final sessions = [
        build(
          startedAt: DateTime.utc(2026, 5, 12, 9),
          endedAt: DateTime.utc(2026, 5, 12, 13),
        ),
        build(
          startedAt: DateTime.utc(2026, 5, 13, 9),
          endedAt: DateTime.utc(2026, 5, 13, 12),
        ),
      ];
      expect(sumNet(sessions), const Duration(hours: 7));
    });

    test('sumNet sur une liste vide vaut zéro', () {
      expect(sumNet([]), Duration.zero);
    });
  });

  group('anomalies', () {
    test('horloge reculée → durée négative signalée', () {
      final s = build(
        startedAt: DateTime.utc(2026, 5, 12, 17),
        endedAt: DateTime.utc(2026, 5, 12, 9),
      );
      expect(s.hasNegativeDuration, isTrue);
      expect(s.anomalyLabel, 'Horloge incohérente');
      expect(s.netDuration, Duration.zero, reason: 'jamais de durée négative');
    });

    test('session close de 20 h → durée inhabituelle', () {
      final s = build(
        startedAt: DateTime.utc(2026, 5, 12, 9),
        endedAt: DateTime.utc(2026, 5, 13, 5),
      );
      expect(s.isImplausiblyLong, isTrue);
      expect(s.anomalyLabel, 'Durée inhabituelle');
    });

    test('session ouverte depuis 2 jours → sortie non pointée', () {
      final s = build(
        startedAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
      );
      expect(s.isOpen, isTrue);
      expect(s.isStaleOpenSession, isTrue);
      expect(s.anomalyLabel, 'Sortie non pointée');
    });

    test('un service de nuit normal de 8 h ne déclenche rien', () {
      final s = build(
        startedAt: DateTime.utc(2026, 5, 12, 18),
        endedAt: DateTime.utc(2026, 5, 13, 2),
        breaks: [(DateTime.utc(2026, 5, 12, 22), DateTime.utc(2026, 5, 12, 22, 30))],
      );
      expect(s.hasTimeAnomaly, isFalse);
      expect(s.anomalyLabel, isNull);
      expect(s.netDuration, const Duration(hours: 7, minutes: 30));
    });

    test('une session ouverte depuis 3 h est normale, pas une anomalie', () {
      final s = build(
        startedAt: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
      );
      expect(s.hasTimeAnomaly, isFalse);
      expect(s.grossDuration.inHours, 3);
    });
  });

  group('groupByLocalDay', () {
    test('regroupe les sessions du même jour', () {
      final groups = groupByLocalDay([
        build(
          startedAt: DateTime(2026, 5, 12, 9),
          endedAt: DateTime(2026, 5, 12, 13),
        ),
        build(
          startedAt: DateTime(2026, 5, 12, 18),
          endedAt: DateTime(2026, 5, 12, 23),
        ),
        build(
          startedAt: DateTime(2026, 5, 13, 9),
          endedAt: DateTime(2026, 5, 13, 13),
        ),
      ]);

      expect(groups, hasLength(2));
      expect(groups[DateTime(2026, 5, 12)], hasLength(2));
      expect(groups[DateTime(2026, 5, 13)], hasLength(1));
    });

    test('une session à cheval sur minuit compte sur son jour de début', () {
      // Convention de paie : la nuit du vendredi appartient au vendredi.
      // Ce test verrouille le choix — le changer déplacerait des heures d'un
      // mois de paie à l'autre.
      final groups = groupByLocalDay([
        build(
          startedAt: DateTime(2026, 5, 12, 22),
          endedAt: DateTime(2026, 5, 13, 2),
        ),
      ]);

      expect(groups.keys.single, DateTime(2026, 5, 12));
      expect(sumNet(groups[DateTime(2026, 5, 12)]!), const Duration(hours: 4));
    });

    test('une liste vide donne une map vide', () {
      expect(groupByLocalDay([]), isEmpty);
    });
  });
}
