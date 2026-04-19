import 'package:intl/intl.dart';

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${h}h$m';
}

String formatHHmm(DateTime dt) {
  return DateFormat.Hm('fr_FR').format(dt.toLocal());
}

String formatDate(DateTime dt) {
  return DateFormat('EEE d MMM', 'fr_FR').format(dt.toLocal());
}

String formatDateFull(DateTime dt) {
  return DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(dt.toLocal());
}

String formatMoneyCents(int? cents) {
  if (cents == null) return '—';
  final euros = cents / 100;
  return NumberFormat.currency(locale: 'fr_FR', symbol: '€').format(euros);
}
