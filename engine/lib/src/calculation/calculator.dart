/// The Cameroonian coefficient-weighted calculation engine
/// (sections 6, 12, 29, 30, 32).
///
/// Flow:
///   assessment marks → subject average → × coefficient → weighted points
///   → Σ(weighted points) ÷ Σ(coefficients) → general average.
library;

import 'package:academic_engine/src/calculation/rounding.dart';
import 'package:academic_engine/src/models/models.dart';

/// Normalize a raw score to the standard /20 scale.
double normalizeTo20(double score, double maxScore) {
  if (maxScore <= 0) return score;
  return score / maxScore * 20.0;
}

/// Compute one subject's average for a student over one period.
///
/// The scheme's components define weights; marks are matched by
/// component id. Components whose mark carries an excluded absence status
/// (or that have no entry and are not configured to count) are dropped from
/// both numerator and denominator (weights renormalize implicitly).
SubjectResult computeSubjectResult({
  required SubjectConfig config,
  required SchemeConfig scheme,
  required List<ComponentMark> marks,
  required MissingMarkPolicy policy,
}) {
  var weightedSum = 0.0;
  var weightTotal = 0.0;
  var entered = 0;

  for (final component in scheme.components) {
    ComponentMark? mark;
    for (final m in marks) {
      if (m.componentId == component.id) {
        mark = m;
        break;
      }
    }

    if (mark == null) {
      // A missing row is a NOT_ENTERED mark: excluded by default, or counted
      // as zero if the school so configures.
      if (policy.excludedStatuses.contains(AbsenceStatus.notEntered)) continue;
      weightTotal += component.weight;
      continue;
    }

    if (policy.excludedStatuses.contains(mark.absenceStatus)) continue;

    final rawScore = mark.absenceStatus == AbsenceStatus.zero
        ? 0.0
        : (mark.score ?? 0.0);
    final score20 = normalizeTo20(rawScore, mark.maxScore > 0 ? mark.maxScore : component.maxScore);

    weightedSum += score20 * component.weight;
    weightTotal += component.weight;
    entered++;
  }

  if (weightTotal <= 0) {
    return SubjectResult(
      config: config,
      subjectAverage: null,
      enteredComponents: entered,
      weightedPoints: null,
    );
  }

  // Keep raw precision; do not round before weighting (section 32).
  final average = weightedSum / weightTotal;
  final weightedPoints = config.countsInAverage ? average * config.coefficient : null;
  return SubjectResult(
    config: config,
    subjectAverage: average,
    enteredComponents: entered,
    weightedPoints: weightedPoints,
  );
}

/// Compute the full period result for one student.
///
/// Excluded subjects (no applicable marks) contribute to neither the
/// numerator nor the denominator.
StudentPeriodResult computeStudentPeriod({
  required String studentId,
  required SchemeConfig scheme,
  required List<SubjectConfig> subjects,
  required List<ComponentMark> marks,
  required MissingMarkPolicy policy,
  required DisplayPrecision display,
}) {
  final results = <SubjectResult>[];
  var points = 0.0;
  var coefficients = 0.0;
  final excluded = <String>[];

  for (final config in subjects) {
    final subjectMarks =
        marks.where((m) => m.subjectId == config.subjectId).toList();
    final resolved = computeSubjectResult(
      config: config,
      scheme: scheme,
      marks: subjectMarks,
      policy: policy,
    );

    final contributes =
        resolved.subjectAverage != null && config.countsInAverage;
    if (contributes) {
      points += resolved.weightedPoints!;
      coefficients += config.coefficient;
    } else if (resolved.subjectAverage == null) {
      excluded.add(config.subjectId);
    }
    results.add(resolved);
  }

  final generalAverage =
      coefficients > 0 ? displayRound(points / coefficients, display) : null;

  return StudentPeriodResult(
    studentId: studentId,
    subjects: results,
    generalAverage: generalAverage,
    totalWeightedPoints: coefficients > 0 ? displayRound(points, display) : null,
    totalCoefficients: coefficients > 0 ? displayRound(coefficients, display) : null,
    excludedSubjects: excluded,
  );
}

/// Term average = mean of the term's sequence averages (default), or a
/// custom formula per the school's configured academic rules.
double? computeTermAverage({
  required List<double?> sequenceAverages,
  String method = 'MEAN_OF_SEQUENCE_AVERAGES',
  required DisplayPrecision display,
}) {
  final present = sequenceAverages.whereType<double>().toList();
  if (present.isEmpty) return null;
  final mean = present.reduce((a, b) => a + b) / present.length;
  return displayRound(mean, display);
}

/// Annual average from term averages (section 15). The method is an
/// academic rule, never hardcoded.
double? computeAnnualAverage({
  required List<double?> termAverages,
  AnnualAverageMethod method = AnnualAverageMethod.meanOfTermAverages,
  required DisplayPrecision display,
}) {
  final present = termAverages.whereType<double>().toList();
  if (present.isEmpty) return null;
  final mean = present.reduce((a, b) => a + b) / present.length;
  return displayRound(mean, display);
}