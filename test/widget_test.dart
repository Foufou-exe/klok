import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klok/data/db/app_database.dart';
import 'package:klok/data/repositories/employee_repository.dart';
import 'package:klok/data/repositories/session_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('employee CRUD works', () async {
    final repo = EmployeeRepository(db);
    final id = await repo.create(firstName: 'Alice', lastName: 'Dupont');
    expect(id, greaterThan(0));

    final list = await repo.watchActive().first;
    expect(list, hasLength(1));
    expect(list.first.firstName, 'Alice');

    await repo.archive(id);
    final active = await repo.watchActive().first;
    expect(active, isEmpty);
  });

  test('session lifecycle: start / break / end computes net time', () async {
    final empRepo = EmployeeRepository(db);
    final sessionRepo = SessionRepository(db);
    final id = await empRepo.create(firstName: 'Bob', lastName: 'Martin');

    final t0 = DateTime.utc(2026, 4, 19, 10);
    final t1 = DateTime.utc(2026, 4, 19, 12); // break start (+2h of work)
    final t2 = DateTime.utc(2026, 4, 19, 12, 30); // break end (30min break)
    final t3 = DateTime.utc(2026, 4, 19, 14); // end (+1h30 after break)

    final session = await sessionRepo.startSession(id, at: t0);
    final brk = await sessionRepo.startBreak(session.id, at: t1);
    await sessionRepo.endBreak(brk.id, at: t2);
    await sessionRepo.endSession(session.id, at: t3);

    final state = await sessionRepo.watchClockState(id).first;
    expect(state.isIdle, true);

    final sessions = await sessionRepo.sessionsInRange(id, t0, t3);
    final breaks =
        await sessionRepo.breaksForSessions(sessions.map((s) => s.id).toList());
    expect(sessions, hasLength(1));
    expect(breaks, hasLength(1));

    final gross = sessions.first.endedAt!.difference(sessions.first.startedAt);
    final pause = breaks.first.endedAt!.difference(breaks.first.startedAt);
    expect(gross, const Duration(hours: 4));
    expect(pause, const Duration(minutes: 30));
    expect(gross - pause, const Duration(hours: 3, minutes: 30));
  });

  test('cannot open two concurrent sessions for same employee', () async {
    final empRepo = EmployeeRepository(db);
    final sessionRepo = SessionRepository(db);
    final id = await empRepo.create(firstName: 'Charlie', lastName: 'Paul');

    await sessionRepo.startSession(id);
    expect(() => sessionRepo.startSession(id), throwsA(isA<StateError>()));
  });
}
