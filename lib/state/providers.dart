import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backup_reminder.dart';
import '../data/db/app_database.dart';
import '../data/repositories/employee_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../services/backup_service.dart';
import '../services/payroll_pdf_service.dart';

export '../core/backup_reminder.dart'
    show BackupReminderFreq, BackupReminderStatus;
export '../data/repositories/session_repository.dart'
    show EmployeeClockState, SessionRepository;

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final employeeRepositoryProvider = Provider<EmployeeRepository>((ref) {
  return EmployeeRepository(ref.watch(databaseProvider));
});

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(ref.watch(databaseProvider));
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(databaseProvider));
});

final activeEmployeesProvider = StreamProvider<List<Employee>>((ref) {
  return ref.watch(employeeRepositoryProvider).watchActive();
});

final allEmployeesProvider = StreamProvider<List<Employee>>((ref) {
  return ref.watch(employeeRepositoryProvider).watchAll();
});

final clockStateProvider = StreamProvider.family<EmployeeClockState, int>((
  ref,
  employeeId,
) {
  return ref.watch(sessionRepositoryProvider).watchClockState(employeeId);
});

final hasAdminPinProvider = FutureProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).hasPin();
});

/// Nom de l'établissement (ex. "Le Comptoir d'Alphonse") — alimente le header
/// admin et l'écran d'accueil. Stream (pas Future) car le patron peut le
/// modifier dans les réglages et on veut que ça se propage tout de suite.
final barNameProvider = StreamProvider<String?>((ref) {
  return ref.watch(settingsRepositoryProvider).watch(SettingsKeys.barName);
});

/// Nom du patron (ex. "Alphonse Martin") — signe les exports PDF.
///
/// Lit en priorité les nouveaux champs séparés `ownerFirstName` /
/// `ownerLastName` (introduits avec l'onboarding étendu). Retombe sur la clé
/// legacy `owner.name` si une installation antérieure n'a pas encore les
/// champs séparés (un patron qui upgrade depuis la v1 ne perd pas son nom).
final ownerNameProvider = StreamProvider<String?>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return repo.watch(SettingsKeys.ownerFirstName).asyncMap((first) async {
    final last = await repo.get(SettingsKeys.ownerLastName);
    final fullName = [
      first ?? '',
      last ?? '',
    ].where((s) => s.isNotEmpty).join(' ').trim();
    if (fullName.isNotEmpty) return fullName;
    // Fallback legacy.
    return repo.get(SettingsKeys.ownerLegacyName);
  });
});

/// Service de sauvegarde — partage la même instance de DB que le reste de
/// l'app, c'est important : sinon un restore via une 2e DB n'aurait aucun
/// effet visible.
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(databaseProvider));
});

/// Service de génération PDF paie — un PDF par salarié sur une période.
final payrollPdfServiceProvider = Provider<PayrollPdfService>((ref) {
  return PayrollPdfService(ref.watch(sessionRepositoryProvider));
});

/// Date de la dernière sauvegarde (ISO8601), si une a été effectuée.
final lastBackupAtProvider = StreamProvider<String?>((ref) {
  return ref.watch(settingsRepositoryProvider).watch(SettingsKeys.lastBackupAt);
});

/// Chemin absolu du logo importé par le patron — null si non défini.
final logoPathProvider = StreamProvider<String?>((ref) {
  return ref.watch(settingsRepositoryProvider).watch(SettingsKeys.logoPath);
});

/// Fréquence du rappel de sauvegarde : 'none' / 'weekly' / 'monthly'.
/// On garde la valeur brute (String) ; les widgets l'interprètent via
/// `BackupReminderFreq.parse`.
final backupReminderFreqProvider = StreamProvider<String?>((ref) {
  return ref
      .watch(settingsRepositoryProvider)
      .watch(SettingsKeys.backupReminderFreq);
});

/// Fréquence du rappel, déjà interprétée.
final backupReminderProvider = Provider<BackupReminderFreq>((ref) {
  return BackupReminderFreq.parse(
    ref.watch(backupReminderFreqProvider).asData?.value,
  );
});

