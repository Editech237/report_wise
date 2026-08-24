/// Core academic domain models for the ReportWise calculation engine.
library;

/// Where a configuration value originates. Used for administrative
/// transparency (section 40-41) and resolution precedence (section 7-8).
enum ConfigSource {
  nationalDefault('NATIONAL_DEFAULT', 1),
  schoolConfiguration('SCHOOL_CONFIGURATION', 2),
  academicYear('ACADEMIC_YEAR', 3);

  final String code;
  final int priority;

  const ConfigSource(this.code, this.priority);

  static ConfigSource fromCode(String code) {
    for (final s in ConfigSource.values) {
      if (s.code == code) return s;
    }
    throw ArgumentError.value(code, 'code', 'Unknown ConfigSource');
  }
}

enum SubjectType {
  general('GENERAL'),
  technical('TECHNICAL'),
  professional('PROFESSIONAL'),
  practical('PRACTICAL'),
  theory('THEORY'),
  language('LANGUAGE'),
  sport('SPORT'),
  other('OTHER');

  final String code;
  const SubjectType(this.code);

  static SubjectType? fromCode(String? code) {
    if (code == null) return null;
    for (final t in SubjectType.values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// Distinguishes NOT_ENTERED / ABSENT / EXCUSED / ZERO / NOT_APPLICABLE /
/// PENDING / ENTERED so the engine never treats missing marks as zero
/// blindly (section 28).
enum AbsenceStatus {
  notEntered('NOT_ENTERED'),
  absent('ABSENT'),
  excused('EXCUSED'),
  zero('ZERO'),
  notApplicable('NOT_APPLICABLE'),
  pending('PENDING'),
  entered('ENTERED');

  final String code;
  const AbsenceStatus(this.code);

  static AbsenceStatus fromCode(String code) {
    for (final s in AbsenceStatus.values) {
      if (s.code == code) return s;
    }
    throw ArgumentError.value(code, 'code', 'Unknown AbsenceStatus');
  }
}

enum RankingMethod {
  /// 1, 2, 2, 4 — equal averages share a rank, positions are skipped.
  competition('COMPETITION'),

  /// 1, 2, 2, 3 — equal averages share a rank, no skips.
  dense('DENSE'),

  /// 1, 2, 3, 4 — every student gets a distinct rank, tie-breaker applied.
  sequential('SEQUENTIAL');

  final String code;
  const RankingMethod(this.code);

  static RankingMethod fromCode(String code) {
    for (final m in RankingMethod.values) {
      if (m.code == code) return m;
    }
    throw ArgumentError.value(code, 'code', 'Unknown RankingMethod');
  }
}

enum TieBreaker {
  totalWeightedPoints('TOTAL_WEIGHTED_POINTS'),
  majorSubjectsAverage('MAJOR_SUBJECTS_AVERAGE'),
  coreSubjectsAverage('CORE_SUBJECTS_AVERAGE'),
  none('NONE');

  final String code;
  const TieBreaker(this.code);

  static TieBreaker fromCode(String code) {
    for (final t in TieBreaker.values) {
      if (t.code == code) return t;
    }
    throw ArgumentError.value(code, 'code', 'Unknown TieBreaker');
  }
}

enum RoundingMode {
  halfUp('HALF_UP'),
  halfAwayFromZero('HALF_AWAY_FROM_ZERO');

  final String code;
  const RoundingMode(this.code);

  static RoundingMode fromCode(String code) {
    for (final r in RoundingMode.values) {
      if (r.code == code) return r;
    }
    throw ArgumentError.value(code, 'code', 'Unknown RoundingMode');
  }
}

enum AnnualAverageMethod {
  meanOfTermAverages('MEAN_OF_TERM_AVERAGES'),
  meanOfSequenceAverages('MEAN_OF_SEQUENCE_AVERAGES');

  final String code;
  const AnnualAverageMethod(this.code);

  static AnnualAverageMethod fromCode(String code) {
    for (final a in AnnualAverageMethod.values) {
      if (a.code == code) return a;
    }
    throw ArgumentError.value(code, 'code', 'Unknown AnnualAverageMethod');
  }
}

/// The full academic context of a student for a given academic year
/// (section 36). The engine resolves all rules against this context.
class AcademicContext {
  final String schoolId;
  final String academicYearId;
  final String subsystem; // FRANCOPHONE | ANGLOPHONE
  final String educationTypeId; // GENERAL | TECHNICAL
  final String cycleId;
  final String levelId;
  final String? seriesId;
  final String? specialtyId;
  final String? classId;

  const AcademicContext({
    required this.schoolId,
    required this.academicYearId,
    required this.subsystem,
    required this.educationTypeId,
    required this.cycleId,
    required this.levelId,
    this.seriesId,
    this.specialtyId,
    this.classId,
  });
}

/// Common nullable scope fields used by every versioned configuration.
abstract class Scoped {
  String? get schoolId;
  String? get academicYearId;
  String? get subsystem;
  String? get educationTypeId;
  String? get cycleId;
  String? get levelId;
  String? get seriesId;
  String? get specialtyId;
}

/// A scoped configuration that participates in "most specific wins"
/// resolution, with deterministic tie-breaking.
abstract class Resolvable implements Scoped {
  String get id;
  int get sourcePriority;
  DateTime? get updatedAt;
}

/// A resolved subject as it applies to a student's context: coefficient,
/// workload and the three applicability flags.
class SubjectConfig {
  final String subjectId;
  final String code;
  final String name;
  final double coefficient;
  final double? weeklyHours;
  final SubjectType? subjectType;
  final bool countsInAverage;
  final bool countsInRanking;
  final bool showsOnReport;
  final ConfigSource source;
  final String? sourceRef;

  const SubjectConfig({
    required this.subjectId,
    required this.code,
    required this.name,
    required this.coefficient,
    this.weeklyHours,
    this.subjectType,
    this.countsInAverage = true,
    this.countsInRanking = true,
    this.showsOnReport = true,
    this.source = ConfigSource.nationalDefault,
    this.sourceRef,
  });

  SubjectConfig copyWith({double? coefficient, ConfigSource? source, String? sourceRef}) {
    return SubjectConfig(
      subjectId: subjectId,
      code: code,
      name: name,
      coefficient: coefficient ?? this.coefficient,
      weeklyHours: weeklyHours,
      subjectType: subjectType,
      countsInAverage: countsInAverage,
      countsInRanking: countsInRanking,
      showsOnReport: showsOnReport,
      source: source ?? this.source,
      sourceRef: sourceRef ?? this.sourceRef,
    );
  }
}

/// A versioned coefficient configuration row (section 7).
class CoefficientConfig implements Resolvable {
  final String id;
  final String subjectId;
  final double coefficient;
  final ConfigSource source;
  final String? sourceRef;
  @override
  final String? schoolId;
  @override
  final String? academicYearId;
  @override
  final String? subsystem;
  @override
  final String? educationTypeId;
  @override
  final String? cycleId;
  @override
  final String? levelId;
  @override
  final String? seriesId;
  @override
  final String? specialtyId;
  @override
  final DateTime? updatedAt;

  const CoefficientConfig({
    required this.id,
    required this.subjectId,
    required this.coefficient,
    required this.source,
    this.sourceRef,
    this.schoolId,
    this.academicYearId,
    this.subsystem,
    this.educationTypeId,
    this.cycleId,
    this.levelId,
    this.seriesId,
    this.specialtyId,
    this.updatedAt,
  });

  @override
  int get sourcePriority => source.priority;
}

/// A curriculum row (scope) + the subjects that belong to it (section 23).
class CurriculumEntry implements Resolvable {
  final String id;
  final List<CurriculumSubject> subjects;
  final ConfigSource source;
  final String? sourceRef;
  @override
  final String? schoolId;
  @override
  final String? academicYearId;
  @override
  final String? subsystem;
  @override
  final String? educationTypeId;
  @override
  final String? cycleId;
  @override
  final String? levelId;
  @override
  final String? seriesId;
  @override
  final String? specialtyId;
  @override
  final DateTime? updatedAt;

  const CurriculumEntry({
    required this.id,
    required this.subjects,
    required this.source,
    this.sourceRef,
    this.schoolId,
    this.academicYearId,
    this.subsystem,
    this.educationTypeId,
    this.cycleId,
    this.levelId,
    this.seriesId,
    this.specialtyId,
    this.updatedAt,
  });

  @override
  int get sourcePriority => source.priority;
}

class CurriculumSubject {
  final String subjectId;
  final double coefficient;
  final double? weeklyHours;
  final SubjectType? subjectType;
  final bool countsInAverage;
  final bool countsInRanking;
  final bool showsOnReport;

  const CurriculumSubject({
    required this.subjectId,
    required this.coefficient,
    this.weeklyHours,
    this.subjectType,
    this.countsInAverage = true,
    this.countsInRanking = true,
    this.showsOnReport = true,
  });
}

class AssessmentComponent {
  final String id;
  final String name;
  final String componentType; // CLASS_TEST | ASSIGNMENT | QUIZ | EXAM | ...
  final double weight; // fraction of the scheme (0..1)
  final double maxScore;

  const AssessmentComponent({
    required this.id,
    required this.name,
    required this.componentType,
    required this.weight,
    required this.maxScore,
  });
}

/// A scoped assessment scheme (section 13-14). Weights and coefficients are
/// deliberately kept apart.
class SchemeConfig implements Resolvable {
  final String id;
  final String name;
  final List<AssessmentComponent> components;
  final ConfigSource source;
  @override
  final String? schoolId;
  @override
  final String? academicYearId;
  @override
  final String? subsystem;
  @override
  final String? educationTypeId;
  @override
  final String? cycleId;
  @override
  final String? levelId;
  @override
  final String? seriesId;
  @override
  final String? specialtyId;
  @override
  final DateTime? updatedAt;

  const SchemeConfig({
    required this.id,
    required this.name,
    required this.components,
    required this.source,
    this.schoolId,
    this.academicYearId,
    this.subsystem,
    this.educationTypeId,
    this.cycleId,
    this.levelId,
    this.seriesId,
    this.specialtyId,
    this.updatedAt,
  });

  @override
  int get sourcePriority => source.priority;

  /// Total weight of the scheme; used for validation (should be 1.0).
  double get totalWeight =>
      components.fold(0.0, (sum, c) => sum + c.weight);
}

/// Which absence statuses remove a mark from the average, and whether
/// ZERO is treated as an academic score (section 28).
class MissingMarkPolicy {
  final Set<AbsenceStatus> excludedStatuses;
  final bool zeroIsScore;

  const MissingMarkPolicy({
    required this.excludedStatuses,
    this.zeroIsScore = true,
  });
}

class DisplayPrecision {
  final int decimals;
  final RoundingMode mode;

  const DisplayPrecision({this.decimals = 2, this.mode = RoundingMode.halfUp});

  static const standard = DisplayPrecision();
}

/// One mark a student received for one assessment component.
class ComponentMark {
  final String subjectId;
  final String componentId;
  final double? score; // on the component's maxScore scale
  final double maxScore;
  final AbsenceStatus absenceStatus;

  const ComponentMark({
    required this.subjectId,
    required this.componentId,
    this.score,
    this.maxScore = 20,
    this.absenceStatus = AbsenceStatus.entered,
  });
}

/// Result of the subject-average calculation for one subject.
class SubjectResult {
  final SubjectConfig config;
  final double? subjectAverage; // out of 20; null when excluded
  final int enteredComponents;
  final double? weightedPoints; // subjectAverage * coefficient

  const SubjectResult({
    required this.config,
    required this.subjectAverage,
    required this.enteredComponents,
    this.weightedPoints,
  });
}

/// Full period result for a single student (section 44: marks →
/// subject averages → weighted points → general average).
class StudentPeriodResult {
  final String studentId;
  final List<SubjectResult> subjects;
  final double? generalAverage;
  final double? totalWeightedPoints;
  final double? totalCoefficients;
  final List<String> excludedSubjects;

  const StudentPeriodResult({
    required this.studentId,
    required this.subjects,
    required this.generalAverage,
    required this.totalWeightedPoints,
    required this.totalCoefficients,
    required this.excludedSubjects,
  });
}

/// A student queued for ranking, with the tie-break metrics precomputed.
class RankedStudent {
  final String studentId;
  final double? generalAverage;
  final double? totalWeightedPoints;
  final double? majorSubjectsAverage;
  final double? coreSubjectsAverage;
  int? rank;

  RankedStudent({
    required this.studentId,
    required this.generalAverage,
    this.totalWeightedPoints,
    this.majorSubjectsAverage,
    this.coreSubjectsAverage,
    this.rank,
  });
}

/// Configurable ranking rules (section 16-17).
class RankingRule {
  final RankingMethod method;
  final TieBreaker tieBreaker;
  final bool sameRankForTies;

  /// Scopes: 'CLASS', 'LEVEL', 'SERIES', 'SCHOOL'.
  final Set<String> scopes;

  const RankingRule({
    this.method = RankingMethod.competition,
    this.tieBreaker = TieBreaker.totalWeightedPoints,
    this.sameRankForTies = true,
    this.scopes = const {'CLASS'},
  });
}
