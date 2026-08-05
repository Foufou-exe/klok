// Génération PDF pour la paie — un fichier par salarié, sur une plage de
// dates donnée. Le format est volontairement simple :
//
//   • Header   : nom de l'établissement + nom du patron + période
//   • Identité : prénom/nom du salarié + taux horaire (si défini)
//   • Tableau  : une ligne par jour travaillé avec heures nettes
//   • Total    : nombre de jours, total heures, paie brute (si taux défini)
//
// On évite tout asset externe : pas de logo embarqué, juste du texte stylé.
// Le PDF est écrit dans le répertoire temporaire puis partagé via share_plus
// (ouverture du share sheet natif). Le patron envoie le fichier à sa compta
// par mail / Drive / clé USB — on ne fait jamais de réseau.

import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/time_math.dart';
import '../data/db/app_database.dart';
import '../data/repositories/session_repository.dart';

/// Une ligne du tableau "jour par jour" — heures nettes et nombre de
/// sessions ce jour (pour repérer les jours coupés en deux services).
class PayrollDayLine {
  PayrollDayLine({
    required this.date,
    required this.netDuration,
    required this.sessionCount,
  });

  final DateTime date;
  final Duration netDuration;
  final int sessionCount;
}

/// Tout ce qu'il faut pour générer un PDF paie pour UN salarié.
class PayrollData {
  PayrollData({
    required this.employee,
    required this.from,
    required this.to,
    required this.lines,
    required this.totalDuration,
  });

  final Employee employee;
  // En local time — c'est ce qu'on affiche au patron (la persistance reste
  // en UTC côté DB).
  final DateTime from;
  final DateTime to;
  final List<PayrollDayLine> lines;
  final Duration totalDuration;

  int get daysWorked =>
      lines.where((l) => l.netDuration > Duration.zero).length;

  double? grossPay() {
    final cents = employee.hourlyRateCents;
    if (cents == null) return null;
    return (totalDuration.inMinutes / 60.0) * (cents / 100);
  }
}

class PayrollPdfService {
  PayrollPdfService(this._sessions);

  final SessionRepository _sessions;

  /// Calcule les `PayrollDayLine` pour un salarié sur la plage `[from, to]`
  /// (inclusive côté `to`). Les bornes sont en local time ; on convertit en
  /// UTC pour la requête puis on regroupe par jour local.
  Future<PayrollData> compute({
    required Employee employee,
    required DateTime from,
    required DateTime to,
  }) async {
    final start = DateTime(from.year, from.month, from.day).toUtc();
    final end = DateTime(
      to.year,
      to.month,
      to.day,
    ).add(const Duration(days: 1)).toUtc();

    final sessions = await _sessions.sessionsInRange(employee.id, start, end);
    final breaks = await _sessions.breaksForSessions(
      sessions.map((s) => s.id).toList(),
    );

    // On regroupe par jour LOCAL (clef "yyyy-MM-dd"). Une session qui
    // commence à 23:30 et finit à 02:00 est attribuée au jour de début —
    // c'est la convention la plus simple pour la paie restau.
    final byDay = <String, List<SessionWithBreaks>>{};
    for (final s in sessions) {
      final local = s.startedAt.toLocal();
      final key = DateFormat('yyyy-MM-dd').format(local);
      byDay
          .putIfAbsent(key, () => [])
          .add(
            SessionWithBreaks(
              session: s,
              breaks: breaks.where((b) => b.sessionId == s.id).toList(),
            ),
          );
    }

    final lines = <PayrollDayLine>[];
    Duration total = Duration.zero;
    for (final entry in byDay.entries) {
      final firstStart = entry.value.first.session.startedAt.toLocal();
      final dayStart = DateTime(
        firstStart.year,
        firstStart.month,
        firstStart.day,
      );
      final net = sumNet(entry.value);
      total += net;
      lines.add(
        PayrollDayLine(
          date: dayStart,
          netDuration: net,
          sessionCount: entry.value.length,
        ),
      );
    }
    lines.sort((a, b) => a.date.compareTo(b.date));

    return PayrollData(
      employee: employee,
      from: from,
      to: to,
      lines: lines,
      totalDuration: total,
    );
  }

