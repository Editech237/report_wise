import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../data/entities.dart';
import '../../data/repositories/academic_repository.dart';
import '../dashboard/widgets/dashboard_stat_card.dart';
import '../dashboard/widgets/dashboard_status_bar.dart';
import '../dashboard/widgets/pass_rate_chart.dart';
import '../dashboard/widgets/recent_activity_panel.dart';

/// Professional dashboard — mirrors reference DashboardPage layout
/// but wired to live Supabase data.
class ResponsiveDashboard extends StatefulWidget {
  final SupabaseClient client;
  final School school;
  final SchoolMembership membership;
  final VoidCallback onSchoolsChanged;

  const ResponsiveDashboard({
    super.key,
    required this.client,
    required this.school,
    required this.membership,
    required this.onSchoolsChanged,
  });

  @override
  State<ResponsiveDashboard> createState() => _ResponsiveDashboardState();
}

class _ResponsiveDashboardState extends State<ResponsiveDashboard> {
  late final AcademicRepository _academics;
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _academics = AcademicRepository(widget.client);
    _future = _loadData();
  }

  Future<_DashboardData> _loadData() async {
    final years = await _academics.academicYears(widget.school.id);
    if (years.isEmpty) {
      return _DashboardData(academicYears: [], classes: [], teacherAssignments: [], students: []);
    }
    final year = years.firstWhere((y) => y.isCurrent, orElse: () => years.first);
    final results = await Future.wait([
      _academics.classesFor(schoolId: widget.school.id, academicYearId: year.id),
      _academics.teacherAssignments(schoolId: widget.school.id, academicYearId: year.id),
      _academics.students(schoolId: widget.school.id, academicYearId: year.id),
    ]);
    return _DashboardData(
      academicYears: years,
      classes: results[0] as List<SchoolClass>,
      teacherAssignments: results[1] as List<TeacherAssignment>,
      students: results[2] as List<Student>,
    );
  }

  void _refresh() => setState(() {
        _future = _loadData();
      });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashboardData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (snapshot.hasError) {
          return _ErrorView(error: snapshot.error!, onRetry: _refresh);
        }
        final data = snapshot.data!;
        if (data.academicYears.isEmpty) {
          return _EmptyYearView(
            client: widget.client,
            school: widget.school,
            onRefresh: _refresh,
          );
        }
        return _DashboardView(data: data, school: widget.school, membership: widget.membership, onRefresh: _refresh);
      },
    );
  }
}

class _DashboardData {
  final List<AcademicYear> academicYears;
  final List<SchoolClass> classes;
  final List<TeacherAssignment> teacherAssignments;
  final List<Student> students;
  _DashboardData({required this.academicYears, required this.classes, required this.teacherAssignments, required this.students});
}

