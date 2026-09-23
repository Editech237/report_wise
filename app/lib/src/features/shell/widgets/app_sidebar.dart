import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_section.dart';
import '../../../core/school_labels.dart';
import '../../../data/entities.dart';

class AppSidebar extends StatelessWidget {
  final AppSection selected;
  final ValueChanged<AppSection> onSelected;
  final School school;
  final List<SchoolMembership> memberships;
  final SchoolMembership current;
  final ValueChanged<SchoolMembership> onSwitchSchool;
  final VoidCallback onSignOut;

  const AppSidebar({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.school,
    required this.memberships,
    required this.current,
    required this.onSwitchSchool,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 236,
      color: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand header — show school logo if available, fallback to icon
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            child: Row(
              children: [
                _SchoolLogoBadge(logoUrl: school.logoUrl, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ReportWise',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        current.role.isTeacherRole && !current.role.isAdminRole
                            ? 'TEACHER PORTAL'
                            : 'ADMIN PORTAL',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB8D5C8),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // School switcher chip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: InkWell(
              onTap: () => _showSchoolSwitcher(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            school.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${school.schoolType == 'GENERAL'
                                ? 'General'
                                : school.schoolType == 'TECHNICAL'
                                ? 'Technical'
                                : school.schoolType} • ${SchoolLabels(school.subsystem).sectionName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 10,
                              color: Colors.white.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Nav Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children:
                  (current.role.isTeacherRole && !current.role.isAdminRole
                          ? const [AppSection.marks]
                          : AppSection.values)
                      .map((section) {
                        final isSelected = section == selected;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => onSelected(section),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? section.iconFilled
                                          : section.icon,
                                      size: 20,
                                      color: isSelected
                                          ? AppColors.primary
                                          : Colors.white.withOpacity(0.9),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      section.label,
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 13.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: isSelected
                                            ? AppColors.primary
                                            : Colors.white.withOpacity(0.95),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(),
            ),
          ),

          // Footer actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      textStyle: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('New Enrollment'),
                    onPressed: () => onSelected(AppSection.studentRegistry),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(0.85),
                      side: BorderSide(color: Colors.white.withOpacity(0.18)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text(
                      'Sign out',
                      style: TextStyle(fontFamily: 'Lexend', fontSize: 13),
                    ),
                    onPressed: onSignOut,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSchoolSwitcher(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: memberships.map((m) {
            final logo = m.school?.logoUrl;
            final hasLogo =
                logo != null &&
                logo.trim().isNotEmpty &&
                (logo.startsWith('http://') || logo.startsWith('https://'));
            return ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasLogo
                    ? Image.network(
                        logo!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.school_outlined,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      )
                    : const Icon(
                        Icons.school_outlined,
                        size: 18,
                        color: AppColors.primary,
                      ),
              ),
              title: Text(
                m.school?.name ?? 'School',
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                m.role.replaceAll('_', ' '),
                style: const TextStyle(fontFamily: 'Lexend', fontSize: 11),
              ),
              trailing: m.schoolId == current.schoolId
                  ? const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.primary,
                    )
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                onSwitchSchool(m);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SchoolLogoBadge extends StatelessWidget {
  final String? logoUrl;
  final double size;
  const _SchoolLogoBadge({required this.logoUrl, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final url = logoUrl?.trim();
    final hasLogo =
        url != null &&
        url.isNotEmpty &&
        (url.startsWith('http://') || url.startsWith('https://'));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLogo
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.school_rounded,
                color: Colors.white,
                size: 22,
              ),
            )
          : const Icon(Icons.school_rounded, color: Colors.white, size: 22),
    );
  }
}
