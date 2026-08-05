// Onboarding — première installation de Klok.
//
// Étapes :
//   0. Bienvenue (CTA "C'est parti")
//   1. Établissement : nom (requis ≥ 2) + lieu (optionnel)
//   2. Patron : prénom (requis ≥ 2) + nom (requis ≥ 2)
//   3. Création du PIN à 8 chiffres (double saisie)
//   4. Récapitulatif + CTA "Lancer Klok"
//
// L'import de logo est volontairement laissé pour plus tard (file_picker à
// câbler) : on conserve une pastille "k" générique en attendant. Tous les
// champs persistés passent par `SettingsKeys` pour garder le repository en
// source de vérité, et on invalide `hasAdminPinProvider` à la fin pour que
// le routeur lâche `/onboarding`.
//
// À la sortie, on redirige sur `/` (homepage employee-select) — explicitement
// PAS sur l'admin. Le patron accède à l'admin par le cadenas en bas à droite
// du bandeau, comme un salarié quelconque (avec PIN). C'est la séparation
// stricte entre l'espace public sur l'appareil et l'espace admin.
//
// Ref design : shared/onboarding.jsx (fonction KlokOnboarding).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/settings_repository.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';
import '../admin/widgets/pin_keypad.dart';

/// Longueur minimum du PIN admin. À garder synchro avec `admin_gate_screen.dart`.
const int kAdminPinLength = 8;

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  final _establishmentCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  // PIN validé (saisi + confirmé) — alimenté par le keypad à l'étape 3.
  // Vide tant que la double saisie n'a pas été validée.
  String _pinValue = '';

  static const _steps = [
    'Bienvenue',
    'Établissement',
    'Patron',
    'Code PIN',
    'Prêt',
  ];

  @override
  void dispose() {
    _establishmentCtrl.dispose();
    _locationCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  bool get _canNext {
    switch (_step) {
      case 1:
        return _establishmentCtrl.text.trim().length >= 2;
      case 2:
        return _firstNameCtrl.text.trim().length >= 2 &&
            _lastNameCtrl.text.trim().length >= 2;
      case 3:
        // L'étape 3 progresse automatiquement (cf. _PinStep) — la barre
        // navigation ne montre pas de bouton "Continuer" ici.
        return false;
      default:
        return true;
    }
  }

  /// Appelé par l'étape 3 quand l'utilisateur a validé son PIN deux fois de
  /// suite. On stocke la valeur et on avance immédiatement à l'étape 4.
  void _onPinValidated(String pin) {
    setState(() {
      _pinValue = pin;
      _step = 4;
    });
  }

  Future<void> _finish() async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.set(SettingsKeys.barName, _establishmentCtrl.text.trim());
    final loc = _locationCtrl.text.trim();
    if (loc.isNotEmpty) {
      await settings.set(SettingsKeys.barLocation, loc);
    }
    await settings.set(SettingsKeys.ownerFirstName, _firstNameCtrl.text.trim());
    await settings.set(SettingsKeys.ownerLastName, _lastNameCtrl.text.trim());
    await settings.setPin(_pinValue);
    ref.invalidate(hasAdminPinProvider);
    if (!mounted) return;
    // On reste cohérent avec le mode kiosque : l'app démarre toujours sur
    // l'écran salarié. Le patron utilise le cadenas dans le footer pour
    // ouvrir l'admin et ajouter sa première recrue.
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KlokTokens.bg,
      body: SafeArea(
        child: Column(
          children: [
            _ProgressHeader(step: _step, labels: _steps),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 24,
                    ),
                    child: _StepContent(
                      step: _step,
                      establishmentCtrl: _establishmentCtrl,
                      locationCtrl: _locationCtrl,
                      firstNameCtrl: _firstNameCtrl,
                      lastNameCtrl: _lastNameCtrl,
                      onStart: () => setState(() => _step = 1),
                      onFinish: _finish,
                      onPinValidated: _onPinValidated,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ),
              ),
            ),
            if (_step > 0 && _step < 4)
              _NavBar(
                canNext: _canNext,
                onBack: () => setState(() => _step--),
                onNext: () {
                  if (!_canNext) return;
                  setState(() => _step++);
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Header avec logo + stepper
// ─────────────────────────────────────────────────────────────
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step, required this.labels});
  final int step;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 720;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: KlokTokens.border)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: narrow ? 20 : 48,
          vertical: 20,
        ),
        child: Row(
          children: [
            Container(
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
            ),
            const SizedBox(width: 12),
            Text(
              'Klok · installation',
              style: TextStyle(
                fontFamily: KlokTokens.fontDisplay,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: KlokTokens.ink,
              ),
            ),
            const Spacer(),
            // En écran étroit on ne montre que le numéro d'étape, pas tous les
            // dots — sinon ça pousse le contenu hors de l'écran.
            if (narrow)
              Text(
                'Étape ${step + 1} / ${labels.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: KlokTokens.inkSoft,
                ),
              )
            else
              for (var i = 0; i < labels.length; i++) ...[
                _StepDot(index: i, current: step),
                if (i < labels.length - 1)
                  Container(
                    width: 20,
                    height: 2,
                    color: i < step ? KlokTokens.success : KlokTokens.border,
                  ),
              ],
          ],
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.index, required this.current});
  final int index;
  final int current;

  @override
  Widget build(BuildContext context) {
    Color bg;
    String content;
    if (index < current) {
      bg = KlokTokens.success;
      content = '✓';
    } else if (index == current) {
      bg = KlokTokens.bordeaux;
      content = '${index + 1}';
    } else {
      bg = KlokTokens.border;
      content = '${index + 1}';
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: Center(
        child: Text(
          content,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Corps selon l'étape
// ─────────────────────────────────────────────────────────────
class _StepContent extends StatelessWidget {
  const _StepContent({
    required this.step,
    required this.establishmentCtrl,
    required this.locationCtrl,
    required this.firstNameCtrl,
    required this.lastNameCtrl,
    required this.onStart,
    required this.onFinish,
    required this.onPinValidated,
    required this.onChanged,
  });

  final int step;
  final TextEditingController establishmentCtrl;
  final TextEditingController locationCtrl;
  final TextEditingController firstNameCtrl;
  final TextEditingController lastNameCtrl;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final ValueChanged<String> onPinValidated;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    switch (step) {
      case 0:
        return _WelcomeStep(onStart: onStart);
      case 1:
        return _EstablishmentStep(
          nameCtrl: establishmentCtrl,
          locationCtrl: locationCtrl,
          onChanged: onChanged,
        );
      case 2:
        return _OwnerStep(
          firstNameCtrl: firstNameCtrl,
          lastNameCtrl: lastNameCtrl,
          onChanged: onChanged,
        );
      case 3:
        return _PinStep(onPinValidated: onPinValidated);
      case 4:
        return _DoneStep(
          establishment: establishmentCtrl.text.trim(),
          location: locationCtrl.text.trim(),
          ownerFirstName: firstNameCtrl.text.trim(),
          ownerLastName: lastNameCtrl.text.trim(),
          onFinish: onFinish,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Étape 0 : bienvenue
// ─────────────────────────────────────────────────────────────
class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Bienvenue sur Klok',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: KlokTokens.fontDisplay,
            fontSize: 52,
            fontWeight: FontWeight.w500,
            letterSpacing: -2,
            color: KlokTokens.ink,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 14),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              fontSize: 16,
              color: KlokTokens.inkSoft,
              height: 1.6,
            ),
            children: [
              const TextSpan(text: 'Le pointage horaire de ton équipe, '),
              TextSpan(
                text: '100% local, hors-ligne',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: KlokTokens.ink,
                ),
              ),
              const TextSpan(text: '.\nQuelques réglages et on est prêts.'),
            ],
          ),
        ),
        const SizedBox(height: 36),
        Row(
          children: const [
            _InfoCell(emoji: '🏠', title: 'Établissement', sub: 'Nom + lieu'),
            SizedBox(width: 12),
            _InfoCell(emoji: '👤', title: 'Patron', sub: 'Prénom + nom'),
            SizedBox(width: 12),
            _InfoCell(emoji: '🔒', title: 'Code PIN', sub: '8 chiffres'),
          ],
        ),
        const SizedBox(height: 36),
        _BordeauxButton(label: "C'est parti →", onTap: onStart),
      ],
    );
  }
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({
    required this.emoji,
    required this.title,
    required this.sub,
  });
  final String emoji;
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KlokTokens.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KlokTokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: KlokTokens.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(fontSize: 11, color: KlokTokens.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Étape 1 : établissement (nom + lieu)
// ─────────────────────────────────────────────────────────────
class _EstablishmentStep extends StatelessWidget {
  const _EstablishmentStep({
    required this.nameCtrl,
    required this.locationCtrl,
    required this.onChanged,
  });

  final TextEditingController nameCtrl;
  final TextEditingController locationCtrl;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepHeader(
          stepLabel: 'Étape 1 / 3',
          title: 'Ton établissement',
          help: "Le nom s'affichera sur l'accueil et sur les PDF de paie.",
        ),
        const SizedBox(height: 28),
        _LabeledInput(
          label: 'Nom du bar / restaurant',
          required: true,
          controller: nameCtrl,
          placeholder: "Le Comptoir d'Alphonse",
          onChanged: onChanged,
        ),
        const SizedBox(height: 18),
        _LabeledInput(
          label: 'Lieu (ville, adresse…)',
          required: false,
          controller: locationCtrl,
          placeholder: 'Montpellier',
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Étape 2 : patron (prénom + nom)
// ─────────────────────────────────────────────────────────────
class _OwnerStep extends StatelessWidget {
  const _OwnerStep({
    required this.firstNameCtrl,
    required this.lastNameCtrl,
    required this.onChanged,
  });

  final TextEditingController firstNameCtrl;
  final TextEditingController lastNameCtrl;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepHeader(
          stepLabel: 'Étape 2 / 3',
          title: 'Ton identité',
          help: 'Utilisé pour signer les exports PDF de paie.',
        ),
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _LabeledInput(
                label: 'Prénom',
                required: true,
                controller: firstNameCtrl,
                placeholder: 'Alphonse',
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _LabeledInput(
                label: 'Nom',
                required: true,
                controller: lastNameCtrl,
                placeholder: 'Martin',
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Étape 3 : PIN 8 chiffres avec keypad (mêmes widgets que la gate admin)
// ─────────────────────────────────────────────────────────────
//
// Double saisie en deux temps comme `_PinCreate` côté gate :
//   1. L'utilisateur tape les 8 chiffres → on bascule en mode "confirmer".
//   2. Re-tape : si match, on lève `onPinValidated(pin)` qui fait avancer
//      l'écran d'onboarding à l'étape 4. Si mismatch, shake + reset complet.
//
// Le clavier garde l'ordre standard (1..9, 0) ici : c'est plus simple à
// mémoriser quand on tape DEUX fois le même code. Le shuffle est réservé à
// la gate (vérification d'un code déjà connu).
class _PinStep extends StatefulWidget {
  const _PinStep({required this.onPinValidated});
  final ValueChanged<String> onPinValidated;

  @override
  State<_PinStep> createState() => _PinStepState();
}

class _PinStepState extends State<_PinStep>
    with SingleTickerProviderStateMixin {
  String _firstPin = '';
  String _secondPin = '';
  // 0 = saisie initiale, 1 = confirmation
  int _phase = 0;
  bool _error = false;
  bool _busy = false;
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  String get _active => _phase == 0 ? _firstPin : _secondPin;

  Future<void> _onDigit(String d) async {
    if (_busy || _active.length >= kAdminPinLength) return;
    setState(() {
      if (_phase == 0) {
        _firstPin = _firstPin + d;
      } else {
        _secondPin = _secondPin + d;
      }
    });
    if (_phase == 0 && _firstPin.length == kAdminPinLength) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      setState(() => _phase = 1);
    } else if (_phase == 1 && _secondPin.length == kAdminPinLength) {
      setState(() => _busy = true);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      if (_firstPin == _secondPin) {
        widget.onPinValidated(_firstPin);
      } else {
        setState(() => _error = true);
        _shake.forward(from: 0);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        setState(() {
          _firstPin = '';
          _secondPin = '';
          _phase = 0;
          _error = false;
          _busy = false;
        });
      }
    }
  }

  void _onBackspace() {
    if (_busy) return;
    setState(() {
      if (_phase == 1 && _secondPin.isNotEmpty) {
        _secondPin = _secondPin.substring(0, _secondPin.length - 1);
      } else if (_phase == 1 && _secondPin.isEmpty) {
        // Permet de revenir corriger la première saisie.
        _phase = 0;
        if (_firstPin.isNotEmpty) {
          _firstPin = _firstPin.substring(0, _firstPin.length - 1);
        }
      } else if (_firstPin.isNotEmpty) {
        _firstPin = _firstPin.substring(0, _firstPin.length - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Tout est centré horizontalement pour s'aligner sur le keypad — c'est
    // la même mise en page que la gate admin, on ne mélange pas les codes
    // visuels entre les deux écrans.
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'ÉTAPE 3 / 3',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: KlokTokens.muted,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _phase == 0 ? 'Crée un code PIN patron' : 'Confirme ton PIN',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: KlokTokens.fontDisplay,
            fontSize: 30,
            fontWeight: FontWeight.w500,
            letterSpacing: -1,
            color: KlokTokens.ink,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _phase == 0
              ? "$kAdminPinLength chiffres. Tu l'utiliseras pour accéder aux écrans admin."
              : 'Retape les $kAdminPinLength mêmes chiffres.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: KlokTokens.inkSoft),
        ),
        const SizedBox(height: 28),
        PinDots(
          length: kAdminPinLength,
          filled: _active.length,
          error: _error,
          shake: _shake,
        ),
        const SizedBox(height: 28),
        PinKeypad(
          digits: kStandardKeypadDigits,
          onDigit: _onDigit,
          onBackspace: _onBackspace,
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: KlokTokens.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KlokTokens.border),
          ),
          child: Text(
            "⚠️ Note ce code quelque part. En cas d'oubli, une restauration "
            'complète des données sera nécessaire.',
            style: TextStyle(fontSize: 12, color: KlokTokens.muted),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Étape 4 : confirmation
// ─────────────────────────────────────────────────────────────
class _DoneStep extends StatelessWidget {
  const _DoneStep({
    required this.establishment,
    required this.location,
    required this.ownerFirstName,
    required this.ownerLastName,
    required this.onFinish,
  });

  final String establishment;
  final String location;
  final String ownerFirstName;
  final String ownerLastName;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final fullName = [
      ownerFirstName,
      ownerLastName,
    ].where((s) => s.isNotEmpty).join(' ');
    final establishmentLine = location.isEmpty
        ? establishment
        : '$establishment · $location';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KlokTokens.success,
          ),
          child: const Center(
            child: Text(
              '✓',
              style: TextStyle(fontSize: 44, color: Colors.white, height: 1.0),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Tout est prêt !',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: KlokTokens.fontDisplay,
            fontSize: 40,
            fontWeight: FontWeight.w500,
            letterSpacing: -1.2,
            color: KlokTokens.ink,
          ),
        ),
        const SizedBox(height: 10),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              fontSize: 15,
              color: KlokTokens.inkSoft,
              height: 1.6,
            ),
            children: [
              TextSpan(
                text: establishment,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: KlokTokens.ink,
                ),
              ),
              const TextSpan(
                text:
                    ' est configuré.\nTu peux maintenant ajouter tes '
                    "salariés depuis l'écran admin.",
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: KlokTokens.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: KlokTokens.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: _Summary(
                  label: 'Établissement',
                  value: establishmentLine,
                ),
              ),
              Expanded(
                child: _Summary(
                  label: 'Patron',
                  value: fullName.isEmpty ? '—' : fullName,
                ),
              ),
              Expanded(
                child: _Summary(
                  label: 'PIN patron',
                  value: '•' * kAdminPinLength,
                  spaced: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        _BordeauxButton(label: 'Lancer Klok →', onTap: onFinish),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.label,
    required this.value,
    this.spaced = false,
  });

  final String label;
  final String value;
  final bool spaced;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: KlokTokens.muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: KlokTokens.ink,
            letterSpacing: spaced ? 3 : 0,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Building blocks partagés
// ─────────────────────────────────────────────────────────────
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.stepLabel,
    required this.title,
    required this.help,
  });

  final String stepLabel;
  final String title;
  final String help;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          stepLabel.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: KlokTokens.muted,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            fontFamily: KlokTokens.fontDisplay,
            fontSize: 34,
            fontWeight: FontWeight.w500,
            letterSpacing: -1,
            color: KlokTokens.ink,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(help, style: TextStyle(fontSize: 14, color: KlokTokens.inkSoft)),
      ],
    );
  }
}

class _LabeledInput extends StatelessWidget {
  const _LabeledInput({
    required this.label,
    required this.required,
    required this.controller,
    required this.placeholder,
    required this.onChanged,
  });

  final String label;
  final bool required;
  final TextEditingController controller;
  final String placeholder;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: KlokTokens.inkSoft,
              ),
            ),
            if (!required)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  '· optionnel',
                  style: TextStyle(fontSize: 11, color: KlokTokens.muted),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: (_) => onChanged(),
          style: TextStyle(
            fontFamily: KlokTokens.fontDisplay,
            fontSize: 20,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
            color: KlokTokens.ink,
          ),
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: TextStyle(color: KlokTokens.muted),
            filled: true,
            fillColor: KlokTokens.card,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: KlokTokens.border, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: KlokTokens.border, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: KlokTokens.bordeaux, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Barre de nav bas
// ─────────────────────────────────────────────────────────────
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.canNext,
    required this.onBack,
    required this.onNext,
  });

  final bool canNext;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: KlokTokens.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _GhostButton(label: '← Retour', onTap: onBack),
            _DarkButton(label: 'Continuer →', enabled: canNext, onTap: onNext),
          ],
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});
  final String label;
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
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: KlokTokens.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KlokTokens.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _DarkButton extends StatelessWidget {
  const _DarkButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? KlokTokens.ink : KlokTokens.border;
    final fg = enabled ? Colors.white : KlokTokens.muted;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KlokTokens.fontDisplay,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _BordeauxButton extends StatelessWidget {
  const _BordeauxButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KlokTokens.bordeaux,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: KlokTokens.fontDisplay,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
