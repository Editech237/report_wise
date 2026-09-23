import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/shimmer.dart';
import '../../data/entities.dart';
import '../../data/repositories/results_repository.dart';
import '../../data/repositories/student_repository.dart';

/// Student profile: personal details, enrollment and recent results.
/// Pop with `true` when something changed so the list refreshes.
class StudentDetailsScreen extends StatefulWidget {
  final School school;
  final StudentWithEnrollment row;
  final List<SchoolClass> classes;
  final String academicYearId;
  final bool isAdmin;

  const StudentDetailsScreen({
    super.key,
    required this.school,
    required this.row,
    required this.classes,
    required this.academicYearId,
    required this.isAdmin,
  });

  @override
  State<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends State<StudentDetailsScreen> {
  late final StudentRepository _students;
  late final ResultsRepository _results;
  late Future<List<Map<String, dynamic>>> _resultsFuture;

  @override
  void initState() {
    super.initState();
    _students = StudentRepository(Supabase.instance.client);
    _results = ResultsRepository(Supabase.instance.client);
    _resultsFuture = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final enrollmentId = widget.row.enrollmentId;
    if (enrollmentId == null) return const [];
    return _results.resultsForEnrollment(enrollmentId);
  }

  String _initials(String name) {
    if (name.trim().isEmpty) return '?';
    return name
        .trim()
        .split(' ')
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e[0].toUpperCase())
        .join();
  }

  Future<void> _edit() async {
    final draft = await showDialog<_DetailsDraft>(
      context: context,
      builder: (_) =>
          _DetailsEditDialog(existing: widget.row, classes: widget.classes),
    );
    if (draft == null || !mounted) return;
    try {
      await _students.update(
        widget.row.student.id,
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
          draft.classId != widget.row.classId &&
          widget.row.enrollmentId != null) {
        await _students.updateEnrollment(
          widget.row.enrollmentId!,
          classId: draft.classId!,
        );
      } else if (draft.classId != null && widget.row.enrollmentId == null) {
        await _students.enroll(
          schoolId: widget.school.id,
          studentId: widget.row.student.id,
          academicYearId: widget.academicYearId,
          classId: draft.classId!,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Student updated')));
      Navigator.pop(context, true);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update: $e'),
          backgroundColor: AppColors.accentRed,
        ),
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete student?'),
        content: Text(
          'Delete "${widget.row.student.fullName}"? This cannot be undone.',
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
    if (ok != true || !mounted) return;
    try {
      await _students.delete(widget.row.student.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete: $e'),
          backgroundColor: AppColors.accentRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.row.student;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Student profile',
          style: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700),
        ),
        actions: [
          if (widget.isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: _edit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: _delete,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      child: Text(
                        _initials(s.fullName),
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.fullName,
                            style: const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.matricule ?? 'No matricule',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13,
                              color: AppColors.onSurfaceVariant.withOpacity(
                                0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _InfoCard(
                    title: 'Enrollment',
                    rows: [
                      ('Class', widget.row.className ?? 'Not enrolled'),
                      ('Status', widget.row.status ?? '—'),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _InfoCard(
                    title: 'Profile',
                    rows: [
                      ('Gender', s.gender ?? '—'),
                      (
                        'Date of birth',
                        s.dateOfBirth == null
                            ? '—'
                            : '${s.dateOfBirth!.day}/${s.dateOfBirth!.month}/${s.dateOfBirth!.year}',
                      ),
                      ('Place of birth', s.placeOfBirth ?? '—'),
                      ('Parent / guardian', s.guardianName ?? '—'),
                      ('Guardian phone', s.guardianPhone ?? '—'),
                      ('Repeater', s.repeater ? 'Yes' : 'No'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Recent results',
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _resultsFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const ShimmerBlock(height: 96, radius: 12);
                }
                final list = snap.data ?? const [];
                if (list.isEmpty) {
                  return Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No results computed yet.',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13,
                          color: AppColors.onSurfaceVariant.withOpacity(0.7),
                        ),
                      ),
                    ),
                  );
                }
                return Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final r in list)
                        ListTile(
                          dense: true,
                          title: Text(
                            '${r['period_type'] ?? 'Period'}',
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            r['status'] == 'FINAL' ? 'Finalized' : 'Draft',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Rank ${r['rank'] ?? '—'}',
                                style: const TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                r['general_average']?.toString() ?? '—',
                                style: const TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _InfoCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$k: ',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12.5,
                        color: AppColors.onSurfaceVariant.withOpacity(0.7),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        v,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailsDraft {
  final String fullName;
  final String? matricule;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? placeOfBirth;
  final String? guardianName;
  final String? guardianPhone;
  final bool repeater;
  final String? classId;
  _DetailsDraft({
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

class _DetailsEditDialog extends StatefulWidget {
  final StudentWithEnrollment existing;
  final List<SchoolClass> classes;
  const _DetailsEditDialog({required this.existing, required this.classes});

  @override
  State<_DetailsEditDialog> createState() => _DetailsEditDialogState();
}

class _DetailsEditDialogState extends State<_DetailsEditDialog> {
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
    final s = widget.existing.student;
    _name = TextEditingController(text: s.fullName);
    _placeOfBirth = TextEditingController(text: s.placeOfBirth ?? '');
    _guardianName = TextEditingController(text: s.guardianName ?? '');
    _guardianPhone = TextEditingController(text: s.guardianPhone ?? '');
    _dob = s.dateOfBirth;
    _gender = s.gender;
    _classId = widget.existing.classId;
    _repeater = s.repeater;
  }

  @override
  void dispose() {
    _name.dispose();
    _placeOfBirth.dispose();
    _guardianName.dispose();
    _guardianPhone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'Edit student',
      icon: Icons.edit_outlined,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            Text(
              'Matricule: ${widget.existing.student.matricule ?? 'Generated on save'}',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _placeOfBirth,
              decoration: const InputDecoration(
                labelText: 'Place of birth (optional)',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _guardianName,
              decoration: const InputDecoration(
                labelText: 'Parent / guardian name (optional)',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _guardianPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Guardian phone (optional)',
              ),
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeater (redoublant)'),
              value: _repeater,
              onChanged: (v) => setState(() => _repeater = v),
            ),
            const SizedBox(height: 14),
            SegmentedButton<String?>(
              segments: const [
                ButtonSegment(value: null, label: Text('Not set')),
                ButtonSegment(value: 'M', label: Text('M')),
                ButtonSegment(value: 'F', label: Text('F')),
              ],
              selected: {_gender},
              onSelectionChanged: (s) => setState(() => _gender = s.first),
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
                  (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
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
          label: 'Save',
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _DetailsDraft(
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
                repeater: _repeater,
                dateOfBirth: _dob,
                gender: _gender,
                classId: _classId,
              ),
            );
          },
        ),
      ],
    );
  }
}
