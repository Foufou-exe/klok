import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../db/app_database.dart';

class SettingsKeys {
  static const pinHash = 'admin.pin_hash';
  static const pinSalt = 'admin.pin_salt';
  // Algorithme utilisé pour `pinHash`. Absent = ancien schéma sha256 simple,
  // migré au premier déverrouillage réussi. Voir `verifyPin`.
  static const pinAlgo = 'admin.pin_algo';
  // Temporisation anti-force-brute : nombre d'échecs consécutifs et date du
  // dernier. Persistés en base pour qu'un redémarrage de l'app ne remette pas
  // le compteur à zéro.
  static const pinFailCount = 'admin.pin_fail_count';
  static const pinLastFailAt = 'admin.pin_last_fail_at';
  static const barName = 'bar.name';
  static const barLocation = 'bar.location';
  static const ownerFirstName = 'owner.first_name';
  static const ownerLastName = 'owner.last_name';
  // Conservé pour compat avec les installations antérieures qui stockaient
  // un seul champ "owner.name". On le lit en lecture si first/last sont vides.
  static const ownerLegacyName = 'owner.name';
  static const lastBackupAt = 'backup.last_at';
  // Logo importé : on stocke le chemin absolu dans le dossier app docs (le
  // fichier est copié là pour survivre aux nettoyages du temp).
  static const logoPath = 'bar.logo_path';
  // Fréquence du rappel de sauvegarde — valeurs : 'none', 'weekly', 'monthly'.
  // Default 'weekly' à l'initialisation. Sert à afficher un bandeau quand la
  // dernière sauvegarde dépasse l'intervalle.
  static const backupReminderFreq = 'backup.reminder_freq';
  // Date du dernier check de mises à jour (ISO8601).
  static const lastUpdateCheckAt = 'updates.last_check_at';
}

/// Identifiants d'algorithme de dérivation du PIN.
class PinAlgo {
  /// Schéma d'origine : `sha256(salt:pin)`, sel dérivé de l'horloge.
  static const legacySha256 = 'sha256';

  /// PBKDF2-HMAC-SHA256, sel 128 bits issu de `Random.secure()`.
  static const pbkdf2 = 'pbkdf2-sha256';
}

/// Itérations PBKDF2. Compromis : assez pour rendre un balayage hors-ligne
/// pénible, assez peu pour que le keypad reste instantané sur une tablette
/// d'entrée de gamme.
const int kPinPbkdf2Iterations = 100000;

/// Nombre d'échecs tolérés avant que la temporisation ne démarre.
const int kPinFreeAttempts = 3;

