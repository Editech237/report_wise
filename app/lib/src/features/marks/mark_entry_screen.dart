import 'package:academic_engine/academic_engine.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/shimmer.dart';
import '../../data/entities.dart';
import '../../data/repositories/academic_repository.dart';
import '../../data/repositories/mark_repository.dart';
import '../../data/repositories/teacher_repository.dart';

/// Mark entry & workflow (spec sections 11, 27, 28, 30).
///
/// A teacher (or admin) picks their assignment (class · subject) and a
/// sequence, then enters per-component scores for the class roster. The grid
/// shows each student's live subject average and weighted points computed by
/// the engine, and the workflow bar moves the mark book through
/// DRAFT → SUBMITTED → REVIEWED → APPROVED → LOCKED (unlock is audited with a
/// reason). Saves are a single transactional RPC.
class MarkEntryScreen extends StatefulWidget {
  final SupabaseClient client;
  final School school;
  final bool isAdmin;
  final String? currentMembershipId;

  const MarkEntryScreen({
    super.key,
    required this.client,
    required this.school,
    required this.isAdmin,
    this.currentMembershipId,
  });

  @override
  State<MarkEntryScreen> createState() => _MarkEntryScreenState();
}

class _MarkEntryScreenState extends State<MarkEntryScreen> {
  late final AcademicRepository _academic;
  late final TeacherRepository _teachers;
  late final MarkRepository _marks;
  late Future<_BaseData> _baseFuture;
  Future<List<MarkBookSummary>>? _booksFuture;

  String? _assignmentId;
  String? _sequenceId;
  String? _mobileClassId;

  bool _loadingBook = false;
  bool _saving = false;

  String? _bookId;
  String _bookStatus = 'DRAFT';
  List<StudentInClass> _students = const [];
  List<AssessmentComponent> _components = const [];
  SubjectConfig? _subjectConfig;
  SchemeConfig? _scheme;
  MissingMarkPolicy _policy = MissingMarkPolicy(
    excludedStatuses: {
      AbsenceStatus.notEntered,
      AbsenceStatus.absent,
      AbsenceStatus.excused,
      AbsenceStatus.notApplicable,
      AbsenceStatus.pending,
    },
    zeroIsScore: true,
  );
  List<MarkBookEvent> _events = const [];

  final Map<String, _CellValue> _cells = {};

  @override
  void initState() {
    super.initState();
    _academic = AcademicRepository(widget.client);
    _teachers = TeacherRepository(widget.client);
    _marks = MarkRepository(widget.client);
    _baseFuture = _loadBase();
    _booksFuture = _baseFuture.then(
      (base) => _marks.listMarkBooks(
        schoolId: widget.school.id,
        academicYearId: base.year.id,
      ),
    );
  }

  @override
  void dispose() {
    _disposeCells();
    super.dispose();
  }

  void _disposeCells() {
    for (final c in _cells.values) {
      c.score.dispose();
    }
    _cells.clear();
  }

  Future<_BaseData> _loadBase() async {
    final years = await _academic.academicYears(widget.school.id);
    final year = years.firstWhere(
      (y) => y.isCurrent,
      orElse: () => years.isNotEmpty
          ? years.first
          : (throw StateError('No academic year')),
    );
    final results = await Future.wait([
      _teachers.listAssignments(
        schoolId: widget.school.id,
        academicYearId: year.id,
      ),
      _academic.sequencesForYear(year.id),
      _academic.terms(year.id),
      _academic.classesFor(schoolId: widget.school.id, academicYearId: year.id),
      _academic.academicRules(widget.school.id),
      _teachers.listMembers(widget.school.id),
    ]);
    var assignments = results[0] as List<TeacherAssignmentDetail>;
    if (!widget.isAdmin && widget.currentMembershipId != null) {
      assignments = assignments
          .where((a) => a.teacherMembershipId == widget.currentMembershipId)
          .toList();
    }
    return _BaseData(
      year: year,
      assignments: assignments,
      sequences: (results[1] as List<Sequence>).where((s) {
        if (widget.school.currentTermNumber == null) return false;
        final terms = results[2] as List<Term>;
        return terms
            .where((t) => t.number == widget.school.currentTermNumber)
            .any((t) => t.id == s.termId);
      }).toList(),
      classes: results[3] as List<SchoolClass>,
      rules: results[4] as List<AcademicRule>,
      members: results[5] as List<SchoolMember>,
    );
  }

