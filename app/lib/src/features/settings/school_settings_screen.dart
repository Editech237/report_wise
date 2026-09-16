import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/entities.dart';
import '../../data/repositories/school_repository.dart';

class SchoolSettingsScreen extends StatefulWidget {
  final School school;
  final SchoolRepository repository;
  final VoidCallback onSaved;

  const SchoolSettingsScreen({
    super.key,
    required this.school,
    required this.repository,
    required this.onSaved,
  });

  @override
  State<SchoolSettingsScreen> createState() => _SchoolSettingsScreenState();
}

class _SchoolSettingsScreenState extends State<SchoolSettingsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _region;
  late final TextEditingController _principal;
  int? _currentTermNumber;
  File? _logo;
  File? _signature;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.school.name);
    _code = TextEditingController(text: widget.school.code ?? '');
    _address = TextEditingController(text: widget.school.address ?? '');
    _phone = TextEditingController(text: widget.school.phone ?? '');
    _email = TextEditingController(text: widget.school.email ?? '');
    _region = TextEditingController(text: widget.school.region ?? '');
    _principal = TextEditingController(text: widget.school.principalName ?? '');
    _currentTermNumber = widget.school.currentTermNumber;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _code,
      _address,
      _phone,
      _email,
      _region,
      _principal,
    ])
      c.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    final path = result.isEmpty ? null : result.first.path;
    if (path != null) setState(() => _logo = File(path));
  }

  Future<void> _pickSignature() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    final path = result.isEmpty ? null : result.first.path;
    if (path != null) setState(() => _signature = File(path));
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.repository.updateSchool(
        schoolId: widget.school.id,
        name: _name.text,
        code: _code.text,
        address: _address.text,
        phone: _phone.text,
        email: _email.text,
        region: _region.text,
        principalName: _principal.text,
        currentTermNumber: _currentTermNumber,
        principalSignatureFile: _signature,
        logoFile: _logo,
      );
      if (!mounted) return;
      widget.onSaved();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('School settings saved')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save settings: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _logo != null
        ? FileImage(_logo!) as ImageProvider
        : (widget.school.logoUrl == null
              ? null
              : NetworkImage(widget.school.logoUrl!));
    final signature = _signature != null
        ? FileImage(_signature!) as ImageProvider
        : (widget.school.principalSignatureUrl == null
              ? null
              : NetworkImage(widget.school.principalSignatureUrl!));
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SCHOOL SETTINGS',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'School profile',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 34,
                            backgroundColor: AppColors.primary.withOpacity(.1),
                            backgroundImage: image,
                            child: image == null
                                ? const Icon(
                                    Icons.school_rounded,
                                    color: AppColors.primary,
                                    size: 30,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          OutlinedButton.icon(
                            onPressed: _pickLogo,
                            icon: const Icon(Icons.upload_outlined),
                            label: const Text('Change school logo'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 120,
                            height: 52,
                            color: Colors.grey.shade100,
                            child: signature == null
                                ? const Icon(Icons.draw_outlined)
                                : Image(image: signature, fit: BoxFit.contain),
                          ),
                          const SizedBox(width: 16),
                          OutlinedButton.icon(
                            onPressed: _pickSignature,
                            icon: const Icon(Icons.draw_outlined),
                            label: const Text('Add principal signature'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _field(_name, 'School name'),
                      _field(_code, 'School code'),
                      _field(_address, 'Address'),
                      Row(
                        children: [
                          Expanded(child: _field(_phone, 'Phone')),
                          const SizedBox(width: 12),
                          Expanded(child: _field(_email, 'Email')),
                        ],
                      ),
                      _field(_region, 'Region'),
                      _field(_principal, 'Principal name'),
                      DropdownButtonFormField<int?>(
                        value: _currentTermNumber,
                        decoration: const InputDecoration(
                          labelText: 'Current academic term',
                        ),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Not set')),
                          DropdownMenuItem(value: 1, child: Text('Term 1')),
                          DropdownMenuItem(value: 2, child: Text('Term 2')),
                          DropdownMenuItem(value: 3, child: Text('Term 3')),
                        ],
                        onChanged: (value) =>
                            setState(() => _currentTermNumber = value),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text('Save changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
    ),
  );
}
