import 'package:academic_engine/academic_engine.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../data/entities.dart';
import '../../data/repositories/academic_repository.dart';
import 'setup_models.dart';
import '../../core/widgets/shimmer.dart';

/// Admin module: per-class coefficient management (with a versioned after-before
/// confirmation, section 34) plus the subject catalog (national + school-owned).
class SubjectsScreen extends StatefulWidget {
  final SupabaseClient client;
  final School school;

  const SubjectsScreen({super.key, required this.client, required this.school});

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  late final AcademicRepository _academic;
  late Future<_SubjectsData> _dataFuture;
  String? _classId;
  Future<_ResolvedRows>? _setupFuture;

  @override
  void initState() {
    super.initState();
    _academic = AcademicRepository(widget.client);
    _dataFuture = _loadData();
  }

  Future<_SubjectsData> _loadData() async {
    final years = await _academic.academicYears(widget.school.id);
    final year = years.firstWhere(
      (y) => y.isCurrent,
      orElse: () => years.isNotEmpty ? years.first : (throw StateError('No academic year')),
    );
    final results = await Future.wait([
      _academic.classesFor(
        schoolId: widget.school.id,
        academicYearId: year.id,
      ),
      _academic.subjectsForSchool(schoolId: widget.school.id),
    ]);
    final data = _SubjectsData(
      year: year,
      classes: results[0] as List<SchoolClass>,
      catalog: results[1] as List<Subject>,
    );
    if (mounted) {
      final first = data.classes.isEmpty ? null : data.classes.first.id;
      setState(() {
        _classId = first;
        _setupFuture = first == null
            ? null
            : _loadSetupFuture(first, data.year, data.catalog);
      });
    }
    return data;
  }

  void _loadSetup(String classId, AcademicYear year, List<Subject> catalog) {
    setState(() {
      _classId = classId;
      _setupFuture = _loadSetupFuture(classId, year, catalog);
    });
  }

  Future<_ResolvedRows> _loadSetupFuture(
    String classId,
    AcademicYear year,
    List<Subject> catalog,
  ) async {
    final cls = await _findClass(classId);
    if (cls == null) throw StateError('Class no longer exists');
    final ctx = _ctxForClass(cls, year);
    final setup = await _academic.loadAcademicSetup(ctx);
    final names = {for (final s in catalog) s.id: s.name};
    final rows = setup.subjects
        .map((s) => _SubjectRow(
              subjectId: s.subjectId,
              name: names[s.subjectId] ?? s.subjectId,
              code: s.subjectId,
              coefficient: s.coefficient,
              source: sourceLabel(s.source.code),
            ))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return _ResolvedRows(className: cls.name, rows: rows);
  }

  Future<SchoolClass?> _findClass(String classId) async {
    final data = await _dataFuture;
    final matches = data.classes.where((c) => c.id == classId).toList();
    return matches.isEmpty ? null : matches.first;
  }

  AcademicContext _ctxForClass(SchoolClass cls, AcademicYear year) {
    return AcademicContext(
      schoolId: cls.schoolId,
      academicYearId: cls.academicYearId,
      subsystem: cls.subsystem,
      educationTypeId: cls.educationTypeId,
      cycleId: cls.cycleId,
      levelId: cls.levelId,
      seriesId: cls.seriesId,
      specialtyId: cls.specialtyId,
      classId: cls.id,
    );
  }

  Future<void> _editCoefficient(
    AcademicYear year,
    SchoolClass cls,
    _SubjectRow row,
  ) async {
    final next = await showDialog<double>(
      context: context,
      builder: (_) => _CoefficientDialog(
        subjectName: row.name,
        current: row.coefficient,
      ),
    );
    if (next == null || !mounted || next == row.coefficient) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmCoefficientDialog(
        subjectName: row.name,
        current: row.coefficient,
        next: next,
        className: cls.name,
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _academic.setClassCoefficient(
        schoolId: cls.schoolId,
        academicYearId: cls.academicYearId,
        subsystem: cls.subsystem,
        educationTypeId: cls.educationTypeId,
        cycleId: cls.cycleId,
        levelId: cls.levelId,
        seriesId: cls.seriesId,
        specialtyId: cls.specialtyId,
        subjectId: row.subjectId,
        coefficient: next,
      );
      _loadSetup(cls.id, year, (await _dataFuture).catalog);
    } on Exception catch (e) {
      _showError('Could not save the coefficient', e);
    }
  }

