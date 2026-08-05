import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klok/data/db/app_database.dart';
import 'package:klok/data/repositories/employee_repository.dart';
import 'package:klok/data/repositories/session_repository.dart';
import 'package:klok/data/repositories/settings_repository.dart';
import 'package:klok/services/backup_service.dart';

/// Le backup est le seul filet contre la perte de données (la tablette n'a
/// aucune réplication). On teste le cycle complet export → restore, la
/// détection de corruption, et la préservation des IDs — un ID qui bouge
/// casserait les références entre sessions et salariés.
void main() {
  late AppDatabase db;
  late BackupService backup;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backup = BackupService(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Peuple la base : 2 salariés, une session terminée avec pause, une session
  /// encore ouverte, et quelques réglages.
  Future<void> seed() async {
    final employees = EmployeeRepository(db);
    final sessions = SessionRepository(db);
    final settings = SettingsRepository(db);

    final alice = await employees.create(
      firstName: 'Alice',
      lastName: 'Dupont',
    );
    await employees.create(firstName: 'Bob', lastName: 'Martin');

    final s = await sessions.startSession(
      alice,
      at: DateTime.utc(2026, 5, 12, 9),
    );
    final b = await sessions.startBreak(
      s.id,
      at: DateTime.utc(2026, 5, 12, 12),
    );
    await sessions.endBreak(b.id, at: DateTime.utc(2026, 5, 12, 12, 30));
    await sessions.endSession(s.id, at: DateTime.utc(2026, 5, 12, 17));

    // Session laissée ouverte : doit survivre au cycle sans être fermée.
    await sessions.startSession(alice, at: DateTime.utc(2026, 5, 13, 9));

    await settings.set(SettingsKeys.barName, 'Le Comptoir');
    await settings.setPin('4271');
  }

  test('export → restore restitue une base identique', () async {
    await seed();
    final before = await _snapshot(db);
    final bytes = await backup.buildPayloadBytes();

    // On vide tout pour prouver que la restauration reconstruit vraiment.
    await db.delete(db.breaks).go();
    await db.delete(db.workSessions).go();
    await db.delete(db.employees).go();
    await db.delete(db.appSettings).go();

    await backup.restore(bytes);

    expect(await _snapshot(db), before);
  });

  test('restore préserve les IDs', () async {
    await seed();
    final idsBefore = (await db.select(db.employees).get())
        .map((e) => e.id)
        .toList();

    final bytes = await backup.buildPayloadBytes();
    await backup.restore(bytes);

    final idsAfter = (await db.select(db.employees).get())
        .map((e) => e.id)
        .toList();
    expect(idsAfter, idsBefore);
  });

  test('restore est idempotent', () async {
    await seed();
    final bytes = await backup.buildPayloadBytes();

    await backup.restore(bytes);
    final once = await _snapshot(db);
    await backup.restore(bytes);

    expect(await _snapshot(db), once);
  });

  test('le PIN survit au cycle de sauvegarde', () async {
    await seed();
    final bytes = await backup.buildPayloadBytes();
    await db.delete(db.appSettings).go();
    await backup.restore(bytes);

    final settings = SettingsRepository(db);
    expect(await settings.verifyPin('4271'), isTrue);
    expect(await settings.verifyPin('0000'), isFalse);
  });

  test('une session ouverte reste ouverte après restauration', () async {
    await seed();
    final bytes = await backup.buildPayloadBytes();
    await backup.restore(bytes);

    final open = await (db.select(
      db.workSessions,
    )..where((s) => s.endedAt.isNull())).get();
    expect(open, hasLength(1));
    // `.toUtc()` obligatoire : drift restitue les DateTime en heure locale
    // (voir le test « l'instant est préservé… » plus bas), et `DateTime.==`
    // compare aussi le flag isUtc.
    expect(open.first.startedAt.toUtc(), DateTime.utc(2026, 5, 13, 9));
  });

  test(
    "l'instant est préservé à la restauration, quel que soit le fuseau",
    () async {
      // Le CLAUDE.md dit « tout est stocké en UTC ». C'est vrai de ce qu'on
      // écrit, mais drift *relit* les DateTime en heure locale. L'instant absolu
      // est identique — ce qui suffit pour les durées et le groupement par jour —
      // mais le flag isUtc ne survit pas. Ce test verrouille ce contrat pour
      // qu'un futur changement de sérialisation ne décale pas les heures de paie.
      final employees = EmployeeRepository(db);
      final sessions = SessionRepository(db);
      final id = await employees.create(firstName: 'Zoe', lastName: 'Tz');
      final startedAt = DateTime.utc(2026, 5, 13, 9);
      await sessions.startSession(id, at: startedAt);

      final bytes = await backup.buildPayloadBytes();
      await backup.restore(bytes);

      final restored = (await db.select(db.workSessions).get()).single;
      expect(
        restored.startedAt.toUtc().microsecondsSinceEpoch,
        startedAt.microsecondsSinceEpoch,
        reason: "l'instant absolu doit être identique au bit près",
      );
    },
  );

  group('inspect', () {
    test('renvoie un aperçu fidèle', () async {
      await seed();
      final preview = backup.inspect(await backup.buildPayloadBytes());

      expect(preview.employeeCount, 2);
      expect(preview.sessionCount, 2);
      expect(preview.breakCount, 1);
      expect(preview.schemaVersion, db.schemaVersion);
      expect(preview.appVersion, isNotEmpty);
    });

    test('rejette un fichier dont les données ont été altérées', () async {
      await seed();
      final bytes = await backup.buildPayloadBytes();
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

      // On trafique une heure de fin sans recalculer le checksum : exactement
      // ce que produirait une édition manuelle du JSON pour gonfler la paie.
      final data = payload['data'] as Map<String, dynamic>;
      (data['sessions'] as List).first['endedAt'] = DateTime.utc(
        2026,
        5,
        12,
        23,
      ).toIso8601String();
      final tampered = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

      expect(() => backup.inspect(tampered), throwsFormatException);
      expect(() => backup.restore(tampered), throwsFormatException);
    });

    test('rejette un JSON étranger', () {
      final foreign = Uint8List.fromList(
        utf8.encode(jsonEncode({'app': 'autre-chose', 'data': {}})),
      );
      expect(() => backup.inspect(foreign), throwsFormatException);
    });
  });

  test('une restauration invalide laisse la base intacte', () async {
    await seed();
    final before = await _snapshot(db);

    // Session référençant un salarié inexistant : les FK doivent faire échouer
    // la transaction, et donc tout annuler.
    final payload =
        jsonDecode(utf8.decode(await backup.buildPayloadBytes()))
            as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    (data['sessions'] as List).first['employeeId'] = 9999;
    // Checksum recalculé : le fichier est « valide » au sens du format, c'est
    // son contenu qui est incohérent.
    payload['checksum'] =
        'sha256:${sha256.convert(utf8.encode(jsonEncode(data)))}';
    final broken = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

    await expectLater(backup.restore(broken), throwsA(anything));
    expect(await _snapshot(db), before);
  });
}

/// Représentation stable de toute la base, pour comparer deux états.
Future<Map<String, List<Map<String, Object?>>>> _snapshot(
  AppDatabase db,
) async {
  Map<String, Object?> row(Insertable<dynamic> r) =>
      r.toColumns(false).map((k, v) => MapEntry(k, v.toString()));

  return {
    'employees': (await db.select(db.employees).get()).map(row).toList(),
    'sessions': (await db.select(db.workSessions).get()).map(row).toList(),
    'breaks': (await db.select(db.breaks).get()).map(row).toList(),
    'settings': (await db.select(db.appSettings).get()).map(row).toList(),
  };
}
