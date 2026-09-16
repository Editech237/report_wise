import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;

import 'report_card.dart';

/// Single-student bulletin as a vector PDF (mirrors ReportCardWidget).
Future<Uint8List> buildReportPdf(ReportCardData data) async {
  final doc = pw.Document(theme: await _pdfTheme());
  final logo = await _networkImage(data.logoUrl);
  final signature = await _networkImage(data.principalSignatureUrl);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => _buildPage(data, logo, signature),
    ),
  );
  return doc.save();
}

/// Whole-class bulletins as ONE multi-page PDF (a page per student).
Future<Uint8List> buildReportPdfBulk(List<ReportCardData> dataList) async {
  final doc = pw.Document(theme: await _pdfTheme());
  for (final data in dataList) {
    final logo = await _networkImage(data.logoUrl);
    final signature = await _networkImage(data.principalSignatureUrl);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => _buildPage(data, logo, signature),
      ),
    );
  }
  return doc.save();
}

Future<pw.ThemeData> _pdfTheme() async {
  try {
    final base = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Manrope-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Manrope-Bold.ttf'),
    );
    return pw.ThemeData.withFont(base: base, bold: bold);
  } catch (_) {
    // Unit tests can run without an initialized Flutter asset bundle.
    return pw.ThemeData();
  }
}

Future<pw.MemoryImage?> _networkImage(String? url) async {
  if (url == null || url.trim().isEmpty) return null;
  try {
    final client = HttpClient();
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) return null;
    final bytes = <int>[];
    await for (final chunk in response) bytes.addAll(chunk);
    client.close();
    return pw.MemoryImage(Uint8List.fromList(bytes));
  } catch (_) {
    return null;
  }
}