  Future<void> _addSubject() async {
    final draft = await showDialog<_SubjectDraft>(
      context: context,
      builder: (_) => const _AddSubjectDialog(),
    );
    if (draft == null || !mounted) return;
    try {
      await _academic.addSchoolSubject(
        schoolId: widget.school.id,
        code: draft.code,
        name: draft.name,
        nameFr: draft.nameFr,
        subjectType: draft.subjectType,
      );
      _dataFuture = _loadData();
      setState(() {});
    } on Exception catch (e) {
      if (!mounted) return;
      _showError('Could not add the subject', e);
    }
  }

  Future<void> _deleteSubject(Subject subject) async {
    if (subject.schoolId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete subject'),
        content: Text(
          'Delete "${subject.name}" for this school? This does not affect '
          'national subjects or results already recorded.',
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
      await _academic.deleteSubject(subject.id);
      _dataFuture = _loadData();
      setState(() {});
    } on Exception catch (e) {
      if (!mounted) return;
      _showError('Could not delete the subject', e);
    }
  }

  void _showError(String message, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$message: $error')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: FutureBuilder<_SubjectsData>(
        future: _dataFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const ShimmerPanel();
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load academic setup.'),
                  const SizedBox(height: 8),
                  Text('${snap.error}',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _dataFuture = _loadData();
                    }),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final data = snap.data!;
          if (data.classes.isEmpty) {
            return const Center(child: Text('Create a class first.'));
          }
          if (_classId == null || _setupFuture == null) {
            return const ShimmerPanel();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Subjects & coefficients',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String>(
                      initialValue: _classId,
                      decoration: InputDecoration(
                        labelText: 'Class',
                        isDense: true,
                      ),
                      items: data.classes
                          .map((c) =>
                              DropdownMenuItem(value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) _loadSetup(v, data.year, data.catalog);
                      },
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () {
                      _dataFuture = _loadData();
                      setState(() {});
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<_ResolvedRows>(
                  future: _setupFuture,
                  builder: (context, s) {
                    if (s.connectionState != ConnectionState.done) {
                      return const ShimmerPanel();
                    }
                    if (s.hasError) {
                      return Center(
                        child:
                            Text('Could not resolve subjects: ${s.error}'),
                      );
                    }
                    final resolved = s.data!;
                    final matches =
                        data.classes.where((c) => c.id == _classId).toList();
                    if (matches.isEmpty) {
                      return const Center(child: Text('Select a class.'));
                    }
                    final cls = matches.first;
                    return DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          const TabBar(
                            tabs: [Tab(text: 'Coefficients'), Tab(text: 'Subject catalog')],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _CoefficientsTable(
                                  rows: resolved.rows,
                                  className: resolved.className,
                                  onEdit: (row) =>
                                      _editCoefficient(data.year, cls, row),
                                ),
                                _CatalogList(
                                  catalog: data.catalog,
                                  schoolId: widget.school.id,
                                  onAdd: _addSubject,
                                  onDelete: _deleteSubject,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

class _SubjectsData {
  final AcademicYear year;
  final List<SchoolClass> classes;
  final List<Subject> catalog;

  _SubjectsData({
    required this.year,
    required this.classes,
    required this.catalog,
  });
}

class _SubjectRow {
  final String subjectId;
  final String name;
  final String code;
  final double coefficient;
  final String source;

  _SubjectRow({
    required this.subjectId,
    required this.name,
    required this.code,
    required this.coefficient,
    required this.source,
  });
}

class _ResolvedRows {
  final String className;
  final List<_SubjectRow> rows;

  _ResolvedRows({required this.className, required this.rows});
}

class _CoefficientsTable extends StatelessWidget {
  final List<_SubjectRow> rows;
  final String className;
  final ValueChanged<_SubjectRow> onEdit;

  const _CoefficientsTable({
    required this.rows,
    required this.className,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: rows.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '$className — subjects & coefficients for this class',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          );
        }
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.menu_book_outlined, size: 32, color: AppColors.onSurfaceVariant),
                const SizedBox(height: 10),
                const Text('No subjects resolved for this class',
                    style: TextStyle(fontFamily: 'Manrope', fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  'Subjects come from the national curriculum for this level / series. '
                  'If this looks wrong, check that the class level and series are correct.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.7)),
                ),
              ],
            ),
          );
        }
        final row = rows[i - 1];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 20,
            child: Text(row.code.length > 2 ? row.code.substring(0, 2) : row.code,
                style: Theme.of(context).textTheme.labelSmall),
          ),
          title: Text(row.name),
          subtitle: Text(row.source,
              style: Theme.of(context).textTheme.bodySmall),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('×${_fmt(row.coefficient)}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Change coefficient',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => onEdit(row),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CatalogList extends StatelessWidget {
  final List<Subject> catalog;
  final String schoolId;
  final VoidCallback onAdd;
  final ValueChanged<Subject> onDelete;

  const _CatalogList({
    required this.catalog,
    required this.schoolId,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const Text('National + school subjects'),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Add subject'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: catalog.length,
            itemBuilder: (context, i) {
              final s = catalog[i];
              final owned = s.schoolId == schoolId;
              return ListTile(
                dense: true,
                leading: Icon(
                  owned ? Icons.school_outlined : Icons.public,
                  size: 20,
                ),
                title: Text('${s.name} (${s.code})'),
                subtitle: Text(
                  owned ? 'School-owned' : 'National',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: owned
                    ? IconButton(
                        tooltip: 'Remove from school',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => onDelete(s),
                      )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CoefficientDialog extends StatefulWidget {
  final String subjectName;
  final double current;

  const _CoefficientDialog({
    required this.subjectName,
    required this.current,
  });

  @override
  State<_CoefficientDialog> createState() => _CoefficientDialogState();
}

class _CoefficientDialogState extends State<_CoefficientDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _fmt(widget.current),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Coefficient — ${widget.subjectName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Current: ×${_fmt(widget.current)}',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'New coefficient',
              errorText: _error,
            ),
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
            final value = double.tryParse(_controller.text.trim());
            if (value == null || value <= 0 || value > 100) {
              setState(() => _error = 'Enter a number between 0 and 100');
              return;
            }
            Navigator.pop(context, value);
          },
          child: const Text('Next'),
        ),
      ],
    );
  }
}

/// Versioned after-before confirmation (section 34): makes the impact of the
/// change explicit before a new ACADEMIC_YEAR configuration row is recorded.
class _ConfirmCoefficientDialog extends StatelessWidget {
  final String subjectName;
  final double current;
  final double next;
  final String className;

  const _ConfirmCoefficientDialog({
    required this.subjectName,
    required this.current,
    required this.next,
    required this.className,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final increase = next > current;
    final delta = (next - current).abs();
    return AlertDialog(
      icon: const Icon(Icons.history_toggle_off),
      title: const Text('Confirm coefficient change'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(subjectName, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('$className — recorded for this level/series/specialty',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _pill('Current', '×${_fmt(current)}', theme.colorScheme.surfaceContainerHighest, theme.colorScheme.onSurface),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.arrow_forward),
              ),
              _pill(
                'New',
                '×${_fmt(next)}',
                increase ? theme.colorScheme.primaryContainer : theme.colorScheme.errorContainer,
                increase ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onErrorContainer,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            increase
                ? 'Coefficient increases by ×${_fmt(delta)}. '
                    'This raises the weight of this subject in averages.'
                : 'Coefficient decreases by ×${_fmt(delta)}. '
                    'This lowers the weight of this subject in averages.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'A new versioned configuration (Academic year layer) is recorded. '
            'Previous values are kept for history, and already-locked report '
            'cards are not recalculated.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.check),
          label: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _pill(String label, String value, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: fg)),
          Text(value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: fg,
              )),
        ],
      ),
    );
  }
}

class _SubjectDraft {
  final String code;
  final String name;
  final String? nameFr;
  final String? subjectType;

  _SubjectDraft({
    required this.code,
    required this.name,
    this.nameFr,
    this.subjectType,
  });
}

class _AddSubjectDialog extends StatefulWidget {
  const _AddSubjectDialog();

  @override
  State<_AddSubjectDialog> createState() => _AddSubjectDialogState();
}

class _AddSubjectDialogState extends State<_AddSubjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _nameFr = TextEditingController();
  String? _type = 'GENERAL';

  static const _types = <String, String>{
    'GENERAL': 'General',
    'TECHNICAL': 'Technical',
    'PROFESSIONAL': 'Professional',
    'LANGUAGE': 'Language',
    'PRACTICAL': 'Practical',
    'THEORY': 'Theory',
    'SPORT': 'Sport',
    'OTHER': 'Other',
  };

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _nameFr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add school subject'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _code,
                decoration: const InputDecoration(labelText: 'Code (e.g. AHLA)'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Code is required' : null,
              ),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              TextFormField(
                controller: _nameFr,
                decoration: const InputDecoration(labelText: 'Name (FR, optional)'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: _types.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _type = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _SubjectDraft(
                code: _code.text.trim(),
                name: _name.text.trim(),
                nameFr: _nameFr.text.trim().isEmpty ? null : _nameFr.text.trim(),
                subjectType: _type,
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}