/// Faut-il alerter le patron sur une sauvegarde en retard ?
///
/// Croise la fréquence choisie et la date de dernière sauvegarde. Réévalué à
/// chaque tick d'horloge pour que le bandeau apparaisse sans relancer l'app.
final backupReminderStatusProvider = Provider<BackupReminderStatus>((ref) {
  final now = ref.watch(tickerProvider).asData?.value;
  return backupReminderStatus(
    lastBackupAtIso: ref.watch(lastBackupAtProvider).asData?.value,
    freq: ref.watch(backupReminderProvider),
    now: now,
  );
});

/// Date du dernier "check" de mise à jour manuel par le patron (ISO8601).
final lastUpdateCheckAtProvider = StreamProvider<String?>((ref) {
  return ref
      .watch(settingsRepositoryProvider)
      .watch(SettingsKeys.lastUpdateCheckAt);
});

final employeeByIdProvider = FutureProvider.family<Employee, int>((ref, id) {
  return ref.watch(employeeRepositoryProvider).getById(id);
});

final tickerProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
    yield DateTime.now();
  }
});

// ─────────────────────────────────────────────────────────────
// Agrégats "équipe entière" — utilisés par l'écran d'accueil pour :
//   • allumer le point vert/ambre sur la pastille de chaque salarié actif,
//   • afficher le bandeau bas "X en service · Y en pause".
// On ouvre 2 streams DB (sessions ouvertes, pauses ouvertes) plutôt qu'un
// clockStateProvider par salarié : 2 souscriptions au lieu de N.
// ─────────────────────────────────────────────────────────────

final openSessionsProvider = StreamProvider<List<WorkSession>>((ref) {
  return ref.watch(sessionRepositoryProvider).watchOpenSessions();
});

final openBreaksProvider = StreamProvider<List<Break>>((ref) {
  return ref.watch(sessionRepositoryProvider).watchOpenBreaks();
});

enum EmployeeStatusKind { off, working, onBreak }

class EmployeeStatus {
  const EmployeeStatus({required this.kind, this.since});

  final EmployeeStatusKind kind;
  // Instant (UTC) de début du "truc en cours" :
  //   • working → startedAt de la session ouverte
  //   • onBreak → startedAt de la pause ouverte
  //   • off     → null
  final DateTime? since;

  bool get isActive =>
      kind == EmployeeStatusKind.working || kind == EmployeeStatusKind.onBreak;
}

class TeamStatus {
  const TeamStatus({
    required this.byEmployee,
    required this.workingCount,
    required this.breakCount,
    required this.workingFirstNames,
    required this.breakFirstNames,
  });

  final Map<int, EmployeeStatus> byEmployee;
  final int workingCount;
  final int breakCount;
  // Prénoms pour le bandeau bas ("Thomas en pause").
  final List<String> workingFirstNames;
  final List<String> breakFirstNames;

  EmployeeStatus statusOf(int employeeId) =>
      byEmployee[employeeId] ??
      const EmployeeStatus(kind: EmployeeStatusKind.off);
}

final teamStatusProvider = Provider<TeamStatus>((ref) {
  final sessions = ref.watch(openSessionsProvider).asData?.value ?? const [];
  final breaks = ref.watch(openBreaksProvider).asData?.value ?? const [];
  final employees =
      ref.watch(activeEmployeesProvider).asData?.value ?? const [];

  // sessionId → pause ouverte (s'il y en a une)
  final breakBySession = <int, Break>{for (final b in breaks) b.sessionId: b};
  final firstNameById = <int, String>{
    for (final e in employees) e.id: e.firstName,
  };

  final byEmployee = <int, EmployeeStatus>{};
  final workingNames = <String>[];
  final breakNames = <String>[];

  for (final s in sessions) {
    final openBreak = breakBySession[s.id];
    if (openBreak != null) {
      byEmployee[s.employeeId] = EmployeeStatus(
        kind: EmployeeStatusKind.onBreak,
        since: openBreak.startedAt,
      );
      final name = firstNameById[s.employeeId];
      if (name != null) breakNames.add(name);
    } else {
      byEmployee[s.employeeId] = EmployeeStatus(
        kind: EmployeeStatusKind.working,
        since: s.startedAt,
      );
      final name = firstNameById[s.employeeId];
      if (name != null) workingNames.add(name);
    }
  }

  return TeamStatus(
    byEmployee: byEmployee,
    workingCount: workingNames.length,
    breakCount: breakNames.length,
    workingFirstNames: workingNames,
    breakFirstNames: breakNames,
  );
});
