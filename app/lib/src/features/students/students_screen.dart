import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../data/entities.dart';
import '../../data/repositories/academic_repository.dart';
import '../../data/repositories/student_repository.dart';

class StudentsScreen extends StatefulWidget {
  final SupabaseClient client;
  final School school;
  const StudentsScreen({super.key, required this.client, required this.school});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  late final AcademicRepository _academic;
  late final StudentRepository _students;
  late Future<_StudentsData> _future;
  String _search = '';
  String? _classFilter; // classId or null = all

  @override
  void initState() {
    super.initState();
    _academic = AcademicRepository(widget.client);
    _students = StudentRepository(widget.client);
    _future = _load();
  }

  Future<_StudentsData> _load() async {
    final years = await _academic.academicYears(widget.school.id);
    if (years.isEmpty) throw StateError('No academic year — create one from dashboard');
    final year = years.firstWhere((y) => y.isCurrent, orElse: () => years.first);
    final results = await Future.wait([
      _students.list(schoolId: widget.school.id, academicYearId: year.id).catchError((_) => _students.listAllForSchool(widget.school.id)),
      _academic.classesFor(schoolId: widget.school.id, academicYearId: year.id),
    ]);
    return _StudentsData(
      year: year,
      students: results[0] as List<StudentWithEnrollment>,
      classes: results[1] as List<SchoolClass>,
    );
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _add() async {
    final data = await _future;
    if (!mounted) return;
    final draft = await showDialog<_StudentDraft>(
      context: context,
      builder: (_) => _StudentDialog(school: widget.school, year: data.year, classes: data.classes),
    );
    if (draft == null || !mounted) return;
    try {
      await _students.create(
        schoolId: widget.school.id,
        fullName: draft.fullName,
        matricule: draft.matricule,
        dateOfBirth: draft.dateOfBirth,
        gender: draft.gender,
        classId: draft.classId,
        academicYearId: data.year.id,
      );
      _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student added')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.accentRed));
    }
  }

  Future<void> _edit(StudentWithEnrollment row) async {
    final data = await _future;
    if (!mounted) return;
    final draft = await showDialog<_StudentDraft>(
      context: context,
      builder: (_) => _StudentDialog(school: widget.school, year: data.year, classes: data.classes, existing: row),
    );
    if (draft == null || !mounted) return;
    try {
      await _students.update(row.student.id, fullName: draft.fullName, matricule: draft.matricule, dateOfBirth: draft.dateOfBirth, gender: draft.gender);
      if (draft.classId != null && draft.classId != row.classId && row.enrollmentId != null) {
        await _students.updateEnrollment(row.enrollmentId!, classId: draft.classId!);
      } else if (draft.classId != null && row.enrollmentId == null) {
        await _students.enroll(schoolId: widget.school.id, studentId: row.student.id, academicYearId: data.year.id, classId: draft.classId!);
      }
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _delete(StudentWithEnrollment row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete student?'),
        content: Text('Delete "${row.student.fullName}"? Enrollments will be removed.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _students.delete(row.student.id);
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: FutureBuilder<_StudentsData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (snap.hasError) {
            return _ErrorPane(message: 'Could not load students', error: snap.error!, onRetry: _refresh);
          }
          final data = snap.data!;
          final filtered = data.students.where((r) {
            final q = _search.trim().toLowerCase();
            final matchesSearch = q.isEmpty ||
                r.student.fullName.toLowerCase().contains(q) ||
                (r.student.matricule?.toLowerCase().contains(q) ?? false) ||
                (r.className?.toLowerCase().contains(q) ?? false);
            final matchesClass = _classFilter == null || r.classId == _classFilter;
            return matchesSearch && matchesClass;
          }).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('STUDENT REGISTRY', style: TextStyle(fontFamily: 'Lexend', fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 1.1)),
                      SizedBox(height: 4),
                      Text('Students', style: TextStyle(fontFamily: 'Manrope', fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.border)),
                    child: Row(children: [
                      const Icon(Icons.event_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(data.year.name, style: const TextStyle(fontFamily: 'Lexend', fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(onPressed: data.classes.isEmpty ? null : _add, icon: const Icon(Icons.person_add_rounded, size: 18), label: const Text('Add student')),
                ],
              ),
              const SizedBox(height: 8),
              Text('${filtered.length} of ${data.students.length} students • ${data.classes.length} classes',
                  style: TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.7))),
              const SizedBox(height: 16),
              // Controls
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(hintText: 'Search name, matricule or class…', prefixIcon: const Icon(Icons.search_rounded, size: 18), isDense: true, filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border))),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String?>(
                      initialValue: _classFilter,
                      decoration: InputDecoration(labelText: 'Class', isDense: true, filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border))),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All classes')),
                        ...data.classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) => setState(() => _classFilter = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
                ],
              ),
              const SizedBox(height: 16),
              if (data.classes.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppColors.accentAmberLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.accentAmber.withOpacity(0.3))),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.accentAmber),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Create a class first (Academic → Classes) before enrolling students.', style: TextStyle(fontFamily: 'Lexend', fontSize: 13, color: AppColors.onSurfaceVariant.withOpacity(0.9)))),
                  ]),
                )
              else if (filtered.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surfaceLow, shape: BoxShape.circle), child: const Icon(Icons.people_outline_rounded, size: 32, color: AppColors.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      const Text('No students found', style: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(_search.isNotEmpty ? 'Try a different search' : 'Add your first student to get started', style: TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.7))),
                    ]),
                  ),
                )
              else
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                    child: Column(
                      children: [
                        // Table header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                          child: Row(children: [
                            const Expanded(flex: 3, child: Text('STUDENT', style: TextStyle(fontFamily: 'Lexend', fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant, letterSpacing: 0.8))),
                            const Expanded(flex: 2, child: Text('CLASS', style: TextStyle(fontFamily: 'Lexend', fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant, letterSpacing: 0.8))),
                            const Expanded(flex: 2, child: Text('MATRICULE', style: TextStyle(fontFamily: 'Lexend', fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant, letterSpacing: 0.8))),
                            const SizedBox(width: 80, child: Text('ACTIONS', textAlign: TextAlign.right, style: TextStyle(fontFamily: 'Lexend', fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant, letterSpacing: 0.8))),
                          ]),
                        ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                            itemBuilder: (context, i) {
                              final row = filtered[i];
                              return _StudentTile(row: row, onEdit: () => _edit(row), onDelete: () => _delete(row));
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StudentsData {
  final AcademicYear year;
  final List<StudentWithEnrollment> students;
  final List<SchoolClass> classes;
  _StudentsData({required this.year, required this.students, required this.classes});
}

class _StudentTile extends StatelessWidget {
  final StudentWithEnrollment row;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _StudentTile({required this.row, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final s = row.student;
    final initials = s.fullName.trim().isEmpty ? '?' : s.fullName.trim().split(' ').where((e) => e.isNotEmpty).take(2).map((e) => e[0].toUpperCase()).join();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(children: [
              CircleAvatar(radius: 18, backgroundColor: AppColors.primary.withOpacity(0.1), child: Text(initials, style: const TextStyle(fontFamily: 'Manrope', fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.fullName, style: const TextStyle(fontFamily: 'Lexend', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(children: [
                    if (s.gender != null) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.surfaceLow, borderRadius: BorderRadius.circular(6)), child: Text(s.gender!, style: TextStyle(fontFamily: 'Lexend', fontSize: 10, color: AppColors.onSurfaceVariant.withOpacity(0.7)))),
                    if (s.dateOfBirth != null) ...[
                      const SizedBox(width: 6),
                      Text('${s.dateOfBirth!.day}/${s.dateOfBirth!.month}/${s.dateOfBirth!.year}', style: TextStyle(fontFamily: 'Lexend', fontSize: 11, color: AppColors.onSurfaceVariant.withOpacity(0.6))),
                    ],
                  ]),
                ]),
              ),
            ]),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: row.className == null ? AppColors.accentRedLight : AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Text(row.className ?? 'Not enrolled', style: TextStyle(fontFamily: 'Lexend', fontSize: 12, fontWeight: FontWeight.w500, color: row.className == null ? AppColors.accentRed : AppColors.primary), overflow: TextOverflow.ellipsis),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(s.matricule ?? '—', style: TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.7)), overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 80,
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: onEdit, style: IconButton.styleFrom(foregroundColor: AppColors.onSurfaceVariant)),
              IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.accentRed), onPressed: onDelete),
            ]),
          ),
        ],
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  final String message;
  final Object error;
  final VoidCallback onRetry;
  const _ErrorPane({required this.message, required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline_rounded, size: 36, color: AppColors.accentRed), const SizedBox(height: 12), Text(message, style: const TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700)), const SizedBox(height: 6), Text(error.toString(), style: TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.7)), textAlign: TextAlign.center), const SizedBox(height: 16), OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Retry'))]));
  }
}

