import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/admin_session.dart';
import '../../state/providers.dart';

class AdminGateScreen extends ConsumerWidget {
  const AdminGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPin = ref.watch(hasAdminPinProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accès administrateur'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: hasPin.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (exists) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: exists ? const _PinEntry() : const _PinCreate(),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinEntry extends ConsumerStatefulWidget {
  const _PinEntry();

  @override
  ConsumerState<_PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends ConsumerState<_PinEntry> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.length < 4) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref
        .read(adminUnlockedProvider.notifier)
        .unlock(_controller.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      context.go('/admin/home');
    } else {
      setState(() {
        _error = 'Code incorrect';
        _controller.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline, size: 64),
        const SizedBox(height: 16),
        Text('Saisissez le code administrateur',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 24),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          autofocus: true,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, letterSpacing: 16),
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            counterText: '',
            errorText: _error,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Valider'),
        ),
      ],
    );
  }
}

class _PinCreate extends ConsumerStatefulWidget {
  const _PinCreate();

  @override
  ConsumerState<_PinCreate> createState() => _PinCreateState();
}

class _PinCreateState extends ConsumerState<_PinCreate> {
  final _pin1 = TextEditingController();
  final _pin2 = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin1.dispose();
    _pin2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_pin1.text.length < 4) {
      setState(() => _error = 'Le code doit faire au moins 4 chiffres.');
      return;
    }
    if (_pin1.text != _pin2.text) {
      setState(() => _error = 'Les codes ne correspondent pas.');
      return;
    }
    setState(() => _busy = true);
    await ref.read(settingsRepositoryProvider).setPin(_pin1.text);
    ref.invalidate(hasAdminPinProvider);
    await ref.read(adminUnlockedProvider.notifier).unlock(_pin1.text);
    if (!mounted) return;
    context.go('/admin/home');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.key_outlined, size: 64),
        const SizedBox(height: 16),
        Text('Définir un code administrateur',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text(
          'Ce code protège l\'accès aux réglages, exports et sauvegardes.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        _pinField(_pin1, 'Nouveau code'),
        const SizedBox(height: 16),
        _pinField(_pin2, 'Confirmer'),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Créer le code'),
        ),
      ],
    );
  }

  Widget _pinField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLength: 8,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 24, letterSpacing: 12),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
    );
  }
}