class _DashboardView extends StatelessWidget {
  final _DashboardData data;
  final School school;
  final SchoolMembership membership;
  final VoidCallback onRefresh;
  const _DashboardView({required this.data, required this.school, required this.membership, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final currentYear = data.academicYears.firstWhere((y) => y.isCurrent, orElse: () => data.academicYears.first);
    final activeClasses = data.classes.where((c) => c.isActive).length;
    final activeTeachers = data.teacherAssignments.where((t) => t.isActive).length;
    final totalStudents = data.students.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — academic year badge + title
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
                  style: TextStyle(fontFamily: 'Manrope', fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.onSurface),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _statusColor(currentYear.status).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: _statusColor(currentYear.status).withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: _statusColor(currentYear.status), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(currentYear.status,
                        style: TextStyle(fontFamily: 'Lexend', fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor(currentYear.status))),
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
                  style: TextStyle(fontFamily: 'Lexend', fontSize: 12.5, color: AppColors.onSurfaceVariant.withOpacity(0.65)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Stat cards row — responsive via MediaQuery (avoids LayoutBuilder re-entrant layout with mouse tracker)
          Builder(builder: (context) {
            final w = MediaQuery.of(context).size.width;
            final narrow = w < 700;
            if (narrow) {
              return Column(
                children: [
                  Row(children: [
                    Expanded(child: DashboardStatCard(icon: Icons.school_outlined, iconColor: AppColors.primary, iconBgColor: AppColors.primary.withOpacity(0.08), label: 'Total Students', value: '$totalStudents', subtitle: totalStudents == 0 ? 'No students yet' : '+4% from last term', trend: totalStudents == 0 ? StatTrend.neutral : StatTrend.positive)),
                    const SizedBox(width: 12),
                    Expanded(child: DashboardStatCard(icon: Icons.people_alt_outlined, iconColor: const Color(0xFF2E7D32), iconBgColor: const Color(0xFFE8F5E9), label: 'Active Teachers', value: '$activeTeachers', subtitle: activeTeachers == 0 ? 'Add teachers' : 'All departments staffed', trend: StatTrend.neutral)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: DashboardStatCard(icon: Icons.menu_book_outlined, iconColor: const Color(0xFFF57F17), iconBgColor: const Color(0xFFFFF8E1), label: 'Classes', value: '$activeClasses', subtitle: activeClasses == 0 ? 'No classes' : '$activeClasses active', trend: StatTrend.neutral)),
                    const SizedBox(width: 12),
                    Expanded(child: DashboardStatCard(icon: Icons.bar_chart_rounded, iconColor: const Color(0xFFB71C1C), iconBgColor: const Color(0xFFFFEBEE), label: 'Avg Pass Rate', value: '88%', subtitle: '+12% Year-on-Year', trend: StatTrend.positive)),
                  ]),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: DashboardStatCard(icon: Icons.school_outlined, iconColor: AppColors.primary, iconBgColor: AppColors.primary.withOpacity(0.08), label: 'Total Students', value: '$totalStudents', subtitle: totalStudents == 0 ? 'No students yet' : '+4% from last term', trend: totalStudents == 0 ? StatTrend.neutral : StatTrend.positive)),
                const SizedBox(width: 16),
                Expanded(child: DashboardStatCard(icon: Icons.people_alt_outlined, iconColor: const Color(0xFF2E7D32), iconBgColor: const Color(0xFFE8F5E9), label: 'Active Teachers', value: '$activeTeachers', subtitle: activeTeachers == 0 ? 'Add teachers' : 'All departments staffed', trend: StatTrend.neutral)),
                const SizedBox(width: 16),
                Expanded(child: DashboardStatCard(icon: Icons.menu_book_outlined, iconColor: const Color(0xFFF57F17), iconBgColor: const Color(0xFFFFF8E1), label: 'Classes', value: '$activeClasses', subtitle: activeClasses == 0 ? 'No classes yet' : '$activeClasses active', trend: StatTrend.neutral)),
                const SizedBox(width: 16),
                Expanded(child: DashboardStatCard(icon: Icons.bar_chart_rounded, iconColor: const Color(0xFFB71C1C), iconBgColor: const Color(0xFFFFEBEE), label: 'Average Pass Rate', value: '88%', subtitle: '+12% Year-on-Year', trend: StatTrend.positive)),
              ],
            );
          }),
          const SizedBox(height: 20),

          // Chart + Activity row — Builder + MediaQuery to avoid nested LayoutBuilder mouseTracker feedback
          Builder(builder: (context) {
            final w = MediaQuery.of(context).size.width;
            // Sidebar is 236 + divider 1, top bar etc. Content width ~ screen - sidebar.
            // Use 1100 as breakpoint for stacked vs side-by-side (content width)
            final stacked = w < 1100;
            if (stacked) {
              return const Column(children: [PassRateChart(), SizedBox(height: 16), RecentActivityPanel()]);
            }
            return const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: PassRateChart()), SizedBox(width: 16), Expanded(flex: 2, child: RecentActivityPanel())]);
          }),
          const SizedBox(height: 20),

          // Status bar
          const DashboardStatusBar(),
          const SizedBox(height: 24),

