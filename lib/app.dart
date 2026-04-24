import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design/theme.dart';
import 'router.dart';

class KlokApp extends ConsumerWidget {
  const KlokApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'klok',
      debugShowCheckedModeBanner: false,
      theme: buildKlokTheme(),
      routerConfig: router,
    );
  }
}
