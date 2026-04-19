import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/time_math.dart';
import '../data/db/app_database.dart';

class PayrollReport {
  PayrollReport({
    required this.employee,
    required this.from,
    required this.to,
    required this.sessions,
    required this.breaks,
  });

  final Employee employee;
  final DateTime from;
  final DateTime to;
  final List<WorkSession> sessions;
  final List<Break> breaks;

  List<SessionWithBreaks> get joined {
    final byId = <int, List<Break>>{};
    for (final b in breaks) {
      byId.putIfAbsent(b.sessionId, () => []).add(b);
    }
    return [
      for (final s in sessions)
        SessionWithBreaks(session: s, breaks: byId[s.id] ?? const []),
    ];
  }
}

class PdfExportService {
  Future<Uint8List> buildPayroll(PayrollReport report) async {
    final doc = pw.Document();
    final df = DateFormat('EEEE d MMMM yyyy', 'fr_FR');
    final dfShort = DateFormat('dd/MM/yyyy', 'fr_FR');
    final tf = DateFormat.Hm('fr_FR');

    final byDay = groupByLocalDay(report.joined);
    final sortedDays = byDay.keys.toList()..sort();
    final totalNet = sumNet(report.joined);

    final totalGross = report.joined.fold<Duration>(
        Duration.zero, (acc, s) => acc + s.grossDuration);
    final totalBreak = report.joined.fold<Duration>(
        Duration.zero, (acc, s) => acc + s.breakDuration);

    final grossPay = _computeGrossPay(
      employee: report.employee,
      netDuration: totalNet,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          _header(report, df, dfShort),
          pw.SizedBox(height: 24),
          _summary(totalGross, totalBreak, totalNet, grossPay),
          pw.SizedBox(height: 24),
          pw.Text('Détail journalier',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          if (sortedDays.isEmpty)
            pw.Text('Aucune activité enregistrée sur la période.')
          else
            _dailyTable(byDay, sortedDays, tf),
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.Text(
            'Document généré par klok le ${dfShort.format(DateTime.now())}.',
            style: const pw.TextStyle(
                fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _header(PayrollReport r, DateFormat df, DateFormat dfShort) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Relevé d\'heures',
            style: pw.TextStyle(
                fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('${r.employee.firstName} ${r.employee.lastName}',
            style: const pw.TextStyle(fontSize: 14)),
        pw.SizedBox(height: 2),
        pw.Text(
            'Période : du ${dfShort.format(r.from)} au ${dfShort.format(r.to)}',
            style: const pw.TextStyle(fontSize: 11)),
      ],
    );
  }

  pw.Widget _summary(
    Duration totalGross,
    Duration totalBreak,
    Duration totalNet,
    String? grossPay,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _kv('Total brut', _fmt(totalGross)),
          _kv('Pauses', _fmt(totalBreak)),
          _kv('Total net travaillé', _fmt(totalNet), bold: true),
          if (grossPay != null) _kv('Rémunération brute estimée', grossPay),
        ],
      ),
    );
  }

  pw.Widget _kv(String k, String v, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(k,
              style: pw.TextStyle(
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(v,
              style: pw.TextStyle(
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  pw.Widget _dailyTable(
    Map<DateTime, List<SessionWithBreaks>> byDay,
    List<DateTime> days,
    DateFormat tf,
  ) {
    final dayFmt = DateFormat('EEE dd/MM', 'fr_FR');
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(1.5),
        3: pw.FlexColumnWidth(1.5),
        4: pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _th('Jour'),
            _th('Plages'),
            _th('Brut'),
            _th('Pauses'),
            _th('Net'),
          ],
        ),
        for (final d in days)
          _dayRow(d, byDay[d]!, dayFmt, tf),
      ],
    );
  }

  pw.TableRow _dayRow(
    DateTime day,
    List<SessionWithBreaks> items,
    DateFormat dayFmt,
    DateFormat tf,
  ) {
    final slots = items.map((s) {
      final start = tf.format(s.session.startedAt.toLocal());
      final end = s.session.endedAt != null
          ? tf.format(s.session.endedAt!.toLocal())
          : '…';
      return '$start – $end';
    }).join('\n');
    final gross = items.fold<Duration>(
        Duration.zero, (acc, s) => acc + s.grossDuration);
    final pauses = items.fold<Duration>(
        Duration.zero, (acc, s) => acc + s.breakDuration);
    final net = items.fold<Duration>(
        Duration.zero, (acc, s) => acc + s.netDuration);

    return pw.TableRow(
      children: [
        _td(dayFmt.format(day)),
        _td(slots),
        _td(_fmt(gross)),
        _td(_fmt(pauses)),
        _td(_fmt(net), bold: true),
      ],
    );
  }

  pw.Widget _th(String t) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(t,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
    );
  }

  pw.Widget _td(String t, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(t,
          style: pw.TextStyle(
              fontSize: 10,
              fontWeight:
                  bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${h}h$m';
  }

  String? _computeGrossPay(
      {required Employee employee, required Duration netDuration}) {
    final cents = employee.hourlyRateCents;
    if (cents == null) return null;
    final hours = netDuration.inMinutes / 60.0;
    final euros = hours * (cents / 100);
    return NumberFormat.currency(locale: 'fr_FR', symbol: '€').format(euros);
  }
}
