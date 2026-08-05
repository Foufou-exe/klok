/// Rappel de sauvegarde.
///
/// La tablette est le seul exemplaire des données : pas de réplication, pas de
/// cloud. Une tablette perdue, volée ou noyée sans sauvegarde récente, c'est
/// toute l'historique de paie qui disparaît. Le patron choisit une fréquence
/// dans les Réglages ; cette logique dit si l'échéance est dépassée.
library;

enum BackupReminderFreq {
  none(key: 'none', label: 'Aucun rappel', interval: null),
  weekly(
    key: 'weekly',
    label: 'Hebdomadaire · lundi',
    interval: Duration(days: 7),
  ),
  monthly(
    key: 'monthly',
    label: 'Mensuel · 1er du mois',
    interval: Duration(days: 30),
  );

  const BackupReminderFreq({
    required this.key,
    required this.label,
    required this.interval,
  });

  final String key;
  final String label;

  /// Délai au-delà duquel la sauvegarde est considérée en retard. `null` quand
  /// le rappel est désactivé.
  final Duration? interval;

  /// Valeur par défaut à l'installation : hebdomadaire.
  static const fallback = BackupReminderFreq.weekly;

  static BackupReminderFreq parse(String? raw) {
    for (final f in BackupReminderFreq.values) {
      if (f.key == raw) return f;
    }
    return fallback;
  }
}

/// État du rappel, prêt à être affiché.
enum BackupReminderStatus {
  /// Rappel désactivé par le patron.
  disabled,

  /// Sauvegarde récente : rien à signaler.
  ok,

  /// L'intervalle choisi est dépassé.
  overdue,

  /// Aucune sauvegarde n'a jamais été faite.
  never;

  bool get needsAttention =>
      this == BackupReminderStatus.overdue ||
      this == BackupReminderStatus.never;
}

/// Détermine si une sauvegarde est due.
///
/// [lastBackupAt] est la valeur brute stockée en réglages (ISO8601), `null` si
/// aucune sauvegarde n'a jamais eu lieu. [now] est injectable pour les tests.
BackupReminderStatus backupReminderStatus({
  required String? lastBackupAtIso,
  required BackupReminderFreq freq,
  DateTime? now,
}) {
  final interval = freq.interval;
  if (interval == null) return BackupReminderStatus.disabled;

  final last = lastBackupAtIso == null
      ? null
      : DateTime.tryParse(lastBackupAtIso);
  if (last == null) return BackupReminderStatus.never;

  final reference = (now ?? DateTime.now()).toUtc();
  final elapsed = reference.difference(last.toUtc());

  // Horloge reculée (elapsed négatif) : on ne crie pas au loup, la sauvegarde
  // est récente du point de vue des données.
  if (elapsed.isNegative) return BackupReminderStatus.ok;

  return elapsed > interval
      ? BackupReminderStatus.overdue
      : BackupReminderStatus.ok;
}
