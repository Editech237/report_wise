import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/supabase_provider.dart';
import '../../core/providers/students_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_section.dart';
import '../../data/entities.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/school_repository.dart';
import '../academic/academic_screen.dart';
import '../marks/mark_entry_screen.dart';
import '../reports/reports_screen.dart';
import '../setup/classes_screen.dart';
import '../setup/subjects_screen.dart';
import '../students/students_screen.dart';
import '../teachers/teachers_screen.dart';
import '../settings/school_settings_screen.dart';
import 'responsive_dashboard.dart';
import 'widgets/app_sidebar.dart';
import 'widgets/app_top_bar.dart';

/// Main app shell — modern two-pane layout copied from reference design:
/// dark green sidebar + white top bar + light surface content.
/// Responsive: wide shows permanent sidebar, narrow uses drawer.
/// Now ConsumerStatefulWidget — selected school/section are still local UI state,
/// but signOut and child data come from Riverpod providers.
class SchoolShell extends ConsumerStatefulWidget {
  final List<SchoolMembership> memberships;
  final VoidCallback onSchoolsChanged;

  const SchoolShell({
    super.key,
    required this.memberships,
    required this.onSchoolsChanged,
  });

  @override
  ConsumerState<SchoolShell> createState() => _SchoolShellState();
}

class _SchoolShellState extends ConsumerState<SchoolShell> {
  late SchoolMembership _current;
  AppSection _section = AppSection.dashboard;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _current = widget.memberships.first;
    // Teachers land directly on their primary tool: mark entry.
    _section = _current.role.isTeacherRole && !_current.role.isAdminRole
        ? AppSection.marks
        : AppSection.dashboard;
  }

  void _onSelect(AppSection s) {
    setState(() => _section = s);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  void _search(String value) {
    ref.read(studentsSearchProvider.notifier).state = value;
    if (value.trim().isNotEmpty && _section != AppSection.studentRegistry) {
      _onSelect(AppSection.studentRegistry);
    }
  }

  void _showNotifications() => showDialog<void>(
    context: context,
    builder: (_) => const AlertDialog(
      title: Text('Notifications'),
      content: Text('You have no new notifications.'),
    ),
  );

  void _showHelp() => showDialog<void>(
    context: context,
    builder: (_) => const AlertDialog(
      title: Text('ReportWise help'),
      content: Text(
        'Use Students to search learners, Marks to enter scores, Academic → Results to compute and finalize results, and Reports to preview or export bulletins.',
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final client = ref.watch(supabaseClientProvider);

    final sidebar = AppSidebar(
      selected: _section,
      onSelected: _onSelect,
      school: _current.school!,
      memberships: widget.memberships,
      current: _current,
      onSwitchSchool: (m) => setState(() => _current = m),
      onSignOut: () => client?.auth.signOut(),
    );

    final content = Column(
      children: [
        AppTopBar(
          schoolName: _current.school?.name,
          schoolLogoUrl: _current.school?.logoUrl,
          userName:
              client?.auth.currentUser?.userMetadata?['full_name']
                  ?.toString() ??
              client?.auth.currentUser?.email,
          onGenerateReports: () => _onSelect(AppSection.reportCards),
          onSearchTap: () => _openGlobalSearch(client!),
          onSearchChanged: _search,
          onNotificationsTap: _showNotifications,
          onHelpTap: _showHelp,
          onProfileTap: () => _onSelect(AppSection.settings),
        ),
        Container(height: 1, color: AppColors.divider),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: KeyedSubtree(
              key: ValueKey(_section),
              child: _Panel(
                client: client!,
                section: _section,
                school: _current.school!,
                membership: _current,
                onSchoolsChanged: widget.onSchoolsChanged,
                onNavigate: _onSelect,
              ),
            ),
          ),
        ),
      ],
    );

    if (isWide) {
      return Scaffold(
        backgroundColor: AppColors.surfaceLow,
        body: Row(
          children: [
            sidebar,
            Container(width: 1, color: AppColors.divider),
            Expanded(child: content),
          ],
        ),
      );
    }

    // Compact: drawer
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.surfaceLow,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.school_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _current.school?.name ?? 'ReportWise',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      drawer: Drawer(
        width: 280,
        backgroundColor: AppColors.primary,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: AppSidebar(
          selected: _section,
          onSelected: _onSelect,
          school: _current.school!,
          memberships: widget.memberships,
          current: _current,
          onSwitchSchool: (m) {
            Navigator.pop(context);
            setState(() => _current = m);
          },
          onSignOut: () => client?.auth.signOut(),
        ),
      ),
      body: content,
    );
  }

  Future<void> _openGlobalSearch(SupabaseClient client) async {
    final picked = await showSearch<_SearchHit?>(
      context: context,
      delegate: _GlobalSearchDelegate(
        client: client,
        schoolId: _current.schoolId,
      ),
    );
    if (picked == null || !mounted) return;
    ref.read(studentsSearchProvider.notifier).state = picked.query;
    _onSelect(picked.section);
  }
}

