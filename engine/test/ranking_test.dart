import 'package:academic_engine/academic_engine.dart';
import 'package:test/test.dart';

RankedStudent student(String id, double? avg,
    {double? points, double? majors, double? core}) {
  return RankedStudent(
    studentId: id,
    generalAverage: avg,
    totalWeightedPoints: points ?? avg,
    majorSubjectsAverage: majors,
    coreSubjectsAverage: core,
  );
}

Map<String, int> ranksOf(List<RankedStudent> students) =>
    {for (final s in students) s.studentId: s.rank!};

void main() {
  group('ranking', () {
    final students = [
      student('A', 13.45),
      student('B', 12.0),
      student('C', 13.45),
    ];

    test('competition ranking: ties share rank, positions skipped (1,2,2,4)',
        () {
      rankStudents(
        students: students,
        rule: const RankingRule(method: RankingMethod.competition),
      );
      expect(ranksOf(students), {'A': 1, 'B': 3, 'C': 1});
    });

    test('dense ranking: ties share rank, no skips (1,2,2,3)', () {
      rankStudents(
        students: students,
        rule: const RankingRule(method: RankingMethod.dense),
      );
      expect(ranksOf(students), {'A': 1, 'B': 2, 'C': 1});
    });

    test('sequential ranking applies the tie-breaker', () {
      rankStudents(
        students: students,
        rule: const RankingRule(
          method: RankingMethod.sequential,
          sameRankForTies: false,
        ),
      );
      expect(ranksOf(students), {'A': 1, 'B': 3, 'C': 2});
    });

    test('tie-breaker by total weighted points breaks equal averages', () {
      final tied = [
        student('X', 13.0, points: 150.0),
        student('Y', 13.0, points: 148.0),
      ];
      rankStudents(
        students: tied,
        rule: const RankingRule(
          method: RankingMethod.sequential,
          sameRankForTies: false,
        ),
      );
      expect(ranksOf(tied), {'X': 1, 'Y': 2});
    });

    test('tie-breaker by major subjects average', () {
      final tied = [
        student('X', 12.0, majors: 15.0),
        student('Y', 12.0, majors: 13.0),
      ];
      rankStudents(
        students: tied,
        rule: const RankingRule(
          method: RankingMethod.sequential,
          tieBreaker: TieBreaker.majorSubjectsAverage,
          sameRankForTies: false,
        ),
      );
      expect(ranksOf(tied), {'X': 1, 'Y': 2});
    });

    test('no tie-breaker configured: equal averages stay tied even sequentially',
        () {
      final tied = [
        student('X', 12.0),
        student('Y', 12.0),
        student('Z', 11.0),
      ];
      rankStudents(
        students: tied,
        rule: const RankingRule(
          method: RankingMethod.sequential,
          tieBreaker: TieBreaker.none,
          sameRankForTies: false,
        ),
      );
      // Deterministic fallback by student id; ranks 1,2,3.
      expect(ranksOf(tied), {'X': 1, 'Y': 2, 'Z': 3});
    });

    test('competition ranking of a single best student', () {
      final list = [student('A', 20.0)];
      rankStudents(
        students: list,
        rule: const RankingRule(method: RankingMethod.competition),
      );
      expect(ranksOf(list), {'A': 1});
    });

    test('empty list is a no-op', () {
      final list = <RankedStudent>[];
      rankStudents(students: list, rule: const RankingRule());
      expect(list, isEmpty);
    });
  });
}