import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/repositories/employee_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/settings_repository.dart';

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

final clockStateProvider =
    StreamProvider.family<EmployeeClockState, int>((ref, employeeId) {
  return ref
      .watch(sessionRepositoryProvider)
      .watchClockState(employeeId);
});

final hasAdminPinProvider = FutureProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).hasPin();
});

final employeeByIdProvider =
    FutureProvider.family<Employee, int>((ref, id) {
  return ref.watch(employeeRepositoryProvider).getById(id);
});

final tickerProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
    yield DateTime.now();
  }
});
