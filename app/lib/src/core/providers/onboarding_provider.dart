import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'repository_providers.dart';

class OnboardingState {
  final int step;
  final bool busy;
  final String? error;
  final String? schoolType;
  final String? subsystem;
  final String name;
  final String code;
  final String address;
  final String phone;
  final String email;
  final String region;
  final String division;
  final String subDivision;
  final String logoUrl;
  final File? logoFile;
  final String yearName;

  const OnboardingState({
    this.step = 0,
    this.busy = false,
    this.error,
    this.schoolType,
    this.subsystem,
    this.name = '',
    this.code = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.region = '',
    this.division = '',
    this.subDivision = '',
    this.logoUrl = '',
    this.logoFile,
    this.yearName = '2026/2027',
  });

  OnboardingState copyWith({
    int? step,
    bool? busy,
    String? error,
    bool clearError = false,
    String? schoolType,
    String? subsystem,
    String? name,
    String? code,
    String? address,
    String? phone,
    String? email,
    String? region,
    String? division,
    String? subDivision,
    String? logoUrl,
    File? logoFile,
    bool clearLogoFile = false,
    String? yearName,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      busy: busy ?? this.busy,
      error: clearError ? null : error ?? this.error,
      schoolType: schoolType ?? this.schoolType,
      subsystem: subsystem ?? this.subsystem,
      name: name ?? this.name,
      code: code ?? this.code,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      region: region ?? this.region,
      division: division ?? this.division,
      subDivision: subDivision ?? this.subDivision,
      logoUrl: logoUrl ?? this.logoUrl,
      logoFile: clearLogoFile ? null : logoFile ?? this.logoFile,
      yearName: yearName ?? this.yearName,
    );
  }

  bool get canContinue => switch (step) {
        0 => schoolType != null,
        1 => subsystem != null,
        2 => name.trim().isNotEmpty,
        3 => yearName.trim().isNotEmpty,
        _ => false,
      };
  bool get isLastStep => step == 3;
}

class OnboardingNotifier extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  void setStep(int s) => state = state.copyWith(step: s, clearError: true);
  void next() {
    if (state.busy) return;
    if (!state.isLastStep) state = state.copyWith(step: state.step + 1, clearError: true);
  }
  void back() {
    if (state.step > 0) state = state.copyWith(step: state.step - 1, clearError: true);
  }
  void setSchoolType(String v) => state = state.copyWith(schoolType: v, clearError: true);
  void setSubsystem(String v) => state = state.copyWith(subsystem: v, clearError: true);
  void updateField({String? name, String? code, String? address, String? phone, String? email, String? region, String? division, String? subDivision, String? logoUrl, String? yearName}) {
    state = state.copyWith(name: name, code: code, address: address, phone: phone, email: email, region: region, division: division, subDivision: subDivision, logoUrl: logoUrl, yearName: yearName, clearError: true);
  }
  void setLogoFile(File? f) => state = state.copyWith(logoFile: f, clearLogoFile: f == null);

  Future<void> pickLogo(BuildContext context) async {
    try {
      File? file;
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        final picked = await FilePicker.pickFile(type: FileType.image);
        if (picked != null && picked.path != null) file = File(picked.path!);
      } else {
        final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
        if (picked != null) file = File(picked.path);
      }
      if (file != null) {
        final size = await file.length();
        if (size > 2 * 1024 * 1024) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image too large. Max 2MB.')));
          return;
        }
        setLogoFile(file);
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  Future<bool> submit(WidgetRef ref) async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearError: true);
    String? createdSchoolId;
    String createdSchoolName = state.name.trim();
    final schools = ref.read(schoolRepositoryProvider);
    final academics = ref.read(academicRepositoryProvider);
    if (schools == null || academics == null) {
      state = state.copyWith(busy: false, error: 'Repositories not ready');
      return false;
    }
    try {
      debugPrint('[Onboarding] Phase 1/3 createSchool $createdSchoolName');
      final school = await schools.createSchool(
        name: state.name,
        schoolType: state.schoolType!,
        subsystem: state.subsystem!,
        code: state.code.trim().isEmpty ? null : state.code.trim(),
        address: state.address.trim().isEmpty ? null : state.address.trim(),
        phone: state.phone.trim().isEmpty ? null : state.phone.trim(),
        email: state.email.trim().isEmpty ? null : state.email.trim(),
        region: state.region.trim().isEmpty ? null : state.region.trim(),
        division: state.division.trim().isEmpty ? null : state.division.trim(),
        subDivision: state.subDivision.trim().isEmpty ? null : state.subDivision.trim(),
        logoUrl: state.logoUrl.trim().isEmpty ? null : state.logoUrl.trim(),
        logoFile: state.logoFile,
      );
      createdSchoolId = school.id;
      createdSchoolName = school.name;
      final yearName = state.yearName.trim().isEmpty ? '2026/2027' : state.yearName.trim();
      debugPrint('[Onboarding] Phase 2/3 createAcademicYear $yearName');
      final year = await academics.createAcademicYear(schoolId: school.id, name: yearName);
      debugPrint('[Onboarding] Phase 3/3 seedDefaultCalendar');
      await academics.seedDefaultCalendar(year: year);
      state = state.copyWith(busy: false);
      return true;
    } catch (e, st) {
      debugPrint('[Onboarding] FAILED school=$createdSchoolId $e\n$st');
      if (createdSchoolId == null) {
        state = state.copyWith(busy: false, error: 'Could not create school: $e');
      } else {
        state = state.copyWith(busy: false, error: 'School "$createdSchoolName" was created (id $createdSchoolId), but setup failed: $e — you will be taken to dashboard where you can create the missing year manually.');
        // Signal success after delay so SchoolsGate can refresh and show empty-year card
        await Future.delayed(const Duration(seconds: 2));
        return true;
      }
      return false;
    }
  }
}

final onboardingProvider = NotifierProvider<OnboardingNotifier, OnboardingState>(OnboardingNotifier.new);
