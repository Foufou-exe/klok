import 'dart:async';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

class EmployeeClockState {
  EmployeeClockState({this.openSession, this.openBreak});

  final WorkSession? openSession;
  final Break? openBreak;

  bool get isIdle => openSession == null;
  bool get isWorking => openSession != null && openBreak == null;
  bool get isOnBreak => openSession != null && openBreak != null;
}

class SessionRepository {
  SessionRepository(this._db);

  final AppDatabase _db;

  Stream<EmployeeClockState> watchClockState(int employeeId) {
    final controller = StreamController<EmployeeClockState>();
    WorkSession? currentSession;
    List<Break> openBreaks = const [];
    StreamSubscription<WorkSession?>? sessionSub;
    StreamSubscription<List<Break>>? breaksSub;

    void emit() {
      if (controller.isClosed) return;
      Break? openBreak;
      if (currentSession != null) {
        for (final b in openBreaks) {
          if (b.sessionId == currentSession!.id) {
            openBreak = b;
            break;
          }
        }
      }
      controller.add(
        EmployeeClockState(openSession: currentSession, openBreak: openBreak),
      );
    }

    controller.onListen = () {
      sessionSub =
          (_db.select(_db.workSessions)
                ..where(
                  (s) => s.employeeId.equals(employeeId) & s.endedAt.isNull(),
                )
                ..limit(1))
              .watchSingleOrNull()
              .listen((s) {
                currentSession = s;
                emit();
              });
      breaksSub = (_db.select(_db.breaks)..where((b) => b.endedAt.isNull()))
          .watch()
          .listen((list) {
            openBreaks = list;
            emit();
          });
    };

    controller.onCancel = () async {
      await sessionSub?.cancel();
      await breaksSub?.cancel();
    };

    return controller.stream;
  }

  Future<WorkSession> startSession(int employeeId, {DateTime? at}) async {
    final now = at ?? DateTime.now().toUtc();
    final existing =
        await (_db.select(_db.workSessions)..where(
              (s) => s.employeeId.equals(employeeId) & s.endedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing != null) {
      throw StateError('Une session est déjà ouverte pour cet employé.');
    }
    final id = await _db
        .into(_db.workSessions)
        .insert(
          WorkSessionsCompanion.insert(employeeId: employeeId, startedAt: now),
        );
    return (_db.select(
      _db.workSessions,
    )..where((s) => s.id.equals(id))).getSingle();
  }

  Future<void> endSession(int sessionId, {DateTime? at}) async {
    final now = at ?? DateTime.now().toUtc();
    await _db.transaction(() async {
      final openBreak =
          await (_db.select(_db.breaks)..where(
                (b) => b.sessionId.equals(sessionId) & b.endedAt.isNull(),
              ))
              .getSingleOrNull();
      if (openBreak != null) {
        await (_db.update(_db.breaks)..where((b) => b.id.equals(openBreak.id)))
            .write(BreaksCompanion(endedAt: Value(now)));
      }
      await (_db.update(_db.workSessions)..where((s) => s.id.equals(sessionId)))
          .write(WorkSessionsCompanion(endedAt: Value(now)));
    });
  }

  Future<Break> startBreak(int sessionId, {DateTime? at}) async {
    final now = at ?? DateTime.now().toUtc();
    final existing =
        await (_db.select(
              _db.breaks,
            )..where((b) => b.sessionId.equals(sessionId) & b.endedAt.isNull()))
            .getSingleOrNull();
    if (existing != null) {
      throw StateError('Une pause est déjà en cours.');
    }
    final id = await _db
        .into(_db.breaks)
        .insert(BreaksCompanion.insert(sessionId: sessionId, startedAt: now));
    return (_db.select(_db.breaks)..where((b) => b.id.equals(id))).getSingle();
  }

  Future<void> endBreak(int breakId, {DateTime? at}) async {
    final now = at ?? DateTime.now().toUtc();
    await (_db.update(_db.breaks)..where((b) => b.id.equals(breakId))).write(
      BreaksCompanion(endedAt: Value(now)),
    );
  }

  /// Stream de toutes les sessions encore ouvertes (tout salarié confondu).
  /// Utilisé par les vues d'accueil / dashboard patron pour afficher en direct
  /// qui est en poste sans multiplier les souscriptions DB.
  Stream<List<WorkSession>> watchOpenSessions() {
    return (_db.select(
      _db.workSessions,
    )..where((s) => s.endedAt.isNull())).watch();
  }

  /// Stream de toutes les pauses encore ouvertes (toutes sessions confondues).
  /// Croisé avec `watchOpenSessions` pour distinguer "en service" vs "en pause".
  Stream<List<Break>> watchOpenBreaks() {
    return (_db.select(_db.breaks)..where((b) => b.endedAt.isNull())).watch();
  }

  Future<List<WorkSession>> sessionsInRange(
    int employeeId,
    DateTime from,
    DateTime to,
  ) {
    return (_db.select(_db.workSessions)
          ..where(
            (s) =>
                s.employeeId.equals(employeeId) &
                s.startedAt.isBetweenValues(from, to),
          )
          ..orderBy([(s) => OrderingTerm(expression: s.startedAt)]))
        .get();
  }

  Future<List<Break>> breaksForSessions(List<int> sessionIds) {
    if (sessionIds.isEmpty) return Future.value(const []);
    return (_db.select(_db.breaks)
          ..where((b) => b.sessionId.isIn(sessionIds))
          ..orderBy([(b) => OrderingTerm(expression: b.startedAt)]))
        .get();
  }
}
