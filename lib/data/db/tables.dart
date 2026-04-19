import 'package:drift/drift.dart';

class Employees extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get firstName => text().withLength(min: 1, max: 80)();
  TextColumn get lastName => text().withLength(min: 1, max: 80)();
  TextColumn get color =>
      text().withLength(min: 7, max: 7).withDefault(const Constant('#3B82F6'))();
  IntColumn get hourlyRateCents => integer().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class WorkSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId =>
      integer().references(Employees, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get note => text().nullable()();
}

class Breaks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId =>
      integer().references(WorkSessions, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
