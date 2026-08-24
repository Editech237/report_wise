/// Configurable class ranking (sections 16, 17).
///
/// * competition: equal averages share a rank; positions are skipped (1,2,2,4).
/// * dense: equal averages share a rank; no skips (1,2,2,3).
/// * sequential: every student gets a distinct rank; the tie-breaker decides
///   order among equal averages.
///
/// When `sameRankForTies` is true (the Cameroon default), equal general
/// averages always share a rank for competition/dense, and the tie-breaker is
/// only used to order the groups deterministically.
library;

import 'package:academic_engine/src/models/models.dart';

const double _negInfinity = double.negativeInfinity;

double _metricFor(RankedStudent s, TieBreaker tieBreaker) {
  switch (tieBreaker) {
    case TieBreaker.totalWeightedPoints:
      return s.totalWeightedPoints ?? _negInfinity;
    case TieBreaker.majorSubjectsAverage:
      return s.majorSubjectsAverage ?? _negInfinity;
    case TieBreaker.coreSubjectsAverage:
      return s.coreSubjectsAverage ?? _negInfinity;
    case TieBreaker.none:
      return _negInfinity;
  }
}

bool _sameGeneralAverage(RankedStudent a, RankedStudent b) {
  final av = a.generalAverage ?? _negInfinity;
  final bv = b.generalAverage ?? _negInfinity;
  return av == bv;
}

/// Assigns ranks in place on the supplied list.
void rankStudents({
  required List<RankedStudent> students,
  required RankingRule rule,
}) {
  if (students.isEmpty) return;

  final ordered = [...students]..sort((a, b) {
      final byAverage =
          (b.generalAverage ?? _negInfinity)
              .compareTo(a.generalAverage ?? _negInfinity);
      if (byAverage != 0) return byAverage;

      if (rule.tieBreaker != TieBreaker.none) {
        final byMetric = _metricFor(b, rule.tieBreaker).compareTo(
          _metricFor(a, rule.tieBreaker),
        );
        if (byMetric != 0) return byMetric;
      }
      return a.studentId.compareTo(b.studentId);
    });

  switch (rule.method) {
    case RankingMethod.sequential:
      var idx = 1;
      for (final s in ordered) {
        s.rank = idx++;
      }
      break;

    case RankingMethod.competition:
    case RankingMethod.dense:
      var rank = 1;
      var i = 0;
      while (i < ordered.length) {
        var j = i;
        if (rule.sameRankForTies) {
          while (j + 1 < ordered.length &&
              _sameGeneralAverage(ordered[i], ordered[j + 1])) {
            j++;
          }
        }
        final assigned = rank;
        for (var k = i; k <= j; k++) {
          ordered[k].rank = assigned;
        }
        rank += rule.method == RankingMethod.dense ? 1 : (j - i + 1);
        i = j + 1;
      }
      break;
  }
}