class _SearchHit {
  final String title;
  final String subtitle;
  final String query;
  final AppSection section;
  const _SearchHit(this.title, this.subtitle, this.query, this.section);
}

class _GlobalSearchDelegate extends SearchDelegate<_SearchHit?> {
  final SupabaseClient client;
  final String schoolId;
  _GlobalSearchDelegate({required this.client, required this.schoolId})
    : super(searchFieldLabel: 'Search students, classes, subjects or teachers');

  Future<List<_SearchHit>> _results() async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final pattern = '%$q%';
    final responses = await Future.wait<dynamic>([
      client
          .from('students')
          .select('full_name, matricule')
          .eq('school_id', schoolId)
          .ilike('full_name', pattern)
          .limit(8),
      client
          .from('classes')
          .select('name')
          .eq('school_id', schoolId)
          .ilike('name', pattern)
          .limit(8),
      client
          .from('subjects')
          .select('name, code')
          .or('school_id.is.null,school_id.eq.$schoolId')
          .ilike('name', pattern)
          .limit(8),
      client.rpc('list_school_members', params: {'p_school': schoolId}),
    ]);
    final hits = <_SearchHit>[];
    for (final row in (responses[0] as List))
      hits.add(
        _SearchHit(
          row['full_name']?.toString() ?? '',
          'Student',
          q,
          AppSection.studentRegistry,
        ),
      );
    for (final row in (responses[1] as List))
      hits.add(
        _SearchHit(
          row['name']?.toString() ?? '',
          'Class',
          q,
          AppSection.classes,
        ),
      );
    for (final row in (responses[2] as List))
      hits.add(
        _SearchHit(
          row['name']?.toString() ?? '',
          'Subject',
          q,
          AppSection.subjects,
        ),
      );
    for (final row in (responses[3] as List)) {
      final name = row['full_name']?.toString() ?? '';
      if (name.toLowerCase().contains(q.toLowerCase()))
        hits.add(
          _SearchHit(name, 'Teacher / staff', q, AppSection.teacherRegistry),
        );
    }
    return hits;
  }

  @override
  Widget buildSuggestions(BuildContext context) =>
      FutureBuilder<List<_SearchHit>>(
        future: _results(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return Center(child: Text('Search failed: ${snapshot.error}'));
          final hits = snapshot.data ?? const [];
          if (hits.isEmpty)
            return const Center(
              child: Text(
                'No matching students, classes, subjects or teachers.',
              ),
            );
          return ListView.builder(
            itemCount: hits.length,
            itemBuilder: (_, i) => ListTile(
              leading: Icon(hits[i].section.icon),
              title: Text(hits[i].title),
              subtitle: Text(hits[i].subtitle),
              onTap: () => close(context, hits[i]),
            ),
          );
        },
      );

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );
}

class _Panel extends StatelessWidget {
  final SupabaseClient client;
  final AppSection section;
  final School school;
  final SchoolMembership membership;
  final VoidCallback onSchoolsChanged;
  final ValueChanged<AppSection> onNavigate;

  const _Panel({
    required this.client,
    required this.section,
    required this.school,
    required this.membership,
    required this.onSchoolsChanged,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = membership.role.isAdminRole;

    switch (section) {
      case AppSection.dashboard:
        return ResponsiveDashboard(
          school: school,
          membership: membership,
          onSchoolsChanged: onSchoolsChanged,
          onNavigate: onNavigate,
        );
      case AppSection.academicRecords:
        return AcademicScreen(client: client, school: school, isAdmin: isAdmin);
      case AppSection.marks:
        return MarkEntryScreen(
          client: client,
          school: school,
          isAdmin: isAdmin,
          currentMembershipId: membership.id,
        );
      case AppSection.studentRegistry:
        return StudentsScreen(school: school, isAdmin: isAdmin);
      case AppSection.teacherRegistry:
        return TeachersScreen(client: client, school: school, isAdmin: isAdmin);
      case AppSection.classes:
        return isAdmin
            ? ClassesScreen(client: client, school: school)
            : const _AdminsOnly();
      case AppSection.subjects:
        return isAdmin
            ? SubjectsScreen(client: client, school: school)
            : const _AdminsOnly();
      case AppSection.reportCards:
        return ReportsScreen(client: client, school: school, isAdmin: isAdmin);
      case AppSection.settings:
        return SchoolSettingsScreen(
          school: school,
          repository: SchoolRepository(client),
          onSaved: onSchoolsChanged,
        );
    }
  }
}

class _AdminsOnly extends StatelessWidget {
  const _AdminsOnly();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 28,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Admins only',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ask an administrator to set up academic structure.',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13,
                color: AppColors.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  final AppSection section;
  final School school;
  final String hint;
  const _PlaceholderPage({
    required this.section,
    required this.school,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.label.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            section.label,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13,
              color: AppColors.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    section.icon,
                    size: 32,
                    color: AppColors.onSurfaceVariant.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '${section.label} module',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This module is built in the next phase and will share the same design system.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.5,
                    color: AppColors.onSurfaceVariant.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
