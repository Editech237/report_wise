import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../data/entities.dart';
import '../../data/repositories/academic_repository.dart';
import 'results_tab.dart';
import '../../core/widgets/shimmer.dart';

/// Academic records (spec sections 10-11).
///
/// Two tabs:
///   * Calendar — terms and sequences for the current academic year
///                (admins open / close / finalize sequences).
///   * Results  — compute, review, finalize class results (coefficient-weighted).
///
/// Assessment schemes and ranking rules are handled by the system defaults and
/// are intentionally not exposed in the UI (they can be re-enabled later).
class AcademicScreen extends StatefulWidget {
  final SupabaseClient client;
  final School school;
  final bool isAdmin;

  const AcademicScreen({
    super.key,
    required this.client,
    required this.school,
    required this.isAdmin,
  });

  @override
  State<AcademicScreen> createState() => _AcademicScreenState();
}

class _AcademicScreenState extends State<AcademicScreen> {
  late final AcademicRepository _academic;
  late Future<_AcademicData> _future;

  @override
  void initState() {
    super.initState();
    _academic = AcademicRepository(widget.client);
    _future = _load();
  }

  Future<_AcademicData> _load() async {
    final years = await _academic.academicYears(widget.school.id);
    final year = years.firstWhere(
      (y) => y.isCurrent,
      orElse: () => years.isNotEmpty ? years.first : (throw StateError('No academic year')),
    );
    final terms = await _academic.terms(year.id);
    final termBlocks = <_TermBlock>[];
    for (final t in terms) {
      final seqs = await _academic.sequences(t.id);
      termBlocks.add(_TermBlock(term: t, sequences: seqs));
    }
    return _AcademicData(year: year, terms: termBlocks);
  }

  void _refresh() => setState(() {
        _future = _load();
      });

  Future<void> _setSequenceStatus(Sequence seq, String status) async {
    if (status == 'FINALIZED') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Finalize sequence'),
          content: Text(
            'Finalize "${seq.name}"? Marks can no longer be entered for a '
            'finalized sequence unless it is reopened.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Finalize')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    try {
      await _academic.updateSequenceStatus(seq.id, status);
      _refresh();
    } on Exception catch (e) {
      _showError('Could not update the sequence', e);
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
    return DefaultTabController(
      length: 2,
      child: FutureBuilder<_AcademicData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const ShimmerPanel();
          }
          if (snap.hasError) {
            return _ErrorPane(
              message: 'Could not load academic records.',
              error: snap.error!,
              onRetry: _refresh,
            );
          }
          final data = snap.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: [
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('ACADEMIC SETUP',
                          style: TextStyle(fontFamily: 'Lexend', fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 1.1)),
                      SizedBox(height: 4),
                      Text('Calendar & results',
                          style: TextStyle(fontFamily: 'Manrope', fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
                    ]),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(children: [
                        const Icon(Icons.event_rounded, size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(data.year.name,
                            style: const TextStyle(fontFamily: 'Lexend', fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ]),
                    ),
                    IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const TabBar(
                tabs: [
                  Tab(text: 'Calendar', icon: Icon(Icons.calendar_month_outlined)),
                  Tab(text: 'Results', icon: Icon(Icons.calculate_outlined)),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _CalendarTab(
                      terms: data.terms,
                      isAdmin: widget.isAdmin,
                      onSetStatus: _setSequenceStatus,
                    ),
                    ResultsTab(
                      client: widget.client,
                      school: widget.school,
                      isAdmin: widget.isAdmin,
                      onError: _showError,
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

class _TermBlock {
  final Term term;
  final List<Sequence> sequences;
  const _TermBlock({required this.term, required this.sequences});
}

class _AcademicData {
  final AcademicYear year;
  final List<_TermBlock> terms;

  _AcademicData({required this.year, required this.terms});
}

class _ErrorPane extends StatelessWidget {
  final String message;
  final Object error;
  final VoidCallback onRetry;
  const _ErrorPane({required this.message, required this.error, required this.onRetry});

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

class _CalendarTab extends StatelessWidget {
  final List<_TermBlock> terms;
  final bool isAdmin;
  final Future<void> Function(Sequence seq, String status) onSetStatus;

  const _CalendarTab({
    required this.terms,
    required this.isAdmin,
    required this.onSetStatus,
  });

  static const _statusLabels = {
    'OPEN': 'Open',
    'CLOSED': 'Closed',
    'FINALIZED': 'Finalized',
  };

  @override
  Widget build(BuildContext context) {
    if (terms.isEmpty) {
      return const Center(child: Text('No terms configured for this academic year.'));
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ...terms.map((tb) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.flag_outlined, size: 18, color: AppColors.primary),
                        ),
                        const SizedBox(width: 10),
                        Text(tb.term.name,
                            style: const TextStyle(fontFamily: 'Manrope', fontSize: 15, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(
                          '${tb.sequences.length} sequence${tb.sequences.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...tb.sequences.map((seq) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.filter_1, size: 16, color: AppColors.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(seq.name,
                                    style: const TextStyle(fontFamily: 'Lexend', fontSize: 13)),
                              ),
                              _StatusChip(status: seq.status),
                              if (isAdmin) ...[
                                const SizedBox(width: 8),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 18),
                                  tooltip: 'Change status',
                                  onSelected: (s) => onSetStatus(seq, s),
                                  itemBuilder: (_) => _statusLabels.entries
                                      .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'OPEN' => (AppColors.accentGreen, 'Open'),
      'CLOSED' => (AppColors.accentRed, 'Closed'),
      'FINALIZED' => (AppColors.primary, 'Finalized'),
      _ => (AppColors.onSurfaceVariant, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label,
          style: TextStyle(fontFamily: 'Lexend', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}