/// Lightweight domain entities with `fromMap` factories matching the
/// Supabase column names. Numeric columns arrive as num/double (or string in
/// some Postgrest versions), so parsers are defensive.
library;

String _str(Object? v, [String? def]) => v == null ? (def ?? '') : v.toString();

double _dbl(Object? v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

DateTime? _date(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString());

/// Pulls a display name out of a Postgrest embedded relation, e.g.
/// `level:levels(name)` returns `{'name': '3ème'}` under key `level`.
String? _relName(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is Map) return v['name']?.toString();
  if (v is List && v.isNotEmpty && v.first is Map) {
    return (v.first as Map)['name']?.toString();
  }
  return null;
}

class AuthProfile {
  final String id;
  final String fullName;
  final String? email;

  AuthProfile({required this.id, required this.fullName, this.email});

  static const genderValues = ['M', 'F'];

  factory AuthProfile.fromMap(Map<String, dynamic> m) => AuthProfile(
    id: _str(m['id']),
    fullName: _str(m['full_name'], 'Unknown'),
    email: m['email'] as String?,
  );
}

extension RoleNamesX on String {
  bool get isAdminRole =>
      this == 'SUPER_ADMIN' || this == 'ADMIN' || this == 'PRINCIPAL';
  bool get isTeacherRole => this == 'TEACHER';
}

class School {
  final String id;
  final String name;
  final String? code;
  final String schoolType; // GENERAL | TECHNICAL | BOTH
  final String subsystem; // FRANCOPHONE | ANGLOPHONE | BILINGUAL
  final String? logoUrl;
  final String? address;
  final String? phone;
  final String? email;
  final String? region;
  final String? principalName;
  final String? principalSignatureUrl;
  final int? currentTermNumber;

  School({
    required this.id,
    required this.name,
    this.code,
    required this.schoolType,
    required this.subsystem,
    this.logoUrl,
    this.address,
    this.phone,
    this.email,
    this.region,
    this.principalName,
    this.principalSignatureUrl,
    this.currentTermNumber,
  });

  static String? _sanitizeLogoUrl(Object? v) {
    final s = v as String?;
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    // Raw local file path like "/Users/..." was stored before the fix — treat as no logo
    return null;
  }

  factory School.fromMap(Map<String, dynamic> m) => School(
    id: _str(m['id']),
    name: _str(m['name']),
    code: m['code'] as String?,
    schoolType: _str(m['school_type']),
    subsystem: _str(m['subsystem']),
    logoUrl: _sanitizeLogoUrl(m['logo_url']),
    address: m['address'] as String?,
    phone: m['phone'] as String?,
    email: m['email'] as String?,
    region: m['region'] as String?,
    principalName: m['principal_name'] as String?,
    principalSignatureUrl: m['principal_signature_url'] as String?,
    currentTermNumber: (m['current_term_number'] as num?)?.toInt(),
  );
}

class SchoolMembership {
  final String id;
  final String schoolId;
  final String profileId;
  final String role;
  final School? school;

  SchoolMembership({
    required this.id,
    required this.schoolId,
    required this.profileId,
    required this.role,
    this.school,
  });

  factory SchoolMembership.fromMap(
    Map<String, dynamic> m, {
    Map<String, dynamic>? joinedSchool,
  }) => SchoolMembership(
    id: _str(m['id']),
    schoolId: _str(m['school_id']),
    profileId: _str(m['profile_id']),
    role: _str(m['role']),
    school: joinedSchool != null ? School.fromMap(joinedSchool) : null,
  );
}

class AcademicYear {
  final String id;
  final String schoolId;
  final String name;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final bool isCurrent;
  final String status;

  AcademicYear({
    required this.id,
    required this.schoolId,
    required this.name,
    this.startsOn,
    this.endsOn,
    required this.isCurrent,
    this.status = 'ACTIVE',
  });

