import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/shimmer.dart';
import '../../data/entities.dart';
import '../../data/repositories/academic_repository.dart';
import '../../data/repositories/teacher_repository.dart';

/// Teacher registry & assignments (spec section 37).
///
///   * Teachers tab — staff directory; admins add teachers (by email) and
///     remove them. Every teacher shows their assignment count.
///   * Assignments tab — teacher → class → subject → role rows; admins create
///     and delete assignments (+ optional specialty for technical schools).
///   * Class teachers — per-class professeur principal selection.
class TeachersScreen extends StatefulWidget {
  final SupabaseClient client;
  final School school;
  final bool isAdmin;

  const TeachersScreen({
    super.key,
    required this.client,
    required this.school,
    required this.isAdmin,
  });

  @override
  State<TeachersScreen> createState() => _TeachersScreenState();
}

class _TeachersScreenState extends State<TeachersScreen> {
  late final AcademicRepository _academic;
  late final TeacherRepository _teachers;
  late Future<_TeachersData> _future;

  @override
  void initState() {
    super.initState();
    _academic = AcademicRepository(widget.client);
    _teachers = TeacherRepository(widget.client);
    _future = _load();
  }

  Future<_TeachersData> _load() async {
    final years = await _academic.academicYears(widget.school.id);
    final year = years.firstWhere(
      (y) => y.isCurrent,
      orElse: () => years.isNotEmpty
          ? years.first
          : (throw StateError('No academic year')),
    );
    final results = await Future.wait([
      _teachers.listMembers(widget.school.id),
      _academic.classesFor(schoolId: widget.school.id, academicYearId: year.id),
      _academic.subjectsForSchool(schoolId: widget.school.id),
      _academic.specialties(),
      _teachers.listAssignments(
        schoolId: widget.school.id,
        academicYearId: year.id,
      ),
    ]);
    return _TeachersData(
      year: year,
      members: results[0] as List<SchoolMember>,
      classes: results[1] as List<SchoolClass>,
      subjects: results[2] as List<Subject>,
      specialties: results[3] as List<Specialty>,
      assignments: results[4] as List<TeacherAssignmentDetail>,
    );
  }

  void _refresh() => setState(() {
    _future = _load();
  });

  void _showError(String message, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$message: $error')));
  }

