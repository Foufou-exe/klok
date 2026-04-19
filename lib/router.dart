import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/admin/admin_backup_screen.dart';
import 'features/admin/admin_employees_screen.dart';
import 'features/admin/admin_export_screen.dart';
import 'features/admin/admin_gate_screen.dart';
import 'features/admin/admin_home_screen.dart';
import 'features/admin/admin_indicators_screen.dart';
import 'features/employee/clock_screen.dart';
import 'features/employee/employee_select_screen.dart';
import 'state/admin_session.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final path = state.matchedLocation;
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
        path: '/clock/:id',
        builder: (ctx, st) {
          final id = int.parse(st.pathParameters['id']!);
          return ClockScreen(employeeId: id);
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
      GoRoute(
        path: '/admin/employees',
        builder: (ctx, st) => const AdminEmployeesScreen(),
      ),
      GoRoute(
        path: '/admin/indicators',
        builder: (ctx, st) => const AdminIndicatorsScreen(),
      ),
      GoRoute(
        path: '/admin/export',
        builder: (ctx, st) => const AdminExportScreen(),
      ),
      GoRoute(
        path: '/admin/backup',
        builder: (ctx, st) => const AdminBackupScreen(),
      ),
    ],
    errorBuilder: (ctx, st) => Scaffold(
      body: Center(child: Text('Route inconnue : ${st.uri}')),
    ),
  );
});
