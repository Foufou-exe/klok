// Écran d'accueil salarié — variante Pastille.
//
// Layout : header ("Hey !" + horloge live) + grille de pastilles colorées
// (1 par salarié) + bandeau bas ("X en service · Y en pause").
// Un point vert/ambre sur la pastille signale les salariés actifs.
//
// Responsive : 6 colonnes en paysage large (tablette 1280w), 4 en paysage
// étroit / portrait large (tablette 800w), 3 en portrait serré, 2 en phone.
//
// Ref design : variants/v2-pastille.jsx (fonction V2PickEmployee).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/db/app_database.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

class EmployeeSelectScreen extends ConsumerWidget {
  const EmployeeSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(activeEmployeesProvider);
    return Scaffold(
      backgroundColor: KlokTokens.bg,
      body: SafeArea(
        child: employees.when(
          data: (list) => list.isEmpty
              ? const _EmptyState()
              : _PickContent(employees: list),
          error: (e, st) => Center(
            child: Text(
              'Erreur : $e',
              style: TextStyle(color: KlokTokens.danger),
            ),
          ),
          loading: () => Center(
            child: CircularProgressIndicator(color: KlokTokens.bordeaux),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Contenu principal (header + grille + bandeau)
// ─────────────────────────────────────────────────────────────
class _PickContent extends ConsumerWidget {
  const _PickContent({required this.employees});
  final List<Employee> employees;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamStatusProvider);
    // MediaQuery.sizeOf au lieu de LayoutBuilder : on évite la re-entrance
    // layout qui peut survenir si un StreamProvider enfant émet une valeur
    // cachée pendant la pose du LayoutBuilder.
    final w = MediaQuery.sizeOf(context).width;
    // Breakpoints. 6 cols quand on a la place, sinon on dégrade
    // vers 4/3/2 pour garder la pastille lisible sur tout format.
    final cols = w >= 1100
        ? 6
        : w >= 850
            ? 5
            : w >= 680
                ? 4
                : w >= 480
                    ? 3
                    : 2;
    final horiz = w >= 900
        ? 48.0
        : w >= 600
            ? 32.0
            : 20.0;
    final headerVert = w >= 900 ? 36.0 : 24.0;

    // Calcule la taille de pastille en fonction de la largeur de colonne
    // disponible, cappée à 116 (valeur du design).
    final gridWidth = w - horiz * 2;
    final colWidth = (gridWidth - (cols - 1) * 20) / cols;
    final pastilleSize = colWidth < 140 ? (colWidth * 0.78) : 116.0;

    return Column(
      children: [
        _Header(horiz: horiz, vert: headerVert),
        // Align(topCenter) plutôt que Center pour caler la grille juste sous
        // le header — sinon, avec une petite équipe, la grille était centrée
        // verticalement et il y avait un grand vide entre les pastilles et le
        // bandeau du bas. Padding bottom réduit aussi pour serrer.
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(horiz, 4, horiz, 12),
            child: Align(
              alignment: Alignment.topCenter,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  // Pastille (pastilleSize) + gap 12 + nom (~40) + padding
                  childAspectRatio: pastilleSize / (pastilleSize + 72),
                ),
                itemCount: employees.length,
                itemBuilder: (ctx, i) {
                  final e = employees[i];
                  return _EmployeeTile(
                    employee: e,
                    status: team.statusOf(e.id),
                    pastilleSize: pastilleSize,
                    onTap: () => context.push('/clock/${e.id}'),
                  );
                },
              ),
            ),
          ),
        ),
        _BottomBand(team: team, horiz: horiz),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Header : "Hey !" + horloge live
// (Le bandeau d'identité de l'établissement vit dans le footer — cf.
// `_BottomBand` plus bas. Demande explicite côté UX : on garde le haut
// dégagé pour mettre en avant l'invitation à pointer.)
// ─────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.horiz, required this.vert});
  final double horiz;
  final double vert;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: EdgeInsets.fromLTRB(horiz, vert, horiz, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hey !',
                  style: TextStyle(
                    fontFamily: KlokTokens.fontDisplay,
                    fontSize: narrow ? 34 : 42,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -1.2,
                    color: KlokTokens.ink,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Appuie sur ta pastille pour pointer',
                  style: TextStyle(
                    fontSize: narrow ? 14 : 16,
                    color: KlokTokens.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const _Clock(),
        ],
      ),
    );
  }
}

/// Petite pastille bordeaux avec un "k" — placeholder visuel tant qu'aucun
/// logo n'est importé par le patron. Quand le pipeline d'import sera câblé,
/// on remplacera par l'image stockée localement.
class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: KlokTokens.bordeaux,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Text(
          'k',
          style: TextStyle(
            fontFamily: KlokTokens.fontDisplay,
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Colors.white,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

/// Horloge vivante, isolée pour ne rebuilder QUE cette zone à chaque seconde.
class _Clock extends ConsumerWidget {
  const _Clock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(tickerProvider).asData?.value ?? DateTime.now();
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          formatHHmm(now),
          style: TextStyle(
            fontFamily: KlokTokens.fontDisplay,
            fontSize: narrow ? 32 : 40,
            fontWeight: FontWeight.w400,
            letterSpacing: -1.2,
            color: KlokTokens.ink,
            height: 1.0,
            fontFeatures: KlokTokens.tabularFigures,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _capitalize(formatDateFull(now)),
          style: TextStyle(
            fontSize: 13,
            color: KlokTokens.inkSoft,
          ),
        ),
      ],
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ─────────────────────────────────────────────────────────────
// Tile "pastille" : cercle coloré + nom
// ─────────────────────────────────────────────────────────────
class _EmployeeTile extends StatefulWidget {
  const _EmployeeTile({
    required this.employee,
    required this.status,
    required this.pastilleSize,
    required this.onTap,
  });

  final Employee employee;
  final EmployeeStatus status;
  final double pastilleSize;
  final VoidCallback onTap;

  @override
  State<_EmployeeTile> createState() => _EmployeeTileState();
}

class _EmployeeTileState extends State<_EmployeeTile> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.employee;
    final color = _parseHexColor(e.color);
    final initials = _initialsOf(e);
    final onColor = _onColorFor(color);
    final lifted = _hovered || _pressed;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, lifted ? -3 : 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Pastille(
                size: widget.pastilleSize,
                color: color,
                onColor: onColor,
                initials: initials,
                status: widget.status.kind,
              ),
              const SizedBox(height: 12),
              Text(
                e.firstName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KlokTokens.fontDisplay,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: KlokTokens.ink,
                ),
              ),
              if (e.lastName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  e.lastName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: KlokTokens.inkSoft,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Cercle coloré avec initiales. Gradient linéaire subtil (blanc haut / noir
/// bas ~10%) pour simuler l'effet inset-shadow de la ref CSS : le cercle a
/// l'air "éclairé par le haut" sans avoir besoin de vraie inset-shadow
/// (que Flutter ne supporte pas nativement).
class _Pastille extends StatelessWidget {
  const _Pastille({
    required this.size,
    required this.color,
    required this.onColor,
    required this.initials,
    required this.status,
  });

  final double size;
  final Color color;
  final Color onColor;
  final String initials;
  final EmployeeStatusKind status;

  @override
  Widget build(BuildContext context) {
    final badgeSize = (size * 0.22).clamp(18.0, 28.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(Colors.white.withValues(alpha: 0.06), color),
                  color,
                  Color.alphaBlend(Colors.black.withValues(alpha: 0.12), color),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x263C2814), // rgba(60,40,20,0.15)
                  offset: Offset(0, 6),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  fontFamily: KlokTokens.fontDisplay,
                  fontWeight: FontWeight.w500,
                  fontSize: size * 0.33,
                  letterSpacing: -1,
                  color: onColor,
                  height: 1.0,
                ),
              ),
            ),
          ),
          if (status != EmployeeStatusKind.off)
            Positioned(
              right: -2,
              bottom: 4,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: status == EmployeeStatusKind.working
                      ? KlokTokens.success
                      : KlokTokens.amber,
                  border: Border.all(color: KlokTokens.bg, width: 3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Bandeau bas : logo + nom établissement | summary équipe | bouton admin
// (Auparavant le logo + nom étaient en haut du Header. Demande explicite :
// les déplacer ici pour libérer le haut de l'écran.)
// ─────────────────────────────────────────────────────────────
class _BottomBand extends ConsumerWidget {
  const _BottomBand({required this.team, required this.horiz});
  final TeamStatus team;
  final double horiz;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final barName =
        ref.watch(barNameProvider).asData?.value?.trim() ?? '';
    return Container(
      width: double.infinity,
      color: KlokTokens.bgDeep,
      padding: EdgeInsets.symmetric(horizontal: horiz, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Identité de l'établissement à gauche : logo + nom. Si le nom n'est
          // pas encore défini (cas improbable post-onboarding), on retombe
          // proprement sur "KLOK" comme avant.
          const _BrandLogo(),
          const SizedBox(width: 10),
          if (!narrow)
            Flexible(
              child: Text(
                barName.isEmpty ? 'KLOK' : barName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KlokTokens.fontDisplay,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  letterSpacing: -0.2,
                  color: KlokTokens.ink,
                ),
              ),
            ),
          const SizedBox(width: 18),
          Expanded(
            child: _TeamSummary(team: team, narrow: narrow),
          ),
          const SizedBox(width: 12),
          // Bouton admin — intégré au bandeau (plutôt qu'en floating) pour
          // éviter le chevauchement avec le texte et garder une cible de tap
          // cohérente pour une tablette utilisée debout.
          const _AdminLockButton(),
        ],
      ),
    );
  }
}

class _TeamSummary extends StatelessWidget {
  const _TeamSummary({required this.team, required this.narrow});
  final TeamStatus team;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final working = team.workingCount;
    final breakCount = team.breakCount;
    final TextStyle labelStyle = TextStyle(
      fontSize: 13,
      color: KlokTokens.inkSoft,
    );
    final TextStyle strongStyle = TextStyle(
      fontSize: 13,
      color: KlokTokens.ink,
      fontWeight: FontWeight.w600,
    );