  Future<void> _addTeacher() async {
    final draft = await showDialog<_TeacherDraft>(
      context: context,
      builder: (_) => const _AddTeacherDialog(),
    );
    if (draft == null || !mounted) return;
    try {
      final result = await _teachers.createTeacher(
        schoolId: widget.school.id,
        fullName: draft.fullName,
        email: draft.email,
        phone: draft.phone,
        staffId: draft.staffId,
      );
      _refresh();
      if (!mounted) return;
      if (result['created'] == true && result['password'] is String) {
        await showDialog<void>(
          context: context,
          builder: (_) => _PasswordRevealDialog(
            fullName: result['full_name']?.toString() ?? draft.fullName,
            email: result['email']?.toString() ?? draft.email,
            password: result['password']!.toString(),
          ),
        );
      } else if (result['alreadyMember'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That user is already a member of this school.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added existing account (${draft.email}) as a teacher.',
            ),
          ),
        );
      }
    } on Exception catch (e) {
      if (!mounted) return;
      final message = e is PostgrestException ? e.message : '$e';
      final friendly = message.contains('administrators can create teachers')
          ? 'Only an administrator can add teachers.'
          : message.contains('already registered') ||
                message.contains('already exists')
          ? 'An account with this email already exists — it was not re-created.'
          : 'Could not add the teacher: $message';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendly)));
    }
  }

  Future<void> _removeTeacher(SchoolMember member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove teacher'),
        content: Text(
          'Remove ${member.fullName} from this school? Their teaching '
          'assignments and mark books will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _teachers.removeTeacher(
        schoolId: widget.school.id,
        membershipId: member.membershipId,
      );
      _refresh();
    } on Exception catch (e) {
      _showError('Could not remove the teacher', e);
    }
  }

  Future<void> _resetTeacherPassword(SchoolMember member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset password'),
        content: Text(
          'Generate a new password for ${member.fullName}? Use this if they '
          'lost it or it may be compromised. The old password stops working '
          'immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Generate new password'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final result = await _teachers.resetTeacherPassword(
        schoolId: widget.school.id,
        membershipId: member.membershipId,
      );
      if (!mounted) return;
      if (result['password'] is String) {
        await showDialog<void>(
          context: context,
          builder: (_) => _PasswordRevealDialog(
            fullName: result['full_name']?.toString() ?? member.fullName,
            email: result['email']?.toString() ?? '',
            password: result['password']!.toString(),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reset the password.')),
        );
      }
    } on Exception catch (e) {
      _showError('Could not reset the password', e);
    }
  }

  Future<void> _addAssignment(_TeachersData data) async {
    final draft = await showDialog<_AssignmentDraft>(
      context: context,
      builder: (_) => _AssignmentDialog(
        members: data.members.where((m) => m.role == 'TEACHER').toList(),
        classes: data.classes,
        subjects: data.subjects,
        specialties: data.specialties,
        showSpecialty: widget.school.schoolType != 'GENERAL',
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await _teachers.createAssignment(
        schoolId: widget.school.id,
        academicYearId: data.year.id,
        teacherMembershipId: draft.teacherMembershipId,
        classId: draft.classId,
        subjectId: draft.subjectId,
        specialtyId: draft.specialtyId,
        teachingRole: draft.role,
      );
      _refresh();
    } on Exception catch (e) {
      _showError('Could not create the assignment', e);
    }
  }

  Future<void> _deleteAssignment(TeacherAssignmentDetail assignment) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete assignment'),
        content: Text(
          'Remove ${assignment.teacherName} from ${assignment.className} · '
          '${assignment.subjectName}?',
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
      await _teachers.deleteAssignment(assignment.id);
      _refresh();
    } on Exception catch (e) {
      _showError('Could not delete the assignment', e);
    }
  }

  Future<void> _setClassTeacher(SchoolClass cls, String? membershipId) async {
    try {
      await _teachers.setClassTeacher(
        classId: cls.id,
        membershipId: membershipId,
      );
      _refresh();
    } on Exception catch (e) {
      _showError('Could not set the class teacher', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: FutureBuilder<_TeachersData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const ShimmerPanel();
          }
          if (snap.hasError) {
            return _ErrorPane(
              message: 'Could not load teachers.',
              error: snap.error!,
              onRetry: _refresh,
            );
          }
          final data = snap.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                  20,
                  MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                  0,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TEACHER REGISTRY',
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
                          'Teachers & assignments',
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
                            data.year.name,
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
                    if (widget.isAdmin) ...[
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      const SizedBox(width: 4),
                      FilledButton.icon(
                        onPressed: _addTeacher,
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: const Text('Add teacher'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const TabBar(
                tabs: [
                  Tab(text: 'Teachers', icon: Icon(Icons.groups_outlined)),
                  Tab(
                    text: 'Assignments & class teachers',
                    icon: Icon(Icons.hub_outlined),
                  ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _TeachersListTab(
                      data: data,
                      isAdmin: widget.isAdmin,
                      onRemove: _removeTeacher,
                      onResetPassword: _resetTeacherPassword,
                    ),
                    _AssignmentsTab(
                      data: data,
                      isAdmin: widget.isAdmin,
                      onAdd: () => _addAssignment(data),
                      onDelete: _deleteAssignment,
                      onSetClassTeacher: _setClassTeacher,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TeachersData {
  final AcademicYear year;
  final List<SchoolMember> members;
  final List<SchoolClass> classes;
  final List<Subject> subjects;
  final List<Specialty> specialties;
  final List<TeacherAssignmentDetail> assignments;

  _TeachersData({
    required this.year,
    required this.members,
    required this.classes,
    required this.subjects,
    required this.specialties,
    required this.assignments,
  });
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

String _roleLabel(String role) => role.replaceAll('_', ' ').toLowerCase();

// =============================================================================
// Tab 1 — Teachers
// =============================================================================

class _TeachersListTab extends StatelessWidget {
  final _TeachersData data;
  final bool isAdmin;
  final ValueChanged<SchoolMember> onRemove;
  final ValueChanged<SchoolMember> onResetPassword;

  const _TeachersListTab({
    required this.data,
    required this.isAdmin,
    required this.onRemove,
    required this.onResetPassword,
  });

  @override
  Widget build(BuildContext context) {
    final teachers = data.members.where((m) => m.role == 'TEACHER').toList();
    final staff = data.members.where((m) => m.role != 'TEACHER').toList();
    final countByTeacher = <String, int>{};
    for (final a in data.assignments) {
      countByTeacher[a.teacherMembershipId] =
          (countByTeacher[a.teacherMembershipId] ?? 0) + 1;
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '${teachers.length} teachers · ${staff.length} other staff',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (teachers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No teachers yet — add one with "Add teacher".'),
            ),
          ),
        for (final m in [...teachers, ...staff])
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text(
                  m.fullName.isEmpty
                      ? '?'
                      : m.fullName.characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(
                m.fullName,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                [
                  if (m.email != null && m.email!.isNotEmpty) m.email!,
                  if (m.staffId != null && m.staffId!.isNotEmpty)
                    'Staff: ${m.staffId}',
                ].join(' · '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      _roleLabel(m.role),
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  if (m.role == 'TEACHER' &&
                      countByTeacher.containsKey(m.membershipId))
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '${countByTeacher[m.membershipId]} assignments',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (isAdmin && m.role == 'TEACHER') ...[
                    IconButton(
                      icon: const Icon(Icons.password_rounded, size: 18),
                      tooltip: 'Reset password',
                      onPressed: () => onResetPassword(m),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      tooltip: 'Remove',
                      onPressed: () => onRemove(m),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Tab 2 — Assignments & class teachers
// =============================================================================

class _AssignmentsTab extends StatelessWidget {
  final _TeachersData data;
  final bool isAdmin;
  final VoidCallback onAdd;
  final ValueChanged<TeacherAssignmentDetail> onDelete;
  final void Function(SchoolClass cls, String? membershipId) onSetClassTeacher;

  const _AssignmentsTab({
    required this.data,
    required this.isAdmin,
    required this.onAdd,
    required this.onDelete,
    required this.onSetClassTeacher,
  });

  @override
  Widget build(BuildContext context) {
    final teachers = data.members.where((m) => m.role == 'TEACHER').toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text(
              'Teacher assignments',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            if (isAdmin)
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('New assignment'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (data.assignments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No assignments yet.'),
          ),
        for (final a in data.assignments)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              dense: true,
              leading: const Icon(
                Icons.school_outlined,
                color: AppColors.primary,
                size: 20,
              ),
              title: Text(
                '${a.teacherName} → ${a.className}',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                [
                  a.subjectName,
                  if (a.specialtyName != null) a.specialtyName!,
                  if (a.teachingRole == 'CLASS_TEACHER') 'class teacher',
                ].join(' · '),
              ),
              trailing: isAdmin
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Delete',
                      onPressed: () => onDelete(a),
                    )
                  : null,
            ),
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Text(
              'Class teachers (professeur principal)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Each class can have one class teacher selected from the staff.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (data.classes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No classes for this academic year.'),
          ),
        for (final cls in data.classes)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      cls.name,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String?>(
                      initialValue: cls.classTeacherId,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Class teacher',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('— None —'),
                        ),
                        ...teachers.map(
                          (t) => DropdownMenuItem(
                            value: t.membershipId,
                            child: Text(
                              t.fullName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: isAdmin
                          ? (v) => onSetClassTeacher(cls, v)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Dialogs
// =============================================================================

class _TeacherDraft {
  final String fullName;
  final String email;
  final String? phone;
  final String? staffId;
  _TeacherDraft({
    required this.fullName,
    required this.email,
    this.phone,
    this.staffId,
  });
}

class _AddTeacherDialog extends StatefulWidget {
  const _AddTeacherDialog();

  @override
  State<_AddTeacherDialog> createState() => _AddTeacherDialogState();
}

class _AddTeacherDialogState extends State<_AddTeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _staffId = TextEditingController();

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _staffId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'Add teacher',
      icon: Icons.person_add_rounded,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accentAmberLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.accentAmber.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: AppColors.accentAmber,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'How it works',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    'An account is created automatically with a generated password, '
                    'which you can share by WhatsApp, email or SMS. The teacher can '
                    'also reset it from the app (Forgot password).',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _fullName,
              decoration: const InputDecoration(
                labelText: 'Full name *',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email *',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty || !v.contains('@'))
                  ? 'Enter a valid email'
                  : null,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone (optional)',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _staffId,
                    decoration: const InputDecoration(
                      labelText: 'Staff ID (optional)',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                ),
              ],
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
          label: 'Create teacher',
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _TeacherDraft(
                fullName: _fullName.text.trim(),
                email: _email.text.trim(),
                phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                staffId: _staffId.text.trim().isEmpty
                    ? null
                    : _staffId.text.trim(),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Shows the one-time generated password so the admin can share it
/// (WhatsApp / email / SMS). Copy button for convenience.
class _PasswordRevealDialog extends StatelessWidget {
  final String fullName;
  final String email;
  final String password;

  const _PasswordRevealDialog({
    required this.fullName,
    required this.email,
    required this.password,
  });

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'Teacher created',
      icon: Icons.check_circle_outline_rounded,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$fullName · $email',
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Share this password with them securely (WhatsApp, email or SMS):',
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    password,
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy password',
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: password));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Password copied to clipboard'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'They sign in with this email and password. If they ever forget it, '
            'they can use "Forgot password" on the login screen to reset it.',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12,
              height: 1.4,
              color: AppColors.onSurfaceVariant.withOpacity(0.8),
            ),
          ),
        ],
      ),
      actions: [
        AppModalButton(label: 'Done', onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}

class _AssignmentDraft {
  final String teacherMembershipId;
  final String classId;
  final String subjectId;
  final String? specialtyId;
  final String role;
  _AssignmentDraft({
    required this.teacherMembershipId,
    required this.classId,
    required this.subjectId,
    this.specialtyId,
    this.role = 'SUBJECT_TEACHER',
  });
}

class _AssignmentDialog extends StatefulWidget {
  final List<SchoolMember> members;
  final List<SchoolClass> classes;
  final List<Subject> subjects;
  final List<Specialty> specialties;
  final bool showSpecialty;

  const _AssignmentDialog({
    required this.members,
    required this.classes,
    required this.subjects,
    required this.specialties,
    required this.showSpecialty,
  });

  @override
  State<_AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends State<_AssignmentDialog> {
  String? _teacher;
  String? _classId;
  String? _subjectId;
  String? _specialtyId;
  String _role = 'SUBJECT_TEACHER';
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'New assignment',
      icon: Icons.hub_outlined,
      width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppDropdown<String>(
            label: 'Teacher *',
            value: _teacher,
            items: widget.members
                .map(
                  (m) => DropdownMenuItem(
                    value: m.membershipId,
                    child: Text(m.fullName),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _teacher = v),
          ),
          const SizedBox(height: 14),
          AppDropdown<String>(
            label: 'Class *',
            value: _classId,
            items: widget.classes
                .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                .toList(),
            onChanged: (v) => setState(() => _classId = v),
          ),
          const SizedBox(height: 14),
          AppDropdown<String>(
            label: 'Subject *',
            value: _subjectId,
            items: widget.subjects
                .map(
                  (s) => DropdownMenuItem(
                    value: s.id,
                    child: Text('${s.name} (${s.code})'),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _subjectId = v),
          ),
          if (widget.showSpecialty) ...[
            const SizedBox(height: 14),
            AppDropdown<String?>(
              label: 'Specialty (optional)',
              value: _specialtyId,
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                ...widget.specialties.map(
                  (s) => DropdownMenuItem(value: s.id, child: Text(s.name)),
                ),
              ],
              onChanged: (v) => setState(() => _specialtyId = v),
            ),
          ],
          const SizedBox(height: 14),
          AppDropdown<String>(
            label: 'Role',
            value: _role,
            items: const [
              DropdownMenuItem(
                value: 'SUBJECT_TEACHER',
                child: Text('Subject teacher'),
              ),
              DropdownMenuItem(
                value: 'CLASS_TEACHER',
                child: Text('Class teacher'),
              ),
            ],
            onChanged: (v) => setState(() => _role = v!),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.accentRed,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppModalButton(
          label: 'Assign',
          onPressed: () {
            if (_teacher == null || _classId == null || _subjectId == null) {
              setState(
                () => _error = 'Teacher, class and subject are required',
              );
              return;
            }
            Navigator.pop(
              context,
              _AssignmentDraft(
                teacherMembershipId: _teacher!,
                classId: _classId!,
                subjectId: _subjectId!,
                specialtyId: _specialtyId,
                role: _role,
              ),
            );
          },
        ),
      ],
    );
  }
}
