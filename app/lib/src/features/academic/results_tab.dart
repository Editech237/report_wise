import 'package:academic_engine/academic_engine.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../data/entities.dart';
import '../../data/repositories/academic_repository.dart';
import '../../data/repositories/results_repository.dart';
import '../../core/widgets/shimmer.dart';

/// Results computation & review (spec sections 15-17, 26, 30, 44).
///
/// Admin flow: pick a class and a period (sequence / term / annual) → "Compute"
/// resolves the class's academic configuration (subjects, coefficients, scheme,
/// missing-mark policy, ranking rule, display precision) and hands it to the
/// server-side compute_period_results RPC, which persists period_results +
/// subject_results atomically with the config snapshot. Results can then be
/// reviewed here and finalized (immutable). Unfinalize is audited with a reason.
class ResultsTab extends StatefulWidget {
  final SupabaseClient client;
  final School school;
  final bool isAdmin;
  final void Function(String, Object) onError;

  const ResultsTab({
    super.key,
    required this.client,
    required this.school,
    required this.isAdmin,
    required this.onError,
  });

  @override
  State<ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends State<ResultsTab> {
  late final AcademicRepository _academic;
  late final ResultsRepository _results;
  late Future<_Base> _baseFuture;
  Future<List<PeriodResultSetSummary>>? _resultSetsFuture;

  String? _classId;
  String _periodType = 'SEQUENCE';
  String? _periodId;
  bool _computing = false;
  Future<List<PeriodResult>>? _resultsFuture;

  @override
  void initState() {
    super.initState();
    _academic = AcademicRepository(widget.client);
    _results = ResultsRepository(widget.client);
    _baseFuture = _load();
    _resultSetsFuture = _baseFuture.then((base) => _results.listPeriodResultSets(
        schoolId: widget.school.id, academicYearId: base.year.id));
  }

  void _refreshResultSets() {
    setState(() {
      _resultSetsFuture = _baseFuture.then((base) => _results.listPeriodResultSets(
          schoolId: widget.school.id, academicYearId: base.year.id));
    });
  }

  /// Opens a previously computed result set (sets pickers + reloads results).
  void _openResultSet(_Base base, PeriodResultSetSummary set) {
    setState(() {
      _classId = set.classId;
      _periodType = set.periodType;
      _periodId = set.periodId;
      _resultsFuture = _results.periodResults(
        classId: set.classId,
        periodType: set.periodType,
        periodId: set.periodType == 'ANNUAL' ? null : set.periodId,
      );
    });
  }

  Future<_Base> _load() async {
    final years = await _academic.academicYears(widget.school.id);
    final year = years.firstWhere(
      (y) => y.isCurrent,
      orElse: () => years.isNotEmpty ? years.first : (throw StateError('No academic year')),
    );
    final results = await Future.wait([
      _academic.classesFor(schoolId: widget.school.id, academicYearId: year.id),
      _academic.terms(year.id),
      _academic.sequencesForYear(year.id),
      _academic.academicRules(widget.school.id),
    ]);
    return _Base(
      year: year,
      classes: results[0] as List<SchoolClass>,
      terms: results[1] as List<Term>,
      sequences: results[2] as List<Sequence>,
      rules: results[3] as List<AcademicRule>,
    );
  }

  List<Sequence> _periodSequences(_Base base) {
    switch (_periodType) {
      case 'TERM':
        return base.sequences.where((s) => s.termId == _periodId).toList();
      case 'ANNUAL':
        return base.sequences;
      default:
        return base.sequences.where((s) => s.id == _periodId).toList();
    }
  }

  void _reload() {
    if (_classId == null) return;
    setState(() {
      _resultsFuture = _results.periodResults(
        classId: _classId!,
        periodType: _periodType,
        periodId: _periodType == 'ANNUAL' ? null : _periodId,
      );
    });
  }

  Future<void> _compute() async {
    if (_classId == null || (_periodType != 'ANNUAL' && _periodId == null)) return;
    final base = await _baseFuture;
    final cls = base.classes.firstWhere((c) => c.id == _classId);
    final ctx = AcademicContext(
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
    setState(() => _computing = true);
    try {
      final setup = await _academic.loadAcademicSetup(ctx);
      if (setup.scheme == null) {
        throw StateError('No assessment scheme resolved for this class');
      }
      final sequenceIds = _periodSequences(base).map((s) => s.id).toList();
      if (sequenceIds.isEmpty) {
        throw StateError('No sequences for this period');
      }
      final config = _configFromRules(base.rules);

      await _results.computePeriodResults(
        schoolId: widget.school.id,
        classId: cls.id,
        academicYearId: cls.academicYearId,
        periodType: _periodType,
        periodId: _periodType == 'ANNUAL' ? null : _periodId,
        sequenceIds: sequenceIds,
        subjects: setup.subjects
            .map((s) => {
                  'subject_id': s.subjectId,
                  'coefficient': s.coefficient,
                  'counts_in_average': s.countsInAverage,
                  'counts_in_ranking': s.countsInRanking,
                  'shows_on_report': s.showsOnReport,
                })
            .toList(),
        scheme: setup.scheme!.components
            .map((c) => {
                  'id': c.id,
                  'weight': c.weight,
                  'max_score': c.maxScore,
                })
            .toList(),
        policy: config.policy,
        ranking: config.ranking,
        display: config.display,
      );
      _reload();
      _refreshResultSets();
    } on Exception catch (e) {
      widget.onError('Could not compute results', e);
    } finally {
      if (mounted) setState(() => _computing = false);
    }
  }

  Future<void> _finalize() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finalize results'),
        content: const Text('Finalized results are immutable and feed report '
            'cards. To change them later you must unfinalize (audited).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Finalize')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _results.finalizePeriodResults(
        classId: _classId!,
        periodType: _periodType,
        periodId: _periodType == 'ANNUAL' ? null : _periodId,
      );
      _reload();
      _refreshResultSets();
    } on Exception catch (e) {
      widget.onError('Could not finalize results', e);
    }
  }

