import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klok/core/version.dart';

/// Garde-fou : `kAppVersion` est estampillé dans chaque backup JSON et affiché
/// dans les Réglages, tandis que `pubspec.yaml` alimente le versionName de
/// l'APK. Les deux ont divergé une fois (1.0.0+1 vs 2026.0.10+1), produisant
/// des backups mal étiquetés. Ce test empêche que ça se reproduise.
void main() {
  test('kAppVersion correspond à la version du pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'champ `version:` introuvable dans pubspec.yaml');
    expect(
      kAppVersion,
      match!.group(1),
      reason: 'lib/core/version.dart doit suivre pubspec.yaml — '
          'bumper les deux ensemble à chaque release',
    );
  });
}
