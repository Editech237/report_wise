/// Report language follows the class section in a bilingual school.
/// School-wide labels can remain bilingual without mixing report terminology.
class SchoolLabels {
  final String subsystem;
  const SchoolLabels(this.subsystem);

  factory SchoolLabels.forClass(
    String schoolSubsystem,
    String classSubsystem,
  ) => SchoolLabels(
    schoolSubsystem == 'BILINGUAL' ? classSubsystem : schoolSubsystem,
  );

  String text(String english, String french) => switch (subsystem) {
    'ANGLOPHONE' => english,
    'FRANCOPHONE' => french,
    _ => english == french ? english : '$english / $french',
  };

  String get sectionName => switch (subsystem) {
    'ANGLOPHONE' => 'Anglophone',
    'FRANCOPHONE' => 'Francophone',
    'BILINGUAL' => 'Bilingual',
    _ => subsystem,
  };

  String period(String original) {
    final match = RegExp(
      r'^(?:term|trimestre|sequence|séquence)\s*(\d+)$',
      caseSensitive: false,
    ).firstMatch(original.trim());
    if (match != null) {
      final sequence = original.toLowerCase().startsWith('s');
      return '${sequence ? text('Sequence', 'Séquence') : text('Term', 'Trimestre')} ${match[1]}';
    }
    if (['Annual Average', 'Annual', 'Moyenne annuelle'].contains(original))
      return text('Annual Average', 'Moyenne annuelle');
    return original;
  }
}
