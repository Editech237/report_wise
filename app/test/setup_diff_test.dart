import 'package:flutter_test/flutter_test.dart';
import 'package:report_wise/src/data/entities.dart';
import 'package:report_wise/src/features/setup/setup_models.dart';

void main() {
  group('diffCoefficients (section 34 before/after):', () {
    test('reports only subjects whose value actually changes', () {
      final changes = diffCoefficients(
        current: {'a': 4, 'b': 3, 'c': 2},
        next: {'a': 4, 'b': 5, 'c': 1},
      );
      expect(changes.length, 2);
      expect(changes.map((c) => c.subjectId).toSet(), {'b', 'c'});
    });

    test('is empty when nothing changes', () {
      expect(
        diffCoefficients(current: {'a': 3}, next: {'a': 3}),
        isEmpty,
      );
    });

    test('captures current and next values and direction', () {
      final changes = diffCoefficients(
        current: {'MATHS': 4},
        next: {'MATHS': 5},
        names: {'MATHS': 'Mathématiques'},
      );
      final c = changes.single;
      expect(c.name, 'Mathématiques');
      expect(c.current, 4);
      expect(c.next, 5);
      expect(c.isIncrease, isTrue);
    });

    test('a subject added from nothing reads as new', () {
      final changes = diffCoefficients(
        current: {},
        next: {'SPORT': 2},
        names: {'SPORT': 'EPS'},
      );
      expect(changes.single.isNew, isTrue);
      expect(changes.single.current, 0);
    });

    test('sorted deterministically by subject id', () {
      final changes = diffCoefficients(
        current: {'z': 1, 'a': 1, 'm': 1},
        next: {'z': 2, 'a': 2, 'm': 2},
      );
      expect(changes.map((c) => c.subjectId).toList(), ['a', 'm', 'z']);
    });
  });

  group('sourceLabel:', () {
    test('maps engine source codes to UI labels', () {
      expect(sourceLabel('NATIONAL_DEFAULT'), 'National');
      expect(sourceLabel('SCHOOL_CONFIGURATION'), 'School');
      expect(sourceLabel('ACADEMIC_YEAR'), 'School · Year');
    });
  });

  group('SchoolClass.fromMap (embedded relation names):', () {
    test('parses aliased embedded relation names', () {
      final cls = SchoolClass.fromMap({
        'id': 'c1',
        'school_id': 's1',
        'academic_year_id': 'y1',
        'subsystem': 'FRANCOPHONE',
        'education_type_id': 'et1',
        'cycle_id': 'cy1',
        'level_id': 'lv1',
        'series_id': 'sr1',
        'specialty_id': 'sp1',
        'name': '3ème A',
        'room': 'B12',
        'is_active': true,
        'education_type': {'name': 'General'},
        'cycle': {'name': 'First cycle'},
        'level': {'name': '3ème'},
        'series': {'name': 'A'},
        'specialty': {'name': 'General technician'},
      });
      expect(cls.name, '3ème A');
      expect(cls.educationTypeName, 'General');
      expect(cls.cycleName, 'First cycle');
      expect(cls.levelName, '3ème');
      expect(cls.seriesName, 'A');
      expect(cls.specialtyName, 'General technician');
      expect(cls.isActive, isTrue);
    });

    test('handles null optional relations', () {
      final cls = SchoolClass.fromMap({
        'id': 'c2',
        'school_id': 's1',
        'academic_year_id': 'y1',
        'subsystem': 'ANGLOPHONE',
        'education_type_id': 'et1',
        'cycle_id': 'cy2',
        'level_id': 'lv9',
        'name': 'Form 1',
        'is_active': false,
      });
      expect(cls.seriesId, isNull);
      expect(cls.seriesName, isNull);
      expect(cls.specialtyName, isNull);
      expect(cls.isActive, isFalse);
    });
  });
}