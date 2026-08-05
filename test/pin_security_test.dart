import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klok/data/db/app_database.dart';
import 'package:klok/data/repositories/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('dérivation', () {
    test('un PIN correct déverrouille, un mauvais non', () async {
      await settings.setPin('4271');
      expect(await settings.verifyPin('4271'), isTrue);
      expect(await settings.verifyPin('4270'), isFalse);
    });

    test('le PIN en clair n\'apparaît nulle part en base', () async {
      await settings.setPin('4271');
      final rows = await db.select(db.appSettings).get();
      for (final row in rows) {
        expect(row.value, isNot(contains('4271')));
      }
    });

    test(
      'deux installations avec le même PIN ont des empreintes différentes',
      () async {
        await settings.setPin('4271');
        final saltA = await settings.get(SettingsKeys.pinSalt);
        final hashA = await settings.get(SettingsKeys.pinHash);

        final otherDb = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(otherDb.close);
        final other = SettingsRepository(otherDb);
        await other.setPin('4271');
        final saltB = await other.get(SettingsKeys.pinSalt);
        final hashB = await other.get(SettingsKeys.pinHash);

        // Sel aléatoire : une table précalculée pour une tablette est inutile
        // sur une autre.
        expect(saltA, isNot(saltB));
        expect(hashA, isNot(hashB));
      },
    );

    test('changer de PIN invalide l\'ancien', () async {
      await settings.setPin('1111');
      await settings.setPin('2222');
      expect(await settings.verifyPin('1111'), isFalse);
      expect(await settings.verifyPin('2222'), isTrue);
    });
  });

  group('migration depuis l\'ancien schéma sha256', () {
    /// Reproduit exactement ce qu'écrivait la version précédente de l'app.
    Future<void> seedLegacyPin(String pin) async {
      const salt = 'a1b2c3d4e5f60718';
      final hash = sha256.convert(utf8.encode('$salt:$pin')).toString();
      await settings.set(SettingsKeys.pinSalt, salt);
      await settings.set(SettingsKeys.pinHash, hash);
      // Pas de clé `pinAlgo` : c'est le marqueur de l'ancien format.
    }

    test('un PIN créé par l\'ancienne version fonctionne toujours', () async {
      await seedLegacyPin('4271');
      expect(await settings.verifyPin('4271'), isTrue);
    });

    test('un mauvais PIN reste refusé sur l\'ancien schéma', () async {
      await seedLegacyPin('4271');
      expect(await settings.verifyPin('9999'), isFalse);
    });

    test('le premier déverrouillage réussi migre vers PBKDF2', () async {
      await seedLegacyPin('4271');
      expect(await settings.get(SettingsKeys.pinAlgo), isNull);

      await settings.verifyPin('4271');

      expect(await settings.get(SettingsKeys.pinAlgo), PinAlgo.pbkdf2);
      // Et le PIN marche toujours après migration.
      expect(await settings.verifyPin('4271'), isTrue);
    });
  });

  group('temporisation anti-force-brute', () {
    test('les premiers essais ne bloquent pas', () async {
      await settings.setPin('4271');
      for (var i = 0; i < kPinFreeAttempts; i++) {
        expect(await settings.verifyPin('0000'), isFalse);
      }
      expect(await settings.remainingLockout(), Duration.zero);
      expect(
        await settings.verifyPin('4271'),
        isTrue,
        reason: 'le patron qui se trompe deux fois ne doit pas être puni',
      );
    });

    test('au-delà du quota, une temporisation démarre', () async {
      await settings.setPin('4271');
      for (var i = 0; i < kPinFreeAttempts + 1; i++) {
        await settings.verifyPin('0000');
      }
      expect(await settings.remainingLockout(), greaterThan(Duration.zero));
    });

    test('pendant la temporisation, même le bon PIN est refusé', () async {
      await settings.setPin('4271');
      for (var i = 0; i < kPinFreeAttempts + 1; i++) {
        await settings.verifyPin('0000');
      }
      expect(
        await settings.verifyPin('4271'),
        isFalse,
        reason: 'sinon la temporisation ne ralentit rien',
      );
    });

    test('un échec pendant la temporisation ne l\'allonge pas', () async {
      await settings.setPin('4271');
      for (var i = 0; i < kPinFreeAttempts + 1; i++) {
        await settings.verifyPin('0000');
      }
      final count = await settings.get(SettingsKeys.pinFailCount);

      await settings.verifyPin('0000');

      expect(
        await settings.get(SettingsKeys.pinFailCount),
        count,
        reason: 'un essai rejeté d\'office ne doit pas compter double',
      );
    });

    test(
      'la temporisation double à chaque salve, mais reste plafonnée',
      () async {
        await settings.setPin('4271');

        /// Fait « passer le temps » sans attendre : on recule la date du dernier
        /// échec pour purger la temporisation en cours.
        Future<void> letLockoutExpire() => settings.set(
          SettingsKeys.pinLastFailAt,
          DateTime.now().toUtc().subtract(kPinMaxLockout * 2).toIso8601String(),
        );

        for (var i = 0; i < kPinFreeAttempts + 1; i++) {
          await settings.verifyPin('0000');
        }
        final first = await settings.remainingLockout();
        expect(first, greaterThan(Duration.zero));

        await letLockoutExpire();
        await settings.verifyPin('0000');
        final second = await settings.remainingLockout();

        expect(second, greaterThan(first), reason: 'le délai doit doubler');

        // Beaucoup d'échecs plus tard : le délai est borné.
        for (var i = 0; i < 20; i++) {
          await letLockoutExpire();
          await settings.verifyPin('0000');
        }
        expect(
          await settings.remainingLockout(),
          lessThanOrEqualTo(kPinMaxLockout),
        );
      },
    );

    test('un déverrouillage réussi remet le compteur à zéro', () async {
      await settings.setPin('4271');
      for (var i = 0; i < kPinFreeAttempts; i++) {
        await settings.verifyPin('0000');
      }
      expect(await settings.verifyPin('4271'), isTrue);

      expect(await settings.get(SettingsKeys.pinFailCount), isNull);
      expect(await settings.remainingLockout(), Duration.zero);
    });

    test('une horloge reculée ne contourne pas la temporisation', () async {
      await settings.setPin('4271');
      for (var i = 0; i < kPinFreeAttempts + 1; i++) {
        await settings.verifyPin('0000');
      }
      // Simule un recul de l'horloge système : le dernier échec est « dans le
      // futur ». Sans garde, `elapsed` négatif rendrait le verrou permanent.
      await settings.set(
        SettingsKeys.pinLastFailAt,
        DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String(),
      );
      expect(
        await settings.remainingLockout(),
        lessThanOrEqualTo(kPinMaxLockout),
      );
    });
  });
}