/// Plafond de la temporisation — au-delà, le patron qui a un doute sur son
/// propre PIN serait puni autant qu'un intrus.
const Duration kPinMaxLockout = Duration(minutes: 2);

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
    final salt = _secureSalt();
    await set(SettingsKeys.pinSalt, salt);
    await set(SettingsKeys.pinHash, _pbkdf2Hash(pin, salt));
    await set(SettingsKeys.pinAlgo, PinAlgo.pbkdf2);
    await resetFailures();
  }

  /// Vérifie le PIN et gère la temporisation anti-force-brute.
  ///
  /// Le PIN fait 8 chiffres (`kAdminPinLength`), soit 10^8 combinaisons :
  /// combiné aux itérations PBKDF2, un balayage hors-ligne sur une copie du
  /// fichier SQLite devient réellement coûteux. Le sel aléatoire empêche en
  /// plus de mutualiser un précalcul entre installations, et la temporisation
  /// couvre l'autre scénario — un salarié qui tente sa chance au clavier.
  Future<bool> verifyPin(String pin) async {
    if (await remainingLockout() > Duration.zero) return false;

    final salt = await get(SettingsKeys.pinSalt);
    final expected = await get(SettingsKeys.pinHash);
    if (salt == null || expected == null) return false;

    final algo = await get(SettingsKeys.pinAlgo) ?? PinAlgo.legacySha256;
    final ok = algo == PinAlgo.pbkdf2
        ? _constantTimeEquals(_pbkdf2Hash(pin, salt), expected)
        : _constantTimeEquals(_legacyHash(pin, salt), expected);

    if (!ok) {
      await _recordFailure();
      return false;
    }

    // Migration transparente : le PIN saisi est bon, on en profite pour le
    // ré-encoder avec le schéma courant. Le patron ne voit rien.
    if (algo != PinAlgo.pbkdf2) {
      await setPin(pin);
    } else {
      await resetFailures();
    }
    return true;
  }

  /// Temps restant avant de pouvoir retenter une saisie. `Duration.zero` si
  /// aucune temporisation n'est active.
  Future<Duration> remainingLockout() async {
    final fails = int.tryParse(await get(SettingsKeys.pinFailCount) ?? '') ?? 0;
    if (fails <= kPinFreeAttempts) return Duration.zero;

    final lastRaw = await get(SettingsKeys.pinLastFailAt);
    final last = lastRaw == null ? null : DateTime.tryParse(lastRaw);
    if (last == null) return Duration.zero;

    final elapsed = DateTime.now().toUtc().difference(last.toUtc());
    // Horloge reculée : un `elapsed` négatif gonflerait la punition bien
    // au-delà du plafond. On borne des deux côtés.
    if (elapsed.isNegative) return kPinMaxLockout;

    final left = _lockoutFor(fails) - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// Doublement du délai à chaque échec au-delà du quota gratuit :
  /// 2 s, 4 s, 8 s… plafonné à [kPinMaxLockout].
  Duration _lockoutFor(int fails) {
    final over = (fails - kPinFreeAttempts).clamp(1, 20);
    final seconds = 1 << over;
    final d = Duration(seconds: seconds);
    return d > kPinMaxLockout ? kPinMaxLockout : d;
  }

  Future<void> _recordFailure() async {
    final fails = int.tryParse(await get(SettingsKeys.pinFailCount) ?? '') ?? 0;
    await set(SettingsKeys.pinFailCount, '${fails + 1}');
    await set(
      SettingsKeys.pinLastFailAt,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> resetFailures() async {
    await delete(SettingsKeys.pinFailCount);
    await delete(SettingsKeys.pinLastFailAt);
  }

  // ── Dérivation ────────────────────────────────────────────────

  String _legacyHash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  String _pbkdf2Hash(String pin, String salt) {
    final key = _pbkdf2(
      password: utf8.encode(pin),
      salt: utf8.encode(salt),
      iterations: kPinPbkdf2Iterations,
      length: 32,
    );
    return base64Encode(key);
  }

  /// Sel 128 bits issu du générateur cryptographique de la plateforme.
  ///
  /// L'implémentation précédente dérivait le sel de `DateTime.now()`, donc
  /// devinable : qui connaît l'heure d'installation reconstruit le sel.
  String _secureSalt() {
    final rnd = Random.secure();
    return base64Encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018). Implémenté ici plutôt que via une
  /// dépendance : une vingtaine de lignes contre un paquet de plus à auditer
  /// sur une app qui doit rester hors-ligne et vivre des années.
  List<int> _pbkdf2({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int length,
  }) {
    final hmac = Hmac(sha256, password);
    final out = <int>[];

    for (var block = 1; out.length < length; block++) {
      final blockIndex = Uint8List(4)
        ..buffer.asByteData().setUint32(0, block, Endian.big);
      var u = hmac.convert([...salt, ...blockIndex]).bytes;
      final acc = List<int>.of(u);

      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < acc.length; j++) {
          acc[j] ^= u[j];
        }
      }
      out.addAll(acc);
    }
    return out.sublist(0, length);
  }

  /// Comparaison à temps constant : ne court-circuite pas au premier octet
  /// différent, pour ne rien laisser fuir par le temps de réponse.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
