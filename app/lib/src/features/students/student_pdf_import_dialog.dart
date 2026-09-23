import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/entities.dart';
import '../../data/imports/local_student_ocr.dart';
import '../../data/repositories/student_import_repository.dart';

class StudentPdfImportDialog extends StatefulWidget {
  final School school;
  final StudentImportRepository repository;

  const StudentPdfImportDialog({
    super.key,
    required this.school,
    required this.repository,
  });

  @override
  State<StudentPdfImportDialog> createState() => _StudentPdfImportDialogState();
}

class _StudentPdfImportDialogState extends State<StudentPdfImportDialog> {
  PlatformFile? _file;
  bool _busy = false;
  String _progress = '';
  String? _error;

  Future<void> _pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (mounted && result.isNotEmpty) {
      setState(() {
        _file = result.first;
        _error = null;
      });
    }
  }

  Future<void> _upload() async {
    final file = _file;
    if (file?.path == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Reading PDF on this computer…';
    });
    try {
      if (await File(file!.path!).length() > 50 * 1024 * 1024) {
        throw const FormatException('Please choose a PDF smaller than 50 MB.');
      }
      final pages = await LocalStudentOcr().extract(
        file.path!,
        onProgress: (page, total) {
          if (mounted) {
            setState(() => _progress = 'Reading page $page of $total…');
          }
        },
      );
      if (!mounted) return;
      setState(() => _progress = 'Saving document and extracted students…');
      var batch = await widget.repository.uploadPdf(
        schoolId: widget.school.id,
        file: File(file.path!),
        filename: file.name,
      );
      batch = await widget.repository.saveLocalExtraction(
        batch: batch,
        pages: pages,
      );
      if (mounted) Navigator.pop(context, batch);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not scan this PDF: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Scan paper register'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Automatically read a clear PDF register on this computer, then review the students before importing. No OCR subscription or API key is required. The PDF and results are saved to your school account.',
              ),
              if (!LocalStudentOcr.isSupported)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Free scanning requires the Windows or Mac desktop app.',
                  ),
                ),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_progress),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(
                    _error!,
                    style: const TextStyle(color: AppColors.accentRed),
                  ),
                ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(_file?.name ?? 'Choose PDF'),
              ),
              if (_file != null) ...[
                const SizedBox(height: 12),
                Text(
                  'The school will be able to review names, identifiers, classes, dates, and confidence warnings before import.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant.withValues(alpha: .8),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed:
                _busy || _file?.path == null || !LocalStudentOcr.isSupported
                ? null
                : _upload,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(_busy ? 'Scanning…' : 'Scan and review'),
          ),
        ],
      ),
    );
  }
}
