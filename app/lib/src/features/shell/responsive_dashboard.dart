import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/academic_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_section.dart';
import '../../core/widgets/shimmer.dart';
import '../../data/entities.dart';
import '../../data/repositories/academic_repository.dart';
import '../dashboard/widgets/dashboard_stat_card.dart';
import '../dashboard/widgets/dashboard_donut_card.dart';
import '../dashboard/widgets/dashboard_status_bar.dart';
import '../dashboard/widgets/pass_rate_chart.dart';
import '../dashboard/widgets/recent_activity_panel.dart';

class ResponsiveDashboard extends ConsumerWidget {
  final School school;
  final SchoolMembership membership;
  final VoidCallback onSchoolsChanged;
  final ValueChanged<AppSection> onNavigate;

  const ResponsiveDashboard({
    super.key,
    required this.school,
    required this.membership,
    required this.onSchoolsChanged,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardDataProvider(school.id));
    final metricsAsync = ref.watch(dashboardMetricsProvider(school.id));

    return dashboardAsync.when(
      loading: () => const ShimmerPanel(),
      error: (e, _) => _ErrorView(
        error: e,
        onRetry: () => ref.invalidate(dashboardDataProvider(school.id)),
      ),
      data: (data) {
        if (data.academicYears.isEmpty) {
          return _EmptyYearView(
            school: school,
            onRefresh: () => ref.invalidate(dashboardDataProvider(school.id)),
          );
        }
        return _DashboardView(
          data: data,
          metrics: metricsAsync.valueOrNull,
          metricsLoading: metricsAsync.isLoading,
          school: school,
          membership: membership,
          onNavigate: onNavigate,
          onRefresh: () {
            final year = data.academicYears.firstWhere(
              (y) => y.isCurrent,
              orElse: () => data.academicYears.first,
            );
            invalidateSchoolData(ref, school.id, year.id);
          },
        );
      },
    );
  }
}

class _DashboardView extends StatelessWidget {
  final DashboardData data;
  final DashboardMetrics? metrics;
  final bool metricsLoading;
  final School school;
  final SchoolMembership membership;
  final ValueChanged<AppSection> onNavigate;
  final VoidCallback onRefresh;

