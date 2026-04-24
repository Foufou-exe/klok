// Porte d'accès admin — variante Pastille (PinGate).
//
// Deux modes :
//   • Pas de PIN en DB → création : 2 saisies concordantes sur le pavé.
//   • PIN existant → vérification : 4 chiffres, animation shake à l'erreur.
//
// On gère le PIN en state local (chaîne "1234" max). Chaque pression ajoute
// un chiffre, la croix efface le dernier. Quand on atteint 4 chiffres, on
// déclenche la vérification (ou la validation en mode création) après un
// petit délai visuel de 200 ms — l'utilisateur voit le 4e point s'allumer
// avant de recevoir le verdict.
//
// Ref design : shared/app.jsx (fonction PinGate).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';
import '../../state/admin_session.dart';
import '../../state/providers.dart';

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
              Center(
                child: exists ? const _PinEntry() : const _PinCreate(),
              ),
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

  Future<void> _onDigit(String d) async {
    if (_busy || _pin.length >= 4) return;
    setState(() => _pin = _pin + d);
    if (_pin.length == 4) {
      setState(() => _busy = true);
      // Petit délai : laisser le 4e point s'allumer visuellement.
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final ok = await ref
          .read(adminUnlockedProvider.notifier)
          .unlock(_pin);
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
      }
    }
  }

  void _onBackspace() {
    if (_busy) return;
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
          'Saisis ton PIN à 4 chiffres',
          style: TextStyle(
            fontSize: 13,
            color: KlokTokens.inkSoft,
          ),
        ),
        const SizedBox(height: 28),
        _PinDots(length: 4, filled: _pin.length, error: _error, shake: _shake),
        const SizedBox(height: 28),
        _Keypad(
          onDigit: _onDigit,
          onBackspace: _onBackspace,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Create : deux saisies concordantes
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
    if (_active.length >= 4) return;
    setState(() {
      if (_step == 0) {
        _firstPin = _firstPin + d;
      } else {
        _secondPin = _secondPin + d;
      }
    });
    if (_step == 0 && _firstPin.length == 4) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      setState(() => _step = 1);
    } else if (_step == 1 && _secondPin.length == 4) {
      setState(() => _busy = true);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (_firstPin == _secondPin) {
        await ref.read(settingsRepositoryProvider).setPin(_firstPin);
        ref.invalidate(hasAdminPinProvider);
        await ref
            .read(adminUnlockedProvider.notifier)
            .unlock(_firstPin);
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
              ? '4 chiffres. Tu les utiliseras pour ouvrir l\'admin.'
              : 'Retape les 4 mêmes chiffres.',
          style: TextStyle(
            fontSize: 13,
            color: KlokTokens.inkSoft,
          ),
        ),
        const SizedBox(height: 28),
        _PinDots(
          length: 4,
          filled: _active.length,
          error: _error,
          shake: _shake,
        ),
        const SizedBox(height: 28),
        _Keypad(
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
      child: Icon(
        Icons.lock_outline,
        size: 24,
        color: KlokTokens.bordeaux,
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.length,
    required this.filled,
    required this.error,
    required this.shake,
  });

  final int length;
  final int filled;
  final bool error;
  final Animation<double> shake;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shake,
      builder: (ctx, child) {
        // Courbe sinusoïdale amortie → oscillation "no/non" de 8 px.
        final t = shake.value;
        final dx = t == 0 ? 0.0 : 8 * (1 - t) * (t * 20).remainder(2) - 8 * (1 - t);
        return Transform.translate(
          offset: Offset(dx, 0),
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(length, (i) {
          final isFilled = i < filled;
          final color = error
              ? KlokTokens.danger
              : KlokTokens.bordeaux;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isFilled ? color : Colors.transparent,
                border: Border.all(
                  color: isFilled ? color : KlokTokens.border,
                  width: 1.5,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    // 4 lignes × 3 colonnes, dernière ligne : [vide, 0, backspace].
    return SizedBox(
      width: 72 * 3 + 10 * 2,
      child: Column(
        children: [
          _row(['1', '2', '3']),
          const SizedBox(height: 10),
          _row(['4', '5', '6']),
          const SizedBox(height: 10),
          _row(['7', '8', '9']),
          const SizedBox(height: 10),
          _row(['', '0', 'back']),
        ],
      ),
    );
  }

  Widget _row(List<String> items) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (items[i] == '')
            const SizedBox(width: 72, height: 72)
          else if (items[i] == 'back')
            _KeyBackspace(onTap: onBackspace)
          else
            _KeyDigit(value: items[i], onTap: () => onDigit(items[i])),
          if (i < items.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _KeyDigit extends StatelessWidget {
  const _KeyDigit({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KlokTokens.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: KlokTokens.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: KlokTokens.border),
          ),
          width: 72,
          height: 72,
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: KlokTokens.fontDisplay,
                fontSize: 26,
                fontWeight: FontWeight.w400,
                color: KlokTokens.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyBackspace extends StatelessWidget {
  const _KeyBackspace({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: KlokTokens.border),
          ),
          width: 72,
          height: 72,
          child: Icon(
            Icons.backspace_outlined,
            size: 20,
            color: KlokTokens.inkSoft,
          ),
        ),
      ),
    );
  }
}
