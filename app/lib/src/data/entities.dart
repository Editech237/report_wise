/// Lightweight domain entities with `fromMap` factories matching the
/// Supabase column names. Numeric columns arrive as num/double (or string in
/// some Postgrest versions), so parsers are defensive.
library;

String _str(Object? v, [String? def]) =>
    v == null ? (def ?? '') : v.toString();

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
  }) =>
      SchoolMembership(
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

  EducationType({required this.id, required this.code, required this.name, this.nameFr});

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

  factory StudentEnrollment.fromMap(Map<String, dynamic> m) => StudentEnrollment(
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

  factory TeacherAssignment.fromMap(Map<String, dynamic> m) => TeacherAssignment(
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

  Student({
    required this.id,
    required this.schoolId,
    required this.fullName,
    this.matricule,
    this.dateOfBirth,
    this.gender,
  });

  factory Student.fromMap(Map<String, dynamic> m) => Student(
        id: _str(m['id']),
        schoolId: _str(m['school_id']),
        fullName: _str(m['full_name']),
        matricule: m['matricule'] as String?,
        dateOfBirth: _date(m['date_of_birth']),
        gender: m['gender'] as String?,
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

double coeffFromMap(Object? v) => _dbl(v);
String idFromMap(Map<String, dynamic> m, String key) => _str(m[key]);