  /// Construit le PDF complet pour un salarié.
  Future<Uint8List> buildPdf({
    required PayrollData data,
    required String establishmentName,
    required String? ownerName,
  }) async {
    final doc = pw.Document(
      title: 'Paie ${data.employee.firstName} ${data.employee.lastName}',
      author: ownerName ?? 'Klok',
    );

    final dateFmt = DateFormat('EEEE d MMMM yyyy', 'fr_FR');
    final shortDateFmt = DateFormat('dd/MM/yyyy');
    final period =
        '${shortDateFmt.format(data.from)} → ${shortDateFmt.format(data.to)}';

    final rate = data.employee.hourlyRateCents != null
        ? '${(data.employee.hourlyRateCents! / 100).toStringAsFixed(2)} €/h'
        : '—';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginTop: 48,
          marginBottom: 48,
          marginLeft: 36,
          marginRight: 36,
        ),
        header: (ctx) => _pdfHeader(
          establishmentName: establishmentName,
          ownerName: ownerName,
          period: period,
        ),
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Généré par Klok · ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
              pw.Text(
                'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        build: (ctx) => [
          pw.SizedBox(height: 12),
          // Bandeau identité salarié
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        '${data.employee.firstName} ${data.employee.lastName}'
                            .trim(),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Taux horaire : $rate',
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Période',
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey600,
                        letterSpacing: 0.6,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      period,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          // Tableau jours travaillés
          if (data.lines.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 30),
              alignment: pw.Alignment.center,
              child: pw.Text(
                'Aucun jour travaillé sur la période.',
                style: pw.TextStyle(
                  fontSize: 12,
                  color: PdfColors.grey600,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.symmetric(
                inside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _th('Jour'),
                    _th('Sessions'),
                    _th('Heures', alignRight: true),
                  ],
                ),
                for (final line in data.lines)
                  pw.TableRow(
                    children: [
                      _td(_capitalize(dateFmt.format(line.date))),
                      _td('${line.sessionCount}'),
                      _td(formatDuration(line.netDuration), alignRight: true),
                    ],
                  ),
              ],
            ),
          pw.SizedBox(height: 18),
          // Récap total
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey900,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'TOTAL',
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey400,
                          letterSpacing: 0.6,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        '${data.daysWorked} jour${data.daysWorked > 1 ? 's' : ''} travaillé${data.daysWorked > 1 ? 's' : ''}',
                        style: pw.TextStyle(
                          fontSize: 12,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      formatDuration(data.totalDuration),
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    if (data.grossPay() != null)
                      pw.Text(
                        '≈ ${data.grossPay()!.toStringAsFixed(2)} € brut',
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: PdfColors.grey300,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 28),
          if (ownerName != null && ownerName.isNotEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.only(top: 14),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                ),
              ),
              child: pw.Text(
                'Document généré par $ownerName · $establishmentName',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ),
        ],
      ),
    );

    return doc.save();
  }

  /// Écrit chaque PDF dans le dossier temp puis ouvre le share sheet pour les
  /// envoyer en une fois (Drive, mail, clé USB...). Renvoie le nombre de
  /// fichiers générés.
  Future<int> generateAndShare({
    required List<PayrollData> bundle,
    required String establishmentName,
    required String? ownerName,
  }) async {
    if (bundle.isEmpty) return 0;
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final files = <XFile>[];
    for (final data in bundle) {
      final bytes = await buildPdf(
        data: data,
        establishmentName: establishmentName,
        ownerName: ownerName,
      );
      final safeName = '${data.employee.firstName}_${data.employee.lastName}'
          .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
      final filename = 'klok_paie_${safeName}_$stamp.pdf';
      final file = File(p.join(dir.path, filename));
      await file.writeAsBytes(bytes);
      files.add(XFile(file.path, mimeType: 'application/pdf'));
    }
    await SharePlus.instance.share(
      ShareParams(
        files: files,
        subject:
            'Paie $establishmentName · ${DateFormat('MM/yyyy').format(bundle.first.from)}',
      ),
    );
    return files.length;
  }
}

// ─────────────────────────────────────────────────────────────
// Helpers PDF
// ─────────────────────────────────────────────────────────────
pw.Widget _pdfHeader({
  required String establishmentName,
  required String? ownerName,
  required String period,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                establishmentName,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (ownerName != null && ownerName.isNotEmpty)
                pw.Text(
                  ownerName,
                  style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
                ),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey900,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              'PAIE',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Container(height: 1, color: PdfColors.grey300),
    ],
  );
}

pw.Widget _th(String text, {bool alignRight = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: pw.Text(
      text.toUpperCase(),
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.grey700,
        letterSpacing: 0.6,
      ),
    ),
  );
}

pw.Widget _td(String text, {bool alignRight = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(fontSize: 11),
    ),
  );
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
