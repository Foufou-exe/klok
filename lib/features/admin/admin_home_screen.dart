// Coquille admin — variante Pastille (V2AdminShell).
//
// Header unique avec logo + 5 onglets (Aperçu / Équipe / Export paie /
// Sauvegarde / Réglages) + bouton "Quitter". Le corps affiche l'onglet
// actif et gère en local la vue détail d'un salarié (depuis l'onglet
// Équipe ou Aperçu → clic sur un salarié en service).
//
// Le tab state reste en local (pas dans un provider) : on n'a pas besoin
// de deep-linking précis et ça évite un provider qui ne sert qu'ici.
//
// Ref design : variants/v2-admin.jsx (fonction V2AdminShell).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/app_database.dart';
import '../../design/tokens.dart';
import '../../state/admin_session.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/backup_tab.dart';
import 'tabs/export_tab.dart';
import 'tabs/settings_tab.dart';
import 'tabs/team_tab.dart';

enum AdminTab { dashboard, team, export, backup, settings }

class AdminHomeScreen extends ConsumerStatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  ConsumerState<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends ConsumerState<AdminHomeScreen> {
  AdminTab _tab = AdminTab.dashboard;
  Employee? _detail;

  void _select(AdminTab t) {
    setState(() {
      _tab = t;
      _detail = null;
    });
  }

  void _openDetail(Employee e) {
    setState(() {
      _tab = AdminTab.team;
      _detail = e;
    });
  }

  void _closeDetail() => setState(() => _detail = null);

  void _exitAdmin() {
    ref.read(adminUnlockedProvider.notifier).lock();
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KlokTokens.bg,
      body: SafeArea(
        child: Column(
          children: [
            _AdminHeader(
              activeTab: _tab,
              onSelect: _select,
              onExit: _exitAdmin,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, bc) {
                  final horiz = bc.maxWidth >= 900 ? 28.0 : 20.0;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(horiz, 28, horiz, 28),
                    child: _body(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_tab) {
      case AdminTab.dashboard:
        return DashboardTab(onOpenEmployee: _openDetail);
      case AdminTab.team:
        return TeamTab(
          detail: _detail,
          onOpen: _openDetail,
          onBack: _closeDetail,
        );
      case AdminTab.export:
        return const ExportTab();
      case AdminTab.backup:
        return const BackupTab();
      case AdminTab.settings:
        return const SettingsTab();
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Header : logo + titre + onglets pill + bouton quitter
// ─────────────────────────────────────────────────────────────
class _AdminHeader extends ConsumerWidget {
  const _AdminHeader({
    required this.activeTab,
    required this.onSelect,
    required this.onExit,
  });

  final AdminTab activeTab;
  final ValueChanged<AdminTab> onSelect;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final narrow = MediaQuery.sizeOf(context).width < 1000;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: KlokTokens.card,
        border: Border(
          bottom: BorderSide(color: KlokTokens.border),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: narrow ? 20 : 36, vertical: 20),
        child: Row(
          children: [
            _Logo(),
            const SizedBox(width: 14),
            if (!narrow) const Flexible(child: _EstablishmentLabel()),
            if (!narrow) const Spacer(),
            // Onglets pill
            Flexible(
              child: _TabPillGroup(
                active: activeTab,
                onSelect: onSelect,
              ),
            ),
            const SizedBox(width: 12),
            _ExitButton(onTap: onExit),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: KlokTokens.bordeaux,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Text(
          'k',
          style: TextStyle(
            fontFamily: KlokTokens.fontDisplay,
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _EstablishmentLabel extends ConsumerWidget {
  const _EstablishmentLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Le nom de l'établissement vient des settings. On watch sans bloquer :
    // valeur temporaire "Klok" si pas encore chargée.
    final barName = ref.watch(barNameProvider);

    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontFamily: KlokTokens.fontDisplay,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: KlokTokens.ink,
        ),
        children: [
          const TextSpan(text: 'Admin  '),
          TextSpan(
            text: '· ${barName.asData?.value ?? ''}'.trimRight() == '·'
                ? ''
                : '· ${barName.asData?.value ?? ''}',
            style: TextStyle(
              color: KlokTokens.muted,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabPillGroup extends StatelessWidget {
  const _TabPillGroup({required this.active, required this.onSelect});

  final AdminTab active;
  final ValueChanged<AdminTab> onSelect;

  static const _tabs = <(AdminTab, String)>[
    (AdminTab.dashboard, 'Aperçu'),
    (AdminTab.team, 'Équipe'),
    (AdminTab.export, 'Export paie'),
    (AdminTab.backup, 'Sauvegarde'),
    (AdminTab.settings, 'Réglages'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: KlokTokens.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (t, label) in _tabs)
            _TabPill(
              label: label,
              active: active == t,
              onTap: () => onSelect(t),
            ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: active ? KlokTokens.card : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0x143C2814), // ~8% sepia
                      offset: Offset(0, 1),
                      blurRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? KlokTokens.ink : KlokTokens.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExitButton extends StatelessWidget {
  const _ExitButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KlokTokens.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: KlokTokens.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: KlokTokens.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout, size: 14, color: KlokTokens.inkSoft),
              const SizedBox(width: 6),
              Text(
                'Quitter',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: KlokTokens.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
