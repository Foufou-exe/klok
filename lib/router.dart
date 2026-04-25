// Routeur racine — sépare l'espace salarié (public sur l'appareil) de
// l'espace admin (verrouillé par PIN). Au premier lancement, si aucun PIN
// n'est défini, on envoie sur l'onboarding.
//
// Redirect logic :
//   • Tant que `hasAdminPinProvider` est en LOADING, on assume "pas de PIN"
//     pour ne pas laisser l'utilisateur voir un écran salarié vide pendant
//     que SQLite charge — l'utilisateur lambda n'est pas censé voir ce
//     flash. Le risque inverse (montrer onboarding alors qu'un PIN existe)
//     est neutralisé par `ref.listen` plus bas qui rafraîchit le routeur
//     dès que la valeur réelle arrive.
//   • `/admin/*` hors `/admin` impose un déverrouillage valide ;
//   • `/` redirige vers `/onboarding` si aucun PIN n'est configuré (le
//     patron n'est pas censé pouvoir utiliser l'app tant que l'installation
//     n'est pas faite).
//
// On câble `ref.listen(hasAdminPinProvider)` → `router.refresh()` pour que
// la transition LOADING → DATA déclenche une re-évaluation du redirect sans
// recréer le GoRouter (sinon on perdrait la pile de navigation).

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
  final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final path = state.matchedLocation;
      final hasPinAsync = ref.read(hasAdminPinProvider);
      // Default à FALSE pendant le loading : si le provider n'a pas encore
      // résolu, on considère qu'on est en première installation et on
      // redirige vers l'onboarding. Ça évite le flash "homepage vide" qu'on
      // avait avant.
      final hasPin = hasPinAsync.asData?.value ?? false;

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

  // Re-évalue le redirect dès que :
  //   • `hasAdminPinProvider` passe de loading à data (boot froid),
  //   • le PIN est créé via onboarding (invalidate post-finish),
  //   • un restore de sauvegarde change l'état (invalidate post-restore),
  //   • la session admin change d'état (lock/unlock côté Settings).
  ref.listen<AsyncValue<bool>>(hasAdminPinProvider, (_, _) => router.refresh());
  ref.listen<bool>(adminUnlockedProvider, (_, _) => router.refresh());
  return router;
});
