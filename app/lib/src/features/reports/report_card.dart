import 'package:flutter/material.dart';

import '../../data/entities.dart';

/// Data needed to render a Cameroonian report card (bulletin de notes).
/// Built from an immutable PeriodResult + school/class/period context, so the
/// rendered card always reflects the snapshot that produced the results.
class ReportCardData {
  final String schoolName;
  final String? schoolAddress;
  final String? logoUrl;
  final String? principalName;
  final String? principalSignatureUrl;
  final String academicYearName;
  final String periodLabel;
  final String studentName;
  final String? matricule;
  final DateTime? dateOfBirth;
  final String? placeOfBirth;
  final String? gender;
  final String? guardianName;
  final String? guardianPhone;
  final bool repeater;
  final String className;
  final String? seriesName;
  final String? specialtyName;
  final String? classMasterName;
  final double? generalAverage;
  final double? totalWeightedPoints;
  final double? totalCoefficients;
  final double? classAverage;
  final int? rank;
  final String appreciation;
  final int numberOfSubjects;
  final int numberOfPassed;
  final List<ReportSubjectRow> subjects;
  final int absences;
  final int disciplinaryCouncils;
  final int warnings;
  final int suspensions;
  final List<String> sequenceLabels;

  ReportCardData({
    required this.schoolName,
    this.schoolAddress,
    this.logoUrl,
    this.principalName,
    this.principalSignatureUrl,
    required this.academicYearName,
    required this.periodLabel,
    required this.studentName,
    this.matricule,
    this.dateOfBirth,
    this.placeOfBirth,
    this.gender,
    this.guardianName,
    this.guardianPhone,
    this.repeater = false,
    required this.className,
    this.seriesName,
    this.specialtyName,
    this.classMasterName,
    this.generalAverage,
    this.totalWeightedPoints,
    this.totalCoefficients,
    this.classAverage,
    this.rank,
    this.appreciation = '—',
    this.numberOfSubjects = 0,
    this.numberOfPassed = 0,
    this.subjects = const [],
    this.absences = 0,
    this.disciplinaryCouncils = 0,
    this.warnings = 0,
    this.suspensions = 0,
    this.sequenceLabels = const ['Seq. 1', 'Seq. 2'],
  });
}

class ReportSubjectRow {
  final String name;
  final String? teacherName;
  final double? coefficient;
  final double? average;
  final double? points;
  final int? rank;
  final String remark;
  final List<double?> sequenceAverages;

  const ReportSubjectRow({
    required this.name,
    this.teacherName,
    this.coefficient,
    this.average,
    this.points,
    this.rank,
    this.remark = '-',
    this.sequenceAverages = const [],
  });
}

/// Cameroon appreciation from a general average (out of 20).
String appreciationFor(double avg) {
  if (avg >= 18) return 'Excellent';
  if (avg >= 16) return 'Très bien';
  if (avg >= 14) return 'Bien';
  if (avg >= 12) return 'Assez bien';
  if (avg >= 10) return 'Passable';
  return 'Insuffisant';
}

