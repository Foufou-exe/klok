import 'package:drift/drift.dart';

import '../db/app_database.dart';

class EmployeeRepository {
  EmployeeRepository(this._db);

  final AppDatabase _db;

  Stream<List<Employee>> watchActive() {
    return (_db.select(_db.employees)
          ..where((e) => e.archived.equals(false))
          ..orderBy([(e) => OrderingTerm(expression: e.firstName)]))
        .watch();
  }

  Stream<List<Employee>> watchAll() {
    return (_db.select(_db.employees)..orderBy([
          (e) => OrderingTerm(expression: e.archived),
          (e) => OrderingTerm(expression: e.firstName),
        ]))
        .watch();
  }

  Future<Employee> getById(int id) {
    return (_db.select(
      _db.employees,
    )..where((e) => e.id.equals(id))).getSingle();
  }

  Future<int> create({
    required String firstName,
    required String lastName,
    String color = '#3B82F6',
    int? hourlyRateCents,
  }) {
    return _db
        .into(_db.employees)
        .insert(
          EmployeesCompanion.insert(
            firstName: firstName,
            lastName: lastName,
            color: Value(color),
            hourlyRateCents: Value(hourlyRateCents),
          ),
        );
  }

  Future<void> update(Employee employee) async {
    await _db.update(_db.employees).replace(employee);
  }

  Future<void> archive(int id) async {
    await (_db.update(_db.employees)..where((e) => e.id.equals(id))).write(
      const EmployeesCompanion(archived: Value(true)),
    );
  }

  Future<void> unarchive(int id) async {
    await (_db.update(_db.employees)..where((e) => e.id.equals(id))).write(
      const EmployeesCompanion(archived: Value(false)),
    );
  }
}
