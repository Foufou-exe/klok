import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tablette kiosque, paysage uniquement. Doublonne volontairement le
  // `android:screenOrientation` du manifest : le manifest couvre le démarrage
  // (splash comprise), celui-ci couvre le cas où une surcouche constructeur
  // ignorerait l'attribut.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Plein écran salarié : on masque barres de statut et de navigation.
  // `immersiveSticky` les laisse réapparaître temporairement sur un swipe puis
  // les remasque — le salarié ne sort pas de l'app par inadvertance, et le
  // patron garde un moyen d'y accéder.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await initializeDateFormatting('fr_FR');
  runApp(const ProviderScope(child: KlokApp()));
}