/// Builds report data from a stored PeriodResult (the immutable snapshot).
ReportCardData buildReportCardData({
  required School school,
  required String academicYearName,
  required String periodLabel,
  required SchoolClass cls,
  required PeriodResult result,
  Student? student,
  Map<String, String> subjectTeacherNames = const {},
  String? classMasterName,
  Map<String, List<double?>> subjectSequenceAverages = const {},
  List<String> sequenceLabels = const ['Seq. 1', 'Seq. 2'],
}) {
  final avg = result.generalAverage;
  final subjects = result.subjects
      .map(
        (s) => ReportSubjectRow(
          name: s.subjectName ?? s.subjectId,
          teacherName: subjectTeacherNames[s.subjectId],
          coefficient: s.coefficient,
          average: s.subjectAverage,
          points: s.weightedPoints,
          rank: s.rankInSubject,
          remark: s.subjectAverage == null
              ? '-'
              : appreciationFor(s.subjectAverage!),
          sequenceAverages: subjectSequenceAverages[s.subjectId] ?? const [],
        ),
      )
      .toList();
  return ReportCardData(
    schoolName: school.name,
    schoolAddress: school.address,
    logoUrl: school.logoUrl,
    principalName: school.principalName,
    principalSignatureUrl: school.principalSignatureUrl,
    academicYearName: academicYearName,
    periodLabel: periodLabel,
    studentName: result.studentName,
    matricule: result.matricule,
    dateOfBirth: student?.dateOfBirth,
    placeOfBirth: student?.placeOfBirth,
    gender: student?.gender,
    guardianName: student?.guardianName,
    guardianPhone: student?.guardianPhone,
    repeater: student?.repeater ?? false,
    className: cls.name,
    seriesName: cls.seriesName,
    specialtyName: cls.specialtyName,
    classMasterName: classMasterName,
    generalAverage: avg,
    totalWeightedPoints: result.totalWeightedPoints,
    totalCoefficients: result.totalCoefficients,
    classAverage: result.classAverage,
    rank: result.rank,
    appreciation: avg == null ? '—' : appreciationFor(avg),
    numberOfSubjects: subjects.length,
    numberOfPassed: subjects.where((s) => (s.average ?? 0) >= 10).length,
    subjects: subjects,
    sequenceLabels: sequenceLabels,
  );
}

String _fmt(double? v) => v == null
    ? '-'
    : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2));

/// A Cameroonian bulletin de notes rendered as a widget (the on-screen preview).
class ReportCardWidget extends StatelessWidget {
  final ReportCardData data;

