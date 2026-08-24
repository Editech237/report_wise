import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_section.dart';
import '../../data/entities.dart';
import '../../data/repositories/auth_repository.dart';
import '../setup/classes_screen.dart';
import '../setup/subjects_screen.dart';
import '../students/students_screen.dart';
import 'responsive_dashboard.dart';
import 'widgets/app_sidebar.dart';
import 'widgets/app_top_bar.dart';

/// Main app shell — modern two-pane layout copied from reference design:
/// dark green sidebar + white top bar + light surface content.
/// Responsive: wide shows permanent sidebar, narrow uses drawer.
class SchoolShell extends StatefulWidget {
  final SupabaseClient client;
  final List<SchoolMembership> memberships;
  final VoidCallback onSchoolsChanged;

  const SchoolShell({
    super.key,
    required this.client,
    required this.memberships,
    required this.onSchoolsChanged,
  });

  @override
  State<SchoolShell> createState() => _SchoolShellState();
}

class _SchoolShellState extends State<SchoolShell> {
  late SchoolMembership _current;
  AppSection _section = AppSection.dashboard;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _current = widget.memberships.first;
  }

  void _onSelect(AppSection s) {
    setState(() => _section = s);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    final sidebar = AppSidebar(
      selected: _section,
      onSelected: _onSelect,
      school: _current.school!,
      memberships: widget.memberships,
      current: _current,
      onSwitchSchool: (m) => setState(() => _current = m),
      onSignOut: () => AuthRepository(widget.client).signOut(),
    );

    final content = Column(
      children: [
        AppTopBar(
          schoolName: _current.school?.name,
          userName: null,
          onGenerateReports: () => _onSelect(AppSection.reportCards),
        ),
        Container(height: 1, color: AppColors.divider),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
            child: KeyedSubtree(
              key: ValueKey(_section),
              child: _Panel(
                client: widget.client,
                section: _section,
                school: _current.school!,
                membership: _current,
                onSchoolsChanged: widget.onSchoolsChanged,
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
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.school_rounded, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _current.school?.name ?? 'ReportWise',
                style: const TextStyle(fontFamily: 'Manrope', fontSize: 15, fontWeight: FontWeight.w700),
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
          onSignOut: () => AuthRepository(widget.client).signOut(),
        ),
      ),
      body: content,
    );
  }
}

class _Panel extends StatelessWidget {
  final SupabaseClient client;
  final AppSection section;
  final School school;
  final SchoolMembership membership;
  final VoidCallback onSchoolsChanged;

  const _Panel({
    required this.client,
    required this.section,
    required this.school,
    required this.membership,
    required this.onSchoolsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = membership.role.isAdminRole;

    switch (section) {
      case AppSection.dashboard:
        return ResponsiveDashboard(
          client: client,
          school: school,
          membership: membership,
          onSchoolsChanged: onSchoolsChanged,
        );
      case AppSection.academicRecords:
        return _PlaceholderPage(section: section, school: school, hint: 'Terms, sequences & calendar — coming soon');
      case AppSection.studentRegistry:
        return StudentsScreen(client: client, school: school);
      case AppSection.teacherRegistry:
        return _PlaceholderPage(section: section, school: school, hint: 'Teacher assignments & workload');
      case AppSection.classes:
        return isAdmin ? ClassesScreen(client: client, school: school) : const _AdminsOnly();
      case AppSection.subjects:
        return isAdmin ? SubjectsScreen(client: client, school: school) : const _AdminsOnly();
      case AppSection.reportCards:
        return _PlaceholderPage(section: section, school: school, hint: 'Coefficient-weighted report cards');
      case AppSection.settings:
        return _PlaceholderPage(section: section, school: school, hint: 'School settings & preferences');
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
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), shape: BoxShape.circle),
              child: const Icon(Icons.lock_outline_rounded, size: 28, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text('Admins only', style: TextStyle(fontFamily: 'Manrope', fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Ask an administrator to set up academic structure.', style: TextStyle(fontFamily: 'Lexend', fontSize: 13, color: AppColors.onSurfaceVariant.withOpacity(0.7))),
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
  const _PlaceholderPage({required this.section, required this.school, required this.hint});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.label.toUpperCase(),
              style: const TextStyle(fontFamily: 'Lexend', fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 1.1)),
          const SizedBox(height: 6),
          Text(section.label, style: const TextStyle(fontFamily: 'Manrope', fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
          const SizedBox(height: 8),
          Text(hint, style: TextStyle(fontFamily: 'Lexend', fontSize: 13, color: AppColors.onSurfaceVariant.withOpacity(0.7))),
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.surfaceLow, borderRadius: BorderRadius.circular(16)),
                  child: Icon(section.icon, size: 32, color: AppColors.onSurfaceVariant.withOpacity(0.6)),
                ),
                const SizedBox(height: 16),
                Text('${section.label} module', style: const TextStyle(fontFamily: 'Manrope', fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('This module is built in the next phase and will share the same design system.',
                    textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Lexend', fontSize: 12.5, color: AppColors.onSurfaceVariant.withOpacity(0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