  Future<void> _unfinalize() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(title: 'Unfinalize results'),
    );
    if (reason == null || !mounted) return;
    try {
      await _results.unfinalizePeriodResults(
        classId: _classId!,
        periodType: _periodType,
        periodId: _periodType == 'ANNUAL' ? null : _periodId,
        reason: reason,
      );
      _reload();
      _refreshResultSets();
    } on Exception catch (e) {
      widget.onError('Could not unfinalize results', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Base>(
      future: _baseFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const ShimmerPanel();
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load results.'),
                const SizedBox(height: 8),
                Text('${snap.error}', style: Theme.of(context).textTheme.bodySmall),
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
        if (base.classes.isEmpty) {
          return const Center(child: Text('Create a class first.'));
        }
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey('rclass:$_classId'),
                      initialValue: _classId,
                      decoration: const InputDecoration(labelText: 'Class'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('— Select —')),
                        ...base.classes.map((c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (v) {
                        setState(() => _classId = v);
                        _reload();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 260,
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'SEQUENCE', label: Text('Sequence')),
                        ButtonSegment(value: 'TERM', label: Text('Term')),
                        ButtonSegment(value: 'ANNUAL', label: Text('Annual')),
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
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey('rperiod:$_periodType:$_periodId'),
                      initialValue: _periodId,
                      decoration: InputDecoration(
                        labelText: switch (_periodType) {
                          'SEQUENCE' => 'Sequence',
                          'TERM' => 'Term',
                          _ => 'Period',
                        },
                      ),
                      items: switch (_periodType) {
                        'ANNUAL' => const [
                            DropdownMenuItem(value: null, child: Text('Whole year')),
                          ],
                        'TERM' => [
                            const DropdownMenuItem(value: null, child: Text('— Select —')),
                            ...base.terms.map((t) =>
                                DropdownMenuItem(value: t.id, child: Text(t.name))),
                          ],
                        _ => [
                            const DropdownMenuItem(value: null, child: Text('— Select —')),
                            ...base.sequences.map((s) => DropdownMenuItem(
                                value: s.id,
                                child: Text('${s.name} · [${s.status}]',
                                    overflow: TextOverflow.ellipsis))),
                          ],
                      },
                      onChanged: (v) {
                        setState(() => _periodId = v);
                        _reload();
                      },
                    ),
                  ),
                  const Spacer(),
                  if (widget.isAdmin)
                    FilledButton.icon(
                      onPressed: _computing
                          ? null
                          : (_classId != null && (_periodType == 'ANNUAL' || _periodId != null))
                              ? _compute
                              : null,
                      icon: _computing
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.calculate_outlined, size: 18),
                      label: const Text('Compute'),
                    ),
                ],
              ),
              _ResultSetsStrip(
                future: _resultSetsFuture,
                onOpen: (set) => _openResultSet(base, set),
              ),
              const SizedBox(height: 16),
              Expanded(child: _buildResults()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResults() {
    final results = _resultsFuture;
    if (results == null) {
      return const Center(child: Text('Select a class and period to review results.'));
    }
    return FutureBuilder<List<PeriodResult>>(
      future: results,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const ShimmerPanel();
        }
        if (snap.hasError) {
          return Center(child: Text('Could not load results: ${snap.error}'));
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return Center(
            child: Text(widget.isAdmin
                ? 'No results yet — press Compute to generate them.'
                : 'No results for this period.'),
          );
        }
        final finalized = list.first.status == 'FINAL';
        final classAverage = list.first.classAverage;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${list.length} students',
                    style: Theme.of(context).textTheme.bodySmall),
                if (classAverage != null) ...[
                  const SizedBox(width: 12),
                  Text('Class average: ${_fmt(classAverage)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(width: 12),
                _StatusPill(finalized: finalized),
                const Spacer(),
                if (widget.isAdmin && !finalized)
                  OutlinedButton.icon(
                    onPressed: _finalize,
                    icon: const Icon(Icons.lock_outline, size: 16),
                    label: const Text('Finalize'),
                  ),
                if (widget.isAdmin && finalized)
                  OutlinedButton.icon(
                    onPressed: _unfinalize,
                    icon: const Icon(Icons.lock_open_outlined, size: 16),
                    label: const Text('Unfinalize'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _ResultCard(result: list[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

class _StatusPill extends StatelessWidget {
  final bool finalized;
  const _StatusPill({required this.finalized});

  @override
  Widget build(BuildContext context) {
    final color = finalized ? AppColors.accentGreen : AppColors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(finalized ? 'FINAL' : 'DRAFT',
          style: TextStyle(
              fontFamily: 'Lexend', fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final PeriodResult result;
  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.primary.withOpacity(0.1),
          child: Text('${result.rank ?? '–'}',
              style: const TextStyle(fontFamily: 'Lexend', fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary)),
        ),
        title: Text(result.studentName,
            style: const TextStyle(fontFamily: 'Manrope', fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(result.matricule ?? '',
            style: Theme.of(context).textTheme.bodySmall),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Stat(label: 'Moy.', value: result.generalAverage),
            const SizedBox(width: 12),
            _Stat(label: 'Pts', value: result.totalWeightedPoints),
          ],
        ),
        children: [
          for (final s in result.subjects)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(s.subjectName ?? s.subjectId,
                        style: const TextStyle(fontFamily: 'Lexend', fontSize: 12.5)),
                  ),
                  Text(s.subjectAverage == null ? '—' : _fmt(s.subjectAverage!),
                      style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(width: 8),
                  Text(s.coefficient == null ? '×—' : '×${_fmt(s.coefficient!)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 56,
                    child: Text(s.weightedPoints == null ? '= —' : '= ${_fmt(s.weightedPoints!)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final double? value;
  const _Stat({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
        Text(value == null ? '–' : _fmt(value!),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, fontFamily: 'Lexend')),
      ],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  final String title;
  const _ReasonDialog({required this.title});

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('This action is audited — a reason is required.',
              style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Reason *'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_reason.text.trim().isEmpty) return;
            Navigator.pop(context, _reason.text.trim());
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

class _Base {
  final AcademicYear year;
  final List<SchoolClass> classes;
  final List<Term> terms;
  final List<Sequence> sequences;
  final List<AcademicRule> rules;

  _Base({
    required this.year,
    required this.classes,
    required this.terms,
    required this.sequences,
    required this.rules,
  });
}

/// Builds the policy / ranking / display config JSON handed to the RPC,
/// resolved from the school's academic rules (school override wins).
({Map<String, Object?> policy, Map<String, Object?> ranking, Map<String, Object?> display})
    _configFromRules(List<AcademicRule> rules) {
  Map<String, dynamic>? by(String key) {
    AcademicRule? found;
    for (final r in rules) {
      if (r.ruleKey == key) {
        found = r;
        if (r.schoolId != null) break;
      }
    }
    return found?.ruleValue;
  }

  final policyRule = by('MISSING_MARK_POLICY');
  final rankingRule = by('RANKING_METHOD');
  final tieRule = by('TIE_BREAKER');
  final tiesRule = by('RANK_TIES_SAME_RANK');
  final displayRule = by('DISPLAY_PRECISION');

  return (
    policy: {
      'exclude': (policyRule?['exclude'] as List?) ??
          const ['NOT_ENTERED', 'ABSENT', 'EXCUSED', 'NOT_APPLICABLE', 'PENDING'],
      'zero_is_score': policyRule?['zero_is_score'] ?? true,
    },
    ranking: {
      'method': rankingRule?['value'] ?? 'COMPETITION',
      'tie_breaker': tieRule?['value'] ?? 'TOTAL_WEIGHTED_POINTS',
      'same_rank_for_ties': tiesRule?['value'] ?? true,
    },
    display: {
      'decimals': displayRule?['value'] ?? 2,
      'rounding': displayRule?['rounding'] ?? 'HALF_UP',
    },
  );
}

/// Horizontal list of computed result sets (persistent history). Tapping one
/// reopens that class + period. Hidden when nothing is computed yet.
class _ResultSetsStrip extends StatelessWidget {
  final Future<List<PeriodResultSetSummary>>? future;
  final ValueChanged<PeriodResultSetSummary> onOpen;

  const _ResultSetsStrip({required this.future, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PeriodResultSetSummary>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: ShimmerBlock(height: 84, radius: 12),
          );
        }
        final sets = snap.data ?? const [];
        if (sets.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Computed results (${sets.length})',
                style: const TextStyle(fontFamily: 'Manrope', fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: sets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _ResultSetCard(set: sets[i], onTap: () => onOpen(sets[i])),
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _ResultSetCard extends StatelessWidget {
  final PeriodResultSetSummary set;
  final VoidCallback onTap;

  const _ResultSetCard({required this.set, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = set.isFinal ? AppColors.accentGreen : AppColors.onSurfaceVariant;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 220,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(set.className,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Manrope', fontSize: 13, fontWeight: FontWeight.w700)),
              Text('${set.periodLabel} · ${set.studentCount} students',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Lexend', fontSize: 11.5, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(99)),
                child: Text(set.isFinal ? 'FINAL' : 'DRAFT',
                    style: TextStyle(fontFamily: 'Lexend', fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}