  const ReportCardWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Container(
      width: 760,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFF1B5E20), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'RÉPUBLIQUE DU CAMEROUN',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const Text(
            'Paix - Travail - Patrie',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'MINISTÈRE DES ENSEIGNEMENTS SECONDAIRES',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10),
          ),
          const SizedBox(height: 2),
          const Text(
            'MINISTRY OF SECONDARY EDUCATION',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (d.logoUrl != null && d.logoUrl!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    d.logoUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.school,
                      size: 48,
                      color: Colors.black45,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      d.schoolName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (d.schoolAddress != null && d.schoolAddress!.isNotEmpty)
                      Text(
                        d.schoolAddress!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'BULLETIN DE NOTES / REPORT CARD',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          Text(
            '${d.academicYearName} - ${d.periodLabel}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          // Identity header
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black45),
            ),
            child: Wrap(
              spacing: 22,
              runSpacing: 4,
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
                _info(
                  'Redoublant / Repeater',
                  d.repeater ? 'Oui / Yes' : 'Non / No',
                ),
                if (d.gender != null) _info('Sexe / Gender', d.gender!),
                _info('Classe / Class', d.className),
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
          const SizedBox(height: 10),
          // Term subjects: two sequence marks roll up into one term average.
          Table(
            border: TableBorder.all(color: Colors.black45),
            columnWidths: const {
              0: FlexColumnWidth(2.2),
              1: FixedColumnWidth(44),
              2: FixedColumnWidth(44),
              3: FixedColumnWidth(48),
              4: FixedColumnWidth(38),
              5: FixedColumnWidth(58),
              6: FixedColumnWidth(38),
              7: FlexColumnWidth(1.7),
              8: FlexColumnWidth(1.7),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFE8E8E8)),
                children: [
                  _cell('SUBJECT NAME\nDISCIPLINE', bold: true),
                  _cell(
                    d.sequenceLabels.elementAtOrNull(0) ?? 'Seq. X',
                    bold: true,
                    center: true,
                  ),
                  _cell(
                    d.sequenceLabels.elementAtOrNull(1) ?? 'Seq. Y',
                    bold: true,
                    center: true,
                  ),
                  _cell('AVERAGE\nMOY. TR.', bold: true, center: true),
                  _cell('Coef', bold: true, center: true),
                  _cell('TOTAL\nAV X C', bold: true, center: true),
                  _cell('POS.\nRANG', bold: true, center: true),
                  _cell('TEACHER\nNAME', bold: true, center: true),
                  _cell("TEACHER'S REMARK", bold: true, center: true),
                ],
              ),
              for (var i = 0; i < d.subjects.length; i++)
                TableRow(
                  children: [
                    _cell(d.subjects[i].name),
                    for (var j = 0; j < 2; j++)
                      _cell(
                        _fmt(d.subjects[i].sequenceAverages.elementAtOrNull(j)),
                        center: true,
                        danger:
                            (d.subjects[i].sequenceAverages.elementAtOrNull(
                                  j,
                                ) ??
                                10) <
                            10,
                      ),
                    _cell(
                      _fmt(d.subjects[i].average),
                      center: true,
                      danger: (d.subjects[i].average ?? 10) < 10,
                    ),
                    _cell(_fmt(d.subjects[i].coefficient), center: true),
                    _cell(
                      _fmt(d.subjects[i].points),
                      center: true,
                      danger: (d.subjects[i].average ?? 10) < 10,
                    ),
                    _cell(
                      d.subjects[i].rank?.toString() ?? '-',
                      center: true,
                      danger: (d.subjects[i].average ?? 10) < 10,
                    ),
                    _cell(d.subjects[i].teacherName ?? '-'),
                    _cell(
                      d.subjects[i].remark,
                      danger: (d.subjects[i].average ?? 10) < 10,
                    ),
                  ],
                ),
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFF2F2F2)),
                children: [
                  _cell('TOTAL', bold: true),
                  _cell('', center: true),
                  _cell('', center: true),
                  _cell('', center: true),
                  _cell(_fmt(d.totalCoefficients), center: true, bold: true),
                  _cell(_fmt(d.totalWeightedPoints), center: true, bold: true),
                  _cell('', center: true),
                  _cell('', center: true),
                  _cell('', center: true),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          _disciplinaryRecord(d),
          const SizedBox(height: 12),
          Row(
            children: [
              _avgBox(
                'Moyenne Générale / General Average',
                d.generalAverage,
                flex: 2,
              ),
              _avgBox(
                'Moyenne de la classe / Class Average',
                d.classAverage,
                flex: 2,
              ),
              _avgBox('Rang / Rank', d.rank?.toDouble(), flex: 1),
              _avgBox(
                'Appréciation / Appreciation',
                null,
                text: d.appreciation,
                flex: 2,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Appréciations / Comments',
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          for (final label in const [
            'Le Professeur / Teacher:',
            'Le Professeur Principal / Class Teacher:',
            'Le Chef d\'Établissement / Principal:',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(label, style: const TextStyle(fontSize: 10)),
            ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Le Professeur',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 28),
                    Text('Signature', style: TextStyle(fontSize: 9)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Le Professeur Principal',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 28),
                    Text('Signature', style: TextStyle(fontSize: 9)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Le Chef d\'Établissement',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 28),
                    Text(
                      'Signature & Tampon / Stamp',
                      style: TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _info(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
        Text(value, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  Widget _avgBox(String label, double? value, {int flex = 1, String? text}) {
    return Expanded(
      flex: flex,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(border: Border.all(color: Colors.black45)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9),
            ),
            const SizedBox(height: 4),
            Text(
              text ?? _fmt(value),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _disciplinaryRecord(ReportCardData d) {
    final rows = <(String, int)>[
      ("No. of absences / Nr. d'absences", d.absences),
      ('Disciplinary council / Conseil disciplinaire', d.disciplinaryCouncils),
      ('Warning / Avertissement', d.warnings),
      ('Suspension', d.suspensions),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DISCIPLINARY RECORD / DOSSIER DISCIPLINAIRE',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Table(
          border: TableBorder.all(color: Colors.black45),
          columnWidths: const {0: FlexColumnWidth(), 1: FixedColumnWidth(46)},
          children: [
            for (final row in rows)
              TableRow(
                children: [_cell(row.$1), _cell('${row.$2}', center: true)],
              ),
          ],
        ),
      ],
    );
  }

  static Widget _cell(
    String text, {
    bool bold = false,
    bool center = false,
    bool danger = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.left,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: danger ? Colors.red : Colors.black,
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
