import 'package:academic_engine/src/models/models.dart';
import 'package:academic_engine/src/rules/resolver.dart';

/// Centralized academic rules engine (section 25).
///
/// All "what applies to this student" questions are answered here, never
/// scattered across the UI layer.
class RulesEngine {
  /// Which subjects apply to a student, with their resolved coefficients.
  /// The applicable curriculum is resolved first (most specific curriculum
  /// row); each subject's coefficient is then overridden by the most
  /// specific coefficient configuration if one exists.
  List<SubjectConfig> resolveSubjects({
    required AcademicContext ctx,
    required Iterable<CurriculumEntry> curricula,
    required Iterable<CoefficientConfig> coefficientConfigs,
  }) {
    final curriculum = resolveMostSpecific(ctx, curricula);
    if (curriculum == null) return const [];

    final subjects = <SubjectConfig>[];
    for (final cs in curriculum.subjects) {
      final override =
          resolveCoefficient(ctx, cs.subjectId, coefficientConfigs);
      final coefficient = override ?? cs.coefficient;
      final source = override != null
          ? _coefficientSource(ctx, cs.subjectId, coefficientConfigs)
          : curriculum.source;

      subjects.add(SubjectConfig(
        subjectId: cs.subjectId,
        code: cs.subjectId,
        name: cs.subjectId,
        coefficient: coefficient,
        weeklyHours: cs.weeklyHours,
        subjectType: cs.subjectType,
        countsInAverage: cs.countsInAverage,
        countsInRanking: cs.countsInRanking,
        showsOnReport: cs.showsOnReport,
        source: source,
      ));
    }
    return subjects;
  }

  ConfigSource _coefficientSource(
    AcademicContext ctx,
    String subjectId,
    Iterable<CoefficientConfig> configs,
  ) {
    final resolved =
        resolveMostSpecific(ctx, configs.where((c) => c.subjectId == subjectId));
    return resolved?.source ?? ConfigSource.nationalDefault;
  }

  /// Resolve the assessment scheme that applies to a context.
  SchemeConfig? resolveScheme(AcademicContext ctx, Iterable<SchemeConfig> schemes) =>
      resolveMostSpecific(ctx, schemes);

  /// Resolve the most specific curriculum row for a context.
  CurriculumEntry? resolveCurriculum(
    AcademicContext ctx,
    Iterable<CurriculumEntry> curricula,
  ) =>
      resolveMostSpecific(ctx, curricula);
}
