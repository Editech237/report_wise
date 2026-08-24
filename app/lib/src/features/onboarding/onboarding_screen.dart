import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/auth_widgets.dart';
import '../../data/repositories/academic_repository.dart';
import '../../data/repositories/school_repository.dart';

/// Polished onboarding wizard — modern split-screen, animated steps,
/// keeps green palette but borrows clean layout from reference design.
class OnboardingScreen extends StatefulWidget {
  final SchoolRepository schools;
  final AcademicRepository academics;
  final VoidCallback onDone;

  const OnboardingScreen({
    super.key,
    required this.schools,
    required this.academics,
    required this.onDone,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  int _step = 0;
  bool _busy = false;
  String? _error;

  String? _schoolType;
  String? _subsystem;
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _region = TextEditingController();
  final _division = TextEditingController();
  final _subDivision = TextEditingController();
  final _logoUrl = TextEditingController();
  File? _logoFile;
  final _yearName = TextEditingController(text: '2026/2027');

  late AnimationController _anim;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  static const _steps = ['School Type', 'Subsystem', 'Details', 'Academic Year'];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _name.dispose();
    _code.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    _region.dispose();
    _division.dispose();
    _subDivision.dispose();
    _logoUrl.dispose();
    _yearName.dispose();
    super.dispose();
  }

  bool get _isLastStep => _step == 3;

  bool get _canContinue => switch (_step) {
        0 => _schoolType != null,
        1 => _subsystem != null,
        2 => _name.text.trim().isNotEmpty,
        3 => _yearName.text.trim().isNotEmpty,
        _ => false,
      };

  Future<void> _next() async {
    if (_busy) return;
    setState(() => _error = null);
    if (!_isLastStep) {
      setState(() => _step++);
      _anim.forward(from: 0);
      return;
    }
    setState(() => _busy = true);
    String? createdSchoolId;
    String createdSchoolName = _name.text.trim();
    try {
      // Phase 1: School
      debugPrint('[Onboarding] Phase 1/3: createSchool name=$createdSchoolName type=$_schoolType subsystem=$_subsystem');
      final school = await widget.schools.createSchool(
        name: _name.text,
        schoolType: _schoolType!,
        subsystem: _subsystem!,
        code: _code.text.trim().isEmpty ? null : _code.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        region: _region.text.trim().isEmpty ? null : _region.text.trim(),
        division: _division.text.trim().isEmpty ? null : _division.text.trim(),
        subDivision: _subDivision.text.trim().isEmpty ? null : _subDivision.text.trim(),
        logoUrl: _logoUrl.text.trim().isEmpty ? null : _logoUrl.text.trim(),
        logoFile: _logoFile,
      );
      createdSchoolId = school.id;
      createdSchoolName = school.name;
      debugPrint('[Onboarding] Phase 1 OK: schoolId=$createdSchoolId');

      // Phase 2: Academic year
      final yearName = _yearName.text.trim().isEmpty ? '2026/2027' : _yearName.text.trim();
      debugPrint('[Onboarding] Phase 2/3: createAcademicYear school=$createdSchoolId year=$yearName');
      final year = await widget.academics.createAcademicYear(
        schoolId: school.id,
        name: yearName,
      );
      debugPrint('[Onboarding] Phase 2 OK: yearId=${year.id}');

      // Phase 3: Calendar
      debugPrint('[Onboarding] Phase 3/3: seedDefaultCalendar year=${year.id}');
      await widget.academics.seedDefaultCalendar(year: year);
      debugPrint('[Onboarding] Phase 3 OK');

      if (mounted) widget.onDone();
    } catch (e, st) {
      debugPrint('[Onboarding] FAILED at school=$createdSchoolId error=$e\n$st');
      if (!mounted) return;
      // Distinguish where we failed: school vs year vs calendar
      if (createdSchoolId == null) {
        // School itself failed — RPC or validation
        setState(() => _error = 'Could not create school: $e\n\nSchool row was NOT created. Check Supabase logs and try again.');
      } else {
        // School was created but year/calendar failed — do NOT leave user stuck
        setState(() => _error =
            'School "$createdSchoolName" was created (id $createdSchoolId), but setup failed at next step: $e\n\nYou will be taken to the dashboard where you can create the missing academic year manually (see “No academic year yet” card). Check debug console for phase logs.');
        // Navigate to dashboard after short delay so user can read the message and still recover
        // Dashboard's _EmptyYearView now allows manual creation of the year
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) widget.onDone();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
      _anim.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: isCompact ? _buildCompact(context) : _buildWide(context),
    );
  }

  Widget _buildWide(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Row(
      children: [
        // Left — stepper + branding
        Expanded(
          flex: size.width > 1600 ? 2 : 1,
          child: Container(
            color: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.school_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ReportWise',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            )),
                        Text('School Onboarding',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 11,
                              color: Colors.white70,
                              letterSpacing: 0.8,
                            )),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                const Text(
                  'Set up your\nschool in\nminutes.',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Configure your Cameroonian secondary school. We align with MINESEC structure while keeping your school specific overrides.',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.7),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 40),
                // Stepper
                ...List.generate(_steps.length, (i) => _StepperItem(
                      index: i,
                      label: _steps[i],
                      isActive: i == _step,
                      isDone: i < _step,
                      isLast: i == _steps.length - 1,
                    )),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.white.withOpacity(0.9), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You can update all settings later from Academic Setup.',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.85),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'REPORTWISE ©2026',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 9,
                    color: Colors.white.withOpacity(0.35),
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Right — form
        Expanded(
          flex: 1,
          child: Container(
            color: AppColors.background,
            child: Column(
              children: [
                // Top progress bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(48, 32, 48, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'STEP ${_step + 1} OF ${_steps.length}',
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            '${((_step + 1) / _steps.length * 100).round()}%',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: (_step + 1) / _steps.length,
                          minHeight: 6,
                          backgroundColor: AppColors.border,
                          valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: size.width < 1300 ? 40 : 64, vertical: 32),
                    child: FadeTransition(
                      opacity: _fade,
                      child: SlideTransition(
                        position: _slide,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
                          child: KeyedSubtree(
                            key: ValueKey(_step),
                            child: _buildStepContent(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Bottom bar
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      if (_step > 0)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _back,
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Back'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.onSurface,
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          ),
                        )
                      else
                        const SizedBox(width: 80),
                      const Spacer(),
                      if (_error != null)
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.accentRedLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 11,
                                color: AppColors.accentRed,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _canContinue && !_busy ? _next : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                          shape: const StadiumBorder(),
                        ),
                        child: _busy
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_isLastStep ? 'Create school' : 'Continue'),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_rounded, size: 18),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: AppColors.primary,
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Set up your school',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  )),
              const SizedBox(height: 8),
              Text(
                'Step ${_step + 1} of ${_steps.length} — ${_steps[_step]}',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (_step + 1) / _steps.length,
                  backgroundColor: Colors.white.withOpacity(0.15),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                  minHeight: 5,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: KeyedSubtree(key: ValueKey(_step), child: _buildStepContent()),
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
          child: Row(
            children: [
              if (_step > 0)
                TextButton.icon(onPressed: _back, icon: const Icon(Icons.arrow_back, size: 16), label: const Text('Back'))
              else
                const SizedBox.shrink(),
              const Spacer(),
              ElevatedButton(
                onPressed: _canContinue && !_busy ? _next : null,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: _busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isLastStep ? 'Create school' : 'Continue'),
              ),
            ],
          ),
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            color: AppColors.accentRedLight,
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: const TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.accentRed)),
          ),
      ],
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _SchoolTypeStep(value: _schoolType, onChanged: (v) => setState(() => _schoolType = v));
      case 1:
        return _SubsystemStep(value: _subsystem, onChanged: (v) => setState(() => _subsystem = v));
      case 2:
        return _DetailsStep(
          name: _name,
          code: _code,
          address: _address,
          phone: _phone,
          email: _email,
          region: _region,
          division: _division,
          subDivision: _subDivision,
          logoUrl: _logoUrl,
          logoFile: _logoFile,
          onLogoChanged: (f) => setState(() {
            _logoFile = f;
            if (f != null) _logoUrl.text = f.path;
          }),
        );
      default:
        return _AcademicYearStep(yearName: _yearName);
    }
  }
}

class _StepperItem extends StatelessWidget {
  final int index;
  final String label;
  final bool isActive;
  final bool isDone;
  final bool isLast;
  const _StepperItem({required this.index, required this.label, required this.isActive, required this.isDone, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isActive || isDone ? Colors.white : Colors.white.withOpacity(0.10),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(isActive ? 1 : 0.3), width: isActive ? 2 : 1),
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check_rounded, size: 16, color: AppColors.primary)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isActive ? AppColors.primary : Colors.white.withOpacity(0.7),
                        ),
                      ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 24,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: isDone ? Colors.white.withOpacity(0.9) : Colors.white.withOpacity(0.15),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              color: isActive ? Colors.white : Colors.white.withOpacity(0.65),
            ),
          ),
        ),
      ],
    );
  }
}

