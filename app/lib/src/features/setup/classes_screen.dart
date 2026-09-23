import 'package:academic_engine/academic_engine.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../data/entities.dart';
import '../../data/repositories/academic_repository.dart';
import '../../core/widgets/shimmer.dart';

/// Admin module: list the school's classes for the current academic year,
/// create new ones (full hierarchy + subject set), edit or inactivate them.
///
/// Read for admins and teachers; create/edit/delete require an admin role.
class ClassesScreen extends StatefulWidget {
  final SupabaseClient client;
  final School school;

  const ClassesScreen({super.key, required this.client, required this.school});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  late final AcademicRepository _academic;
  late Future<_ClassesData> _future;

  @override
  void initState() {
    super.initState();
    _academic = AcademicRepository(widget.client);
    _future = _load();
  }

  Future<_ClassesData> _load() async {
    final years = await _academic.academicYears(widget.school.id);
    final year = years.firstWhere(
      (y) => y.isCurrent,
      orElse: () => years.isNotEmpty
          ? years.first
          : (throw StateError('No academic year')),
    );
    final results = await Future.wait([
      _academic.classesFor(schoolId: widget.school.id, academicYearId: year.id),
      _academic.cycles(),
      _academic.levels(),
      _academic.series(),
      _academic.specialties(),
      _academic.subjectsForSchool(schoolId: widget.school.id),
      _academic.educationTypes(),
    ]);
    return _ClassesData(
      year: year,
      classes: results[0] as List<SchoolClass>,
      cycles: results[1] as List<Cycle>,
      levels: results[2] as List<Level>,
      series: results[3] as List<Series>,
      specialties: results[4] as List<Specialty>,
      subjects: results[5] as List<Subject>,
      educationTypes: results[6] as List<EducationType>,
    );
  }

  void _refresh() => setState(() {
    _future = _load();
  });