  void _refreshBooks() {
    if (!mounted) return;
    setState(() {
      _booksFuture = _baseFuture.then(
        (base) => _marks.listMarkBooks(
          schoolId: widget.school.id,
          academicYearId: base.year.id,
        ),
      );
    });
  }

  /// Opens a saved mark book from history (sets the pickers and loads the grid).
  Future<void> _openBook(_BaseData base, MarkBookSummary book) async {
    setState(() {
      _assignmentId = book.teacherAssignmentId;
      _sequenceId = book.sequenceId;
      _mobileClassId = base.assignments
          .where((a) => a.id == book.teacherAssignmentId)
          .firstOrNull
          ?.classId;
    });
    await _loadBook(base, book.teacherAssignmentId, book.sequenceId);
  }

  Future<ResolvedAcademicSetup> _resolveSetup(SchoolClass cls) async {
    return _academic.loadAcademicSetup(
      AcademicContext(
        schoolId: cls.schoolId,
        academicYearId: cls.academicYearId,
        subsystem: cls.subsystem,
        educationTypeId: cls.educationTypeId,
        cycleId: cls.cycleId,
        levelId: cls.levelId,
        seriesId: cls.seriesId,
        specialtyId: cls.specialtyId,
        classId: cls.id,
      ),
    );
  }

