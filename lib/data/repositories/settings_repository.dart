import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../db/app_database.dart';

class SettingsKeys {
  static const pinHash = 'admin.pin_hash';
  static const pinSalt = 'admin.pin_salt';
  static const barName = 'bar.name';
  static const lastBackupAt = 'backup.last_at';
}

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Stream<String?> watch(String key) {
    return (_db.select(_db.appSettings)..where((s) => s.key.equals(key)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }

  Future<void> set(String key, String value) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<void> delete(String key) async {
    await (_db.delete(_db.appSettings)..where((s) => s.key.equals(key))).go();
  }

  Future<bool> hasPin() async {
    final hash = await get(SettingsKeys.pinHash);
    return hash != null && hash.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    final salt = _randomSalt();
    final hash = _hash(pin, salt);
    await set(SettingsKeys.pinSalt, salt);
    await set(SettingsKeys.pinHash, hash);
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await get(SettingsKeys.pinSalt);
    final expected = await get(SettingsKeys.pinHash);
    if (salt == null || expected == null) return false;
    return _hash(pin, salt) == expected;
  }

  String _hash(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  String _randomSalt() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rnd = now.toRadixString(16);
    return sha256.convert(utf8.encode(rnd)).toString().substring(0, 16);
  }
}