  factory AcademicYear.fromMap(Map<String, dynamic> m) => AcademicYear(
    id: _str(m['id']),
    schoolId: _str(m['school_id']),
    name: _str(m['name']),
    startsOn: _date(m['starts_on']),
    endsOn: _date(m['ends_on']),
    isCurrent: m['is_current'] == true,
    status: _str(m['status'], 'ACTIVE'),
  );
}

class Term {
  final String id;
  final String schoolId;
  final String academicYearId;
  final int number;
  final String name;
  final DateTime? startsOn;
  final DateTime? endsOn;

  Term({
    required this.id,
    required this.schoolId,
    required this.academicYearId,
    required this.number,
    required this.name,
    this.startsOn,
    this.endsOn,
  });

  factory Term.fromMap(Map<String, dynamic> m) => Term(
    id: _str(m['id']),
    schoolId: _str(m['school_id']),
    academicYearId: _str(m['academic_year_id']),
    number: (m['number'] as num).toInt(),
    name: _str(m['name']),
    startsOn: _date(m['starts_on']),
    endsOn: _date(m['ends_on']),
  );
}

class Sequence {
  final String id;
  final String schoolId;
  final String termId;
  final int number;
  final String name;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final String status;

  Sequence({
    required this.id,
    required this.schoolId,
    required this.termId,
    required this.number,
    required this.name,
    this.startsOn,
    this.endsOn,
    this.status = 'OPEN',
  });

  factory Sequence.fromMap(Map<String, dynamic> m) => Sequence(
    id: _str(m['id']),
    schoolId: _str(m['school_id']),
    termId: _str(m['term_id']),
    number: (m['number'] as num).toInt(),
    name: _str(m['name']),
    startsOn: _date(m['starts_on']),
    endsOn: _date(m['ends_on']),
    status: _str(m['status'], 'OPEN'),
  );
}

class EducationType {
  final String id;
  final String code;
  final String name;
  final String? nameFr;

  EducationType({
    required this.id,
    required this.code,
    required this.name,
    this.nameFr,
  });

  factory EducationType.fromMap(Map<String, dynamic> m) => EducationType(
    id: _str(m['id']),
    code: _str(m['code']),
    name: _str(m['name']),
    nameFr: m['name_fr'] as String?,
  );
}

class Cycle {
  final String id;
  final String? schoolId;
  final String educationTypeId;
  final String? subsystem;
  final String code;
  final String name;

  Cycle({
    required this.id,
    this.schoolId,
    required this.educationTypeId,
    this.subsystem,
    required this.code,
    required this.name,
  });

  factory Cycle.fromMap(Map<String, dynamic> m) => Cycle(
    id: _str(m['id']),
    schoolId: m['school_id'] as String?,
    educationTypeId: _str(m['education_type_id']),
    subsystem: m['subsystem'] as String?,
    code: _str(m['code']),
    name: _str(m['name']),
  );
}

class Level {
  final String id;
  final String? schoolId;
  final String cycleId;
  final String? subsystem;
  final String code;
  final String name;

  Level({
    required this.id,
    this.schoolId,
    required this.cycleId,
    this.subsystem,
    required this.code,
    required this.name,
  });

  factory Level.fromMap(Map<String, dynamic> m) => Level(
    id: _str(m['id']),
    schoolId: m['school_id'] as String?,
    cycleId: _str(m['cycle_id']),
    subsystem: m['subsystem'] as String?,
    code: _str(m['code']),
    name: _str(m['name']),
  );
}

class Series {
  final String id;
  final String? schoolId;
  final String educationTypeId;
  final String? subsystem;
  final String code;
  final String name;

  Series({
    required this.id,
    this.schoolId,
    required this.educationTypeId,
    this.subsystem,
    required this.code,
    required this.name,
  });

  factory Series.fromMap(Map<String, dynamic> m) => Series(
    id: _str(m['id']),
    schoolId: m['school_id'] as String?,
    educationTypeId: _str(m['education_type_id']),
    subsystem: m['subsystem'] as String?,
    code: _str(m['code']),
    name: _str(m['name']),
  );
}

