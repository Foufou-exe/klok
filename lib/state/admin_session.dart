import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

class AdminSessionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<bool> unlock(String pin) async {
    final ok = await ref.read(settingsRepositoryProvider).verifyPin(pin);
    if (ok) state = true;
    return ok;
  }

  void lock() => state = false;
}

final adminUnlockedProvider =
    NotifierProvider<AdminSessionNotifier, bool>(AdminSessionNotifier.new);