pw.Widget _buildPage(
  ReportCardData d,
  pw.MemoryImage? logo,
  pw.MemoryImage? signature,
) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(9),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.green900, width: 2),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'RÉPUBLIQUE DU CAMEROUN',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        pw.Text(
          'Paix - Travail - Patrie',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'MINISTÈRE DES ENSEIGNEMENTS SECONDAIRES',
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.Text(
          'MINISTRY OF SECONDARY EDUCATION',
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 8.5),
        ),
        pw.SizedBox(height: 8),
        if (logo != null)
          pw.Center(
            child: pw.Image(
              logo,
              width: 54,
              height: 54,
              fit: pw.BoxFit.contain,
            ),
          ),
        pw.Text(
          d.schoolName,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        if (d.schoolAddress != null && d.schoolAddress!.isNotEmpty)
          pw.Text(
            d.schoolAddress!,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 9.5),
          ),
        pw.SizedBox(height: 8),
        pw.Text(
          'BULLETIN DE NOTES / REPORT CARD',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          '${d.academicYearName} - ${d.periodLabel}',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black),
          ),
          child: pw.Wrap(
            spacing: 20,
            runSpacing: 2,
            children: [
              _info('Nom / Name', d.studentName),
              if (d.matricule != null) _info('Matricule', d.matricule!),
              _info(
                'Date de naissance',
                d.dateOfBirth == null ? '-' : _fmtDate(d.dateOfBirth!),
              ),
              if (d.placeOfBirth != null)
                _info('Lieu de naissance', d.placeOfBirth!),
              if (d.guardianName != null)
                _info('Parent / Tuteur', d.guardianName!),
              if (d.guardianPhone != null)
                _info('Contact parent', d.guardianPhone!),
              _info('Redoublant', d.repeater ? 'Oui / Yes' : 'Non / No'),
              if (d.gender != null) _info('Sexe', d.gender!),
              _info('Classe', d.className),
              if (d.seriesName != null) _info('Série', d.seriesName!),
              if (d.specialtyName != null)
                _info('Spécialité', d.specialtyName!),
              _info('Nb matières', '${d.numberOfSubjects}'),
              _info('Nb réussites', '${d.numberOfPassed}'),
              if (d.classMasterName != null)
                _info('Professeur principal', d.classMasterName!),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.2),
            1: pw.FixedColumnWidth(38),
            2: pw.FixedColumnWidth(38),
            3: pw.FixedColumnWidth(42),
            4: pw.FixedColumnWidth(28),
            5: pw.FixedColumnWidth(44),
            6: pw.FixedColumnWidth(32),
            7: pw.FlexColumnWidth(1.7),
            8: pw.FlexColumnWidth(1.7),
          },
          children: [
            _row(
              [
                'SUBJECT NAME\nDISCIPLINE',
                d.sequenceLabels.elementAtOrNull(0) ?? 'Seq. X',
                d.sequenceLabels.elementAtOrNull(1) ?? 'Seq. Y',
                'AVERAGE\nMOY. TR.',
                'Coef',
                'TOTAL\nAV X C',
                'POS.\nRANG',
                "TEACHER'S NAME",
                "TEACHER'S REMARK",
              ],
              bold: true,
              fill: PdfColors.grey300,
            ),
            for (var i = 0; i < d.subjects.length; i++)
              _row(
                [
                  d.subjects[i].name,
                  _fmt(d.subjects[i].sequenceAverages.elementAtOrNull(0)),
                  _fmt(d.subjects[i].sequenceAverages.elementAtOrNull(1)),
                  _fmt(d.subjects[i].average),
                  _fmt(d.subjects[i].coefficient),
                  _fmt(d.subjects[i].points),
                  d.subjects[i].rank?.toString() ?? '-',
                  d.subjects[i].teacherName ?? '-',
                  d.subjects[i].remark,
                ],
                redCols: (d.subjects[i].average ?? 10) < 10
                    ? const {1, 2, 3, 5, 6, 8}
                    : const {},
                centerCols: const {1, 2, 3, 4, 5, 6},
              ),
            _row(
              [
                'TOTAL',
                '',
                '',
                '',
                '',
                _fmt(d.totalCoefficients),
                _fmt(d.totalWeightedPoints),
                '',
                '',
              ],
              bold: true,
              centerCols: const {0, 2, 3, 4, 5, 6},
              fill: PdfColors.grey200,
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        _disciplinaryRecord(d),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _avgBox('Moyenne Générale', _fmt(d.generalAverage), flex: 2),
            _avgBox('Moyenne de la classe', _fmt(d.classAverage), flex: 2),
            _avgBox('Rang', d.rank == null ? '-' : '${d.rank}', flex: 1),
            _avgBox('Appréciation', d.appreciation, flex: 2),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Appréciations / Comments',
          style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        for (final label in const [
          'Le Professeur / Teacher:',
          'Le Professeur Principal / Class Teacher:',
          'Le Chef d\'Établissement / Principal:',
        ])
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 5),
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            _sign('Le Professeur'),
            _sign('Le Professeur Principal'),
            _sign(
              'Le Chef d\'Établissement',
              signature: signature,
              principalName: d.principalName,
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _info(String label, String value) {
  return pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Text(
        '$label: ',
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
    ],
  );
}

pw.TableRow _row(
  List<String> cells, {
  bool bold = false,
  Set<int> centerCols = const {},
  Set<int> redCols = const {},
  PdfColor? fill,
}) {
  return pw.TableRow(
    decoration: fill == null ? null : pw.BoxDecoration(color: fill),
    children: [
      for (var i = 0; i < cells.length; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: pw.Text(
            cells[i],
            textAlign: centerCols.contains(i)
                ? pw.TextAlign.center
                : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: redCols.contains(i) ? PdfColors.red : PdfColors.black,
            ),
          ),
        ),
    ],
  );
}

pw.Widget _avgBox(String label, String value, {int flex = 1}) {
  return pw.Expanded(
    flex: flex,
    child: pw.Container(
      margin: const pw.EdgeInsets.only(right: 5),
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            label,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8.5),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _disciplinaryRecord(ReportCardData d) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'DISCIPLINARY RECORD / DOSSIER DISCIPLINAIRE',
        style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 2),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black),
        columnWidths: const {
          0: pw.FlexColumnWidth(),
          1: pw.FixedColumnWidth(35),
        },
        children: [
          _row(
            ["No. of absences / Nr. d'absences", '${d.absences}'],
            centerCols: const {1},
          ),
          _row(
            [
              'Disciplinary council / Conseil disciplinaire',
              '${d.disciplinaryCouncils}',
            ],
            centerCols: const {1},
          ),
          _row(
            ['Warning / Avertissement', '${d.warnings}'],
            centerCols: const {1},
          ),
          _row(['Suspension', '${d.suspensions}'], centerCols: const {1}),
        ],
      ),
    ],
  );
}

pw.Widget _sign(
  String label, {
  pw.MemoryImage? signature,
  String? principalName,
}) {
  return pw.Expanded(
    child: pw.Column(
      children: [
        pw.Text(
          principalName == null ? label : '$label: $principalName',
          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
        ),
        if (signature != null)
          pw.Image(signature, width: 80, height: 28, fit: pw.BoxFit.contain),
        pw.SizedBox(height: signature == null ? 24 : 4),
        pw.Text('Signature', style: const pw.TextStyle(fontSize: 8.5)),
      ],
    ),
  );
}

String _fmt(double? v) => v == null
    ? '-'
    : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2));

String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