class Specialty {
  final String id;
  final String? schoolId;
  final String? seriesId;
  final String code;
  final String name;

  Specialty({
    required this.id,
    this.schoolId,
    this.seriesId,
    required this.code,
    required this.name,
  });

  factory Specialty.fromMap(Map<String, dynamic> m) => Specialty(
    id: _str(m['id']),
    schoolId: m['school_id'] as String?,
    seriesId: m['series_id'] as String?,
    code: _str(m['code']),
    name: _str(m['name']),
  );
}

class Subject {
  final String id;
  final String? schoolId;
  final String code;
  final String name;
  final String? nameFr;
  final String? subjectType;

  Subject({
    required this.id,
    this.schoolId,
    required this.code,
    required this.name,
    this.nameFr,
    this.subjectType,
  });

  factory Subject.fromMap(Map<String, dynamic> m) => Subject(
    id: _str(m['id']),
    schoolId: m['school_id'] as String?,
    code: _str(m['code']),
    name: _str(m['name']),
    nameFr: m['name_fr'] as String?,
    subjectType: m['subject_type'] as String?,
  );
}

/// A concrete class for an academic year. The `*Name` fields are populated
/// from embedded relations (`level:levels(name)`, ...) when the row is fetched
/// with those aliases; they are null when the row comes from a bare select.
class SchoolClass {
  final String id;
  final String schoolId;
  final String academicYearId;
  final String subsystem;
  final String educationTypeId;
  final String cycleId;
  final String levelId;
  final String? seriesId;
  final String? specialtyId;
  final String name;
  final String? room;
  final bool isActive;
  final String? classTeacherId;
  final String? educationTypeName;
  final String? cycleName;
  final String? levelName;
  final String? seriesName;
  final String? specialtyName;

  SchoolClass({
    required this.id,
    required this.schoolId,
    required this.academicYearId,
    required this.subsystem,
    required this.educationTypeId,
    required this.cycleId,
    required this.levelId,
    this.seriesId,
    this.specialtyId,
    required this.name,
    this.room,
    this.isActive = true,
    this.classTeacherId,
    this.educationTypeName,
    this.cycleName,
    this.levelName,
    this.seriesName,
    this.specialtyName,
  });

  factory SchoolClass.fromMap(Map<String, dynamic> m) => SchoolClass(
    id: _str(m['id']),
    schoolId: _str(m['school_id']),
    academicYearId: _str(m['academic_year_id']),
    subsystem: _str(m['subsystem']),
    educationTypeId: _str(m['education_type_id']),
    cycleId: _str(m['cycle_id']),
    levelId: _str(m['level_id']),
    seriesId: m['series_id'] as String?,
    specialtyId: m['specialty_id'] as String?,
    name: _str(m['name']),
    room: m['room'] as String?,
    isActive: m['is_active'] != false,
    classTeacherId: m['class_teacher_id'] as String?,
    educationTypeName: _relName(m, 'education_type'),
    cycleName: _relName(m, 'cycle'),
    levelName: _relName(m, 'level'),
    seriesName: _relName(m, 'series'),
    specialtyName: _relName(m, 'specialty'),
  );
}

class StudentEnrollment {
  final String id;
  final String studentId;
  final String classId;
  final String? status;

  StudentEnrollment({
    required this.id,
    required this.studentId,
    required this.classId,
    this.status,
  });

  factory StudentEnrollment.fromMap(Map<String, dynamic> m) =>
      StudentEnrollment(
        id: _str(m['id']),
        studentId: _str(m['student_id']),
        classId: _str(m['class_id']),
        status: m['status'] as String?,
      );
}

class TeacherAssignment {
  final String id;
  final String teacherMembershipId;
  final String classId;
  final String subjectId;
  final String? className;
  final String? subjectName;
  final bool isActive;

  TeacherAssignment({
    required this.id,
    required this.teacherMembershipId,
    required this.classId,
    required this.subjectId,
    this.className,
    this.subjectName,
    this.isActive = true,
  });