  const _DashboardView({
    required this.data,
    required this.metrics,
    required this.metricsLoading,
    required this.school,
    required this.membership,
    required this.onNavigate,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final currentYear = data.academicYears.firstWhere(
      (y) => y.isCurrent,
      orElse: () => data.academicYears.first,
    );
    final activeClasses = data.classes.where((c) => c.isActive).length;
    final totalStudents = data.students.length;
    final passMap = <String, int>{
      for (final c in metrics?.classes ?? const <ClassPassRate>[])
        c.className: c.passRate.round(),
    };
    final overallPass = metrics?.overallPassRate;
    final hasPass = (metrics?.hasPassRate ?? false);
    final schoolKpi = metrics?.overallPassRate;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ACADEMIC YEAR ${currentYear.name.toUpperCase()}',
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Text(
                  'Dashboard Overview',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(currentYear.status).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: _statusColor(currentYear.status).withOpacity(0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _statusColor(currentYear.status),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currentYear.status,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _statusColor(currentYear.status),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _DashboardSchoolLogo(logoUrl: school.logoUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${school.name} • ${school.schoolType} • ${school.subsystem}',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.5,
                    color: AppColors.onSurfaceVariant.withOpacity(0.65),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Builder(
            builder: (context) {
              final w = MediaQuery.of(context).size.width;
              final narrow = w < 700;
              final statCards = <Widget>[
                DashboardStatCard(
                  icon: Icons.school_outlined,
                  iconColor: AppColors.primary,
                  iconBgColor: AppColors.primary.withOpacity(0.08),
                  label: 'Total Students',
                  value: '$totalStudents',
                  subtitle: totalStudents == 0
                      ? 'No students yet'
                      : 'Enrolled this year',
                  trend: StatTrend.neutral,
                ),
                DashboardStatCard(
                  icon: Icons.menu_book_outlined,
                  iconColor: const Color(0xFFF57F17),
                  iconBgColor: const Color(0xFFFFF8E1),
                  label: 'Classes',
                  value: '$activeClasses',
                  subtitle: activeClasses == 0
                      ? 'No classes'
                      : '$activeClasses active',
                  trend: StatTrend.neutral,
                ),
                DashboardStatCard(
                  icon: Icons.bar_chart_rounded,
                  iconColor: const Color(0xFFB71C1C),
                  iconBgColor: const Color(0xFFFFEBEE),
                  label: 'Avg Pass Rate',
                  value: hasPass ? '${overallPass!.round()}%' : '—',
                  subtitle: hasPass ? 'Latest sequence' : 'No results yet',
                  trend: hasPass ? StatTrend.positive : StatTrend.neutral,
                ),
              ];
              if (narrow) {
                return Column(
                  children: [
                    for (final card in statCards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: card,
                      ),
                  ],
                );
              }
              return Row(
                children: [
                  for (final card in statCards)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: card,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = <Widget>[
                DashboardDonutCard(
                  label: 'Report cards generated',
                  value: '${data.generatedReportCards}',
                  subtitle: 'This academic year',
                  color: const Color(0xFF00639A),
                  icon: Icons.description_outlined,
                ),
                DashboardDonutCard(
                  label: 'Teachers',
                  value: '${data.teachers.length}',
                  subtitle: 'School staff directory',
                  color: const Color(0xFF2E7D32),
                  icon: Icons.people_outline_rounded,
                ),
                DashboardDonutCard(
                  label: 'Subjects',
                  value: '${data.subjects.length}',
                  subtitle: 'Available catalogue',
                  color: const Color(0xFFF57F17),
                  icon: Icons.menu_book_outlined,
                ),
                DashboardDonutCard(
                  label: 'Overall school KPI',
                  value: schoolKpi == null ? '—' : '${schoolKpi.round()}%',
                  subtitle: schoolKpi == null
                      ? 'Awaiting results'
                      : 'Overall pass rate',
                  color: const Color(0xFF6A1B9A),
                  icon: Icons.insights_outlined,
                  progress: (schoolKpi ?? 0) / 100,
                ),
              ];
              final columns = constraints.maxWidth >= 1250
                  ? 4
                  : constraints.maxWidth >= 760
                  ? 2
                  : 1;
              if (columns == 1)
                return Column(
                  children: [
                    for (final card in cards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: card,
                      ),
                  ],
                );
              return GridView.count(
                crossAxisCount: columns,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 2.25,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: cards,
              );
            },
          ),
          const SizedBox(height: 20),
          Builder(
            builder: (context) {
              final w = MediaQuery.of(context).size.width;
              final stacked = w < 1100;
              if (stacked) {
                return Column(
                  children: [
                    PassRateChart(data: passMap, loading: metricsLoading),
                    const SizedBox(height: 16),
                    RecentActivityPanel(
                      items: metrics?.activity,
                      loading: metricsLoading,
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: PassRateChart(
                      data: passMap,
                      loading: metricsLoading,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: RecentActivityPanel(
                      items: metrics?.activity,
                      loading: metricsLoading,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          DashboardStatusBar(
            statusLabel:
                'Academic year ${currentYear.name} — ${currentYear.status}',
            deadlineLabel:
                '${data.classes.length} classes · ${data.students.length} students · finalize results for report cards',
          ),
          const SizedBox(height: 24),
          if (membership.role.isAdminRole) ...[
            const Text(
              'Quick Actions',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickChip(
                  icon: Icons.person_add_rounded,
                  label: 'Students',
                  color: AppColors.primary,
                  onTap: () => onNavigate(AppSection.studentRegistry),
                ),
                _QuickChip(
                  icon: Icons.class_rounded,
                  label: 'Classes',
                  color: const Color(0xFF2E7D32),
                  onTap: () => onNavigate(AppSection.classes),
                ),
                _QuickChip(
                  icon: Icons.menu_book_rounded,
                  label: 'Subjects',
                  color: const Color(0xFFF57F17),
                  onTap: () => onNavigate(AppSection.subjects),
                ),
                _QuickChip(
                  icon: Icons.edit_note_rounded,
                  label: 'Mark entry',
                  color: const Color(0xFF6A1B9A),
                  onTap: () => onNavigate(AppSection.marks),
                ),
                _QuickChip(
                  icon: Icons.calculate_outlined,
                  label: 'Results',
                  color: const Color(0xFF00639A),
                  onTap: () => onNavigate(AppSection.academicRecords),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static Color _statusColor(String s) {
    switch (s) {
      case 'ACTIVE':
        return const Color(0xFF2E7D32);
      case 'PLANNED':
        return AppColors.primary;
      default:
        return Colors.grey;
    }
  }
}

class _QuickChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.accentRedLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 32,
                color: AppColors.accentRed,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not load dashboard',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 12,
                color: AppColors.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyYearView extends ConsumerStatefulWidget {
  final School school;
  final VoidCallback onRefresh;
  const _EmptyYearView({required this.school, required this.onRefresh});
  @override
  ConsumerState<_EmptyYearView> createState() => _EmptyYearViewState();
}

class _EmptyYearViewState extends ConsumerState<_EmptyYearView> {
  bool _busy = false;
  String? _error;
  final _yearCtrl = TextEditingController(text: '2026/2027');

  @override
  void dispose() {
    _yearCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _yearCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(academicRepositoryProvider);
      if (repo == null) throw StateError('Academic repo not ready');
      final year = await repo.createAcademicYear(
        schoolId: widget.school.id,
        name: name,
      );
      await repo.seedDefaultCalendar(year: year);
      widget.onRefresh();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No academic year yet',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create the first academic year for this school to begin.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12.5,
                  color: AppColors.onSurfaceVariant.withOpacity(0.7),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _yearCtrl,
                decoration: const InputDecoration(
                  hintText: '2026/2027',
                  labelText: 'Academic year name',
                  prefixIcon: Icon(Icons.event_rounded),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12,
                    color: AppColors.accentRed,
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: _busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded),
                  label: const Text('Create academic year'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardSchoolLogo extends StatelessWidget {
  final String? logoUrl;
  const _DashboardSchoolLogo({required this.logoUrl});

  @override
  Widget build(BuildContext context) {
    final url = logoUrl?.trim();
    if (url == null ||
        url.isEmpty ||
        !(url.startsWith('http://') || url.startsWith('https://'))) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(
          Icons.school_outlined,
          size: 18,
          color: AppColors.primary,
        ),
      );
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
        color: Colors.white,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.school_outlined,
          size: 18,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