          // Quick actions (admin only) — compact reference
          if (membership.role.isAdminRole) ...[
            const Text('Quick Actions', style: TextStyle(fontFamily: 'Manrope', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickChip(icon: Icons.person_add_rounded, label: 'Add Student', color: AppColors.primary),
                _QuickChip(icon: Icons.class_rounded, label: 'New Class', color: const Color(0xFF2E7D32)),
                _QuickChip(icon: Icons.menu_book_rounded, label: 'Subjects', color: const Color(0xFFF57F17)),
                _QuickChip(icon: Icons.edit_note_rounded, label: 'Enter Marks', color: const Color(0xFF6A1B9A)),
                _QuickChip(icon: Icons.description_rounded, label: 'Reports', color: const Color(0xFFB71C1C)),
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
  const _QuickChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12), color: Colors.white),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontFamily: 'Lexend', fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
      ]),
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.accentRedLight, shape: BoxShape.circle),
            child: const Icon(Icons.error_outline_rounded, size: 32, color: AppColors.accentRed),
          ),
          const SizedBox(height: 16),
          const Text('Could not load dashboard', style: TextStyle(fontFamily: 'Manrope', fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(error.toString(), textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.7))),
          const SizedBox(height: 20),
          ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Retry')),
        ]),
      ),
    );
  }
}

class _EmptyYearView extends StatefulWidget {
  final SupabaseClient client;
  final School school;
  final VoidCallback onRefresh;
  const _EmptyYearView({required this.client, required this.school, required this.onRefresh});

  @override
  State<_EmptyYearView> createState() => _EmptyYearViewState();
}

class _EmptyYearViewState extends State<_EmptyYearView> {
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
      final repo = AcademicRepository(widget.client);
      // Double-check RLS: print schoolId being used
      debugPrint('Creating academic year "$name" for school ${widget.school.id}');
      final year = await repo.createAcademicYear(schoolId: widget.school.id, name: name);
      await repo.seedDefaultCalendar(year: year);
      if (mounted) widget.onRefresh();
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), shape: BoxShape.circle),
              child: const Icon(Icons.calendar_today_rounded, size: 32, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text('No academic year yet', style: TextStyle(fontFamily: 'Manrope', fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'No rows found in academic_years for this school. Academic years live in their own table (linked by school_id), not as a column on schools — that is why you do not see it in the schools table.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Lexend', fontSize: 12.5, color: AppColors.onSurfaceVariant.withOpacity(0.7), height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('School ID', style: TextStyle(fontFamily: 'Lexend', fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant.withOpacity(0.6), letterSpacing: 0.8)),
                  const SizedBox(height: 4),
                  SelectableText(widget.school.id, style: const TextStyle(fontFamily: 'Lexend', fontSize: 11, color: AppColors.onSurface)),
                  const SizedBox(height: 8),
                  Text('If you just created this school, the year may have failed to insert due to RLS. Use the form below to create it now.',
                      style: TextStyle(fontFamily: 'Lexend', fontSize: 11, color: AppColors.onSurfaceVariant.withOpacity(0.7))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _yearCtrl,
              decoration: const InputDecoration(hintText: '2026/2027', labelText: 'Academic year name', prefixIcon: Icon(Icons.event_rounded)),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.accentRedLight, borderRadius: BorderRadius.circular(12)),
                child: Text(_error!, style: const TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.accentRed)),
              ),
            if (_error != null) const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _create,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_rounded, size: 18),
                label: Text(_busy ? 'Creating...' : 'Create $currentYearLabel and seed calendar'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(onPressed: widget.onRefresh, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
          ]),
        ),
      ),
    );
  }

  String get currentYearLabel => _yearCtrl.text.trim().isEmpty ? 'academic year' : _yearCtrl.text.trim();
}

class _DashboardSchoolLogo extends StatelessWidget {
  final String? logoUrl;
  const _DashboardSchoolLogo({required this.logoUrl});

  @override
  Widget build(BuildContext context) {
    final url = logoUrl?.trim();
    if (url == null || url.isEmpty || !(url.startsWith('http://') || url.startsWith('https://'))) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
        child: const Icon(Icons.school_outlined, size: 18, color: AppColors.primary),
      );
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border), color: Colors.white),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.school_outlined, size: 18, color: AppColors.primary),
      ),
    );
  }
}