  factory TeacherAssignment.fromMap(Map<String, dynamic> m) =>
      TeacherAssignment(
        id: _str(m['id']),
        teacherMembershipId: _str(m['teacher_membership_id']),
        classId: _str(m['class_id']),
        subjectId: _str(m['subject_id']),
        className: _relName(m, 'class'),
        subjectName: _relName(m, 'subject'),
        isActive: m['is_active'] != false,
      );
}

class Student {
  final String id;
  final String schoolId;
  final String fullName;
  final String? matricule;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? placeOfBirth;
  final String? guardianName;
  final String? guardianPhone;
  final bool repeater;

  Student({
    required this.id,
    required this.schoolId,
    required this.fullName,
    this.matricule,
    this.dateOfBirth,
    this.gender,
    this.placeOfBirth,
    this.guardianName,
    this.guardianPhone,
    this.repeater = false,
  });

  factory Student.fromMap(Map<String, dynamic> m) => Student(
    id: _str(m['id']),
    schoolId: _str(m['school_id']),
    fullName: _str(m['full_name']),
    matricule: m['matricule'] as String?,
    dateOfBirth: _date(m['date_of_birth']),
    gender: m['gender'] as String?,
    placeOfBirth: m['place_of_birth'] as String?,
    guardianName: m['guardian_name'] as String?,
    guardianPhone: m['guardian_phone'] as String?,
    repeater: m['repeater'] == true,
  );
}

class MarkBook {
  final String id;
  final String teacherAssignmentId;
  final String classId;
  final String subjectId;
  final String sequenceId;
  final String status;

  MarkBook({
    required this.id,
    required this.teacherAssignmentId,
    required this.classId,
    required this.subjectId,
    required this.sequenceId,
    this.status = 'DRAFT',
  });

  factory MarkBook.fromMap(Map<String, dynamic> m) => MarkBook(
    id: _str(m['id']),
    teacherAssignmentId: _str(m['teacher_assignment_id']),
    classId: _str(m['class_id']),
    subjectId: _str(m['subject_id']),
    sequenceId: _str(m['sequence_id']),
    status: _str(m['status'], 'DRAFT'),
  );
}

class AssessmentSchemeComponent {
  final String id;
  final String name;
  final String? nameFr;
  final String componentType;
  final double weight; // percentage (0-100)
  final double maxScore;
  final int sortOrder;

  AssessmentSchemeComponent({
    required this.id,
    required this.name,
    this.nameFr,
    this.componentType = 'EXAM',
    required this.weight,
    this.maxScore = 20,
    this.sortOrder = 0,
  });

