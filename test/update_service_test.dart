import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:klok/services/update_service.dart';

/// La comparaison de versions décide si le patron voit ou non une alerte de
/// mise à jour. Une erreur ici lui ferait rater une correction, ou l'enverrait
/// réinstaller une version qu'il a déjà.
void main() {
  group('compareVersions', () {
    test('ordonne numériquement, pas alphabétiquement', () {
      // Le piège classique : en comparaison de chaînes, "2026.0.9" passerait
      // pour plus récent que "2026.0.10".
      expect(compareVersions('2026.0.10', '2026.0.9'), greaterThan(0));
      expect(compareVersions('2026.0.9', '2026.0.10'), lessThan(0));
    });

    test('deux versions identiques sont équivalentes', () {
      expect(compareVersions('2026.0.10', '2026.0.10'), 0);
    });

    test('le suffixe de build est ignoré', () {
      expect(compareVersions('2026.0.10+7', '2026.0.10+2'), 0);
    });

    test('les segments manquants valent zéro', () {
      expect(compareVersions('2026.1', '2026.1.0'), 0);
      expect(compareVersions('2026.1.1', '2026.1'), greaterThan(0));
    });

    test('un segment illisible vaut zéro plutôt que de planter', () {
      // Manifeste malformé côté serveur : on dégrade sans lever, quitte à ne
      // pas proposer la mise à jour. Ne rien proposer est moins grave que
      // faire planter les Réglages du patron.
      expect(compareVersions('2026.x.1', '2026.0.1'), 0);
      expect(compareVersions('nawak', '0.0.0'), 0);
    });
  });

  group('check', () {
    late HttpServer server;
    late String url;

    /// Sert un corps fixe sur 127.0.0.1 — on teste le vrai chemin réseau
    /// plutôt qu'un client simulé.
    Future<void> serve(int status, String body) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      url = 'http://127.0.0.1:${server.port}/updates.json';
      server.listen((req) async {
        req.response.statusCode = status;
        req.response.write(body);
        await req.response.close();
      });
    }

    tearDown(() async => server.close(force: true));

    test('une version plus récente est signalée', () async {
      await serve(
        200,
        jsonEncode({
          'version': '2026.0.11',
          'url': 'https://example.invalid/klok.apk',
          'notes': 'Correction export PDF.',
        }),
      );

      final result = await UpdateService(
        manifestUrl: url,
      ).check(currentVersion: '2026.0.10+1');

      expect(result, isA<UpdateAvailable>());
      final available = result as UpdateAvailable;
      expect(available.version, '2026.0.11');
      expect(available.notes, 'Correction export PDF.');
    });

    test('une version identique ne déclenche rien', () async {
      await serve(
        200,
        jsonEncode({
          'version': '2026.0.10',
          'url': 'https://example.invalid/klok.apk',
        }),
      );

      final result = await UpdateService(
        manifestUrl: url,
      ).check(currentVersion: '2026.0.10+1');

      expect(result, isA<UpdateUpToDate>());
    });

    test('un manifeste plus ancien que l\'installé ne propose rien', () async {
      // Cas d'un retour arrière côté serveur : on ne propose jamais de
      // « descendre » de version.
      await serve(
        200,
        jsonEncode({
          'version': '2026.0.9',
          'url': 'https://example.invalid/klok.apk',
        }),
      );

      final result = await UpdateService(
        manifestUrl: url,
      ).check(currentVersion: '2026.0.10+1');

      expect(result, isA<UpdateUpToDate>());
    });

    test('un manifeste incomplet est rejeté', () async {
      await serve(200, jsonEncode({'version': '2026.0.11'})); // pas d'url

      final result = await UpdateService(
        manifestUrl: url,
      ).check(currentVersion: '2026.0.10');

      expect(result, isA<UpdateCheckFailed>());
    });

    test('une réponse non-JSON est rejetée proprement', () async {
      await serve(200, '<html>oops</html>');

      final result = await UpdateService(
        manifestUrl: url,
      ).check(currentVersion: '2026.0.10');

      expect(result, isA<UpdateCheckFailed>());
    });

    test('une erreur serveur est rapportée sans planter', () async {
      await serve(503, 'indisponible');

      final result = await UpdateService(
        manifestUrl: url,
      ).check(currentVersion: '2026.0.10');

      expect(result, isA<UpdateCheckFailed>());
    });

    test('une tablette hors réseau obtient un échec explicite', () async {
      await serve(200, '{}');
      final dead = url;
      await server.close(force: true);
      // Le serveur est fermé : le port ne répond plus, comme sans connexion.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      final result = await UpdateService(
        manifestUrl: dead,
      ).check(currentVersion: '2026.0.10');

      expect(result, isA<UpdateCheckFailed>());
      expect((result as UpdateCheckFailed).reason, isNotEmpty);
    });
  });
}
