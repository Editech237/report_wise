import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/academic_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/students_provider.dart';
import '../../core/providers/supabase_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/shimmer.dart';
import '../../data/entities.dart';
import '../../data/repositories/student_repository.dart';
import '../../data/repositories/student_import_repository.dart';
import 'student_details_screen.dart';
import 'student_import_dialog.dart';
import 'student_import_review_dialog.dart';
import 'student_pdf_import_dialog.dart';

class StudentsScreen extends ConsumerWidget {
  final School school;
  final bool isAdmin;

  const StudentsScreen({
    super.key,
    required this.school,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardDataProvider(school.id));
    final search = ref.watch(studentsSearchProvider);
    final classFilter = ref.watch(studentsClassFilterProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: dashboardAsync.when(
        loading: () => const ShimmerPanel(),
        error: (e, _) => _ErrorPane(
          message: 'Could not load students',
          error: e,
          onRetry: () {
            final year = _currentYear(ref);
            if (year != null) invalidateSchoolData(ref, school.id, year);
          },
        ),
        data: (data) {
          if (data.academicYears.isEmpty) {
            return const Center(
              child: Text('No academic year — create one from dashboard'),
            );
          }
          final year = data.academicYears.firstWhere(
            (y) => y.isCurrent,
            orElse: () => data.academicYears.first,
          );
          final filtered = ref.watch(filteredStudentsProvider(school.id));
          void refresh() => invalidateSchoolData(ref, school.id, year.id);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'STUDENT REGISTRY',
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
                        'Students',
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
                  _YearChip(name: year.name),
                  const SizedBox(width: 12),
                  if (isAdmin)
                    OutlinedButton.icon(
                      onPressed: data.classes.isEmpty
                          ? null
                          : () => _import(
                              context,
                              ref,
                              school,
                              year,
                              data.classes,
                              data.students,
                            ),
                      icon: const Icon(Icons.upload_file_outlined, size: 18),
                      label: const Text('Import'),
                    ),
                  if (isAdmin) const SizedBox(width: 8),
                  if (isAdmin)
                    OutlinedButton.icon(
                      onPressed: () => _scanPdf(context, ref, school),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('Scan PDF'),
                    ),
                  if (isAdmin) const SizedBox(width: 8),
                  if (isAdmin)
                    FilledButton.icon(
                      onPressed: data.classes.isEmpty
                          ? null
                          : () =>
                                _add(context, ref, school, year, data.classes),
                      icon: const Icon(Icons.person_add_rounded, size: 18),
                      label: const Text('Add student'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${filtered.length} of ${data.students.length} students • ${data.classes.length} classes',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search name, matricule or class…',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      onChanged: (v) =>
                          ref.read(studentsSearchProvider.notifier).state = v,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 200,
                    child: AppDropdown<String?>(
                      label: 'Class',
                      value: classFilter,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All classes'),
                        ),
                        ...data.classes.map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              c.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          ref.read(studentsClassFilterProvider.notifier).state =
                              v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (data.classes.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.accentAmberLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.accentAmber.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.accentAmber,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Create a class first (Classes) before enrolling students.',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13,
                            color: AppColors.onSurfaceVariant.withOpacity(0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (filtered.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLow,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.people_outline_rounded,
                            size: 32,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No students found',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          search.isNotEmpty
                              ? 'Try a different search'
                              : 'Add your first student to get started',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            color: AppColors.onSurfaceVariant.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final row = filtered[i];
                      return _StudentCard(
                        row: row,
                        isAdmin: isAdmin,
                        onTap: () => _openDetails(
                          context,
                          ref,
                          school,
                          year,
                          data.classes,
                          row,
                        ),
                        onEdit: isAdmin
                            ? () => _edit(
                                context,
                                ref,
                                school,
                                year,
                                data.classes,
                                row,
                              )
                            : null,
                        onDelete: isAdmin
                            ? () => _delete(context, ref, row)
                            : null,
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String? _currentYear(WidgetRef ref) {
    final data = ref.read(dashboardDataProvider(school.id)).valueOrNull;
    if (data == null || data.academicYears.isEmpty) return null;
    return data.academicYears
        .firstWhere((y) => y.isCurrent, orElse: () => data.academicYears.first)
        .id;
  }

  Future<void> _openDetails(
    BuildContext context,
    WidgetRef ref,
    School school,
    AcademicYear year,
    List<SchoolClass> classes,
    StudentWithEnrollment row,
  ) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StudentDetailsScreen(
          school: school,
          row: row,
          classes: classes,
          academicYearId: year.id,
          isAdmin: isAdmin,
        ),
      ),
    );
    if (changed == true && context.mounted) {
      invalidateSchoolData(ref, school.id, year.id);
    }
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    School school,
    AcademicYear year,
    List<SchoolClass> classes,
  ) async {
    final draft = await showDialog<_StudentDraft>(
      context: context,
      builder: (_) => _StudentDialog(classes: classes),
    );
    if (draft == null || !context.mounted) return;
    final repo = ref.read(studentRepositoryProvider);
    if (repo == null) return;
    try {
      await repo.create(
        schoolId: school.id,
        fullName: draft.fullName,
        matricule: draft.matricule,
        dateOfBirth: draft.dateOfBirth,
        gender: draft.gender,
        placeOfBirth: draft.placeOfBirth,
        guardianName: draft.guardianName,
        guardianPhone: draft.guardianPhone,
        repeater: draft.repeater,
        classId: draft.classId,
        academicYearId: year.id,
      );
      invalidateSchoolData(ref, school.id, year.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Student added')));
      }
    } on Exception catch (e) {
      _showError(context, 'Could not add the student', e);
    }
  }

  Future<void> _import(
    BuildContext context,
    WidgetRef ref,
    School school,
    AcademicYear year,
    List<SchoolClass> classes,
    List<StudentWithEnrollment> existing,
  ) async {
    final repo = ref.read(studentRepositoryProvider);
    if (repo == null) return;
    final imported = await showDialog<int>(
      context: context,
      builder: (_) => StudentImportDialog(
        school: school,
        year: year,
        classes: classes,
        existing: existing,
        repository: repo,
      ),
    );
    if (imported != null && context.mounted) {
      invalidateSchoolData(ref, school.id, year.id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Imported $imported students')));
    }
  }

  Future<void> _scanPdf(
    BuildContext context,
    WidgetRef ref,
    School school,
  ) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    final yearId = _currentYear(ref);
    if (yearId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select an academic year before scanning students.'),
        ),
      );
      return;
    }
    final academicRepository = ref.read(academicRepositoryProvider);
    if (academicRepository == null) return;
    List<SchoolClass> classes;
    try {
      classes = await academicRepository.classesFor(
        schoolId: school.id,
        academicYearId: yearId,
      );
    } catch (error) {
      if (context.mounted) _showError(context, 'Could not load classes', error);
      return;
    }
    if (!context.mounted) return;
    final batch = await showDialog<StudentImportBatch>(
      context: context,
      builder: (_) => StudentPdfImportDialog(
        school: school,
        repository: StudentImportRepository(client),
      ),
      barrierDismissible: false,
    );
    if (batch != null && context.mounted) {
      final importRepository = StudentImportRepository(client);
      final imported = await showDialog<int>(
        context: context,
        builder: (_) => StudentImportReviewDialog(
          academicYearId: yearId,
          classes: classes,
          batch: batch,
          repository: importRepository,
        ),
      );
      if (imported != null && context.mounted) {
        invalidateSchoolData(ref, school.id, yearId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $imported students from PDF')),
        );
      }
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    School school,
    AcademicYear year,
    List<SchoolClass> classes,
    StudentWithEnrollment row,
  ) async {
    final draft = await showDialog<_StudentDraft>(
      context: context,
      builder: (_) => _StudentDialog(classes: classes, existing: row),
    );
    if (draft == null || !context.mounted) return;
    final repo = ref.read(studentRepositoryProvider);
    if (repo == null) return;
    try {
      await repo.update(
        row.student.id,
        fullName: draft.fullName,
        matricule: draft.matricule,
        dateOfBirth: draft.dateOfBirth,
        gender: draft.gender,
        placeOfBirth: draft.placeOfBirth,
        guardianName: draft.guardianName,
        guardianPhone: draft.guardianPhone,
        repeater: draft.repeater,
      );
      if (draft.classId != null &&
          draft.classId != row.classId &&
          row.enrollmentId != null) {
        await repo.updateEnrollment(row.enrollmentId!, classId: draft.classId!);
      } else if (draft.classId != null && row.enrollmentId == null) {
        await repo.enroll(
          schoolId: school.id,
          studentId: row.student.id,
          academicYearId: year.id,
          classId: draft.classId!,
        );
      }
      invalidateSchoolData(ref, school.id, year.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Student updated')));
      }
    } on Exception catch (e) {
      _showError(context, 'Could not update the student', e);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    StudentWithEnrollment row,
  ) async {
    final yearId = _currentYear(ref);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete student?'),
        content: Text(
          'Delete "${row.student.fullName}"? Their enrollment and all associated '
          'records will be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final repo = ref.read(studentRepositoryProvider);
    if (repo == null) return;
    try {
      await repo.delete(row.student.id);
      if (yearId != null) invalidateSchoolData(ref, school.id, yearId);
    } on Exception catch (e) {
      _showError(context, 'Could not delete the student', e);
    }
  }

  void _showError(BuildContext context, String message, Object error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$message: ${_friendlyError(error)}'),
        backgroundColor: AppColors.accentRed,
      ),
    );
  }
}

String _friendlyError(Object e) {
  if (e is PostgrestException) {
    final m = e.message;
    if (m.contains('row-level security') ||
        m.contains('permission denied') ||
        m.contains('violates row-level')) {
      return 'You do not have permission for that action (administrator required).';
    }
    if (m.contains('foreign key') || m.contains('conflicts with key')) {
      return 'This record is still referenced by other data (e.g. finalized results).';
    }
    return m;
  }
  return e.toString();
}

class _YearChip extends StatelessWidget {
  final String name;
  const _YearChip({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_rounded, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            name,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  final StudentWithEnrollment row;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _StudentCard({
    required this.row,
    required this.isAdmin,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = row.student;
    final initials = s.fullName.trim().isEmpty
        ? '?'
        : s.fullName
              .trim()
              .split(' ')
              .where((e) => e.isNotEmpty)
              .take(2)
              .map((e) => e[0].toUpperCase())
              .join();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.fullName,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: row.className == null
                                ? AppColors.accentRedLight
                                : AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            row.className ?? 'Not enrolled',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: row.className == null
                                  ? AppColors.accentRed
                                  : AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            s.matricule ?? 'No matricule',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant.withOpacity(
                                0.7,
                              ),
                            ),
                          ),
                        ),
                        if (s.gender != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            s.gender!,
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 11,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.onSurfaceVariant,
                ),
                onPressed: onTap,
              ),
              if (isAdmin) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Edit',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Delete',
                  onPressed: onDelete,
                ),
              ],
            ],
          ),
        ),
      ),
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
          const Icon(
            Icons.error_outline_rounded,
            size: 36,
            color: AppColors.accentRed,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _friendlyError(error),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12,
              color: AppColors.onSurfaceVariant.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _StudentDraft {
  final String fullName;
  final String? matricule;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? placeOfBirth;
  final String? guardianName;
  final String? guardianPhone;
  final bool repeater;
  final String? classId;
  _StudentDraft({
    required this.fullName,
    this.matricule,
    this.dateOfBirth,
    this.gender,
    this.placeOfBirth,
    this.guardianName,
    this.guardianPhone,
    this.repeater = false,
    this.classId,
  });
}

class _StudentDialog extends StatefulWidget {
  final List<SchoolClass> classes;
  final StudentWithEnrollment? existing;
  const _StudentDialog({required this.classes, this.existing});

  @override
  State<_StudentDialog> createState() => _StudentDialogState();
}

class _StudentDialogState extends State<_StudentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name,
      _placeOfBirth,
      _guardianName,
      _guardianPhone;
  DateTime? _dob;
  String? _gender;
  String? _classId;
  bool _repeater = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.student.fullName ?? '');
    _placeOfBirth = TextEditingController(text: e?.student.placeOfBirth ?? '');
    _guardianName = TextEditingController(text: e?.student.guardianName ?? '');
    _guardianPhone = TextEditingController(
      text: e?.student.guardianPhone ?? '',
    );
    _dob = e?.student.dateOfBirth;
    _gender = e?.student.gender;
    _classId = e?.classId;
    _repeater = e?.student.repeater ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _placeOfBirth.dispose();
    _guardianName.dispose();
    _guardianPhone.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _StudentDraft(
        fullName: _name.text.trim(),
        matricule: null,
        placeOfBirth: _placeOfBirth.text.trim().isEmpty
            ? null
            : _placeOfBirth.text.trim(),
        guardianName: _guardianName.text.trim().isEmpty
            ? null
            : _guardianName.text.trim(),
        guardianPhone: _guardianPhone.text.trim().isEmpty
            ? null
            : _guardianPhone.text.trim(),
        dateOfBirth: _dob,
        gender: _gender,
        repeater: _repeater,
        classId: _classId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AppModal(
      title: isEdit ? 'Edit student' : 'Add student',
      icon: Icons.person_outline_rounded,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Full name *',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            if (isEdit)
              Text(
                'Matricule: ${widget.existing!.student.matricule ?? 'Generated on save'}',
              ),
            if (isEdit) const SizedBox(height: 14),
            const SizedBox(height: 14),
            TextFormField(
              controller: _placeOfBirth,
              decoration: const InputDecoration(
                labelText: 'Place of birth (optional)',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _guardianName,
                    decoration: const InputDecoration(
                      labelText: 'Parent / guardian name (optional)',
                      prefixIcon: Icon(Icons.family_restroom_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _guardianPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Guardian phone (optional)',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Repeater (redoublant)',
                style: TextStyle(fontFamily: 'Lexend', fontSize: 13),
              ),
              value: _repeater,
              onChanged: (v) => setState(() => _repeater = v),
            ),
            const SizedBox(height: 14),
            Text(
              'Gender',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<String?>(
              segments: const [
                ButtonSegment(
                  value: null,
                  label: Text('Not set'),
                  icon: Icon(Icons.remove, size: 16),
                ),
                ButtonSegment(
                  value: 'M',
                  label: Text('M'),
                  icon: Icon(Icons.male, size: 16),
                ),
                ButtonSegment(
                  value: 'F',
                  label: Text('F'),
                  icon: Icon(Icons.female, size: 16),
                ),
              ],
              selected: {_gender},
              onSelectionChanged: (s) => setState(() => _gender = s.first),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dob ?? DateTime(2010),
                  firstDate: DateTime(1950),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _dob = picked);
              },
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date of birth',
                  prefixIcon: const Icon(Icons.cake_outlined),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
                child: Text(
                  _dob == null
                      ? 'Select date'
                      : '${_dob!.day}/${_dob!.month}/${_dob!.year}',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13,
                    color: _dob == null
                        ? AppColors.onSurfaceVariant.withOpacity(0.5)
                        : AppColors.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            AppDropdown<String?>(
              label: 'Class',
              value: _classId,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Not enrolled yet'),
                ),
                ...widget.classes.map(
                  (c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _classId = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppModalButton(
          label: isEdit ? 'Save changes' : 'Add student',
          onPressed: _submit,
        ),
      ],
    );
  }
}
