/// Pure helpers for the academic-setup UI so the versioned before/after
/// coefficient-diff logic can be unit tested without a database.
library;

/// A single coefficient change surfaced in the confirmation dialog
/// (section 34): what is in effect now vs. what will be recorded.
class CoefficientChange {
  final String subjectId;
  final String name;
  final double current;
  final double next;

  const CoefficientChange({
    required this.subjectId,
    required this.name,
    required this.current,
    required this.next,
  });

  bool get isIncrease => next > current;
  bool get isNew => current == 0;
}

/// Builds the ordered list of coefficient changes between two maps keyed by
/// subject id. `current` is the resolved effective value; `next` is what the
/// admin wants. Unchanged subjects are omitted. Unknown subject ids fall back
/// to the id itself for display when no name is supplied.
List<CoefficientChange> diffCoefficients({
  required Map<String, double> current,
  required Map<String, double> next,
  Map<String, String>? names,
}) {
  final ids = {...current.keys, ...next.keys}.toList()..sort();
  final changes = <CoefficientChange>[];
  for (final id in ids) {
    final before = current[id] ?? 0;
    final after = next[id] ?? 0;
    if (before != after) {
      changes.add(CoefficientChange(
        subjectId: id,
        name: names?[id] ?? id,
        current: before,
        next: after,
      ));
    }
  }
  return changes;
}

/// Human label for an engine ConfigSource code.
String sourceLabel(String sourceCode) {
  switch (sourceCode) {
    case 'NATIONAL_DEFAULT':
      return 'National';
    case 'SCHOOL_CONFIGURATION':
      return 'School';
    case 'ACADEMIC_YEAR':
      return 'School · Year';
    default:
      return sourceCode;
  }
}