    // Rien en service → indication sobre, pas d'état bizarre.
    if (working == 0 && breakCount == 0) {
      return Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KlokTokens.muted,
            ),
          ),
          const SizedBox(width: 8),
          Text('Personne en service', style: labelStyle),
        ],
      );
    }

    final spans = <InlineSpan>[
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KlokTokens.success,
          ),
        ),
      ),
      const WidgetSpan(child: SizedBox(width: 8)),
      TextSpan(
        text: '$working en service',
        style: strongStyle,
      ),
    ];

    if (breakCount > 0) {
      spans
        ..add(TextSpan(text: '  ·  ', style: labelStyle.copyWith(color: KlokTokens.muted)))
        ..add(TextSpan(
          text: team.breakFirstNames.join(', '),
          style: strongStyle,
        ))
        ..add(TextSpan(
          text: breakCount > 1 ? ' en pause' : ' en pause',
          style: labelStyle,
        ));
    }

    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: labelStyle, children: spans),
    );
  }
}

class _AdminLockButton extends StatelessWidget {
  const _AdminLockButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KlokTokens.cream200.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context.push('/admin'),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            Icons.lock_outline,
            size: 18,
            color: KlokTokens.muted,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Empty state — pas de salarié encore créé
// (Pas de bouton "Ouvrir admin" ici : on garde la séparation stricte
// salarié/admin. Le patron passe par le cadenas en bas à droite du footer.)
// ─────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KlokTokens.cream200,
              ),
              child: Icon(
                Icons.group_outlined,
                size: 52,
                color: KlokTokens.muted,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Aucun salarié enregistré',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KlokTokens.fontDisplay,
                fontSize: 28,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.8,
                color: KlokTokens.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Tape sur le cadenas en bas à droite pour ouvrir l'admin "
              "et ajouter ton équipe.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: KlokTokens.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Utilitaires
// ─────────────────────────────────────────────────────────────

String _initialsOf(Employee e) {
  final f = e.firstName.isNotEmpty ? e.firstName[0] : '';
  final l = e.lastName.isNotEmpty ? e.lastName[0] : '';
  final out = '$f$l';
  return out.isEmpty ? '?' : out.toUpperCase();
}

Color _parseHexColor(String hex) {
  final clean = hex.replaceAll('#', '').trim();
  // Tolère un hex de 3, 6 ou 8 caractères — on force l'alpha à 0xFF si absent.
  if (clean.length == 3) {
    final r = clean[0] * 2;
    final g = clean[1] * 2;
    final b = clean[2] * 2;
    return Color(int.parse('FF$r$g$b', radix: 16));
  }
  if (clean.length == 8) return Color(int.parse(clean, radix: 16));
  return Color(int.parse('FF$clean', radix: 16));
}

/// Choisit noir ou blanc sur fond coloré, en fonction de la luminance
/// perçue. Protège contre une couleur salarié très claire (peu probable
/// vu la palette recommandée, mais robuste).
Color _onColorFor(Color bg) {
  final lum = bg.computeLuminance();
  return lum > 0.55 ? KlokTokens.ink : Colors.white;
}
