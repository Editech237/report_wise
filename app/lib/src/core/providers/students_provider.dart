import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/entities.dart';
import '../../data/repositories/student_repository.dart';
import 'academic_providers.dart';

// Search query for students list — replaces local _search setState
final studentsSearchProvider = StateProvider<String>((ref) => '');

// Class filter for students list — replaces local _classFilter setState
final studentsClassFilterProvider = StateProvider<String?>((ref) => null);

// Students list is derived from dashboardDataProvider — no separate fetch needed
// This provider just filters the dashboard data reactively
final filteredStudentsProvider = Provider.family<List<StudentWithEnrollment>, String>((ref, schoolId) {
  final search = ref.watch(studentsSearchProvider).trim().toLowerCase();
  final classFilter = ref.watch(studentsClassFilterProvider);
  final dashboardAsync = ref.watch(dashboardDataProvider(schoolId));
  return dashboardAsync.when(
    data: (data) {
      final students = data.students;
      return students.where((r) {
        final q = search;
        final matchesSearch = q.isEmpty ||
            r.student.fullName.toLowerCase().contains(q) ||
            (r.student.matricule?.toLowerCase().contains(q) ?? false) ||
            (r.className?.toLowerCase().contains(q) ?? false);
        final matchesClass = classFilter == null || r.classId == classFilter;
        return matchesSearch && matchesClass;
      }).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});
