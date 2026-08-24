import 'package:academic_engine/academic_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:report_wise/src/data/mapping/academic_mapper.dart';

void main() {
  group('academic_mapper', () {
    test('coefficientConfigFromRow coerces numeric & scope fields', () {
      final cfg = coefficientConfigFromRow({
        'id': 'c1',
        'subject_id': 'MATHS',
        'coefficient': 5, // Postgrest may send num or string
        'source': 'SCHOOL_CONFIGURATION',
        'source_ref': 'school docs',
        'school_id': 's1',
        'academic_year_id': '2026/2027',
        'level_id': '3EME',
        'updated_at': '2026-01-01T00:00:00Z',
      });

      expect(cfg.id, 'c1');
      expect(cfg.subjectId, 'MATHS');
      expect(cfg.coefficient, 5.0);
      expect(cfg.source, ConfigSource.schoolConfiguration);
      expect(cfg.schoolId, 's1');
      expect(cfg.levelId, '3EME');
      expect(cfg.updatedAt, DateTime.utc(2026, 1, 1));

      // string numeric
      final cfg2 = coefficientConfigFromRow({
        'id': 'c2',
        'subject_id': 'PHY',
        'coefficient': '4.5',
        'source': 'NATIONAL_DEFAULT',
      });
      expect(cfg2.coefficient, 4.5);
    });

    test('curriculumFromRow builds an engine curriculum with children', () {
      final curriculum = curriculumFromRow({
        'id': 'cur1',
        'source': 'NATIONAL_DEFAULT',
        'school_id': null,
        'level_id': '3EME',
        'subsystem': 'FRANCOPHONE',
      }, [
        {
          'subject_id': 'MATHS',
          'coefficient': 5,
          'weekly_hours': 5,
          'subject_type': 'GENERAL',
          'counts_in_average': true,
          'counts_in_ranking': true,
          'shows_on_report': true,
        },
        {
          'subject_id': 'PRAC',
          'coefficient': 2,
          'weekly_hours': null,
          'subject_type': 'PRACTICAL',
          'counts_in_average': false,
          'counts_in_ranking': false,
          'shows_on_report': true,
        },
      ]);

      expect(curriculum.id, 'cur1');
      expect(curriculum.levelId, '3EME');
      expect(curriculum.subjects, hasLength(2));
      expect(curriculum.subjects[0].coefficient, 5.0);
      expect(curriculum.subjects[1].subjectType, SubjectType.practical);
      expect(curriculum.subjects[1].countsInAverage, isFalse);
    });

    test('schemeFromRow converts percentage weights to fractions', () {
      final scheme = schemeFromRow({
        'id': 'sch1',
        'name': 'Classic',
        'source': 'NATIONAL_DEFAULT',
      }, [
        {'id': 'ic', 'name': 'Interro', 'component_type': 'CLASS_TEST', 'weight': 20, 'max_score': 20},
        {'id': 'dv', 'name': 'Devoir', 'component_type': 'ASSIGNMENT', 'weight': 30, 'max_score': 20},
        {'id': 'ex', 'name': 'Exam', 'component_type': 'EXAM', 'weight': 50, 'max_score': 20},
      ]);

      expect(scheme.components, hasLength(3));
      expect(scheme.totalWeight, closeTo(1.0, 1e-9));
      expect(scheme.components[1].weight, 0.3);
    });

    test('academicContextFromClassRow maps a class to its engine context', () {
      final ctx = academicContextFromClassRow({
        'id': 'cls-3a',
        'subsystem': 'FRANCOPHONE',
        'education_type_id': 'ed-type-general',
        'cycle_id': 'cyc-1',
        'level_id': 'lv-3eme',
        'series_id': 'sr-a',
        'specialty_id': null,
      }, schoolId: 's1', academicYearId: '2026/2027');

      expect(ctx.schoolId, 's1');
      expect(ctx.academicYearId, '2026/2027');
      expect(ctx.seriesId, 'sr-a');
      expect(ctx.specialtyId, isNull);
    });

    test('mapped rows + engine resolve school coefficient override', () {
      final curricula = [
        curriculumFromRow({
          'id': 'nat',
          'source': 'NATIONAL_DEFAULT',
          'level_id': '3EME',
        }, [
          {'subject_id': 'MATHS', 'coefficient': 5, 'subject_type': 'GENERAL'},
          {'subject_id': 'PHY', 'coefficient': 4, 'subject_type': 'GENERAL'},
        ]),
      ];
      final configs = [
        coefficientConfigFromRow({
          'id': 'ov',
          'subject_id': 'MATHS',
          'coefficient': 6,
          'source': 'SCHOOL_CONFIGURATION',
          'school_id': 's1',
        }),
      ];

      final engine = RulesEngine();
      final subjects = engine.resolveSubjects(
        ctx: AcademicContext(
          schoolId: 's1',
          academicYearId: '2025/2026',
          subsystem: 'FRANCOPHONE',
          educationTypeId: 'GENERAL',
          cycleId: 'c1',
          levelId: '3EME',
        ),
        curricula: curricula,
        coefficientConfigs: configs,
      );

      expect(subjects.first.coefficient, 6.0);
      expect(subjects.first.source, ConfigSource.schoolConfiguration);
    });
  });
}