  Future<void> _loadBook(
    _BaseData base,
    String assignmentId,
    String sequenceId,
  ) async {
    setState(() => _loadingBook = true);
    try {
      final assignment = base.assignments.firstWhere(
        (a) => a.id == assignmentId,
      );
      final cls = base.classes.firstWhere((c) => c.id == assignment.classId);
      final bookId = await _marks.getOrCreateMarkBook(
        assignmentId: assignmentId,
        sequenceId: sequenceId,
      );
      final setup = await _resolveSetup(cls);
      final results = await Future.wait([
        _marks.studentsInClass(
          classId: assignment.classId,
          academicYearId: base.year.id,
        ),
        _marks.markEntries(bookId),
        _marks.markBookEvents(bookId),
      ]);
      final book = await _marks.markBook(bookId);

      _disposeCells();
      final students = results[0] as List<StudentInClass>;
      final entries = results[1] as List<MarkEntry>;
      final events = results[2] as List<MarkBookEvent>;

      for (final e in entries) {
        _cells['${e.studentEnrollmentId}::${e.schemeComponentId}'] = _CellValue(
          score: e.score,
          status: e.absenceStatus,
        );
      }

      if (!mounted) return;
      setState(() {
        _bookId = bookId;
        _bookStatus = book?['status']?.toString() ?? 'DRAFT';
        _students = students;
        _components = setup.scheme?.components ?? const [];
        _subjectConfig = setup.subjects
            .where((s) => s.subjectId == assignment.subjectId)
            .firstOrNull;
        _scheme = setup.scheme;
        _policy = _policyFromRules(base.rules);
        _events = events;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the mark book: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingBook = false);
    }
  }

  MissingMarkPolicy _policyFromRules(List<AcademicRule> rules) {
    AcademicRule? rule;
    for (final r in rules) {
      if (r.ruleKey == 'MISSING_MARK_POLICY') {
        rule = r;
        if (r.schoolId != null) break; // school override wins
      }
    }
    if (rule == null) return _policy;
    final excluded = <AbsenceStatus>[];
    final ex = rule.ruleValue['exclude'];
    if (ex is List) {
      for (final s in ex) {
        try {
          excluded.add(AbsenceStatus.fromCode(s.toString()));
        } catch (_) {}
      }
    }
    return MissingMarkPolicy(
      excludedStatuses: excluded.toSet(),
      zeroIsScore: rule.ruleValue['zero_is_score'] == true,
    );
  }

  // ---------------------------------------------------------------------------
  // Cell helpers
  // ---------------------------------------------------------------------------

  _CellValue _cellFor(String enrollmentId, String componentId) {
    final key = '$enrollmentId::$componentId';
    return _cells.putIfAbsent(key, () => _CellValue());
  }

  ({double? avg, double? points}) _studentPreview(StudentInClass student) {
    if (_scheme == null || _subjectConfig == null) {
      return (avg: null, points: null);
    }
    final marks = <ComponentMark>[
      for (final comp in _components)
        ComponentMark(
          subjectId: _subjectConfig!.subjectId,
          componentId: comp.id,
          score: double.tryParse(
            _cellFor(student.enrollmentId, comp.id).score.text,
          ),
          maxScore: comp.maxScore,
          absenceStatus: AbsenceStatus.fromCode(
            _cellFor(student.enrollmentId, comp.id).status,
          ),
        ),
    ];
    final result = computeSubjectResult(
      config: _subjectConfig!,
      scheme: _scheme!,
      marks: marks,
      policy: _policy,
    );
    return (avg: result.subjectAverage, points: result.weightedPoints);
  }

  int get _enteredCount {
    var n = 0;
    for (final c in _cells.values) {
      if (c.status != 'NOT_ENTERED' || c.score.text.trim().isNotEmpty) n++;
    }
    return n;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    final bookId = _bookId;
    if (bookId == null || _saving) return;
    final entries = <Map<String, Object?>>[];
    _cells.forEach((key, cell) {
      final parts = key.split('::');
      final score = double.tryParse(cell.score.text);
      final hasScore = cell.score.text.trim().isNotEmpty;
      final hasStatus = cell.status != 'NOT_ENTERED';
      if (!hasScore && !hasStatus) return;
      entries.add({
        'student_enrollment_id': parts[0],
        'scheme_component_id': parts[1],
        'score': score,
        'absence_status': cell.status,
        'teacher_note': null,
      });
    });
    setState(() => _saving = true);
    try {
      await _marks.saveMarkEntries(bookId: bookId, entries: entries);
      _refreshBooks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            entries.isEmpty
                ? 'Nothing to save'
                : 'Saved ${entries.length} mark entries',
          ),
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _transition(String status) async {
    final bookId = _bookId;
    if (bookId == null) return;
    if (status == 'LOCKED') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Lock marks'),
          content: const Text(
            'Locking makes these marks immutable. An '
            'administrator can unlock them later (audited).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Lock'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    try {
      await _marks.setMarkBookStatus(bookId, status);
      final book = await _marks.markBook(bookId);
      final events = await _marks.markBookEvents(bookId);
      if (!mounted) return;
      setState(() {
        _bookStatus = book?['status']?.toString() ?? status;
        _events = events;
      });
      _refreshBooks();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Transition failed: $e')));
    }
  }

  Future<void> _unlock() async {
    final bookId = _bookId;
    if (bookId == null) return;
    final draft = await showDialog<_UnlockDraft>(
      context: context,
      builder: (_) => const _UnlockDialog(),
    );
    if (draft == null || !mounted) return;
    try {
      await _marks.unlockMarkBook(
        bookId: bookId,
        reason: draft.reason,
        newStatus: draft.newStatus,
      );
      final book = await _marks.markBook(bookId);
      final events = await _marks.markBookEvents(bookId);
      if (!mounted) return;
      setState(() {
        _bookStatus = book?['status']?.toString() ?? 'REVIEWED';
        _events = events;
      });
      _refreshBooks();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unlock failed: $e')));
    }
  }

  List<_WorkflowAction> get _workflowActions {
    // Teachers just enter and save marks. Administrators lock (finalize) a
    // mark book when the marks are complete; unlocking is a separate action.
    if (!widget.isAdmin) return const [];
    if (_bookStatus == 'LOCKED') return const [];
    return const [_WorkflowAction('LOCKED', 'Lock marks')];
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BaseData>(
      future: _baseFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const ShimmerPanel();
        }
        if (snap.hasError) {
          return _ErrorPane(
            message: 'Could not load mark entry.',
            error: snap.error!,
            onRetry: () => setState(() => _baseFuture = _loadBase()),
          );
        }
        final base = snap.data!;
        return Padding(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MARK ENTRY',
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
                        'Enter & review marks',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ],
                  ),
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
                    child: Row(
                      children: [
                        const Icon(
                          Icons.event_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          base.year.name,
                          style: const TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SavedBooksStrip(
                future: _booksFuture,
                onOpen: (book) => _openBook(base, book),
              ),
              if (base.assignments.isEmpty)
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 40,
                            color: AppColors.onSurfaceVariant,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No teaching assignments for you yet',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Ask your school administrator to assign you classes and subjects '
                            'in Teachers → Assignments. You can only enter marks for your own classes.',
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
                  ),
                )
              else ...[
                if (widget.school.currentTermNumber != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'ACTIVE TERM: Term ${widget.school.currentTermNumber} · Entering one of its two sequences',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (MediaQuery.sizeOf(context).width < 700)
                  Expanded(child: _buildMobileFlow(base))
                else ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth < 600
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 12) / 2;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          SizedBox(
                            width: width,
                            child: AppDropdown<String?>(
                              key: ValueKey('assign:$_assignmentId'),
                              label: '1. Choose your class · subject',
                              value: _assignmentId,
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Select your class · subject'),
                                ),
                                ...base.assignments.map(
                                  (a) => DropdownMenuItem(
                                    value: a.id,
                                    child: Text(
                                      '${a.className} · ${a.subjectName}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                setState(() => _assignmentId = v);
                                if (v != null && _sequenceId != null) {
                                  _loadBook(base, v, _sequenceId!);
                                }
                              },
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: AppDropdown<String?>(
                              key: ValueKey('seq:$_sequenceId'),
                              label:
                                  '2. Choose the sequence for the active term',
                              value: _sequenceId,
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Select the sequence'),
                                ),
                                ...base.sequences.map(
                                  (s) => DropdownMenuItem(
                                    value: s.id,
                                    child: Text(
                                      '${s.name} · ${s.status}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                setState(() => _sequenceId = v);
                                if (v != null && _assignmentId != null) {
                                  _loadBook(base, _assignmentId!, v);
                                }
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  if (widget.school.currentTermNumber == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Set the current academic term in School Settings before entering marks.',
                        style: TextStyle(
                          color: AppColors.accentRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_loadingBook)
                    const Expanded(child: ShimmerPanel())
                  else if (_bookId == null)
                    const Expanded(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                size: 40,
                                color: AppColors.onSurfaceVariant,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Pick your class · subject and the sequence above',
                                style: TextStyle(
                                  fontFamily: 'Manrope',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'The list of students in that class will appear here and you can enter their marks.',
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
                      ),
                    )
                  else if (_students.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'This class has no students yet. Add students from the Students screen.',
                        ),
                      ),
                    )
                  else
                    Expanded(child: _buildBook(base)),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildBook(_BaseData base) {
    final assignment = base.assignments
        .where((a) => a.id == _assignmentId)
        .firstOrNull;
    final me = widget.currentMembershipId == null
        ? null
        : base.members
              .where((m) => m.membershipId == widget.currentMembershipId)
              .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TeacherBanner(
          currentName: me?.fullName ?? (widget.isAdmin ? 'Administrator' : ''),
          assignment: assignment,
        ),
        const SizedBox(height: 12),
        _WorkflowBar(
          status: _bookStatus,
          actions: _workflowActions,
          isAdmin: widget.isAdmin,
          saving: _saving,
          onSave: _save,
          onTransition: _transition,
          onUnlock: _unlock,
          canEdit: _canEdit,
        ),
        const SizedBox(height: 12),
        _buildSummary(base),
        const SizedBox(height: 10),
        const _GradingLegend(),
        const SizedBox(height: 10),
        Expanded(
          child: MediaQuery.sizeOf(context).width < 700
              ? _buildMobileGrid()
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(child: _buildGrid()),
                ),
        ),
        if (_events.isNotEmpty) _HistoryTile(events: _events),
      ],
    );
  }

  bool get _canEdit {
    final status = _bookStatus;
    if (status == 'LOCKED') return false;
    if (widget.isAdmin) return true;
    return status == 'DRAFT';
  }

  Widget _buildSummary(_BaseData base) {
    final subject = _subjectConfig;
    final totalCells = _students.length * _components.length;
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.functions, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                subject == null
                    ? 'Subject not resolved in curriculum'
                    : 'Subject: ${subject.name} · Coefficient ×${_fmtNum(subject.coefficient)}',
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (_scheme != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'Marking: ${_scheme!.name.replaceAll(' (100%)', '')}',
              style: const TextStyle(fontFamily: 'Lexend', fontSize: 12.5),
            ),
          ),
        Text(
          totalCells == 0
              ? '${_students.length} students'
              : '$_enteredCount / $totalCells marks entered',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildMobileFlow(_BaseData base) {
    final classIds = <String>[];
    for (final assignment in base.assignments) {
      if (!classIds.contains(assignment.classId))
        classIds.add(assignment.classId);
    }

    if (_bookId != null && _assignmentId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MobileBackButton(
            label: 'Change class or subject',
            onPressed: () => setState(() {
              _disposeCells();
              _bookId = null;
              _assignmentId = null;
              _sequenceId = null;
              _mobileClassId = null;
              _students = const [];
            }),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBook(base)),
        ],
      );
    }

    final selectedClassId = _mobileClassId;
    if (selectedClassId == null) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _MobileStepHeader(
              step: 'STEP 1 OF 3',
              title: 'Choose your class',
              help: 'Tap the class where you want to enter marks.',
            ),
            const SizedBox(height: 12),
            for (final classId in classIds)
              _MobileChoiceCard(
                icon: Icons.class_outlined,
                title: base.assignments
                    .firstWhere((a) => a.classId == classId)
                    .className,
                subtitle:
                    '${base.assignments.where((a) => a.classId == classId).length} subject(s) assigned to you',
                onTap: () => setState(() => _mobileClassId = classId),
              ),
          ],
        ),
      );
    }

    final classAssignments = base.assignments
        .where((a) => a.classId == selectedClassId)
        .toList();
    final selectedAssignment = classAssignments
        .where((a) => a.id == _assignmentId)
        .firstOrNull;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MobileBackButton(
            label: 'All my classes',
            onPressed: () => setState(() {
              _mobileClassId = null;
              _assignmentId = null;
              _sequenceId = null;
            }),
          ),
          const SizedBox(height: 8),
          _MobileStepHeader(
            step: selectedAssignment == null ? 'STEP 2 OF 3' : 'STEP 3 OF 3',
            title: selectedAssignment == null
                ? '${classAssignments.first.className} subjects'
                : selectedAssignment.subjectName,
            help: selectedAssignment == null
                ? 'Choose the subject you are teaching.'
                : 'Choose the sequence, then enter marks for each student.',
          ),
          const SizedBox(height: 12),
          if (selectedAssignment == null)
            for (final assignment in classAssignments)
              _MobileChoiceCard(
                icon: Icons.menu_book_outlined,
                title: assignment.subjectName,
                subtitle: 'Open mark entry for this subject',
                onTap: () => setState(() {
                  _assignmentId = assignment.id;
                  _sequenceId = null;
                }),
              )
          else ...[
            _MobileSelectionCard(
              label: 'SUBJECT SELECTED',
              value: selectedAssignment.subjectName,
              icon: Icons.check_circle_outline,
            ),
            const SizedBox(height: 16),
            const Text(
              'Which sequence are you entering?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            for (final sequence in base.sequences)
              _MobileChoiceCard(
                icon: Icons.edit_note_rounded,
                title: sequence.name,
                subtitle: sequence.status == 'OPEN'
                    ? 'Open for mark entry'
                    : sequence.status,
                enabled: sequence.status == 'OPEN',
                onTap: sequence.status == 'OPEN'
                    ? () {
                        setState(() => _sequenceId = sequence.id);
                        _loadBook(base, selectedAssignment.id, sequence.id);
                      }
                    : null,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileGrid() {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _students.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final student = _students[index];
        final preview = _studentPreview(student);
        return Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${index + 1}. ${student.fullName}',
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    _PreviewCell(preview: preview.avg, label: 'AVG /20'),
                  ],
                ),
                if (student.matricule?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    student.matricule!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const Divider(height: 20),
                for (final component in _components)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            component.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          'out of ${_fmtNum(component.maxScore)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                        _ScoreCell(
                          value: _cellFor(student.enrollmentId, component.id),
                          editable: _canEdit,
                          large: true,
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    preview.points == null
                        ? 'Total: —'
                        : 'Weighted points: ${_fmtNum(preview.points!)}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGrid() {
    final columns = <DataColumn>[
      const DataColumn(
        label: SizedBox(
          width: 180,
          child: Text('Student', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
      for (final c in _components)
        DataColumn(
          label: SizedBox(
            width: 116,
            child: Text(
              c.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      const DataColumn(
        label: Text('Avg /20', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      const DataColumn(
        label: Text('Points', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    ];

    final rows = <DataRow>[
      for (final student in _students)
        DataRow(
          cells: [
            DataCell(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    student.fullName,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (student.matricule != null &&
                      student.matricule!.isNotEmpty)
                    Text(
                      student.matricule!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            for (final comp in _components)
              DataCell(
                _ScoreCell(
                  value: _cellFor(student.enrollmentId, comp.id),
                  editable: _canEdit,
                ),
              ),
            DataCell(_PreviewCell(preview: _studentPreview(student).avg)),
            DataCell(
              _PreviewCell(
                preview: _subjectConfig == null
                    ? null
                    : _studentPreview(student).points,
                bold: true,
              ),
            ),
          ],
        ),
    ];

    return DataTable(
      columnSpacing: 12,
      headingRowColor: WidgetStatePropertyAll(AppColors.surfaceLow),
      columns: columns,
      rows: rows,
    );
  }
}

class _BaseData {
  final AcademicYear year;
  final List<TeacherAssignmentDetail> assignments;
  final List<Sequence> sequences;
  final List<SchoolClass> classes;
  final List<AcademicRule> rules;
  final List<SchoolMember> members;

  _BaseData({
    required this.year,
    required this.assignments,
    required this.sequences,
    required this.classes,
    required this.rules,
    required this.members,
  });
}

class _CellValue {
  final TextEditingController score;
  String status;

  _CellValue({double? score, this.status = 'NOT_ENTERED'})
    : score = TextEditingController(text: score == null ? '' : _fmtNum(score));
}

String _fmtNum(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

class _WorkflowAction {
  final String status;
  final String label;
  const _WorkflowAction(this.status, this.label);
}

class _UnlockDraft {
  final String reason;
  final String newStatus;
  _UnlockDraft({required this.reason, required this.newStatus});
}

// =============================================================================
// Widgets
// =============================================================================

/// Confirms who is entering the marks and for which assignment. If the signed-in
/// teacher does not match the assigned teacher (non-admin), it warns — an
/// anti-impersonation safeguard on top of the server-side RLS/RPC checks.
class _TeacherBanner extends StatelessWidget {
  final String currentName;
  final TeacherAssignmentDetail? assignment;

  const _TeacherBanner({required this.currentName, this.assignment});

  @override
  Widget build(BuildContext context) {
    final assignedName = assignment?.teacherName ?? '';
    final mismatch = currentName.isNotEmpty && assignedName != currentName;
    final color = mismatch ? AppColors.accentRed : AppColors.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(
            mismatch
                ? Icons.warning_amber_rounded
                : Icons.verified_user_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Entering marks as: $currentName',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                if (assignment != null)
                  Text(
                    '${assignment!.className} · ${assignment!.subjectName}'
                    '${assignedName.isNotEmpty ? ' — assigned to $assignedName' : ''}',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant.withOpacity(0.85),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowBar extends StatelessWidget {
  final String status;
  final List<_WorkflowAction> actions;
  final bool isAdmin;
  final bool saving;
  final VoidCallback onSave;
  final ValueChanged<String> onTransition;
  final VoidCallback onUnlock;

  final bool canEdit;

  const _WorkflowBar({
    required this.status,
    required this.actions,
    required this.isAdmin,
    required this.saving,
    required this.onSave,
    required this.onTransition,
    required this.onUnlock,
    required this.canEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.flag_outlined, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text('Status: ', style: Theme.of(context).textTheme.bodySmall),
          _StatusPill(status: status),
          const SizedBox(width: 8),
          if (status == 'LOCKED')
            Text(
              '(immutable)',
              style: TextStyle(
                color: AppColors.accentRed,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          if (canEdit)
            FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save'),
            ),
          if (canEdit) const SizedBox(width: 8),
          for (final a in actions) ...[
            OutlinedButton(
              onPressed: saving ? null : () => onTransition(a.status),
              child: Text(a.label),
            ),
            const SizedBox(width: 8),
          ],
          if (status == 'LOCKED' && isAdmin) ...[
            OutlinedButton.icon(
              onPressed: onUnlock,
              icon: const Icon(Icons.lock_open_outlined, size: 16),
              label: const Text('Unlock'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'DRAFT' => AppColors.onSurfaceVariant,
      'SUBMITTED' => const Color(0xFF1565C0),
      'REVIEWED' => const Color(0xFF6A1B9A),
      'APPROVED' => AppColors.accentGreen,
      'LOCKED' => AppColors.accentRed,
      _ => AppColors.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ScoreCell extends StatefulWidget {
  final _CellValue value;
  final bool editable;
  final bool large;
  const _ScoreCell({
    required this.value,
    required this.editable,
    this.large = false,
  });

  @override
  State<_ScoreCell> createState() => _ScoreCellState();
}

class _ScoreCellState extends State<_ScoreCell> {
  static const _statuses = [
    'ENTERED',
    'ABSENT',
    'EXCUSED',
    'ZERO',
    'NOT_APPLICABLE',
    'PENDING',
  ];

  static const _labels = {
    'ENTERED': 'Entered',
    'ABSENT': 'Absent',
    'EXCUSED': 'Excused',
    'ZERO': 'Zero (0)',
    'NOT_APPLICABLE': 'Not applicable',
    'PENDING': 'Pending',
  };

  static const _symbols = {
    'NOT_ENTERED': '·',
    'ENTERED': '✓',
    'ABSENT': 'A',
    'EXCUSED': 'E',
    'ZERO': '0',
    'NOT_APPLICABLE': '—',
    'PENDING': '?',
  };

  static const _colors = {
    'NOT_ENTERED': AppColors.onSurfaceVariant,
    'ENTERED': AppColors.accentGreen,
    'ABSENT': AppColors.accentRed,
    'EXCUSED': Color(0xFFEF6C00),
    'ZERO': AppColors.onSurfaceVariant,
    'NOT_APPLICABLE': AppColors.onSurfaceVariant,
    'PENDING': Color(0xFF1565C0),
  };

  bool get _scoreLocked => const {
    'ABSENT',
    'EXCUSED',
    'NOT_APPLICABLE',
    'PENDING',
  }.contains(widget.value.status);

  void _onChanged(String v) {
    setState(() {
      // Typing a mark marks the cell as entered; clearing it reverts.
      if (v.trim().isNotEmpty && widget.value.status == 'NOT_ENTERED') {
        widget.value.status = 'ENTERED';
      } else if (v.trim().isEmpty && widget.value.status == 'ENTERED') {
        widget.value.status = 'NOT_ENTERED';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canType = widget.editable && !_scoreLocked;
    final entered = widget.value.status == 'ENTERED';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.large ? 94 : 76,
          child: TextField(
            controller: widget.value.score,
            enabled: canType,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '/20',
              hintStyle: TextStyle(
                fontSize: 12,
                color: AppColors.onSurfaceVariant.withOpacity(0.4),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 8,
              ),
              filled: true,
              fillColor: entered ? AppColors.accentGreenLight : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: entered ? AppColors.accentGreen : AppColors.border,
                ),
              ),
            ),
            onChanged: _onChanged,
          ),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          enabled: widget.editable,
          tooltip: 'Status',
          onSelected: (s) => setState(() {
            widget.value.status = s;
            if (s != 'ENTERED' && s != 'ZERO') {
              widget.value.score.clear();
            }
          }),
          itemBuilder: (_) => _statuses
              .map(
                (s) => PopupMenuItem(
                  value: s,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(
                          _symbols[s]!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _colors[s],
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_labels[s]!, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              )
              .toList(),
          icon: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  (_colors[widget.value.status] ?? AppColors.onSurfaceVariant)
                      .withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: Text(
              _symbols[widget.value.status] ?? '·',
              style: TextStyle(
                color:
                    _colors[widget.value.status] ?? AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One-line help + status legend shown above the mark grid so a teacher always
/// knows what to type and what the symbols mean.
class _GradingLegend extends StatelessWidget {
  const _GradingLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Type each student\'s mark out of 20:',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12,
              color: AppColors.onSurfaceVariant.withOpacity(0.85),
            ),
          ),
          const _LegendDot(
            symbol: '✓',
            label: 'Entered',
            color: AppColors.accentGreen,
          ),
          const _LegendDot(
            symbol: 'A',
            label: 'Absent',
            color: AppColors.accentRed,
          ),
          const _LegendDot(
            symbol: 'E',
            label: 'Excused',
            color: Color(0xFFEF6C00),
          ),
          const _LegendDot(
            symbol: '0',
            label: 'Zero',
            color: AppColors.onSurfaceVariant,
          ),
          const _LegendDot(
            symbol: '—',
            label: 'Not applicable',
            color: AppColors.onSurfaceVariant,
          ),
          Text(
            'Points = average × coefficient',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12,
              color: AppColors.onSurfaceVariant.withOpacity(0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final String symbol;
  final String label;
  final Color color;

  const _LegendDot({
    required this.symbol,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            shape: BoxShape.circle,
          ),
          child: Text(
            symbol,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontFamily: 'Lexend', fontSize: 11.5),
        ),
      ],
    );
  }
}

/// Horizontal list of saved mark books (persistent history). Tapping a book
/// opens its full grid. Hidden when there are no saved books.
class _SavedBooksStrip extends StatelessWidget {
  final Future<List<MarkBookSummary>>? future;
  final ValueChanged<MarkBookSummary> onOpen;

  const _SavedBooksStrip({required this.future, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MarkBookSummary>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: ShimmerBlock(height: 96, radius: 12),
          );
        }
        final books = snap.data ?? const [];
        if (books.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saved mark books (${books.length})',
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: books.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) =>
                    _BookCard(book: books[i], onTap: () => onOpen(books[i])),
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _BookCard extends StatelessWidget {
  final MarkBookSummary book;
  final VoidCallback onTap;

  const _BookCard({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 244,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${book.className} · ${book.subjectName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                book.sequenceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 11.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _StatusPill(status: book.status),
                  const Spacer(),
                  Text(
                    '${book.enteredCount}/${book.studentCount} entered',
                    style: const TextStyle(fontFamily: 'Lexend', fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: book.progress,
                  minHeight: 5,
                  backgroundColor: AppColors.surfaceLow,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileStepHeader extends StatelessWidget {
  final String step;
  final String title;
  final String help;

  const _MobileStepHeader({
    required this.step,
    required this.title,
    required this.help,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          step,
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          help,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 12.5,
            color: AppColors.onSurfaceVariant.withOpacity(0.8),
          ),
        ),
      ],
    );
  }
}

class _MobileBackButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _MobileBackButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back_rounded, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(padding: EdgeInsets.zero),
      ),
    );
  }
}

class _MobileChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  const _MobileChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.primary : AppColors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: enabled ? Colors.white : AppColors.surfaceLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant.withOpacity(0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  enabled
                      ? Icons.chevron_right_rounded
                      : Icons.lock_outline_rounded,
                  color: color,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileSelectionCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MobileSelectionCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCell extends StatelessWidget {
  final double? preview;
  final bool bold;
  final String? label;
  const _PreviewCell({required this.preview, this.bold = false, this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (label != null)
            Text(
              label!,
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          Text(
            preview == null ? '—' : _fmtNum(preview!),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: preview == null
                  ? AppColors.onSurfaceVariant
                  : AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final List<MarkBookEvent> events;
  const _HistoryTile({required this.events});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        'History (${events.length})',
        style: const TextStyle(
          fontFamily: 'Lexend',
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        for (final e in events)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    e.action,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Lexend',
                    ),
                  ),
                ),
                Text(
                  '${e.previousStatus ?? ''} → ${e.newStatus ?? ''}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e.reason ?? (e.actorName ?? ''),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '${e.createdAt.day.toString().padLeft(2, '0')}/${e.createdAt.month.toString().padLeft(2, '0')} ${e.createdAt.hour.toString().padLeft(2, '0')}:${e.createdAt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog();

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
  final _reason = TextEditingController();
  String _newStatus = 'REVIEWED';

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unlock mark book'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Unlocking is audited — a reason is required.'),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Reason *'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _newStatus,
            decoration: const InputDecoration(labelText: 'Return to status'),
            items: const [
              DropdownMenuItem(value: 'REVIEWED', child: Text('Reviewed')),
              DropdownMenuItem(value: 'APPROVED', child: Text('Approved')),
              DropdownMenuItem(
                value: 'DRAFT',
                child: Text('Draft (teacher can edit again)'),
              ),
            ],
            onChanged: (v) => setState(() => _newStatus = v!),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_reason.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _UnlockDraft(reason: _reason.text.trim(), newStatus: _newStatus),
            );
          },
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}

class _ErrorPane extends StatelessWidget {
  final String message;
  final Object error;
  final VoidCallback onRetry;
  const _ErrorPane({
    required this.message,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 8),
          Text(message),
          const SizedBox(height: 4),
          Text('$error', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
