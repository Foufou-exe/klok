// Routeur racine — sépare l'espace salarié (public sur l'appareil) de
// l'espace admin (verrouillé par PIN). Au premier lancement, si aucun PIN
// n'est défini, on envoie sur l'onboarding.
//
// Redirect logic :
//   • `/admin/*` hors `/admin` impose un déverrouillage valide ;
//   • `/` redirige vers `/onboarding` si aucun PIN n'est configuré (le
//     patron n'est pas censé pouvoir utiliser l'app tant que l'installation
//     n'est pas faite).
//
// Le routeur ne remet pas en cache les `Future` d'onboarding : on écoute
// `hasAdminPinProvider` via `ref.watch` dans le Provider, donc GoRouter sera
// re-forgé à la volée quand le PIN vient d'être créé.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/admin/admin_gate_screen.dart';
import 'features/admin/admin_home_screen.dart';
import 'features/employee/clock_screen.dart';
import 'features/employee/confirm_screen.dart';
import 'features/employee/employee_select_screen.dart';
import 'features/onboarding/klok_onboarding.dart';
import 'state/admin_session.dart';
import 'state/providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final path = state.matchedLocation;
      // Onboarding : si pas de PIN, force à passer par /onboarding.
      final hasPinAsync = ref.read(hasAdminPinProvider);
      final hasPin = hasPinAsync.asData?.value ?? true;
      if (!hasPin && path != '/onboarding') {
        return '/onboarding';
      }
      if (hasPin && path == '/onboarding') {
        return '/';
      }

      // Admin gate : tout `/admin/xxx` derrière requiert un unlock.
      if (path.startsWith('/admin/')) {
        final unlocked = ref.read(adminUnlockedProvider);
        if (!unlocked) return '/admin';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (ctx, st) => const EmployeeSelectScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (ctx, st) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/clock/:id',
        builder: (ctx, st) {
          final id = int.parse(st.pathParameters['id']!);
          return ClockScreen(employeeId: id);
        },
      ),
      GoRoute(
        path: '/confirm/:id/:action',
        builder: (ctx, st) {
          final id = int.parse(st.pathParameters['id']!);
          final action = st.pathParameters['action']!;
          return ConfirmScreen(employeeId: id, action: action);
        },
      ),
      GoRoute(
        path: '/admin',
        builder: (ctx, st) => const AdminGateScreen(),
      ),
      GoRoute(
        path: '/admin/home',
        builder: (ctx, st) => const AdminHomeScreen(),
      ),
    ],
    errorBuilder: (ctx, st) => Scaffold(
      body: Center(child: Text('Route inconnue : ${st.uri}')),
    ),
  );
});
