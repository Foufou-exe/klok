// Vérification de mise à jour — la seule requête réseau de Klok.
//
// Klok est une app hors-ligne : aucune donnée métier ne circule, jamais. Cette
// vérification est l'unique exception, et elle est encadrée :
//
//   • déclenchée uniquement par le patron, depuis les Réglages. Aucun appel au
//     démarrage, aucune tâche de fond, aucune reprise automatique ;
//   • un seul GET vers un fichier JSON statique. Rien n'est envoyé : ni
//     identifiant d'appareil, ni statistique, ni contenu de la base ;
//   • le téléchargement et l'installation restent manuels. L'app n'installe
//     rien toute seule ;
//   • un échec réseau est sans conséquence — l'app fonctionne intégralement
//     sans jamais faire cette requête.
//
// Le manifeste distant ressemble à ceci :
//
//   {
//     "version": "2026.0.11",
//     "url": "https://github.com/Foufou-exe/klok/releases/latest",
//     "notes": "Correction de l'export PDF sur les mois à cheval."
//   }

import 'dart:convert';
import 'dart:io';

import '../core/version.dart';

/// Emplacement du manifeste de versions.
///
/// Pointe sur le dépôt de distribution. À adapter si le canal change — c'est
/// la seule URL que Klok contacte.
const String kUpdateManifestUrl =
    'https://raw.githubusercontent.com/Foufou-exe/klok/main/updates.json';

/// Au-delà, on abandonne : la tablette est probablement hors réseau, et le
/// patron ne doit pas rester devant un écran figé.
const Duration kUpdateCheckTimeout = Duration(seconds: 8);

/// Ce que la vérification a appris.
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// L'app est à jour.
class UpdateUpToDate extends UpdateCheckResult {
  const UpdateUpToDate(this.currentVersion);
  final String currentVersion;
}

/// Une version plus récente est publiée.
class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable({required this.version, required this.url, this.notes});

  final String version;
  final String url;
  final String? notes;
}

/// La vérification n'a pas abouti — pas de réseau, manifeste illisible, etc.
/// Ce n'est pas une panne de l'app : il n'y a simplement rien à en conclure.
class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed(this.reason);
  final String reason;
}

class UpdateService {
  const UpdateService({this.manifestUrl = kUpdateManifestUrl});

  final String manifestUrl;

  Future<UpdateCheckResult> check({String currentVersion = kAppVersion}) async {
    final client = HttpClient()..connectionTimeout = kUpdateCheckTimeout;
    try {
      final request = await client
          .getUrl(Uri.parse(manifestUrl))
          .timeout(kUpdateCheckTimeout);
      final response = await request.close().timeout(kUpdateCheckTimeout);

      if (response.statusCode != HttpStatus.ok) {
        return UpdateCheckFailed(
          'Le serveur a répondu ${response.statusCode}.',
        );
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(kUpdateCheckTimeout);
      final manifest = jsonDecode(body) as Map<String, dynamic>;

      final latest = (manifest['version'] as String?)?.trim();
      final url = (manifest['url'] as String?)?.trim();
      if (latest == null || latest.isEmpty || url == null || url.isEmpty) {
        return const UpdateCheckFailed('Manifeste de mise à jour incomplet.');
      }

      if (compareVersions(latest, currentVersion) <= 0) {
        return UpdateUpToDate(currentVersion);
      }
      return UpdateAvailable(
        version: latest,
        url: url,
        notes: (manifest['notes'] as String?)?.trim(),
      );
    } on SocketException {
      return const UpdateCheckFailed(
        'Pas de connexion. La tablette est hors réseau — '
        "c'est normal, Klok n'en a pas besoin pour fonctionner.",
      );
    } on FormatException {
      return const UpdateCheckFailed('Réponse illisible du serveur.');
    } catch (_) {
      return const UpdateCheckFailed('La vérification a échoué.');
    } finally {
      client.close(force: true);
    }
  }
}

/// Compare deux versions segment par segment : négatif si [a] précède [b],
/// zéro si elles sont équivalentes, positif sinon.
///
/// Le suffixe de build (`+1`) est ignoré : il ne participe pas à l'ordre des
/// versions publiées. Une comparaison de chaînes ne conviendrait pas —
/// « 2026.0.9 » y passerait pour plus récent que « 2026.0.10 ».
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split('+')
      .first
      .split('.')
      .map((s) => int.tryParse(s.trim()) ?? 0)
      .toList();

  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va.compareTo(vb);
  }
  return 0;
}
