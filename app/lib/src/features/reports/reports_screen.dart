import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/shimmer.dart';
import '../../data/entities.dart';
import '../../data/repositories/academic_repository.dart';
import '../../data/repositories/reports_repository.dart';
import '../../data/repositories/results_repository.dart';
import '../../data/repositories/student_repository.dart';
import '../../data/repositories/teacher_repository.dart';
import 'report_card.dart';
import 'report_pdf.dart';

/// Report cards (spec section 18): pick a class + period, preview a student's
/// Cameroonian bulletin, export/print a single card or the whole class.
class ReportsScreen extends StatefulWidget {
  final SupabaseClient client;
  final School school;
  final bool isAdmin;

  const ReportsScreen({
    super.key,
    required this.client,
    required this.school,
    required this.isAdmin,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final AcademicRepository _academic;
  late final ResultsRepository _results;
  late final ReportsRepository _reports;
  late final StudentRepository _students;
  late final TeacherRepository _teachers;
  late Future<_Base> _baseFuture;

  String? _classId;
  String _periodType = 'TERM';
  String? _periodId;
  Future<List<PeriodResult>>? _resultsFuture;
  PeriodResult? _selected;
  Map<String, List<PeriodResult>> _termSequenceResultsBySequence = const {};
  bool _termReady = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _academic = AcademicRepository(widget.client);
    _results = ResultsRepository(widget.client);
    _reports = ReportsRepository(widget.client);
    _students = StudentRepository(widget.client);
    _teachers = TeacherRepository(widget.client);
    _baseFuture = _load();
  }

  Future<_Base> _load() async {
    final years = await _academic.academicYears(widget.school.id);
    final year = years.firstWhere(
      (y) => y.isCurrent,
      orElse: () => years.isNotEmpty
          ? years.first
          : (throw StateError('No academic year')),
    );
    final results = await Future.wait([
      _academic.classesFor(schoolId: widget.school.id, academicYearId: year.id),
      _academic.terms(year.id),
      _academic.sequencesForYear(year.id),
      _students.list(schoolId: widget.school.id, academicYearId: year.id),
      _teachers.listAssignments(
        schoolId: widget.school.id,
        academicYearId: year.id,
      ),
      _teachers.listMembers(widget.school.id),
    ]);
    return _Base(
      year: year,
      classes: results[0] as List<SchoolClass>,
      terms: results[1] as List<Term>,
      sequences: results[2] as List<Sequence>,
      students: results[3] as List<StudentWithEnrollment>,
      assignments: results[4] as List<TeacherAssignmentDetail>,
      members: results[5] as List<SchoolMember>,
    );
  }

  void _reload() {
    if (_classId == null) return;
    setState(() {
      _selected = null;
      _termSequenceResultsBySequence = const {};
      _termReady = false;
      _resultsFuture = _results.periodResults(
        classId: _classId!,
        periodType: _periodType,
        periodId: _periodType == 'ANNUAL' ? null : _periodId,
      );
    });
    if (_periodType == 'TERM' && _periodId != null) {
      final classId = _classId!;
      final termId = _periodId!;
      _baseFuture.then((base) async {
        final sequences = base.sequences
            .where((s) => s.termId == termId)
            .toList();
        final results = await Future.wait(
          sequences.map(
            (s) => _results.periodResults(
              classId: classId,
              periodType: 'SEQUENCE',
              periodId: s.id,
            ),
          ),
        );
        if (!mounted || classId != _classId || termId != _periodId) return;
        final expected = base.students
            .where((s) => s.classId == classId)
            .length;
        final ready =
            expected > 0 &&
            sequences.length == 2 &&
            results.every(
              (rows) =>
                  rows.length >= expected &&
                  rows.every((row) => row.subjects.isNotEmpty),
            );
        setState(() {
          _termSequenceResultsBySequence = {
            for (var i = 0; i < sequences.length; i++)
              sequences[i].id: results[i],
          };
          _termReady = ready;
        });
      });
    }
  }

  String _periodLabel(_Base base) {
    switch (_periodType) {
      case 'SEQUENCE':
        return base.sequences
                .where((s) => s.id == _periodId)
                .firstOrNull
                ?.name ??
            'Sequence';
      case 'TERM':
        return base.terms.where((t) => t.id == _periodId).firstOrNull?.name ??
            'Term';
      default:
        return 'Annual Average';
    }
  }

  ReportCardData _buildCard(_Base base, PeriodResult result) {
    final cls = base.classes.firstWhere((c) => c.id == _classId);
    final student = base.students
        .where((s) => s.enrollmentId == result.studentEnrollmentId)
        .firstOrNull
        ?.student;
    final teacherNames = <String, String>{
      for (final a in base.assignments.where((a) => a.classId == _classId))
        a.subjectId: a.teacherName,
    };
    final classMaster = cls.classTeacherId == null
        ? null
        : base.members
              .where((m) => m.membershipId == cls.classTeacherId)
              .firstOrNull
              ?.fullName;
    final subjectSequenceAverages = <String, List<double?>>{};
    final termSequences = base.sequences
        .where((s) => s.termId == _periodId)
        .toList();
    for (final subject in result.subjects) {
      subjectSequenceAverages[subject.subjectId] = [
        for (final sequence in termSequences)
          _termSequenceResultsBySequence[sequence.id]
              ?.where(
                (r) => r.studentEnrollmentId == result.studentEnrollmentId,
              )
              .firstOrNull
              ?.subjects
              .where((s) => s.subjectId == subject.subjectId)
              .firstOrNull
              ?.subjectAverage,
      ];
    }
    return buildReportCardData(
      school: widget.school,
      academicYearName: base.year.name,
      periodLabel: _periodLabel(base),
      cls: cls,
      result: result,
      student: student,
      subjectTeacherNames: teacherNames,
      classMasterName: classMaster,
      subjectSequenceAverages: subjectSequenceAverages,
      sequenceLabels: termSequences.map((s) => s.name).toList(),
    );
  }

  List<ReportCardData> _buildAll(_Base base, List<PeriodResult> list) =>
      list.map((r) => _buildCard(base, r)).toList();

  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  Future<void> _saveOrShare(Uint8List bytes, String filename) async {
    if (_isDesktop) {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save report card',
        fileName: filename,
        bytes: bytes,
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to $path')));
      }
    } else {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    }
  }