  Future<void> _create() async {
    final data = await _future;
    if (!mounted) return;
    final draft = await showDialog<_ClassSubmission>(
      context: context,
      builder: (_) => _ClassEditorDialog(
        school: widget.school,
        yearId: data.year.id,
        cycles: data.cycles,
        levels: data.levels,
        series: data.series,
        specialties: data.specialties,
        subjects: data.subjects,
        educationTypes: data.educationTypes,
        academic: _academic,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      final created = await _academic.createClass(
        schoolId: widget.school.id,
        academicYearId: data.year.id,
        subsystem: draft.subsystem,
        educationTypeId: draft.educationTypeId,
        cycleId: draft.cycleId,
        levelId: draft.levelId,
        seriesId: draft.seriesId,
        specialtyId: draft.specialtyId,
        name: draft.name,
        room: draft.room,
      );
      if (draft.subjectMode == SubjectSetMode.custom &&
          draft.customEntries.isNotEmpty) {
        final ctx = AcademicContext(
          schoolId: created.schoolId,
          academicYearId: created.academicYearId,
          subsystem: created.subsystem,
          educationTypeId: created.educationTypeId,
          cycleId: created.cycleId,
          levelId: created.levelId,
          seriesId: created.seriesId,
          specialtyId: created.specialtyId,
          classId: created.id,
        );
        await _academic.setClassSubjects(
          ctx: ctx,
          entries: draft.customEntries,
        );
      }
      _refresh();
    } on Exception catch (e) {
      if (!mounted) return;
      _showError('Could not create the class', e);
    }
  }

  Future<void> _edit(SchoolClass cls) async {
    final data = await _future;
    if (!mounted) return;
    final draft = await showDialog<_ClassSubmission>(
      context: context,
      builder: (_) => _ClassEditorDialog(
        school: widget.school,
        yearId: data.year.id,
        cycles: data.cycles,
        levels: data.levels,
        series: data.series,
        specialties: data.specialties,
        subjects: data.subjects,
        educationTypes: data.educationTypes,
        academic: _academic,
        existing: cls,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await _academic.updateClass(cls.id, name: draft.name, room: draft.room);
      _refresh();
    } on Exception catch (e) {
      if (!mounted) return;
      _showError('Could not update the class', e);
    }
  }

  Future<void> _toggleActive(SchoolClass cls, bool active) async {
    try {
      await _academic.updateClass(cls.id, isActive: active);
      _refresh();
    } on Exception catch (e) {
      if (!mounted) return;
      _showError('Could not update the class', e);
    }
  }

  void _showError(String message, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$message: $error')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 24),
      child: FutureBuilder<_ClassesData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ShimmerPanel();
          }
          if (snapshot.hasError) {
            return _ErrorPane(
              message: 'Could not load classes.',
              error: snapshot.error!,
              onRetry: _refresh,
            );
          }
          final data = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Classes',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(width: 12),
                  Chip(
                    avatar: const Icon(Icons.event, size: 16),
                    label: Text(data.year.name),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add),
                    label: const Text('New class'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (data.classes.isEmpty)
                const _EmptyClasses()
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: data.classes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final cls = data.classes[i];
                      return _ClassTile(
                        cls: cls,
                        onEdit: () => _edit(cls),
                        onToggleActive: (v) => _toggleActive(cls, v),
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
}

class _ClassesData {
  final AcademicYear year;
  final List<SchoolClass> classes;
  final List<Cycle> cycles;
  final List<Level> levels;
  final List<Series> series;
  final List<Specialty> specialties;
  final List<Subject> subjects;
  final List<EducationType> educationTypes;

  _ClassesData({
    required this.year,
    required this.classes,
    required this.cycles,
    required this.levels,
    required this.series,
    required this.specialties,
    required this.subjects,
    required this.educationTypes,
  });
}

class _ClassTile extends StatelessWidget {
  final SchoolClass cls;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggleActive;

  const _ClassTile({
    required this.cls,
    required this.onEdit,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    String subtitle = cls.levelName ?? '';
    if (cls.seriesName != null) subtitle += ' · ${cls.seriesName}';
    if (cls.specialtyName != null) subtitle += ' · ${cls.specialtyName}';
    if (cls.room != null && cls.room!.isNotEmpty)
      subtitle += '  ·  Room ${cls.room}';

    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.menu_book_outlined)),
        title: Text(cls.name),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: cls.isActive, onChanged: onToggleActive),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: onEdit,
            ),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}

class _EmptyClasses extends StatelessWidget {
  const _EmptyClasses();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const Icon(Icons.add, size: 40),
            const SizedBox(height: 8),
            const Text('No classes yet'),
            const SizedBox(height: 4),
            Text(
              'Create your first class to start building the academic structure.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
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

class _ClassSubmission {
  final String subsystem;
  final String educationTypeId;
  final String cycleId;
  final String levelId;
  final String? seriesId;
  final String? specialtyId;
  final String name;
  final String? room;
  final SubjectSetMode subjectMode;
  final List<({String subjectId, double coefficient, double? weeklyHours})>
  customEntries;

  _ClassSubmission({
    required this.subsystem,
    required this.educationTypeId,
    required this.cycleId,
    required this.levelId,
    this.seriesId,
    this.specialtyId,
    required this.name,
    this.room,
    required this.subjectMode,
    required this.customEntries,
  });
}

enum SubjectSetMode { national, custom }

/// One customizable subject row for a class subject set.
class SubjectEntry {
  final Subject subject;
  double coefficient;
  bool selected;
  late final TextEditingController controller;

  SubjectEntry({
    required this.subject,
    required this.coefficient,
    this.selected = true,
  }) {
    controller = TextEditingController(text: _fmtCoeff(coefficient));
  }

  void dispose() => controller.dispose();
}

String _fmtCoeff(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

enum _Source { national, custom }

/// Create/edit class form. On creation it also lets the admin pick the subject
/// set (national default vs. a custom set with per-subject coefficients).
class _ClassEditorDialog extends StatefulWidget {
  final School school;
  final String yearId;
  final List<Cycle> cycles;
  final List<Level> levels;
  final List<Series> series;
  final List<Specialty> specialties;
  final List<Subject> subjects;
  final List<EducationType> educationTypes;
  final AcademicRepository academic;
  final SchoolClass? existing;

  const _ClassEditorDialog({
    required this.school,
    required this.yearId,
    required this.cycles,
    required this.levels,
    required this.series,
    required this.specialties,
    required this.subjects,
    required this.educationTypes,
    required this.academic,
    this.existing,
  });

  @override
  State<_ClassEditorDialog> createState() => _ClassEditorDialogState();
}

class _ClassEditorDialogState extends State<_ClassEditorDialog> {
  final _formKey = GlobalKey<FormState>();

  late String _subsystem;
  late String _educationTypeId;
  String? _cycleId;
  String? _levelId;
  String? _seriesId;
  String? _specialtyId;
  final _nameController = TextEditingController();
  final _roomController = TextEditingController();
  _Source _source = _Source.national;
  late List<SubjectEntry> _customEntries;
  bool _busy = false;
  bool _previewing = false;
  int _previewCount = 0;

  List<String> get _subsystemOptions => switch (widget.school.subsystem) {
    'BILINGUAL' => const ['FRANCOPHONE', 'ANGLOPHONE'],
    _ => [widget.school.subsystem],
  };

  List<String> get _educationTypeOptions => switch (widget.school.schoolType) {
    'BOTH' => const ['GENERAL', 'TECHNICAL'],
    _ => [widget.school.schoolType],
  };

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _subsystem = existing?.subsystem ?? _subsystemOptions.first;
    final typeCode = _educationTypeOptions.first;
    _educationTypeId =
        existing?.educationTypeId ?? _idForEducationType(typeCode);
    _cycleId = existing?.cycleId;
    _levelId = existing?.levelId;
    _seriesId = existing?.seriesId;
    _specialtyId = existing?.specialtyId;
    _nameController.text = existing?.name ?? '';
    _roomController.text = existing?.room ?? '';

    _customEntries = widget.subjects.map((s) {
      return SubjectEntry(subject: s, coefficient: 1);
    }).toList();
  }

  String _idForEducationType(String code) {
    for (final et in widget.educationTypes) {
      if (et.code == code) return et.id;
    }
    return widget.educationTypes.isEmpty ? '' : widget.educationTypes.first.id;
  }

  List<Cycle> get _cyclesForType => widget.cycles
      .where(
        (c) =>
            c.educationTypeId == _educationTypeId &&
            (c.subsystem == null || c.subsystem == _subsystem),
      )
      .toList();

  List<Level> get _levelsForSelection {
    if (_cycleId == null) return const [];
    return widget.levels
        .where(
          (l) =>
              l.cycleId == _cycleId &&
              (l.subsystem == null || l.subsystem == _subsystem),
        )
        .toList();
  }

  List<Series> get _seriesForType => widget.series
      .where(
        (s) =>
            s.educationTypeId == _educationTypeId &&
            (s.subsystem == null || s.subsystem == _subsystem),
      )
      .toList();

  List<Specialty> get _specialtiesForSeries {
    if (_seriesId == null) return const [];
    return widget.specialties.where((s) => s.seriesId == _seriesId).toList();
  }

  List<SubjectEntry> get _selectedEntries =>
      _customEntries.where((e) => e.selected).toList();

  void _autoName() {
    final levels = widget.levels.where((l) => l.id == _levelId).toList();
    final level = levels.isEmpty ? null : levels.first;
    if (level == null) return;
    final base = level.name;
    final matches = widget.series.where((s) => s.id == _seriesId).toList();
    final series = matches.isEmpty ? null : matches.first;
    final suggested = series == null ? base : '$base ${series.code}';
    final currentName = _nameController.text.trim();
    if (currentName.isEmpty || currentName == _lastSuggestedName) {
      _nameController.text = suggested;
      _lastSuggestedName = suggested;
    }
  }

  String _lastSuggestedName = '';

  Future<void> _previewSubjects() async {
    final cycleId = _cycleId;
    final levelId = _levelId;
    if (cycleId == null || levelId == null) return;
    setState(() => _previewing = true);
    try {
      final ctx = AcademicContext(
        schoolId: widget.school.id,
        academicYearId: widget.yearId,
        subsystem: _subsystem,
        educationTypeId: _educationTypeId,
        cycleId: cycleId,
        levelId: levelId,
        seriesId: _seriesId,
        specialtyId: _specialtyId,
        classId: 'preview',
      );
      final setup = await widget.academic.loadAcademicSetup(ctx);
      if (!mounted) return;
      setState(() {
        _previewCount = setup.subjects.length;
        // Seed the custom list with the national set so "custom" starts from
        // a sensible baseline.
        final national = {
          for (final s in setup.subjects) s.subjectId: s.coefficient,
        };
        for (final e in _customEntries) {
          e.selected = national.containsKey(e.subject.id);
          e.coefficient = national[e.subject.id] ?? 1;
          e.controller.text = _fmtCoeff(e.coefficient);
        }
      });
    } on Exception {
      if (mounted) setState(() => _previewCount = 0);
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<_ClassSubmission?> _submit() async {
    if (!_formKey.currentState!.validate()) return null;
    final levelId = _levelId;
    final cycleId = _cycleId;
    if (levelId == null || cycleId == null) return null;
    final name = _nameController.text.trim();
    if (name.isEmpty) return null;

    return _ClassSubmission(
      subsystem: _subsystem,
      educationTypeId: _educationTypeId,
      cycleId: cycleId,
      levelId: levelId,
      seriesId: _seriesId,
      specialtyId: _specialtyId,
      name: name,
      room: _roomController.text.trim().isEmpty
          ? null
          : _roomController.text.trim(),
      subjectMode: _source == _Source.custom
          ? SubjectSetMode.custom
          : SubjectSetMode.national,
      customEntries: _selectedEntries
          .map(
            (e) => (
              subjectId: e.subject.id,
              coefficient: e.coefficient,
              weeklyHours: null,
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit class' : 'New class'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isEdit)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accentAmberLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.accentAmber.withOpacity(0.3),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: AppColors.accentAmber,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Level, series and specialty cannot be changed after creation '
                            '(they drive the curriculum). Edit the name and room here — '
                            'create a new class to change the academic path.',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _dropdown(
                  label: 'Education type',
                  value: _educationTypeId,
                  enabled: !isEdit,
                  items: _educationTypeOptions.map((code) {
                    final et = widget.educationTypes
                        .where((e) => e.code == code)
                        .toList();
                    final match = et.isEmpty ? null : et.first;
                    final id = match?.id ?? _educationTypeId;
                    final label = match?.name ?? code;
                    return (id, label);
                  }).toList(),
                  onChanged: (v) {
                    setState(() {
                      _educationTypeId = v!;
                      _cycleId = null;
                      _levelId = null;
                      _seriesId = null;
                      _specialtyId = null;
                      _previewCount = 0;
                    });
                  },
                ),
                _dropdown(
                  label: 'Sub-system',
                  value: _subsystem,
                  enabled: !isEdit,
                  items: _subsystemOptions.map((s) => (s, s)).toList(),
                  onChanged: _subsystemOptions.length == 1
                      ? null
                      : (v) => setState(() {
                          _subsystem = v!;
                          _cycleId = null;
                          _levelId = null;
                          _seriesId = null;
                          _previewCount = 0;
                        }),
                ),
                _dropdown(
                  label: 'Cycle',
                  value: _cycleId,
                  enabled: !isEdit,
                  items: _cyclesForType
                      .map(
                        (c) => (
                          c.id,
                          '${c.name} (${c.code})${c.subsystem != null ? ' · ${c.subsystem}' : ''}',
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    _cycleId = v;
                    _levelId = null;
                    _seriesId = null;
                    _previewCount = 0;
                  }),
                ),
                _dropdown(
                  label: 'Level',
                  value: _levelId,
                  enabled: !isEdit,
                  items: _levelsForSelection
                      .map((l) => (l.id, l.name))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _levelId = v;
                      _previewCount = 0;
                    });
                    _autoName();
                    _previewSubjects();
                  },
                ),
                _dropdown(
                  label: 'Series (optional)',
                  value: _seriesId,
                  enabled: !isEdit,
                  items: [
                    (null, '— None —'),
                    ..._seriesForType.map(
                      (s) => (s.id, '${s.name} (${s.code})'),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _seriesId = v;
                    _specialtyId = null;
                    _previewCount = 0;
                    _autoName();
                    _previewSubjects();
                  }),
                ),
                if (_specialtiesForSeries.isNotEmpty)
                  _dropdown(
                    label: 'Specialty',
                    value: _specialtyId,
                    enabled: !isEdit,
                    items: [
                      (null, '— None —'),
                      ..._specialtiesForSeries.map(
                        (s) => (s.id, '${s.name} (${s.code})'),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      _specialtyId = v;
                      _previewCount = 0;
                      _previewSubjects();
                    }),
                  ),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Class name'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                TextFormField(
                  controller: _roomController,
                  decoration: const InputDecoration(
                    labelText: 'Room (optional)',
                  ),
                ),
                if (!isEdit) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.menu_book_outlined, size: 16),
                      const SizedBox(width: 8),
                      if (_previewing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Text(
                          _previewCount == 0
                              ? 'Select a level to preview subjects'
                              : '$_previewCount subjects resolve for this class',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<_Source>(
                    segments: const [
                      ButtonSegment(
                        value: _Source.national,
                        label: Text('National set'),
                      ),
                      ButtonSegment(
                        value: _Source.custom,
                        label: Text('Customize'),
                      ),
                    ],
                    selected: {_source},
                    onSelectionChanged: (s) =>
                        setState(() => _source = s.first),
                  ),
                  if (_source == _Source.custom) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        itemCount: _customEntries.length,
                        itemBuilder: (context, i) {
                          final e = _customEntries[i];
                          return CheckboxListTile(
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: e.selected,
                            onChanged: (v) =>
                                setState(() => e.selected = v ?? false),
                            title: Text(
                              e.subject.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(e.subject.code),
                            secondary: SizedBox(
                              width: 72,
                              child: TextField(
                                enabled: e.selected,
                                controller: e.controller,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Coeff',
                                  isDense: true,
                                ),
                                onChanged: (v) => e.coefficient =
                                    double.tryParse(v) ?? e.coefficient,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
                if (isEdit) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.menu_book_outlined,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Subjects and coefficients follow the level / series '
                            'curriculum. Manage them in Subjects.',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant.withOpacity(
                                0.8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final submission = await _submit();
                  if (!context.mounted) return;
                  Navigator.pop(context, submission);
                },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<(String?, String)> items,
    required ValueChanged<String?>? onChanged,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String?>(
        key: ObjectKey('${value ?? ''}::$label'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
        items: items
            .map((it) => DropdownMenuItem(value: it.$1, child: Text(it.$2)))
            .toList(),
        onChanged: enabled ? onChanged : null,
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roomController.dispose();
    super.dispose();
  }
}
