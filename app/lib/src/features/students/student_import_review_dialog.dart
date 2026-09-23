import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/theme/app_colors.dart';
import '../../data/entities.dart';
import '../../data/imports/student_register_parser.dart';
import '../../data/imports/student_import_review.dart';
import '../../data/repositories/student_import_repository.dart';

class StudentImportReviewDialog extends StatefulWidget {
  final String academicYearId;
  final List<SchoolClass> classes;
  final StudentImportBatch batch;
  final StudentImportRepository repository;

  const StudentImportReviewDialog({
    super.key,
    required this.academicYearId,
    required this.classes,
    required this.batch,
    required this.repository,
  });

  @override
  State<StudentImportReviewDialog> createState() =>
      _StudentImportReviewDialogState();
}

class _StudentImportReviewDialogState extends State<StudentImportReviewDialog> {
  List<StudentImportRow> _rows = const [];
  bool _loading = true;
  bool _busy = false;
  String? _loadError;
  List<Map<String, dynamic>> _pages = const [];
  String? _notice;
  List<SchoolClass> get _classes => widget.classes
      .where(
        (c) =>
            c.isActive &&
            c.schoolId == widget.batch.schoolId &&
            c.academicYearId == widget.academicYearId,
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rows = await widget.repository.listRows(widget.batch.id);
      final pages = await widget.repository.listExtractedPages(widget.batch.id);
      if (mounted) {
        setState(() {
          _rows = rows;
          _pages = pages;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = 'Could not load the review: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showExtractedText() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Text read from the PDF'),
        content: SizedBox(
          width: 750,
          height: 500,
          child: SingleChildScrollView(
            child: SelectableText(
              _pages
                  .map((page) {
                    final payload = page['extraction_payload'] as Map?;
                    final warnings = (payload?['warnings'] as List?) ?? [];
                    return 'Page ${page['page_number']}\n${warnings.join('\n')}\n${page['raw_text'] ?? ''}';
                  })
                  .join('\n\n'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showOriginalPdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await widget.repository.downloadOriginalPdf(
        widget.batch.storagePath,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Original register'),
          content: SizedBox(
            width: 800,
            height: 600,
            child: PdfPreview(
              build: (_) async => bytes,
              allowPrinting: false,
              allowSharing: false,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the original PDF: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(StudentImportRow row) async {
    if (!mounted) return;
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _ImportRowEditor(
        row: row,
        classes: _classes,
        repository: widget.repository,
      ),
    );
    if (updated == true) await _load();
  }

  Future<void> _addManualRow() async {
    try {
      final highest = _rows.fold<int>(
        0,
        (max, row) => row.rowNumber > max ? row.rowNumber : max,
      );
      final row = StudentImportRow(
        id: '',
        rowNumber: highest + 1,
        normalizedData: const {},
        confidence: const {},
        status: 'NEEDS_REVIEW',
      );
      if (!mounted) return;
      await showDialog<bool>(
        context: context,
        builder: (_) => _ImportRowEditor(
          row: row,
          classes: _classes,
          repository: widget.repository,
          newRowBatchId: widget.batch.id,
        ),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add a row: $error')));
      }
    }
  }

  Future<void> _approve(List<StudentImportRow> candidates) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    var approved = 0, skipped = 0;
    try {
      for (final row in candidates) {
        if (!['READY', 'NEEDS_REVIEW'].contains(row.status)) continue;
        final data = reviewValues(row, _classes);
        if (approvalProblem(data, _classes) != null) {
          skipped++;
          continue;
        }
        await widget.repository.updateRow(
          rowId: row.id,
          normalizedData: data,
          status: 'APPROVED',
        );
        approved++;
      }
      if (mounted)
        setState(
          () => _notice =
              '$approved rows approved.${skipped > 0 ? ' $skipped rows need a name, class, or date corrected. Open Review to fix them.' : ''}',
        );
    } catch (error) {
      if (mounted)
        setState(
          () => _notice =
              '$approved rows approved before an error: $error. Refresh and retry the remaining rows.',
        );
    } finally {
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    setState(() => _busy = true);
    try {
      final count = await widget.repository.commitApproved(
        batchId: widget.batch.id,
        academicYearId: widget.academicYearId,
      );
      if (mounted) Navigator.pop(context, count);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not import approved rows: $error'),
            backgroundColor: AppColors.accentRed,
          ),
        );
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final approved = _rows.where((r) => r.status == 'APPROVED').length;
    final pending = _rows
        .where((r) => !['APPROVED', 'REJECTED', 'IMPORTED'].contains(r.status))
        .length;
    final warnings = _pages
        .expand(
          (page) =>
              ((page['extraction_payload'] as Map?)?['warnings'] as List?) ??
              [],
        )
        .map((w) => w.toString())
        .toList();
    return AlertDialog(
      title: Text('Review ${widget.batch.originalFilename}'),
      content: SizedBox(
        width: 900,
        height: 600,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(child: SelectableText(_loadError!))
            : _rows.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No student rows were identified. Check the extracted text, try a clearer scan with visible table headings, or add rows manually.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy ? null : _addManualRow,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Add student row'),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_notice != null) Text(_notice!),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: _busy || pending == 0
                          ? null
                          : () => _approve(_rows),
                      child: const Text('Approve All'),
                    ),
                  ),
                  Text(
                    '${_rows.length} rows found · $approved approved · $pending need review',
                  ),
                  const Text(
                    'Compare names and identifiers with the original register. OCR can make mistakes, especially with handwriting.',
                  ),
                  if (warnings.isNotEmpty)
                    Text(
                      '${warnings.length} page warnings. View extracted text for details.',
                      style: const TextStyle(color: AppColors.accentRed),
                    ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final row = _rows[index];
                        final values = reviewValues(row, _classes);
                        final name = values['full_name']?.toString();
                        final className = values['class_name']?.toString();
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 16,
                            child: Text('${row.rowNumber}'),
                          ),
                          title: Text(
                            name?.isNotEmpty == true ? name! : 'Missing name',
                          ),
                          subtitle: Text(
                            '${className ?? 'Class not mapped'} · ${row.status} · confidence ${row.confidenceLabel}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if ([
                                'READY',
                                'NEEDS_REVIEW',
                              ].contains(row.status)) ...[
                                FilledButton.tonal(
                                  onPressed: _busy
                                      ? null
                                      : () => _approve([row]),
                                  child: const Text('Approve'),
                                ),
                                const SizedBox(width: 8),
                              ],
                              OutlinedButton(
                                onPressed: _busy || row.status == 'IMPORTED'
                                    ? null
                                    : () => _edit(row),
                                child: Text(
                                  row.status == 'APPROVED' ? 'Edit' : 'Review',
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _showOriginalPdf,
          child: const Text('View original PDF'),
        ),
        if (_pages.isNotEmpty)
          TextButton(
            onPressed: _busy ? null : _showExtractedText,
            child: const Text('View extracted text'),
          ),
        TextButton(
          onPressed: _busy ? null : _load,
          child: const Text('Refresh'),
        ),
        if (_rows.isNotEmpty)
          TextButton(
            onPressed: _busy ? null : _addManualRow,
            child: const Text('Add row'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _busy || _loading || _loadError != null || approved == 0
              ? null
              : _commit,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_add_alt_1),
          label: Text(_busy ? 'Please wait…' : 'Import approved students'),
        ),
      ],
    );
  }
}

class _ImportRowEditor extends StatefulWidget {
  final StudentImportRow row;
  final List<SchoolClass> classes;
  final StudentImportRepository repository;
  final String? newRowBatchId;
  const _ImportRowEditor({
    required this.row,
    required this.classes,
    required this.repository,
    this.newRowBatchId,
  });

  @override
  State<_ImportRowEditor> createState() => _ImportRowEditorState();
}

class _ImportRowEditorState extends State<_ImportRowEditor> {
  late final TextEditingController _name, _matricule, _externalId, _dob;
  String? _classId;
  String? _gender;
  bool _saving = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final data = reviewValues(widget.row, widget.classes);
    _name = TextEditingController(text: data['full_name']?.toString() ?? '');
    _matricule = TextEditingController(
      text: data['matricule']?.toString() ?? '',
    );
    _externalId = TextEditingController(
      text: data['external_student_id']?.toString() ?? '',
    );
    _dob = TextEditingController(text: data['date_of_birth']?.toString() ?? '');
    _classId = data['class_id']?.toString();
    if (!widget.classes.any((c) => c.id == _classId)) {
      final matches = widget.classes
          .where(
            (c) =>
                StudentRegisterParser.key(c.name) ==
                StudentRegisterParser.key(data['class_name']?.toString() ?? ''),
          )
          .toList();
      _classId = matches.length == 1 ? matches.single.id : null;
    }
    _gender = ['M', 'F'].contains(data['gender'])
        ? data['gender'] as String
        : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _matricule.dispose();
    _externalId.dispose();
    _dob.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _classId == null) {
      setState(() => _validationError = 'Enter a name and select a class.');
      return;
    }
    final dob = _dob.text.trim();
    if (dob.isNotEmpty &&
        (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dob) ||
            StudentRegisterParser.normalizeDate(dob) == null)) {
      setState(
        () => _validationError =
            'Enter a valid birth date as YYYY-MM-DD, or leave it blank.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });
    final selectedClass = widget.classes
        .where((c) => c.id == _classId)
        .firstOrNull;
    final data = <String, dynamic>{
      ...widget.row.normalizedData,
      'full_name': _name.text.trim(),
      'matricule': _matricule.text.trim().isEmpty
          ? null
          : _matricule.text.trim(),
      'external_student_id': _externalId.text.trim().isEmpty
          ? null
          : _externalId.text.trim(),
      'date_of_birth': _dob.text.trim().isEmpty ? null : _dob.text.trim(),
      'gender': _gender,
      'class_id': _classId,
      'class_name': selectedClass?.name,
    };
    try {
      if (widget.newRowBatchId != null) {
        await widget.repository.createManualRow(
          batchId: widget.newRowBatchId!,
          rowNumber: widget.row.rowNumber,
          normalizedData: data,
        );
      } else {
        await widget.repository.updateRow(
          rowId: widget.row.id,
          normalizedData: data,
          status: 'APPROVED',
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save row: $error')));
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _reject() async {
    setState(() => _saving = true);
    try {
      await widget.repository.updateRow(
        rowId: widget.row.id,
        normalizedData: widget.row.normalizedData,
        status: 'REJECTED',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _validationError = 'Could not exclude this row: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.newRowBatchId != null
          ? 'Add student row'
          : 'Review row ${widget.row.rowNumber}',
    ),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_validationError != null)
              Text(
                _validationError!,
                style: const TextStyle(color: AppColors.accentRed),
              ),
            if (widget.row.reviewNotes?.isNotEmpty == true)
              Text(
                widget.row.reviewNotes!,
                style: const TextStyle(color: AppColors.accentRed),
              ),
            if (widget.row.rawData.isNotEmpty)
              ExpansionTile(
                title: const Text('Original extracted values'),
                children: [
                  SelectableText(
                    widget.row.rawData.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join('\n'),
                  ),
                ],
              ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name *'),
            ),
            TextField(
              controller: _externalId,
              decoration: const InputDecoration(
                labelText: 'School ID (optional)',
              ),
            ),
            TextField(
              controller: _matricule,
              decoration: const InputDecoration(
                labelText: 'Matricule (optional)',
              ),
            ),
            TextField(
              controller: _dob,
              decoration: const InputDecoration(
                labelText: 'Date of birth (YYYY-MM-DD)',
              ),
            ),
            DropdownButtonFormField<String?>(
              initialValue: _gender,
              decoration: const InputDecoration(labelText: 'Gender'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Not set')),
                DropdownMenuItem(value: 'M', child: Text('M')),
                DropdownMenuItem(value: 'F', child: Text('F')),
              ],
              onChanged: (value) => setState(() => _gender = value),
            ),
            DropdownButtonFormField<String>(
              initialValue: _classId,
              decoration: const InputDecoration(labelText: 'Class *'),
              items: widget.classes
                  .map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _classId = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      if (widget.newRowBatchId == null)
        TextButton(
          onPressed: _saving ? null : _reject,
          child: const Text('Exclude row'),
        ),
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('Approve row'),
      ),
    ],
  );
}
