import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/academic_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/school_repository.dart';
import '../../data/repositories/student_repository.dart';
import 'supabase_provider.dart';

final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  return AuthRepository(client);
});

final schoolRepositoryProvider = Provider<SchoolRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  return SchoolRepository(client);
});

final academicRepositoryProvider = Provider<AcademicRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  return AcademicRepository(client);
});

final studentRepositoryProvider = Provider<StudentRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  return StudentRepository(client);
});
