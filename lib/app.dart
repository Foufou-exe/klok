import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

class KlokApp extends ConsumerWidget {
  const KlokApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'klok',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.light,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
          headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(fontSize: 18),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            minimumSize: const Size(200, 80),
          ),
        ),
      ),
      routerConfig: router,
    );
  }
}
