import '../data/db/app_database.dart';

class SessionWithBreaks {
  SessionWithBreaks({required this.session, required this.breaks});

  final WorkSession session;
  final List<Break> breaks;

  Duration get grossDuration {
    final end = session.endedAt ?? DateTime.now().toUtc();
    return end.difference(session.startedAt);
  }

  Duration get breakDuration {
    var total = Duration.zero;
    for (final b in breaks) {
      final end = b.endedAt ?? DateTime.now().toUtc();
      total += end.difference(b.startedAt);
    }
    return total;
  }

  Duration get netDuration {
    final gross = grossDuration;
    final breaks = breakDuration;
    final net = gross - breaks;
    return net.isNegative ? Duration.zero : net;
  }

  bool get hasTimeAnomaly => grossDuration.isNegative;
}

Duration sumNet(Iterable<SessionWithBreaks> sessions) {
  return sessions.fold(Duration.zero, (acc, s) => acc + s.netDuration);
}

Map<DateTime, List<SessionWithBreaks>> groupByLocalDay(
  Iterable<SessionWithBreaks> items,
) {
  final map = <DateTime, List<SessionWithBreaks>>{};
  for (final item in items) {
    final local = item.session.startedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    map.putIfAbsent(day, () => []).add(item);
  }
  return map;
}