  String _safeName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');

  Future<void> _exportSingle(_Base base) async {
    if (!widget.isAdmin || !_termReady) {
      _showNotReady();
      return;
    }
    final result = _selected;
    if (result == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await buildReportPdf(_buildCard(base, result));
      await _saveOrShare(
        bytes,
        'bulletin_${_safeName(result.studentName)}.pdf',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printSingle(_Base base) async {
    if (!widget.isAdmin || !_termReady) {
      _showNotReady();
      return;
    }
    final result = _selected;
    if (result == null) return;
    final bytes = await buildReportPdf(_buildCard(base, result));
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _exportAll(_Base base, List<PeriodResult> list) async {
    if (!widget.isAdmin || !_termReady) {
      _showNotReady();
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await buildReportPdfBulk(_buildAll(base, list));
      await _saveOrShare(
        bytes,
        'bulletins_${base.classes.firstWhere((c) => c.id == _classId).name}.pdf',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printAll(_Base base, List<PeriodResult> list) async {
    if (!widget.isAdmin || !_termReady) {
      _showNotReady();
      return;
    }
    final bytes = await buildReportPdfBulk(_buildAll(base, list));
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _record(_Base base) async {
    if (!_termReady) {
      _showNotReady();
      return;
    }
    final result = _selected;
    if (result == null || !widget.isAdmin) return;
    try {
      final templateId = await _reports.defaultTemplateId(kind: _periodType);
      await _reports.recordReportCard(
        schoolId: widget.school.id,
        academicYearId: base.year.id,
        periodResultId: result.id,
        templateId: templateId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report recorded')));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not record the report: $e'),
          backgroundColor: AppColors.accentRed,
        ),
      );
    }
  }

  void _showNotReady() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Report cards are unavailable until both sequences have complete computed results.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Base>(
      future: _baseFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done)
          return const ShimmerPanel();
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load reports.'),
                const SizedBox(height: 8),
                Text(
                  '${snap.error}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => setState(() => _baseFuture = _load()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final base = snap.data!;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'REPORT CARDS',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          letterSpacing: 1.1,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Bulletins de notes',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      base.year.name,
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: AppDropdown<String?>(
                      label: 'Class',
                      value: _classId,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Select a class'),
                        ),
                        ...base.classes.map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() => _classId = v);
                        _reload();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 250,
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'TERM', label: Text('Term')),
                      ],
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        textStyle: WidgetStatePropertyAll(
                          const TextStyle(fontFamily: 'Lexend', fontSize: 12),
                        ),
                      ),
                      selected: {_periodType},
                      onSelectionChanged: (s) => setState(() {
                        _periodType = s.first;
                        _periodId = null;
                        _reload();
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String?>(
                      key: ValueKey(_periodType),
                      label: 'Period',
                      value: _periodId,
                      items: switch (_periodType) {
                        'TERM' => [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Select a term'),
                          ),
                          ...base.terms
                              .where(
                                (t) =>
                                    widget.school.currentTermNumber == null ||
                                    t.number == widget.school.currentTermNumber,
                              )
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t.id,
                                  child: Text(t.name),
                                ),
                              ),
                        ],
                        _ => const [
                          DropdownMenuItem(
                            value: null,
                            child: Text('Select a term'),
                          ),
                        ],
                      },
                      onChanged: (v) {
                        setState(() => _periodId = v);
                        _reload();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(child: _buildBody(base)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(_Base base) {
    final results = _resultsFuture;
    if (results == null) {
      return const Center(
        child: Text('Select a class and period to view report cards.'),
      );
    }
    return FutureBuilder<List<PeriodResult>>(
      future: results,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done)
          return const ShimmerPanel();
        if (snap.hasError)
          return Center(child: Text('Could not load results: ${snap.error}'));
        final list = snap.data ?? const <PeriodResult>[];
        if (list.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 40,
                    color: AppColors.onSurfaceVariant,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No results for this class and period',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Compute results first in Academic → Results, then come back to generate report cards.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (_periodType == 'TERM' && !_termReady) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This term report is locked until both sequences have complete computed results for every student. Check Academic > Results and compute both sequences first.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.accentRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }
        final wide = MediaQuery.of(context).size.width >= 1200;
        final listPane = SizedBox(
          width: wide ? 300 : null,
          child: ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = list[i];
              final selected = _selected?.id == r.id;
              return Card(
                margin: EdgeInsets.zero,
                color: selected ? AppColors.primary.withOpacity(0.08) : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: selected ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: InkWell(
                  onTap: () => setState(() => _selected = r),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.primary.withOpacity(0.12),
                          child: Text(
                            '${r.rank ?? '—'}',
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.studentName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Manrope',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Moy: ${r.generalAverage?.toString() ?? '—'}',
                                style: const TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 11.5,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );

        final preview = _selected == null
            ? const Center(
                child: Text('Select a student to preview their bulletin.'),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy || !widget.isAdmin || !_termReady
                              ? null
                              : () => _exportSingle(base),
                          icon: _busy
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_alt_outlined, size: 18),
                          label: const Text('Export PDF'),
                        ),
                        OutlinedButton.icon(
                          onPressed: widget.isAdmin && _termReady
                              ? () => _printSingle(base)
                              : null,
                          icon: const Icon(Icons.print_outlined, size: 18),
                          label: const Text('Print'),
                        ),
                        OutlinedButton.icon(
                          onPressed: widget.isAdmin && _termReady
                              ? () => _exportAll(base, list)
                              : null,
                          icon: const Icon(
                            Icons.file_download_outlined,
                            size: 18,
                          ),
                          label: Text('Export all (${list.length})'),
                        ),
                        OutlinedButton.icon(
                          onPressed: widget.isAdmin && _termReady
                              ? () => _printAll(base, list)
                              : null,
                          icon: const Icon(Icons.print_rounded, size: 18),
                          label: Text('Print all (${list.length})'),
                        ),
                        if (widget.isAdmin)
                          OutlinedButton.icon(
                            onPressed: () => _record(base),
                            icon: const Icon(Icons.save_outlined, size: 18),
                            label: const Text('Record report'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ReportCardWidget(
                          data: _buildCard(base, _selected!),
                        ),
                      ),
                    ),
                  ],
                ),
              );

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              listPane,
              const SizedBox(width: 16),
              Expanded(child: preview),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(height: 200, child: listPane),
            const SizedBox(height: 12),
            Expanded(child: preview),
          ],
        );
      },
    );
  }
}

class _Base {
  final AcademicYear year;
  final List<SchoolClass> classes;
  final List<Term> terms;
  final List<Sequence> sequences;
  final List<StudentWithEnrollment> students;
  final List<TeacherAssignmentDetail> assignments;
  final List<SchoolMember> members;

  _Base({
    required this.year,
    required this.classes,
    required this.terms,
    required this.sequences,
    required this.students,
    required this.assignments,
    required this.members,
  });
}
