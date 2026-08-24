/// "Most specific applicable configuration wins" resolution
/// (sections 7, 8, 23, 40).
///
/// Specificity is scored per matched scope field with strong weighting so
/// that:
///   * school-scoped rows beat national rows,
///   * academic-year versioned rows beat unversioned school rows,
///   * a row pinned to the exact level/series/specialty beats a broader row.
/// Ties fall back to source priority, then updated_at, then id.
library;

import '../models/models.dart';

int specificityScore(AcademicContext ctx, Scoped s) {
  var score = 0;
  if (s.schoolId != null && s.schoolId == ctx.schoolId) score += 10000;
  if (s.academicYearId != null && s.academicYearId == ctx.academicYearId) {
    score += 1000;
  }
  if (s.subsystem != null && s.subsystem == ctx.subsystem) score += 100;
  if (s.educationTypeId != null && s.educationTypeId == ctx.educationTypeId) {
    score += 100;
  }
  if (s.cycleId != null && s.cycleId == ctx.cycleId) score += 100;
  if (s.levelId != null && s.levelId == ctx.levelId) score += 100;
  if (s.seriesId != null && s.seriesId == ctx.seriesId) score += 10;
  if (s.specialtyId != null && s.specialtyId == ctx.specialtyId) score += 10;
  return score;
}

/// A candidate applies to the context when every non-null scope field
/// matches the context exactly (null = "any"). A non-null field that differs
/// excludes the row entirely.
bool matchesContext(AcademicContext ctx, Scoped s) {
  if (s.schoolId != null && s.schoolId != ctx.schoolId) return false;
  if (s.academicYearId != null && s.academicYearId != ctx.academicYearId) {
    return false;
  }
  if (s.subsystem != null && s.subsystem != ctx.subsystem) return false;
  if (s.educationTypeId != null && s.educationTypeId != ctx.educationTypeId) {
    return false;
  }
  if (s.cycleId != null && s.cycleId != ctx.cycleId) return false;
  if (s.levelId != null && s.levelId != ctx.levelId) return false;
  if (s.seriesId != null && s.seriesId != ctx.seriesId) return false;
  if (s.specialtyId != null && s.specialtyId != ctx.specialtyId) return false;
  return true;
}

/// Returns the single most specific, deterministic candidate, or null.
T? resolveMostSpecific<T extends Resolvable>(
  AcademicContext ctx,
  Iterable<T> candidates,
) {
  T? best;
  int? bestScore;
  int? bestSource;
  DateTime? bestUpdated;
  String? bestId;

  for (final c in candidates) {
    if (!matchesContext(ctx, c)) continue;
    final score = specificityScore(ctx, c);

    var isBetter = best == null;
    if (!isBetter) {
      if (score != bestScore) {
        isBetter = score > bestScore!;
      } else if (c.sourcePriority != bestSource) {
        isBetter = c.sourcePriority > bestSource!;
      } else {
        final cUpdated = c.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bUpdated = bestUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
        isBetter = cUpdated != bUpdated
            ? cUpdated.isAfter(bUpdated)
            : c.id.compareTo(bestId!) < 0;
      }
    }

    if (isBetter) {
      best = c;
      bestScore = score;
      bestSource = c.sourcePriority;
      bestUpdated = c.updatedAt;
      bestId = c.id;
    }
  }

  return best;
}

/// Resolve the coefficient that applies to `subjectId` for `ctx`.
double? resolveCoefficient(
  AcademicContext ctx,
  String subjectId,
  Iterable<CoefficientConfig> configs,
) {
  final matching = configs.where((c) => c.subjectId == subjectId);
  return resolveMostSpecific(ctx, matching)?.coefficient;
}
