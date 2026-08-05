// Porte d'accès admin — variante Pastille (PinGate).
//
// Deux modes :
//   • Pas de PIN en DB → création : 2 saisies concordantes sur le pavé.
//     (En pratique l'onboarding crée déjà le PIN, mais on conserve ce
//     fallback si on entre en mode "réinitialisation" depuis Réglages.)
//   • PIN existant → vérification : `kAdminPinLength` chiffres,
//     animation shake à l'erreur.
//
// Les chiffres du pavé sont mélangés aléatoirement à chaque ouverture de la
// gate (anti shoulder-surfing). Le shuffle est fait une fois en `initState`
// — remélanger à chaque touche serait insupportable côté UX.
//
// Ref design : shared/app.jsx (fonction PinGate).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';
import '../../state/admin_session.dart';
import '../../state/providers.dart';
import '../onboarding/klok_onboarding.dart' show kAdminPinLength;
import 'widgets/pin_keypad.dart';

class AdminGateScreen extends ConsumerWidget {
  const AdminGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPin = ref.watch(hasAdminPinProvider);
    return Scaffold(
      backgroundColor: KlokTokens.bg,
      body: SafeArea(
        child: hasPin.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: KlokTokens.bordeaux),
          ),
          error: (e, _) => Center(child: Text('Erreur : $e')),
          data: (exists) => Stack(
            children: [
              // Bouton retour en overlay (coin haut-gauche).
              Positioned(
                left: 24,
                top: 24,
                child: _BackButton(
                  label: 'Retour',
                  onTap: () => context.go('/'),
                ),
              ),
              Center(child: exists ? const _PinEntry() : const _PinCreate()),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chevron_left, size: 16, color: KlokTokens.inkSoft),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: KlokTokens.inkSoft,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Entry : vérification du PIN existant
// ─────────────────────────────────────────────────────────────
class _PinEntry extends ConsumerStatefulWidget {
  const _PinEntry();

  @override
  ConsumerState<_PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends ConsumerState<_PinEntry>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _error = false;
  bool _busy = false;
  // Temporisation anti-force-brute restante (cf. SettingsRepository). Tant
  // qu'elle est non nulle, le keypad est inerte et on affiche le décompte.
  Duration _lockout = Duration.zero;
  Timer? _lockoutTicker;
  late final AnimationController _shake;
  // Shuffle figé pour la durée de la session de saisie. Si la gate se
  // referme et se ré-ouvre, on aura un nouvel ordre.
  late final List<String> _digits = randomKeypadDigits();

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    // Le compteur d'échecs est persisté : redémarrer l'app ne remet pas les
    // compteurs à zéro, donc on peut arriver ici déjà temporisé.
    _refreshLockout();
  }

  @override
  void dispose() {
    _lockoutTicker?.cancel();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _refreshLockout() async {
    final left = await ref.read(settingsRepositoryProvider).remainingLockout();
    if (!mounted) return;
    setState(() => _lockout = left);
    _lockoutTicker?.cancel();
    if (left > Duration.zero) {
      _lockoutTicker = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        final next = _lockout - const Duration(seconds: 1);
        setState(() => _lockout = next.isNegative ? Duration.zero : next);
        if (_lockout == Duration.zero) t.cancel();
      });
    }
  }

  Future<void> _onDigit(String d) async {
    if (_busy || _locked || _pin.length >= kAdminPinLength) return;
    setState(() => _pin = _pin + d);
    if (_pin.length == kAdminPinLength) {
      setState(() => _busy = true);
      // Petit délai : laisser le dernier point s'allumer visuellement.
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final ok = await ref.read(adminUnlockedProvider.notifier).unlock(_pin);
      if (!mounted) return;
      if (ok) {
        context.go('/admin/home');
      } else {
        setState(() => _error = true);
        _shake.forward(from: 0);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        setState(() {
          _pin = '';
          _error = false;
          _busy = false;
        });
        await _refreshLockout();
      }
    }
  }

  bool get _locked => _lockout > Duration.zero;

