import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class StudentImportBatch {
  final String id;
  final String schoolId;
  final String originalFilename;
  final String status;
  final String storagePath;
  final int? pageCount;
  final int? rowCount;
  final int reviewedCount;
  final DateTime createdAt;

  const StudentImportBatch({
    required this.id,
    required this.schoolId,
    required this.originalFilename,
    required this.status,
    required this.storagePath,
    required this.pageCount,
    required this.rowCount,
    required this.reviewedCount,
    required this.createdAt,
  });

  factory StudentImportBatch.fromMap(Map<String, dynamic> map) {
    return StudentImportBatch(
      id: map['id'].toString(),
      schoolId: map['school_id'].toString(),
      originalFilename: map['original_filename']?.toString() ?? 'Untitled PDF',
      status: map['status']?.toString() ?? 'UPLOADED',
      storagePath: map['storage_path']?.toString() ?? '',
      pageCount: (map['page_count'] as num?)?.toInt(),
      rowCount: (map['row_count'] as num?)?.toInt(),
      reviewedCount: (map['reviewed_count'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class StudentImportRow {
  final String id;
  final int rowNumber;
  final Map<String, dynamic> normalizedData;
  final Map<String, dynamic> confidence;
  final Map<String, dynamic> rawData;
  final String? reviewNotes;
  final String status;

  const StudentImportRow({
    required this.id,
    required this.rowNumber,
    required this.normalizedData,
    required this.confidence,
    required this.status,
    this.rawData = const {},
    this.reviewNotes,
  });

  factory StudentImportRow.fromMap(Map<String, dynamic> map) =>
      StudentImportRow(
        id: map['id'].toString(),
        rowNumber: (map['row_number'] as num?)?.toInt() ?? 0,
        normalizedData: Map<String, dynamic>.from(
          (map['normalized_data'] as Map?) ?? const {},
        ),
        confidence: Map<String, dynamic>.from(
          (map['confidence'] as Map?) ?? const {},
        ),
        rawData: Map<String, dynamic>.from(
          (map['raw_data'] as Map?) ?? const {},
        ),
        reviewNotes: map['review_notes'] as String?,
        status: map['status']?.toString() ?? 'NEEDS_REVIEW',
      );

  String get confidenceLabel {
    final values = confidence.values.whereType<num>().toList();
    if (values.isEmpty) return 'unknown';
    return '${(values.reduce((a, b) => a + b) / values.length * 100).round()}%';
  }
}

class StudentImportRepository {
  final SupabaseClient _client;

  StudentImportRepository(this._client);

  Future<StudentImportBatch> uploadPdf({
    required String schoolId,
    required File file,
    required String filename,
  }) async {
    final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$schoolId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    try {
      await _client.storage
          .from('student-imports')
          .upload(
            path,
            file,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: false,
            ),
          );
    } on StorageException catch (error) {
      final message = error.message.toLowerCase();
      final statusCode = error.statusCode?.toString();

      if (statusCode == '404' || message.contains('bucket')) {
        throw Exception(
          'Student import storage is not configured yet. Apply the '
          '0029_student_document_imports.sql Supabase migration, then try again.',
        );
      }
      if (statusCode == '401' || statusCode == '403') {
        throw Exception(
          'Only a school administrator can upload student documents.',
        );
      }
      if (message.contains('mime') || message.contains('type')) {
        throw Exception('Please upload a PDF document.');
      }
      if (message.contains('size') || message.contains('large')) {
        throw Exception('The PDF is too large. Please keep it under 50 MB.');
      }
      throw Exception('Could not upload the PDF: ${error.message}');
    }

    try {
      final row = await _client
          .from('student_import_batches')
          .insert({
            'school_id': schoolId,
            'original_filename': filename,
            'storage_path': path,
            'source_type': 'PDF',
            'status': 'UPLOADED',
          })
          .select()
          .single();
      return StudentImportBatch.fromMap(row);
    } catch (_) {
      // Do not leave a private orphaned document if batch creation fails.
      await _client.storage.from('student-imports').remove([path]);
      rethrow;
    }
  }

  Future<List<StudentImportBatch>> listBatches(String schoolId) async {
    final rows = await _client
        .from('student_import_batches')
        .select()
        .eq('school_id', schoolId)
        .order('created_at', ascending: false)
        .limit(25);
    return (rows as List)
        .map((row) => StudentImportBatch.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Only stages suggestions in the existing admin-protected review tables.
  /// No student or enrollment is created until the administrator approves it.
  Future<StudentImportBatch> saveLocalExtraction({
    required StudentImportBatch batch,
    required List<Map<String, dynamic>> pages,
  }) async {
    final claimed = await _client
        .from('student_import_batches')
        .update({'status': 'PROCESSING', 'error_message': null})
        .eq('id', batch.id)
        .eq('status', 'UPLOADED')
        .select('id')
        .maybeSingle();
    if (claimed == null) {
      throw StateError('This document is already being processed.');
    }
    try {
      final savedPages = await _client
          .from('student_import_pages')
          .insert([
            for (final page in pages)
              {
                'batch_id': batch.id,
                'page_number': page['page_number'],
                'status': 'EXTRACTED',
                'raw_text': page['raw_text'],
                'extraction_payload': {
                  'engine': 'local',
                  'warnings': page['warnings'],
                },
              },
          ])
          .select('id,page_number');
      final ids = {
        for (final page in savedPages) page['page_number']: page['id'],
      };
      final rows = <Map<String, dynamic>>[];
      for (final page in pages) {
        for (final row in page['rows'] as List) {
          rows.add({
            'batch_id': batch.id,
            'page_id': ids[page['page_number']],
            'row_number': rows.length + 1,
            'raw_data': row['raw_data'],
            'normalized_data': row['normalized_data'],
            'confidence': row['confidence'],
            'review_notes': (row['warnings'] as List).join(' '),
            'status': 'NEEDS_REVIEW',
          });
        }
      }
      if (rows.isNotEmpty) {
        await _client.from('student_import_rows').insert(rows);
      }
      final updated = await _client
          .from('student_import_batches')
          .update({
            'status': 'NEEDS_REVIEW',
            'page_count': pages.length,
            'row_count': rows.length,
            'reviewed_count': 0,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', batch.id)
          .select()
          .single();
      return StudentImportBatch.fromMap(updated);
    } catch (error, stack) {
      try {
        await _client
            .from('student_import_batches')
            .update({
              'status': 'FAILED',
              'error_message':
                  'Could not save extracted rows. Upload again to retry.',
            })
            .eq('id', batch.id);
      } catch (_) {
        /* Preserve the original failure if the connection is down. */
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<List<Map<String, dynamic>>> listExtractedPages(String batchId) async {
    return await _client
        .from('student_import_pages')
        .select('page_number,raw_text,extraction_payload')
        .eq('batch_id', batchId)
        .order('page_number');
  }

  Future<List<StudentImportRow>> listRows(String batchId) async {
    final result = <StudentImportRow>[];
    const pageSize = 500;
    for (var offset = 0; ; offset += pageSize) {
      final rows = await _client
          .from('student_import_rows')
          .select()
          .eq('batch_id', batchId)
          .order('row_number', ascending: true)
          .range(offset, offset + pageSize - 1);
      result.addAll(rows.map(StudentImportRow.fromMap));
      if (rows.length < pageSize) return result;
    }
  }

  Future<Uint8List> downloadOriginalPdf(String storagePath) =>
      _client.storage.from('student-imports').download(storagePath);

  Future<void> updateRow({
    required String rowId,
    required Map<String, dynamic> normalizedData,
    required String status,
  }) async {
    final updated = await _client
        .from('student_import_rows')
        .update({'normalized_data': normalizedData, 'status': status})
        .eq('id', rowId)
        .neq('status', 'IMPORTED')
        .select('id')
        .maybeSingle();
    if (updated == null)
      throw StateError(
        'This row was already imported or is no longer available. Refresh the review.',
      );
  }

  Future<StudentImportRow> createManualRow({
    required String batchId,
    required int rowNumber,
    required Map<String, dynamic> normalizedData,
  }) async {
    final row = await _client
        .from('student_import_rows')
        .insert({
          'batch_id': batchId,
          'row_number': rowNumber,
          'raw_data': {},
          'normalized_data': normalizedData,
          'confidence': {},
          'status': 'APPROVED',
        })
        .select()
        .single();
    return StudentImportRow.fromMap(row);
  }

  Future<int> commitApproved({
    required String batchId,
    required String academicYearId,
  }) async {
    final result = await _client.rpc(
      'import_approved_student_rows',
      params: {'p_batch': batchId, 'p_year': academicYearId},
    );
    return (result as num?)?.toInt() ?? 0;
  }

  Future<void> processPdf(String batchId) async {
    final response = await _client.functions.invoke(
      'process-student-import',
      body: {'batch_id': batchId},
    );
    if (response.data is Map && response.data['error'] != null) {
      throw Exception(response.data['error']);
    }
  }
}