  factory AssessmentSchemeComponent.fromMap(Map<String, dynamic> m) =>
      AssessmentSchemeComponent(
        id: _str(m['id']),
        name: _str(m['name']),
        nameFr: m['name_fr'] as String?,
        componentType: _str(m['component_type'], 'EXAM'),
        weight: _dbl(m['weight']),
        maxScore: _dbl(m['max_score']) == 0 ? 20 : _dbl(m['max_score']),
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class AssessmentScheme {
  final String id;
  final String? schoolId;
  final String? academicYearId;
  final String? educationTypeId;
  final String? levelId;
  final String? seriesId;
  final String name;
  final String source;
  final bool isDefault;
  final List<AssessmentSchemeComponent> components;

  AssessmentScheme({
    required this.id,
    this.schoolId,
    this.academicYearId,
    this.educationTypeId,
    this.levelId,
    this.seriesId,
    required this.name,
    this.source = 'NATIONAL_DEFAULT',
    this.isDefault = false,
    this.components = const [],
  });

  double get totalWeight => components.fold(0.0, (sum, c) => sum + c.weight);

  factory AssessmentScheme.fromMap(
    Map<String, dynamic> m, {
    List<Map<String, dynamic>> componentRows = const [],
  }) => AssessmentScheme(
    id: _str(m['id']),
    schoolId: m['school_id'] as String?,
    academicYearId: m['academic_year_id'] as String?,
    educationTypeId: m['education_type_id'] as String?,
    levelId: m['level_id'] as String?,
    seriesId: m['series_id'] as String?,
    name: _str(m['name']),
    source: _str(m['source'], 'NATIONAL_DEFAULT'),
    isDefault: m['is_default'] == true,
    components: componentRows.map(AssessmentSchemeComponent.fromMap).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
  );
}

class AcademicRule {
  final String id;
  final String? schoolId;
  final String? academicYearId;
  final String ruleKey;
  final Map<String, dynamic> ruleValue;
  final String source;
  final String? description;

  AcademicRule({
    required this.id,
    this.schoolId,
    this.academicYearId,
    required this.ruleKey,
    required this.ruleValue,
    this.source = 'NATIONAL_DEFAULT',
    this.description,
  });

  factory AcademicRule.fromMap(Map<String, dynamic> m) => AcademicRule(
    id: _str(m['id']),
    schoolId: m['school_id'] as String?,
    academicYearId: m['academic_year_id'] as String?,
    ruleKey: _str(m['rule_key']),
    ruleValue: m['rule_value'] is Map
        ? Map<String, dynamic>.from(m['rule_value'] as Map)
        : const <String, dynamic>{},
    source: _str(m['source'], 'NATIONAL_DEFAULT'),
    description: m['description'] as String?,
  );
}

/// A school staff member, returned by the list_school_members RPC.
class SchoolMember {
  final String membershipId;
  final String profileId;
  final String role;
  final String? staffId;
  final bool isActive;
  final String fullName;
  final String? email;
  final String? avatarUrl;

  SchoolMember({
    required this.membershipId,
    required this.profileId,
    required this.role,
    this.staffId,
    this.isActive = true,
    this.fullName = '',
    this.email,
    this.avatarUrl,
  });

  factory SchoolMember.fromMap(Map<String, dynamic> m) => SchoolMember(
    membershipId: _str(m['membership_id']),
    profileId: _str(m['profile_id']),
    role: _str(m['role']),
    staffId: m['staff_id'] as String?,
    isActive: m['is_active'] != false,
    fullName: _str(m['full_name'], 'Unnamed staff'),
    email: m['email'] as String?,
    avatarUrl: m['avatar_url'] as String?,
  );
}

/// A teacher → class → subject assignment, returned by the
/// list_teacher_assignments RPC (spec section 37).
class TeacherAssignmentDetail {
  final String id;
  final String teacherMembershipId;
  final String teacherName;
  final String classId;
  final String className;
  final String subjectId;
  final String subjectCode;
  final String subjectName;
  final String? specialtyId;
  final String? specialtyName;
  final String teachingRole;

  TeacherAssignmentDetail({
    required this.id,
    required this.teacherMembershipId,
    required this.teacherName,
    required this.classId,
    required this.className,
    required this.subjectId,
    required this.subjectCode,
    required this.subjectName,
    this.specialtyId,
    this.specialtyName,
    this.teachingRole = 'SUBJECT_TEACHER',
  });

  factory TeacherAssignmentDetail.fromMap(Map<String, dynamic> m) =>
      TeacherAssignmentDetail(
        id: _str(m['id']),
        teacherMembershipId: _str(m['teacher_membership_id']),
        teacherName: _str(m['teacher_name'], 'Unknown teacher'),
        classId: _str(m['class_id']),
        className: _str(m['class_name']),
        subjectId: _str(m['subject_id']),
        subjectCode: _str(m['subject_code']),
        subjectName: _str(m['subject_name']),
        specialtyId: m['specialty_id'] as String?,
        specialtyName: m['specialty_name'] as String?,
        teachingRole: _str(m['teaching_role'], 'SUBJECT_TEACHER'),
      );
}

/// A student enrolled in a class (mark entry roster), from students_in_class.
class StudentInClass {
  final String enrollmentId;
  final String studentId;
  final String fullName;
  final String? matricule;

  StudentInClass({
    required this.enrollmentId,
    required this.studentId,
    required this.fullName,
    this.matricule,
  });

  factory StudentInClass.fromMap(Map<String, dynamic> m) => StudentInClass(
    enrollmentId: _str(m['enrollment_id']),
    studentId: _str(m['student_id']),
    fullName: _str(m['full_name'], 'Unnamed student'),
    matricule: m['matricule'] as String?,
  );
}

/// One mark entry cell, from list_mark_entries.
class MarkEntry {
  final String id;
  final String studentEnrollmentId;
  final String studentName;
  final String schemeComponentId;
  final double? score;
  final String absenceStatus;
  final String? teacherNote;

  MarkEntry({
    required this.id,
    required this.studentEnrollmentId,
    required this.studentName,
    required this.schemeComponentId,
    this.score,
    this.absenceStatus = 'ENTERED',
    this.teacherNote,
  });

  factory MarkEntry.fromMap(Map<String, dynamic> m) => MarkEntry(
    id: _str(m['id']),
    studentEnrollmentId: _str(m['student_enrollment_id']),
    studentName: _str(m['student_name']),
    schemeComponentId: _str(m['scheme_component_id']),
    score: m['score'] == null ? null : _dbl(m['score']),
    absenceStatus: _str(m['absence_status'], 'ENTERED'),
    teacherNote: m['teacher_note'] as String?,
  );
}

/// An audited mark book event, from list_mark_book_events.
class MarkBookEvent {
  final String action;
  final String? previousStatus;
  final String? newStatus;
  final String? reason;
  final String? actorName;
  final DateTime createdAt;

  MarkBookEvent({
    required this.action,
    this.previousStatus,
    this.newStatus,
    this.reason,
    this.actorName,
    required this.createdAt,
  });

  factory MarkBookEvent.fromMap(Map<String, dynamic> m) => MarkBookEvent(
    action: _str(m['action']),
    previousStatus: m['previous_status'] as String?,
    newStatus: m['new_status'] as String?,
    reason: m['reason'] as String?,
    actorName: m['actor_name'] as String?,
    createdAt: _date(m['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// A stored per-subject result for a student within a period.
class SubjectResultItem {
  final String subjectId;
  final String? subjectName;
  final double? subjectAverage;
  final double? coefficient;
  final double? weightedPoints;
  final int marksCount;
  final int? rankInSubject;

  SubjectResultItem({
    required this.subjectId,
    this.subjectName,
    this.subjectAverage,
    this.coefficient,
    this.weightedPoints,
    this.marksCount = 0,
    this.rankInSubject,
  });

  factory SubjectResultItem.fromMap(Map<String, dynamic> m) {
    final subject = m['subject'];
    return SubjectResultItem(
      subjectId: _str(m['subject_id']),
      subjectName: subject is Map ? subject['name']?.toString() : null,
      subjectAverage: m['subject_average'] == null
          ? null
          : _dbl(m['subject_average']),
      coefficient: m['coefficient'] == null ? null : _dbl(m['coefficient']),
      weightedPoints: m['weighted_points'] == null
          ? null
          : _dbl(m['weighted_points']),
      marksCount: (m['marks_count'] as num?)?.toInt() ?? 0,
      rankInSubject: (m['rank_in_subject'] as num?)?.toInt(),
    );
  }
}

/// A stored period result for one student (from period_results, embedded).
class PeriodResult {
  final String id;
  final String studentEnrollmentId;
  final String studentName;
  final String? matricule;
  final double? generalAverage;
  final double? totalWeightedPoints;
  final double? totalCoefficients;
  final double? classAverage;
  final int? rank;
  final String status;
  final List<SubjectResultItem> subjects;

  PeriodResult({
    required this.id,
    required this.studentEnrollmentId,
    required this.studentName,
    this.matricule,
    this.generalAverage,
    this.totalWeightedPoints,
    this.totalCoefficients,
    this.classAverage,
    this.rank,
    this.status = 'DRAFT',
    this.subjects = const [],
  });

  factory PeriodResult.fromMap(Map<String, dynamic> m) {
    final enrollment = m['enrollment'];
    final student = enrollment is Map ? enrollment['student'] : null;
    final subjectRows =
        (m['subject_results'] as List?)?.cast<Map>() ?? const [];
    return PeriodResult(
      id: _str(m['id']),
      studentEnrollmentId: _str(m['student_enrollment_id']),
      studentName: student is Map
          ? _str(student['full_name'], 'Unnamed student')
          : 'Unnamed student',
      matricule: student is Map ? student['matricule'] as String? : null,
      generalAverage: m['general_average'] == null
          ? null
          : _dbl(m['general_average']),
      totalWeightedPoints: m['total_weighted_points'] == null
          ? null
          : _dbl(m['total_weighted_points']),
      totalCoefficients: m['total_coefficients'] == null
          ? null
          : _dbl(m['total_coefficients']),
      classAverage: m['class_average'] == null
          ? null
          : _dbl(m['class_average']),
      rank: (m['rank'] as num?)?.toInt(),
      status: _str(m['status'], 'DRAFT'),
      subjects: subjectRows
          .map((r) => SubjectResultItem.fromMap(r as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A computed result set (class + period) for the results-history strip.
class PeriodResultSetSummary {
  final String classId;
  final String className;
  final String periodType;
  final String? periodId;
  final String periodLabel;
  final int studentCount;
  final String status;

  PeriodResultSetSummary({
    required this.classId,
    required this.className,
    required this.periodType,
    this.periodId,
    required this.periodLabel,
    this.studentCount = 0,
    this.status = 'DRAFT',
  });

  bool get isFinal => status == 'FINAL';

  factory PeriodResultSetSummary.fromMap(Map<String, dynamic> m) =>
      PeriodResultSetSummary(
        classId: _str(m['class_id']),
        className: _str(m['class_name']),
        periodType: _str(m['period_type']),
        periodId: m['period_id']?.toString(),
        periodLabel: _str(m['period_label']),
        studentCount: (m['student_count'] as num?)?.toInt() ?? 0,
        status: _str(m['status'], 'DRAFT'),
      );
}

/// A saved mark book summary for the mark-entry history strip.
class MarkBookSummary {
  final String id;
  final String teacherAssignmentId;
  final String teacherName;
  final String className;
  final String subjectName;
  final String sequenceId;
  final String sequenceName;
  final String sequenceStatus;
  final String status;
  final int enteredCount;
  final int studentCount;
  final DateTime createdAt;

  MarkBookSummary({
    required this.id,
    required this.teacherAssignmentId,
    required this.teacherName,
    required this.className,
    required this.subjectName,
    required this.sequenceId,
    required this.sequenceName,
    this.sequenceStatus = 'OPEN',
    this.status = 'DRAFT',
    this.enteredCount = 0,
    this.studentCount = 0,
    required this.createdAt,
  });

  double get progress =>
      studentCount == 0 ? 0 : (enteredCount / studentCount).clamp(0, 1);

  factory MarkBookSummary.fromMap(Map<String, dynamic> m) => MarkBookSummary(
    id: _str(m['id']),
    teacherAssignmentId: _str(m['teacher_assignment_id']),
    teacherName: _str(m['teacher_name'], ''),
    className: _str(m['class_name']),
    subjectName: _str(m['subject_name']),
    sequenceId: _str(m['sequence_id']),
    sequenceName: _str(m['sequence_name']),
    sequenceStatus: _str(m['sequence_status'], 'OPEN'),
    status: _str(m['status'], 'DRAFT'),
    enteredCount: (m['entered_count'] as num?)?.toInt() ?? 0,
    studentCount: (m['student_count'] as num?)?.toInt() ?? 0,
    createdAt: _date(m['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}

double coeffFromMap(Object? v) => _dbl(v);
String idFromMap(Map<String, dynamic> m, String key) => _str(m[key]);