  void _onBackspace() {
    if (_busy || _locked) return;
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderIcon(),
        const SizedBox(height: 14),
        Text(
          'Accès patron',
          style: TextStyle(
            fontFamily: KlokTokens.fontDisplay,
            fontSize: 26,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.6,
            color: KlokTokens.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _locked
              ? 'Trop d\'essais — patiente ${_formatLockout(_lockout)}'
              : 'Saisis ton PIN à $kAdminPinLength chiffres',
          style: TextStyle(
            fontSize: 13,
            color: _locked ? KlokTokens.danger : KlokTokens.inkSoft,
            fontWeight: _locked ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        const SizedBox(height: 28),
        PinDots(
          length: kAdminPinLength,
          filled: _pin.length,
          error: _error,
          shake: _shake,
        ),
        const SizedBox(height: 28),
        // Grisé pendant la temporisation : le keypad reste visible pour ne pas
        // faire sauter la mise en page, mais n'accepte plus rien.
        Opacity(
          opacity: _locked ? 0.35 : 1,
          child: IgnorePointer(
            ignoring: _locked,
            child: PinKeypad(
              digits: _digits,
              onDigit: _onDigit,
              onBackspace: _onBackspace,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Create : deux saisies concordantes (fallback sans onboarding)
// ─────────────────────────────────────────────────────────────
class _PinCreate extends ConsumerStatefulWidget {
  const _PinCreate();

  @override
  ConsumerState<_PinCreate> createState() => _PinCreateState();
}

class _PinCreateState extends ConsumerState<_PinCreate>
    with SingleTickerProviderStateMixin {
  String _firstPin = '';
  String _secondPin = '';
  // 0: saisie 1, 1: saisie 2
  int _step = 0;
  bool _error = false;
  bool _busy = false;
  late final AnimationController _shake;
  // Pour la création on garde l'ordre standard (plus simple à mémoriser
  // pour l'utilisateur qui saisit DEUX fois le même code).
  static const _digits = kStandardKeypadDigits;

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

  String get _active => _step == 0 ? _firstPin : _secondPin;

  Future<void> _onDigit(String d) async {
    if (_busy) return;
    if (_active.length >= kAdminPinLength) return;
    setState(() {
      if (_step == 0) {
        _firstPin = _firstPin + d;
      } else {
        _secondPin = _secondPin + d;
      }
    });
    if (_step == 0 && _firstPin.length == kAdminPinLength) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      setState(() => _step = 1);
    } else if (_step == 1 && _secondPin.length == kAdminPinLength) {
      setState(() => _busy = true);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (_firstPin == _secondPin) {
        await ref.read(settingsRepositoryProvider).setPin(_firstPin);
        ref.invalidate(hasAdminPinProvider);
        await ref.read(adminUnlockedProvider.notifier).unlock(_firstPin);
        if (!mounted) return;
        context.go('/admin/home');
      } else {
        setState(() => _error = true);
        _shake.forward(from: 0);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        setState(() {
          _firstPin = '';
          _secondPin = '';
          _step = 0;
          _error = false;
          _busy = false;
        });
      }
    }
  }

  void _onBackspace() {
    if (_busy) return;
    setState(() {
      if (_step == 1 && _secondPin.isNotEmpty) {
        _secondPin = _secondPin.substring(0, _secondPin.length - 1);
      } else if (_step == 1 && _secondPin.isEmpty) {
        _step = 0;
        _firstPin = _firstPin.substring(0, _firstPin.length - 1);
      } else if (_firstPin.isNotEmpty) {
        _firstPin = _firstPin.substring(0, _firstPin.length - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderIcon(),
        const SizedBox(height: 14),
        Text(
          _step == 0 ? 'Créer ton PIN patron' : 'Confirme ton PIN',
          style: TextStyle(
            fontFamily: KlokTokens.fontDisplay,
            fontSize: 26,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.6,
            color: KlokTokens.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _step == 0
              ? "$kAdminPinLength chiffres. Tu les utiliseras pour ouvrir l'admin."
              : 'Retape les $kAdminPinLength mêmes chiffres.',
          style: TextStyle(fontSize: 13, color: KlokTokens.inkSoft),
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
          digits: _digits,
          onDigit: _onDigit,
          onBackspace: _onBackspace,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// UI building blocks
// ─────────────────────────────────────────────────────────────
class _HeaderIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: KlokTokens.bg,
        border: Border.all(color: KlokTokens.border),
      ),
      child: Icon(Icons.lock_outline, size: 24, color: KlokTokens.bordeaux),
    );
  }
}

/// Décompte de la temporisation, arrondi à la seconde supérieure pour ne
/// jamais afficher « 0 s » alors que le clavier est encore inerte.
String _formatLockout(Duration d) {
  final total = d.inMilliseconds <= 0 ? 0 : (d.inMilliseconds / 1000).ceil();
  if (total < 60) return '$total s';
  final m = total ~/ 60;
  final s = total % 60;
  return s == 0 ? '$m min' : '$m min $s s';
}
