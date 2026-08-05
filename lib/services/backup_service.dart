import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/version.dart';
import '../data/db/app_database.dart';

class BackupResult {
  BackupResult({required this.filePath, required this.bytes});
  final String filePath;
  final Uint8List bytes;
}

class RestorePreview {
  RestorePreview({
    required this.exportedAt,
    required this.appVersion,
    required this.schemaVersion,
    required this.employeeCount,
    required this.sessionCount,
    required this.breakCount,
    required this.settingCount,
  });

  final DateTime exportedAt;
  final String appVersion;
  final int schemaVersion;
  final int employeeCount;
  final int sessionCount;
  final int breakCount;
  final int settingCount;
}

class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  /// Sérialise toute la base en bytes JSON, sans toucher au disque.
  ///
  /// Séparé de [exportAll] pour être testable : `getTemporaryDirectory()` passe
  /// par un canal de plateforme indisponible sous `flutter test`.
  Future<Uint8List> buildPayloadBytes() async {
    final employees = await _db.select(_db.employees).get();
    final sessions = await _db.select(_db.workSessions).get();
    final breaks = await _db.select(_db.breaks).get();
    final settings = await _db.select(_db.appSettings).get();

    final data = <String, dynamic>{
      'employees': employees.map(_employeeToJson).toList(),
      'sessions': sessions.map(_sessionToJson).toList(),
      'breaks': breaks.map(_breakToJson).toList(),
      'settings': settings
          .map((s) => {'key': s.key, 'value': s.value})
          .toList(),
    };

    final dataJson = jsonEncode(data);
    final checksum = sha256.convert(utf8.encode(dataJson)).toString();

    final payload = <String, dynamic>{
      'app': 'klok',
      'appVersion': kAppVersion,
      'schemaVersion': _db.schemaVersion,
      'formatVersion': kBackupFormatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'checksum': 'sha256:$checksum',
      'data': data,
    };

    return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  }

  Future<BackupResult> exportAll() async {
    final bytes = await buildPayloadBytes();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File(p.join(dir.path, 'klok_backup_$stamp.json'));
    await file.writeAsBytes(bytes);
    return BackupResult(filePath: file.path, bytes: bytes);
  }

  Future<void> share(BackupResult r) async {
    // share_plus 12.x : `Share.shareXFiles` est deprecated au profit de
    // `SharePlus.instance.share(ShareParams(...))`.
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(r.filePath, mimeType: 'application/json')],
        subject: 'Sauvegarde klok',
      ),
    );
  }

  RestorePreview inspect(Uint8List bytes) {
    final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final checksumField = payload['checksum'] as String?;
    final data = payload['data'] as Map<String, dynamic>?;
    if (data == null || checksumField == null) {
      throw const FormatException('Fichier de sauvegarde invalide.');
    }
    final expected = checksumField.split(':').last;
    final got = sha256.convert(utf8.encode(jsonEncode(data))).toString();
    if (expected != got) {
      throw const FormatException(
        'Le fichier est corrompu (checksum invalide).',
      );
    }
    if (payload['app'] != 'klok') {
      throw const FormatException('Ce fichier n\'est pas une sauvegarde klok.');
    }
    return RestorePreview(
      exportedAt: DateTime.parse(payload['exportedAt'] as String),
      appVersion: (payload['appVersion'] as String?) ?? '?',
      schemaVersion: (payload['schemaVersion'] as num?)?.toInt() ?? 0,
      employeeCount: (data['employees'] as List).length,
      sessionCount: (data['sessions'] as List).length,
      breakCount: (data['breaks'] as List).length,
      settingCount: (data['settings'] as List).length,
    );
  }

  Future<void> restore(Uint8List bytes) async {
    final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final checksumField = payload['checksum'] as String?;
    final data = payload['data'] as Map<String, dynamic>?;
    if (data == null || checksumField == null) {
      throw const FormatException('Sauvegarde invalide.');
    }
    final expected = checksumField.split(':').last;
    final got = sha256.convert(utf8.encode(jsonEncode(data))).toString();
    if (expected != got) {
      throw const FormatException('Sauvegarde corrompue.');
    }

    // Remplacement total. On garde les contraintes FK actives : SQLite ignore
    // silencieusement `PRAGMA foreign_keys` à l'intérieur d'une transaction
    // (c'est un no-op documenté), donc les désactiver ici serait une illusion.
    // L'intégrité tient à l'ordre des opérations — suppression des feuilles
    // vers la racine, réinsertion de la racine vers les feuilles — et les FK
    // servent alors de filet : un backup incohérent échoue et la transaction
    // est annulée, plutôt que d'importer des sessions orphelines.
    await _db.transaction(() async {
      await _db.delete(_db.breaks).go();
      await _db.delete(_db.workSessions).go();
      await _db.delete(_db.employees).go();
      await _db.delete(_db.appSettings).go();

      for (final e in data['employees'] as List) {
        final m = e as Map<String, dynamic>;
        await _db
            .into(_db.employees)
            .insert(
              EmployeesCompanion(
                id: Value(m['id'] as int),
                firstName: Value(m['firstName'] as String),
                lastName: Value(m['lastName'] as String),
                color: Value(m['color'] as String),
                hourlyRateCents: Value(m['hourlyRateCents'] as int?),
                archived: Value(m['archived'] as bool),
                createdAt: Value(DateTime.parse(m['createdAt'] as String)),
              ),
            );
      }
      for (final s in data['sessions'] as List) {
        final m = s as Map<String, dynamic>;
        await _db
            .into(_db.workSessions)
            .insert(
              WorkSessionsCompanion(
                id: Value(m['id'] as int),
                employeeId: Value(m['employeeId'] as int),
                startedAt: Value(DateTime.parse(m['startedAt'] as String)),
                endedAt: Value(
                  m['endedAt'] != null
                      ? DateTime.parse(m['endedAt'] as String)
                      : null,
                ),
                note: Value(m['note'] as String?),
              ),
            );
      }
      for (final b in data['breaks'] as List) {
        final m = b as Map<String, dynamic>;
        await _db
            .into(_db.breaks)
            .insert(
              BreaksCompanion(
                id: Value(m['id'] as int),
                sessionId: Value(m['sessionId'] as int),
                startedAt: Value(DateTime.parse(m['startedAt'] as String)),
                endedAt: Value(
                  m['endedAt'] != null
                      ? DateTime.parse(m['endedAt'] as String)
                      : null,
                ),
              ),
            );
      }
      for (final kv in data['settings'] as List) {
        final m = kv as Map<String, dynamic>;
        await _db
            .into(_db.appSettings)
            .insert(
              AppSettingsCompanion.insert(
                key: m['key'] as String,
                value: m['value'] as String,
              ),
            );
      }
    });
  }

  Map<String, dynamic> _employeeToJson(dynamic e) {
    return {
      'id': e.id,
      'firstName': e.firstName,
      'lastName': e.lastName,
      'color': e.color,
      'hourlyRateCents': e.hourlyRateCents,
      'archived': e.archived,
      'createdAt': (e.createdAt as DateTime).toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> _sessionToJson(dynamic s) {
    return {
      'id': s.id,
      'employeeId': s.employeeId,
      'startedAt': (s.startedAt as DateTime).toUtc().toIso8601String(),
      'endedAt': (s.endedAt as DateTime?)?.toUtc().toIso8601String(),
      'note': s.note,
    };
  }

  Map<String, dynamic> _breakToJson(dynamic b) {
    return {
      'id': b.id,
      'sessionId': b.sessionId,
      'startedAt': (b.startedAt as DateTime).toUtc().toIso8601String(),
      'endedAt': (b.endedAt as DateTime?)?.toUtc().toIso8601String(),
    };
  }
}
