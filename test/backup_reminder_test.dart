import 'package:flutter_test/flutter_test.dart';

import 'package:klok/core/backup_reminder.dart';

void main() {
  final now = DateTime.utc(2026, 6, 15, 12);
  String isoDaysAgo(int days) =>
      now.subtract(Duration(days: days)).toIso8601String();

  group('parse', () {
    test('reconnaît les clés stockées', () {
      expect(BackupReminderFreq.parse('none'), BackupReminderFreq.none);
      expect(BackupReminderFreq.parse('weekly'), BackupReminderFreq.weekly);
      expect(BackupReminderFreq.parse('monthly'), BackupReminderFreq.monthly);
    });

    test('retombe sur hebdomadaire si la valeur est absente ou inconnue', () {
      expect(BackupReminderFreq.parse(null), BackupReminderFreq.weekly);
      expect(BackupReminderFreq.parse('bidon'), BackupReminderFreq.weekly);
    });
  });

  group('status', () {
    test('rappel désactivé → jamais d\'alerte, même sans sauvegarde', () {
      expect(
        backupReminderStatus(
          lastBackupAtIso: null,
          freq: BackupReminderFreq.none,
          now: now,
        ),
        BackupReminderStatus.disabled,
      );
    });

    test('aucune sauvegarde → alerte "never"', () {
      final status = backupReminderStatus(
        lastBackupAtIso: null,
        freq: BackupReminderFreq.weekly,
        now: now,
      );
      expect(status, BackupReminderStatus.never);
      expect(status.needsAttention, isTrue);
    });

    test('sauvegarde d\'hier en hebdo → rien à signaler', () {
      final status = backupReminderStatus(
        lastBackupAtIso: isoDaysAgo(1),
        freq: BackupReminderFreq.weekly,
        now: now,
      );
      expect(status, BackupReminderStatus.ok);
      expect(status.needsAttention, isFalse);
    });

    test('sauvegarde de 10 jours en hebdo → en retard', () {
      expect(
        backupReminderStatus(
          lastBackupAtIso: isoDaysAgo(10),
          freq: BackupReminderFreq.weekly,
          now: now,
        ),
        BackupReminderStatus.overdue,
      );
    });

    test('sauvegarde de 10 jours en mensuel → encore bon', () {
      expect(
        backupReminderStatus(
          lastBackupAtIso: isoDaysAgo(10),
          freq: BackupReminderFreq.monthly,
          now: now,
        ),
        BackupReminderStatus.ok,
      );
    });

    test('sauvegarde de 40 jours en mensuel → en retard', () {
      expect(
        backupReminderStatus(
          lastBackupAtIso: isoDaysAgo(40),
          freq: BackupReminderFreq.monthly,
          now: now,
        ),
        BackupReminderStatus.overdue,
      );
    });

    test('une date illisible est traitée comme aucune sauvegarde', () {
      expect(
        backupReminderStatus(
          lastBackupAtIso: 'pas-une-date',
          freq: BackupReminderFreq.weekly,
          now: now,
        ),
        BackupReminderStatus.never,
      );
    });

    test('une sauvegarde datée dans le futur ne déclenche pas d\'alerte', () {
      // Horloge système reculée après une sauvegarde : les données sont
      // fraîches, inutile d'affoler le patron.
      expect(
        backupReminderStatus(
          lastBackupAtIso: now.add(const Duration(days: 3)).toIso8601String(),
          freq: BackupReminderFreq.weekly,
          now: now,
        ),
        BackupReminderStatus.ok,
      );
    });
  });
}
