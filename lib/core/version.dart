/// Version de l'app, affichée dans les Réglages et estampillée dans chaque
/// backup JSON (`backup_service.dart`).
///
/// DOIT rester identique au champ `version:` de `pubspec.yaml` — c'est ce
/// dernier qui alimente versionName/versionCode de l'APK. Le test
/// `test/version_test.dart` échoue si les deux divergent.
const String kAppVersion = '2026.0.10+1';

const int kBackupFormatVersion = 1;