class _StudentDraft {
  final String fullName;
  final String? matricule;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? classId;
  _StudentDraft({required this.fullName, this.matricule, this.dateOfBirth, this.gender, this.classId});
}

class _StudentDialog extends StatefulWidget {
  final School school;
  final AcademicYear year;
  final List<SchoolClass> classes;
  final StudentWithEnrollment? existing;
  const _StudentDialog({required this.school, required this.year, required this.classes, this.existing});

  @override
  State<_StudentDialog> createState() => _StudentDialogState();
}

class _StudentDialogState extends State<_StudentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _matricule;
  DateTime? _dob;
  String? _gender;
  String? _classId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.student.fullName ?? '');
    _matricule = TextEditingController(text: e?.student.matricule ?? '');
    _dob = e?.student.dateOfBirth;
    _gender = e?.student.gender;
    _classId = e?.classId;
  }

  @override
  void dispose() {
    _name.dispose();
    _matricule.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit student' : 'Add student'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full name *', prefixIcon: Icon(Icons.person_outline_rounded)), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _matricule, decoration: const InputDecoration(labelText: 'Matricule (optional)', prefixIcon: Icon(Icons.badge_outlined), hintText: 'e.g. 24-0123')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _gender,
                    decoration: const InputDecoration(labelText: 'Gender', prefixIcon: Icon(Icons.wc_rounded)),
                    items: const [DropdownMenuItem(value: null, child: Text('— Not specified —')), DropdownMenuItem(value: 'M', child: Text('M — Masculin')), DropdownMenuItem(value: 'F', child: Text('F — Féminin'))],
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(context: context, initialDate: _dob ?? DateTime(2010), firstDate: DateTime(1995), lastDate: DateTime.now());
                      if (picked != null) setState(() => _dob = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Date of birth', prefixIcon: Icon(Icons.cake_outlined)),
                      child: Text(_dob == null ? 'Select date' : '${_dob!.day}/${_dob!.month}/${_dob!.year}', style: TextStyle(fontFamily: 'Lexend', fontSize: 13, color: _dob == null ? AppColors.onSurfaceVariant.withOpacity(0.5) : AppColors.onSurface)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _classId,
                decoration: const InputDecoration(labelText: 'Class', prefixIcon: Icon(Icons.class_outlined)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— Not enrolled yet —')),
                  ...widget.classes.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.name} • ${c.levelName ?? ''}'))),
                ],
                onChanged: (v) => setState(() => _classId = v),
              ),
              if (widget.classes.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('No classes for this year — create one first.', style: TextStyle(fontFamily: 'Lexend', fontSize: 11, color: AppColors.accentRed))),
            ]),
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () { if (!_formKey.currentState!.validate()) return; Navigator.pop(context, _StudentDraft(fullName: _name.text.trim(), matricule: _matricule.text.trim().isEmpty ? null : _matricule.text.trim(), dateOfBirth: _dob, gender: _gender, classId: _classId)); }, child: Text(isEdit ? 'Save' : 'Add'))],
    );
  }
}