class _SchoolTypeStep extends StatelessWidget {
  final String? value;
  final ValueChanged<String> onChanged;
  const _SchoolTypeStep({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('What kind of school are you?',
            style: TextStyle(fontFamily: 'Manrope', fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
        const SizedBox(height: 8),
        Text('Choose the education type that matches your MINESEC authorization.',
            style: TextStyle(fontFamily: 'Lexend', fontSize: 13, color: AppColors.onSurfaceVariant.withOpacity(0.7), height: 1.5)),
        const SizedBox(height: 24),
        _ChoiceCard(
          title: 'General / Grammar',
          subtitle: 'Général — secondary classical, series A, C, D, TI…',
          icon: Icons.menu_book_rounded,
          selected: value == 'GENERAL',
          onTap: () => onChanged('GENERAL'),
        ),
        _ChoiceCard(
          title: 'Technical / Vocational',
          subtitle: 'Technique & Professional — STT, IND, hospitality…',
          icon: Icons.build_rounded,
          selected: value == 'TECHNICAL',
          onTap: () => onChanged('TECHNICAL'),
        ),
        _ChoiceCard(
          title: 'Both',
          subtitle: 'Both general and technical sections on same campus',
          icon: Icons.account_tree_rounded,
          selected: value == 'BOTH',
          onTap: () => onChanged('BOTH'),
        ),
      ],
    );
  }
}

class _SubsystemStep extends StatelessWidget {
  final String? value;
  final ValueChanged<String> onChanged;
  const _SubsystemStep({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Which subsystem?',
            style: TextStyle(fontFamily: 'Manrope', fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
        const SizedBox(height: 8),
        Text('Francophone, Anglophone, or bilingual. You can configure cycles and levels per subsystem later.',
            style: TextStyle(fontFamily: 'Lexend', fontSize: 13, color: AppColors.onSurfaceVariant.withOpacity(0.7), height: 1.5)),
        const SizedBox(height: 24),
        _ChoiceCard(title: 'Francophone', subtitle: 'Système francophone — 6ème → Tle', icon: Icons.translate_rounded, selected: value == 'FRANCOPHONE', onTap: () => onChanged('FRANCOPHONE')),
        _ChoiceCard(title: 'Anglophone', subtitle: 'Anglophone system — Form 1 → Upper Sixth', icon: Icons.language_rounded, selected: value == 'ANGLOPHONE', onTap: () => onChanged('ANGLOPHONE')),
        _ChoiceCard(title: 'Bilingual', subtitle: 'Runs both subsystems in parallel', icon: Icons.sync_alt_rounded, selected: value == 'BILINGUAL', onTap: () => onChanged('BILINGUAL')),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceCard({required this.title, required this.subtitle, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withOpacity(0.06) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: selected ? Colors.white : AppColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontFamily: 'Manrope', fontSize: 14, fontWeight: FontWeight.w700, color: selected ? AppColors.primary : AppColors.onSurface)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.7), height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 2),
                ),
                child: selected ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsStep extends StatefulWidget {
  final TextEditingController name;
  final TextEditingController code;
  final TextEditingController address;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController region;
  final TextEditingController division;
  final TextEditingController subDivision;
  final TextEditingController logoUrl;
  final File? logoFile;
  final ValueChanged<File?>? onLogoChanged;

  const _DetailsStep({
    required this.name,
    required this.code,
    required this.address,
    required this.phone,
    required this.email,
    required this.region,
    required this.division,
    required this.subDivision,
    required this.logoUrl,
    this.logoFile,
    this.onLogoChanged,
  });

  @override
  State<_DetailsStep> createState() => _DetailsStepState();
}

class _DetailsStepState extends State<_DetailsStep> {
  Future<void> _pickLogo() async {
    try {
      File? file;
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        final pickedFile = await FilePicker.pickFile(type: FileType.image);
        if (pickedFile != null && pickedFile.path != null) file = File(pickedFile.path!);
      } else {
        final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
        if (picked != null) file = File(picked.path);
      }
      if (file != null) {
        final size = await file.length();
        if (size > 2 * 1024 * 1024) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image too large. Max 2MB.')));
          return;
        }
        widget.onLogoChanged?.call(file);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('School details',
            style: TextStyle(fontFamily: 'Manrope', fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
        const SizedBox(height: 6),
        Text('This appears on report cards and official documents.',
            style: TextStyle(fontFamily: 'Lexend', fontSize: 13, color: AppColors.onSurfaceVariant.withOpacity(0.7))),
        const SizedBox(height: 20),
        const AuthSectionTitle(icon: Icons.business_rounded, title: 'INSTITUTIONAL IDENTITY'),
        const SizedBox(height: 12),
        AuthTextField(label: 'SCHOOL NAME *', hint: 'e.g. GBHS Yaoundé', icon: Icons.school_outlined, controller: widget.name),
        const SizedBox(height: 16),
        ResponsiveLayoutWrapper(
          isCompact: MediaQuery.of(context).size.width < 600,
          children: [
            AuthTextField(label: 'SCHOOL CODE', hint: 'Optional — MINSEC code', icon: Icons.tag_rounded, controller: widget.code),
            AuthTextField(label: 'REGION', hint: 'e.g. Centre', icon: Icons.map_outlined, controller: widget.region),
          ],
        ),
        const SizedBox(height: 16),
        ResponsiveLayoutWrapper(
          isCompact: MediaQuery.of(context).size.width < 600,
          children: [
            AuthTextField(label: 'DIVISION', hint: 'Optional', icon: Icons.location_city_outlined, controller: widget.division),
            AuthTextField(label: 'SUB-DIVISION', hint: 'Optional', icon: Icons.location_on_outlined, controller: widget.subDivision),
          ],
        ),
        const SizedBox(height: 20),
        const AuthSectionTitle(icon: Icons.contact_mail_outlined, title: 'CONTACT & LOCATION'),
        const SizedBox(height: 12),
        AuthTextField(label: 'EMAIL', hint: 'admin@school.cm', icon: Icons.mail_outline, controller: widget.email, keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 16),
        ResponsiveLayoutWrapper(
          isCompact: MediaQuery.of(context).size.width < 600,
          children: [
            AuthTextField(label: 'PHONE', hint: '+237 6XX XXX XXX', icon: Icons.phone_outlined, controller: widget.phone, keyboardType: TextInputType.phone),
            AuthTextField(label: 'ADDRESS', hint: 'Street / PO Box', icon: Icons.place_outlined, controller: widget.address),
          ],
        ),
        const SizedBox(height: 20),
        const AuthSectionTitle(icon: Icons.image_outlined, title: 'SCHOOL LOGO'),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickLogo,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: widget.logoFile != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(widget.logoFile!, fit: BoxFit.cover)),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: InkWell(
                          onTap: () => widget.onLogoChanged?.call(null),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.cloud_upload_outlined, color: AppColors.primary),
                      ),
                      const SizedBox(height: 8),
                      const Text('Upload logo', style: TextStyle(fontFamily: 'Lexend', fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      Text('512×512 • 2MB', style: TextStyle(fontFamily: 'Lexend', fontSize: 10, color: AppColors.onSurfaceVariant.withOpacity(0.5))),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _AcademicYearStep extends StatelessWidget {
  final TextEditingController yearName;
  const _AcademicYearStep({required this.yearName});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Academic year',
            style: TextStyle(fontFamily: 'Manrope', fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withOpacity(0.12))),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'A default Cameroon calendar will be created: 3 terms × 2 sequences (6 sequences total). You can customise it later.',
                  style: TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.8), height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const AuthSectionTitle(icon: Icons.event_rounded, title: 'ACADEMIC YEAR CONFIGURATION'),
        const SizedBox(height: 12),
        AuthTextField(label: 'ACADEMIC YEAR *', hint: 'e.g. 2026/2027', icon: Icons.calendar_today_outlined, controller: yearName),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('What gets created',
                  style: TextStyle(fontFamily: 'Lexend', fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              _CheckRow(label: '3 Terms (Trimester 1, 2, 3)'),
              _CheckRow(label: '6 Sequences (Seq 1–6)'),
              _CheckRow(label: 'Default assessment calendar'),
              _CheckRow(label: 'Ready for class & subject setup'),
            ],
          ),
        ),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  const _CheckRow({required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: AppColors.accentGreenLight, borderRadius: BorderRadius.circular(99)),
            child: const Icon(Icons.check_rounded, size: 12, color: AppColors.accentGreen),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontFamily: 'Lexend', fontSize: 12.5, color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}
