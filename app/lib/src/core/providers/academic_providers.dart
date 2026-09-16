import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/entities.dart';
import '../../data/repositories/academic_repository.dart';
import '../../data/repositories/student_repository.dart';
import 'repository_providers.dart';

/// Academic years for a school — cached via AcademicCache inside AcademicRepository
final academicYearsProvider = FutureProvider.family<List<AcademicYear>, String>((ref, schoolId) async {
  final repo = ref.watch(academicRepositoryProvider);
  if (repo == null) return [];
  return repo.academicYears(schoolId);
});

/// Classes for a school + academic year
final classesProvider = FutureProvider.family<List<SchoolClass>, ({String schoolId, String academicYearId})>((ref, args) async {
  final repo = ref.watch(academicRepositoryProvider);
  if (repo == null) return [];
  return repo.classesFor(schoolId: args.schoolId, academicYearId: args.academicYearId);
});

/// Student enrollments for a school + year (via StudentRepository)
final studentsForYearProvider = FutureProvider.family<List<StudentWithEnrollment>, ({String schoolId, String academicYearId})>((ref, args) async {
  final repo = ref.watch(studentRepositoryProvider);
  if (repo == null) return [];
  return repo.list(schoolId: args.schoolId, academicYearId: args.academicYearId);
});

/// Teacher assignments for a school + year
final teacherAssignmentsProvider = FutureProvider.family<List<TeacherAssignment>, ({String schoolId, String academicYearId})>((ref, args) async {
  final repo = ref.watch(academicRepositoryProvider);
  if (repo == null) return [];
  return repo.teacherAssignments(schoolId: args.schoolId, academicYearId: args.academicYearId);
});

/// Dashboard bundle — replaces ResponsiveDashboard's FutureBuilder + manual _loadData setState
final dashboardDataProvider = FutureProvider.family<DashboardData, String>((ref, schoolId) async {
  final academicRepo = ref.watch(academicRepositoryProvider);
  if (academicRepo == null) throw StateError('No academic repo');
  final years = await ref.watch(academicYearsProvider(schoolId).future);
  if (years.isEmpty) return DashboardData.empty();
  final year = years.firstWhere((y) => y.isCurrent, orElse: () => years.first);
  final results = await Future.wait([
    ref.watch(classesProvider((schoolId: schoolId, academicYearId: year.id)).future),
    ref.watch(teacherAssignmentsProvider((schoolId: schoolId, academicYearId: year.id)).future),
    ref.watch(studentsForYearProvider((schoolId: schoolId, academicYearId: year.id)).future),
  ]);
  return DashboardData(
    academicYears: years,
    classes: results[0] as List<SchoolClass>,
    teacherAssignments: results[1] as List<TeacherAssignment>,
    students: results[2] as List<StudentWithEnrollment>,
  );
});

class DashboardData {
  final List<AcademicYear> academicYears;
  final List<SchoolClass> classes;
  final List<TeacherAssignment> teacherAssignments;
  final List<StudentWithEnrollment> students;
  const DashboardData({required this.academicYears, required this.classes, required this.teacherAssignments, required this.students});
  factory DashboardData.empty() => const DashboardData(academicYears: [], classes: [], teacherAssignments: [], students: []);
}

/// Real dashboard metrics (pass rate + recent activity).
final dashboardMetricsProvider = FutureProvider.family<DashboardMetrics?, String>(
    (ref, schoolId) async {
  final repo = ref.watch(academicRepositoryProvider);
  if (repo == null) return null;
  final data = ref.watch(dashboardDataProvider(schoolId)).valueOrNull;
  if (data == null || data.academicYears.isEmpty) return null;
  final year =
      data.academicYears.firstWhere((y) => y.isCurrent, orElse: () => data.academicYears.first);
  return repo.dashboardMetrics(schoolId: schoolId, academicYearId: year.id);
});

/// Invalidates every provider that feeds the dashboard so no stale child cache
/// survives an add/edit/delete/refresh. Without this, invalidating only
/// dashboardDataProvider returns the cached child lists (stale students etc.).
void invalidateSchoolData(WidgetRef ref, String schoolId, String academicYearId) {
  ref.invalidate(academicYearsProvider(schoolId));
  ref.invalidate(classesProvider((schoolId: schoolId, academicYearId: academicYearId)));
  ref.invalidate(teacherAssignmentsProvider((schoolId: schoolId, academicYearId: academicYearId)));
  ref.invalidate(studentsForYearProvider((schoolId: schoolId, academicYearId: academicYearId)));
  ref.invalidate(dashboardDataProvider(schoolId));
}
