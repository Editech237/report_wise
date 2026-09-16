import 'package:flutter_test/flutter_test.dart';
import 'package:report_wise/src/data/entities.dart';

void main() {
  group('AssessmentScheme.fromMap (academic records)', () {
    test('parses scheme with nested components and totals weight', () {
      final scheme = AssessmentScheme.fromMap(
        {
          'id': 'sch1',
          'school_id': null,
          'name': 'Classic Cameroon',
          'source': 'NATIONAL_DEFAULT',
          'is_default': true,
        },
        componentRows: [
          {
            'id': 'c1',
            'name': 'Interrogation',
            'component_type': 'CLASS_TEST',
            'weight': 20,
            'max_score': 20,
            'sort_order': 1,
          },
          {
            'id': 'c2',
            'name': 'Examen',
            'component_type': 'EXAM',
            'weight': 80,
            'max_score': 20,
            'sort_order': 2,
          },
        ],
      );

      expect(scheme.id, 'sch1');
      expect(scheme.schoolId, isNull);
      expect(scheme.source, 'NATIONAL_DEFAULT');
      expect(scheme.isDefault, isTrue);
      expect(scheme.components.length, 2);
      expect(scheme.components.first.weight, 20);
      expect(scheme.totalWeight, closeTo(100, 0.01));
    });

    test('orders components by sort_order and defaults max_score', () {
      final scheme = AssessmentScheme.fromMap(
        {'id': 's', 'name': 'n', 'source': 'SCHOOL_CONFIGURATION'},
        componentRows: [
          {'id': 'b', 'name': 'b', 'weight': 50, 'sort_order': 2},
          {'id': 'a', 'name': 'a', 'weight': 50, 'sort_order': 1},
        ],
      );
      expect(scheme.components.map((c) => c.id).toList(), ['a', 'b']);
      expect(scheme.components.first.maxScore, 20);
    });
  });

  group('AcademicRule.fromMap', () {
    test('parses jsonb rule value into a map', () {
      final rule = AcademicRule.fromMap({
        'id': 'r1',
        'rule_key': 'RANKING_METHOD',
        'rule_value': {'value': 'COMPETITION'},
        'source': 'NATIONAL_DEFAULT',
        'description': 'Standard competition ranking',
      });
      expect(rule.ruleKey, 'RANKING_METHOD');
      expect(rule.ruleValue['value'], 'COMPETITION');
      expect(rule.source, 'NATIONAL_DEFAULT');
      expect(rule.schoolId, isNull);
    });

    test('survives missing rule_value', () {
      final rule = AcademicRule.fromMap({'id': 'r2', 'rule_key': 'X'});
      expect(rule.ruleValue, isEmpty);
    });
  });

  group('SchoolMember.fromMap (teachers)', () {
    test('parses list_school_members row', () {
      final m = SchoolMember.fromMap({
        'membership_id': 'm1',
        'profile_id': 'p1',
        'role': 'TEACHER',
        'staff_id': 'T-042',
        'is_active': true,
        'full_name': 'Mme Ngo Bassa',
        'email': 'teacher@school.cm',
      });
      expect(m.membershipId, 'm1');
      expect(m.role, 'TEACHER');
      expect(m.staffId, 'T-042');
      expect(m.fullName, 'Mme Ngo Bassa');
      expect(m.email, 'teacher@school.cm');
      expect(m.role.isTeacherRole, isTrue);
      expect(m.role.isAdminRole, isFalse);
    });
  });

  group('TeacherAssignmentDetail.fromMap (teachers)', () {
    test('parses list_teacher_assignments row', () {
      final a = TeacherAssignmentDetail.fromMap({
        'id': 'a1',
        'teacher_membership_id': 'm1',
        'teacher_name': 'M. Ekollo',
        'class_id': 'c1',
        'class_name': '3ème A',
        'subject_id': 's1',
        'subject_code': 'MATHS',
        'subject_name': 'Mathematics',
        'specialty_id': 'sp1',
        'specialty_name': 'Comptabilité et Gestion',
        'teaching_role': 'SUBJECT_TEACHER',
      });
      expect(a.teacherName, 'M. Ekollo');
      expect(a.className, '3ème A');
      expect(a.subjectCode, 'MATHS');
      expect(a.specialtyName, 'Comptabilité et Gestion');
      expect(a.teachingRole, 'SUBJECT_TEACHER');
    });

    test('handles null specialty (grammar school)', () {
      final a = TeacherAssignmentDetail.fromMap({
        'id': 'a2',
        'teacher_membership_id': 'm2',
        'teacher_name': 'Mme Abena',
        'class_id': 'c2',
        'class_name': 'Form 4B',
        'subject_id': 's2',
        'subject_code': 'ENG',
        'subject_name': 'English',
        'specialty_id': null,
        'specialty_name': null,
        'teaching_role': 'CLASS_TEACHER',
      });
      expect(a.specialtyName, isNull);
      expect(a.teachingRole, 'CLASS_TEACHER');
    });
  });

  group('mark entry entities', () {
    test('StudentInClass parses roster row', () {
      final s = StudentInClass.fromMap({
        'enrollment_id': 'e1',
        'student_id': 'st1',
        'full_name': 'Abanda Marie',
        'matricule': 'CM-2026-001',
      });
      expect(s.enrollmentId, 'e1');
      expect(s.fullName, 'Abanda Marie');
      expect(s.matricule, 'CM-2026-001');
    });

    test('MarkBookSummary parses history row + progress', () {
      final b = MarkBookSummary.fromMap({
        'id': 'b1',
        'teacher_assignment_id': 'ta1',
        'teacher_name': 'Mme Ngo',
        'class_name': 'Form 3 SCI',
        'subject_name': 'Physics',
        'sequence_id': 'sq1',
        'sequence_name': 'Sequence 1',
        'sequence_status': 'OPEN',
        'status': 'APPROVED',
        'entered_count': 2,
        'student_count': 4,
        'created_at': '2026-09-06T10:00:00Z',
      });
      expect(b.className, 'Form 3 SCI');
      expect(b.subjectName, 'Physics');
      expect(b.status, 'APPROVED');
      expect(b.progress, 0.5);
    });

    test('MarkBookSummary progress guards divide-by-zero', () {
      final b = MarkBookSummary.fromMap({
        'id': 'b2',
        'teacher_assignment_id': 'ta2',
        'class_name': 'A',
        'subject_name': 'B',
        'sequence_id': 'sq2',
        'sequence_name': 'Sequence 1',
        'entered_count': 0,
        'student_count': 0,
        'created_at': '2026-09-06T10:00:00Z',
      });
      expect(b.progress, 0);
    });

    test('MarkEntry parses a score cell', () {
      final m = MarkEntry.fromMap({
        'id': 'm1',
        'student_enrollment_id': 'e1',
        'student_name': 'Abanda Marie',
        'scheme_component_id': 'comp1',
        'score': 14.5,
        'absence_status': 'ENTERED',
        'teacher_note': null,
      });
      expect(m.studentName, 'Abanda Marie');
      expect(m.score, 14.5);
      expect(m.absenceStatus, 'ENTERED');
    });

    test('MarkEntry handles null score (ABSENT)', () {
      final m = MarkEntry.fromMap({
        'id': 'm2',
        'student_enrollment_id': 'e2',
        'student_name': 'Bello',
        'scheme_component_id': 'comp2',
        'score': null,
        'absence_status': 'ABSENT',
      });
      expect(m.score, isNull);
      expect(m.absenceStatus, 'ABSENT');
    });

    test('MarkBookEvent parses audit row', () {
      final ev = MarkBookEvent.fromMap({
        'action': 'UNLOCKED',
        'previous_status': 'LOCKED',
        'new_status': 'REVIEWED',
        'reason': 'Score entry mistake',
        'actor_name': 'M. Ekollo',
        'created_at': '2026-01-01T10:00:00Z',
      });
      expect(ev.action, 'UNLOCKED');
      expect(ev.reason, 'Score entry mistake');
      expect(ev.createdAt, DateTime.utc(2026, 1, 1, 10));
    });
  });

  group('results entities', () {
    test('PeriodResult parses embedded student + subject rows', () {
      final pr = PeriodResult.fromMap({
        'id': 'pr1',
        'student_enrollment_id': 'e1',
        'general_average': 13.11,
        'total_weighted_points': 118,
        'total_coefficients': 9,
        'class_average': 12.67,
        'rank': 1,
        'status': 'DRAFT',
        'enrollment': {
          'student': {'full_name': 'Abanda Marie', 'matricule': 'CM-001'},
        },
        'subject_results': [
          {
            'subject_id': 's1',
            'subject': {'name': 'Mathematics'},
            'subject_average': 14,
            'coefficient': 5,
            'weighted_points': 70,
            'marks_count': 1,
            'rank_in_subject': 1,
          },
        ],
      });
      expect(pr.studentName, 'Abanda Marie');
      expect(pr.matricule, 'CM-001');
      expect(pr.generalAverage, 13.11);
      expect(pr.rank, 1);
      expect(pr.subjects.single.subjectName, 'Mathematics');
      expect(pr.subjects.single.weightedPoints, 70);
    });

    test('SubjectResultItem leaves coefficient null when missing', () {
      final item = SubjectResultItem.fromMap({
        'subject_id': 's1',
        'subject_average': 12,
        'weighted_points': 48,
      });
      expect(item.coefficient, isNull);
      expect(item.subjectAverage, 12);
      expect(item.subjectName, isNull);
    });
  });
}