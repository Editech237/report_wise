import 'package:supabase_flutter/supabase_flutter.dart';

import '../entities.dart';

/// Mark entry & workflow (spec sections 11, 27, 28).
///
/// All reads/writes go through security-definer RPCs that validate the caller
/// (assigned teacher or admin), the sequence state and that every enrollment
/// reference belongs to the mark book's class. Direct table writes are only
/// used for the workflow status transition, which the Phase-0 trigger already
/// guards.
class MarkRepository {
  final SupabaseClient _client;

  MarkRepository(this._client);

  Future<String> getOrCreateMarkBook({
    required String assignmentId,
    required String sequenceId,
  }) async {
    final result = await _client.rpc('get_or_create_mark_book', params: {
      'p_assignment': assignmentId,
      'p_sequence': sequenceId,
    });
    return result.toString();
  }

  /// Persistent mark-book history for the current user's school + year.
  /// Teachers get their own books; administrators get all books.
  Future<List<MarkBookSummary>> listMarkBooks({
    required String schoolId,
    required String academicYearId,
  }) async {
    final rows = await _client.rpc('list_mark_books', params: {
      'p_school': schoolId,
      'p_year': academicYearId,
    });
    return (rows as List)
        .map((r) => MarkBookSummary.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<StudentInClass>> studentsInClass({
    required String classId,
    required String academicYearId,
  }) async {
    final rows = await _client.rpc('students_in_class', params: {
      'p_class': classId,
      'p_year': academicYearId,
    });
    return (rows as List)
        .map((r) => StudentInClass.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<MarkEntry>> markEntries(String bookId) async {
    final rows =
        await _client.rpc('list_mark_entries', params: {'p_book': bookId});
    return (rows as List)
        .map((r) => MarkEntry.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<MarkBookEvent>> markBookEvents(String bookId) async {
    final rows =
        await _client.rpc('list_mark_book_events', params: {'p_book': bookId});
    return (rows as List)
        .map((r) => MarkBookEvent.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Transactionally upserts the given entries for a mark book.
  Future<void> saveMarkEntries({
    required String bookId,
    required List<Map<String, Object?>> entries,
  }) async {
    if (entries.isEmpty) return;
    await _client.rpc('save_mark_entries', params: {
      'p_book': bookId,
      'p_entries': entries,
    });
  }

  /// Teacher: DRAFT → SUBMITTED. Administrator: any forward transition.
  /// The DB trigger validates the transition and records the audit event.
  Future<void> setMarkBookStatus(String bookId, String status) async {
    await _client.from('mark_books').update({
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', bookId);
  }

  /// Administrator unlock (audited, reason required).
  Future<void> unlockMarkBook({
    required String bookId,
    required String reason,
    String newStatus = 'REVIEWED',
  }) async {
    await _client.rpc('unlock_mark_book', params: {
      'p_book': bookId,
      'p_reason': reason,
      'p_new_status': newStatus,
    });
  }

  Future<Map<String, dynamic>?> markBook(String bookId) async {
    return await _client
        .from('mark_books')
        .select()
        .eq('id', bookId)
        .maybeSingle();
  }
}