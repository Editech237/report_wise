import 'dart:math' as math;

/// Word coordinates use a top-left origin, normalized to the page size.
/// Parsing is deliberately separate from the platform OCR engine.
class StudentRegisterParser {
  static String key(String value) {
    var result = value.toLowerCase();
    const accents = {
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'à': 'a',
      'â': 'a',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ù': 'u',
      'û': 'u',
      'ç': 'c',
    };
    accents.forEach((from, to) => result = result.replaceAll(from, to));
    return result.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static const _aliases = <String, List<String>>{
    'full_name': [
      'full name',
      'student name',
      'name',
      'names',
      'nom complet',
      'nom et prenoms',
      'noms et prenoms',
    ],
    'first_name': ['first name', 'given name', 'prenom', 'prenoms'],
    'last_name': ['last name', 'surname', 'family name', 'nom', 'noms'],
    'matricule': ['matricule', 'matricules', 'matricul'],
    'external_student_id': [
      'student id',
      'student identification number',
      'admission no',
      'admission number',
      'admission',
      'registration no',
      'registration number',
      'school id',
      'id',
      'identifiant',
    ],
    'date_of_birth': [
      'date of birth',
      'birth date',
      'dob',
      'date naissance',
      'date de naissance',
      'ne le',
      'nee le',
    ],
    'gender': ['sex', 'gender', 'sexe'],
    'class_name': ['class', 'classe', 'level', 'grade', 'form', 'niveau'],
    '_number': ['no', 'n', 'number', 'numero', 'sn'],
    '_phone': [
      'guardian phone',
      'parent phone',
      'phone',
      'telephone',
      'contact',
    ],
  };

  List<Map<String, dynamic>> parse(List<Map<String, dynamic>> pages) {
    return pages.map(_parsePage).toList();
  }

  Map<String, dynamic> _parsePage(Map<String, dynamic> page) {
    final words = ((page['words'] as List?) ?? [])
        .map((v) => _Word.fromMap(Map<String, dynamic>.from(v as Map)))
        .toList();
    final lines = _lines(words);
    final headers = <({int index, List<_Column> columns})>[];
    for (var i = 0; i < lines.length; i++) {
      final columns = _columns(lines[i]);
      if (columns.where((c) => !c.field.startsWith('_unmapped')).length >= 2 &&
          columns.any(
            (c) =>
                c.field == 'full_name' ||
                c.field == 'first_name' ||
                c.field == 'last_name',
          )) {
        headers.add((index: i, columns: columns));
      }
    }
    final rows = <Map<String, dynamic>>[];
    final warnings = <String>[];
    if (headers.isEmpty) {
      warnings.add(
        words.isEmpty
            ? 'No text was recognized. Try a sharper, upright scan.'
            : 'No supported table headings found. Review the extracted text or add rows manually.',
      );
    }
    for (var section = 0; section < headers.length; section++) {
      final header = headers[section];
      final endIndex = section + 1 < headers.length
          ? headers[section + 1].index
          : lines.length;
      final below = lines
          .sublist(header.index + 1, endIndex)
          .expand((line) => line)
          .toList();
      String? fieldFor(_Word word) {
        // Left-aligned headings establish column starts, allowing small OCR skew.
        final matches = header.columns.where(
          (column) => word.x + word.width / 2 >= column.x - .008,
        );
        return matches.isEmpty ? null : matches.last.field;
      }

      final names = below
          .where(
            (w) =>
                ['full_name', 'first_name', 'last_name'].contains(fieldFor(w)),
          )
          .toList();
      final anchors = _lines(names);
      if (anchors.isEmpty) continue;
      final heights = names.map((w) => w.height).toList()..sort();
      final rowReach = math.max(.012, heights[heights.length ~/ 2] * 2.5);
      for (var i = 0; i < anchors.length; i++) {
        final center = _center(anchors[i]);
        final top = math.max(
          center - rowReach,
          i == 0 ? 0.0 : (_center(anchors[i - 1]) + center) / 2,
        );
        final bottom = math.min(
          center + rowReach,
          i + 1 == anchors.length
              ? 1.0
              : (center + _center(anchors[i + 1])) / 2,
        );
        final cells = <String, List<_Word>>{};
        for (final word in below.where(
          (w) => w.center >= top && w.center < bottom,
        )) {
          final field = fieldFor(word);
          if (field != null) cells.putIfAbsent(field, () => []).add(word);
        }
        String value(String field) => _lines(
          cells[field] ?? [],
        ).map((line) => line.map((w) => w.text).join(' ')).join(' ').trim();
        final fullName = value('full_name').isNotEmpty
            ? value('full_name')
            : [
                value('first_name'),
                value('last_name'),
              ].where((v) => v.isNotEmpty).join(' ');
        // A name plus a second populated column avoids treating footnotes as students.
        if (fullName.isEmpty ||
            !RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(fullName) ||
            cells.keys
                .where(
                  (k) => !['full_name', 'first_name', 'last_name'].contains(k),
                )
                .isEmpty) {
          continue;
        }
        final rowWarnings = <String>[];
        final dob = normalizeDate(value('date_of_birth'));
        if (value('date_of_birth').isNotEmpty && dob == null) {
          rowWarnings.add(
            'Birth date is ambiguous or invalid; check the original.',
          );
        }
        final gender = switch (key(value('gender'))) {
          'm' || 'male' || 'masculin' => 'M',
          'f' || 'female' || 'feminin' => 'F',
          _ => null,
        };
        // Footnotes may span several column positions. Require a plausible
        // registry value, not just text that happens to sit below a heading.
        final hasIdentifier = ['matricule', 'external_student_id'].any(
          (field) =>
              RegExp(
                r'^[A-Za-z0-9][A-Za-z0-9./_-]{0,30}$',
              ).hasMatch(value(field)) ||
              RegExp(r'^[A-Za-z0-9./_-]+[-_/]\s+\d+$').hasMatch(value(field)),
        );
        if (RegExp(r'\s|[A-Za-zÀ-ÿ]{3,}').hasMatch(value('_number'))) {
          continue;
        }
        final hasDate = RegExp(
          r'^\d{1,4}[/.-]\d{1,2}[/.-]\d{1,4}$',
        ).hasMatch(value('date_of_birth'));
        if (!hasIdentifier &&
            !hasDate &&
            gender == null &&
            value('class_name').isEmpty &&
            !RegExp(r'^\d+$').hasMatch(value('_number'))) {
          continue;
        }
        if (value('gender').isNotEmpty && gender == null) {
          rowWarnings.add('Check the gender in the original.');
        }
        final schoolId = value(
          'external_student_id',
        ).replaceAll(RegExp(r'\s+'), '');
        final matricule = value('matricule').replaceAll(RegExp(r'\s+'), '');
        final normalized = <String, dynamic>{
          'full_name': fullName,
          'external_student_id': schoolId.isEmpty ? null : schoolId,
          // Existing school identifiers override generated matricules, as on CSV imports.
          'matricule': matricule.isNotEmpty
              ? matricule
              : (schoolId.isEmpty ? null : schoolId),
          'date_of_birth': dob, 'gender': gender,
          'class_name': value('class_name'), 'class_id': null,
        };
        final confidence = <String, double>{};
        for (final entry in cells.entries) {
          final scores = entry.value
              .map((w) => w.confidence)
              .whereType<double>()
              .toList();
          if (!entry.key.startsWith('_') && scores.isNotEmpty) {
            confidence[entry.key] = scores.reduce(math.min);
          }
        }
        final uncertain = confidence.entries
            .where((entry) => entry.value < .85)
            .map((entry) => entry.key.replaceAll('_', ' '))
            .toList();
        if (uncertain.isNotEmpty) {
          rowWarnings.add('Check OCR values: ${uncertain.join(', ')}.');
        }
        rows.add({
          'raw_data': {for (final field in cells.keys) field: value(field)},
          'normalized_data': normalized,
          'confidence': confidence,
          'warnings': rowWarnings,
        });
      }
    }
    if (headers.isNotEmpty && rows.isEmpty) {
      warnings.add(
        'Headings were found, but no student rows could be mapped. Check the extracted text.',
      );
    }
    return {
      'page_number': page['page_number'],
      'raw_text': page['raw_text'] ?? '',
      'rows': rows,
      'warnings': warnings,
    };
  }

  static String? normalizeDate(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final parts = text.split(RegExp(r'[/.-]'));
    if (parts.length != 3) return null;
    final numbers = parts.map(int.tryParse).toList();
    if (numbers.any((n) => n == null)) return null;
    int year, month, day;
    if (parts.first.length == 4) {
      year = numbers[0]!;
      month = numbers[1]!;
      day = numbers[2]!;
    } else if (parts.last.length == 4) {
      year = numbers[2]!;
      // Do not silently choose US vs day-first for ambiguous dates.
      if (numbers[0]! <= 12 && numbers[1]! <= 12 && numbers[0] != numbers[1]) {
        return null;
      }
      day = numbers[0]! > 12 ? numbers[0]! : numbers[1]!;
      month = numbers[0]! > 12 ? numbers[1]! : numbers[0]!;
    } else {
      return null;
    }
    final date = DateTime(year, month, day);
    if (year < 1900 ||
        date.isAfter(DateTime.now()) ||
        date.year != year ||
        date.month != month ||
        date.day != day) {
      return null;
    }
    return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  List<_Column> _columns(List<_Word> line) {
    final columns = <_Column>[];
    for (var start = 0; start < line.length; start++) {
      _Column? match;
      var matchEnd = start;
      var exactFound = false;
      for (var end = start; end < math.min(start + 5, line.length); end++) {
        final candidate = key(
          line.sublist(start, end + 1).map((w) => w.text).join(' '),
        );
        for (final entry in _aliases.entries) {
          final exact = entry.value.any((alias) => key(alias) == candidate);
          if (exact ||
              (!exactFound &&
                  entry.value.any(
                    (alias) => _headerMatches(key(alias), candidate),
                  ))) {
            match = _Column(entry.key, line[start].x);
            matchEnd = end;
            exactFound = exactFound || exact;
          }
        }
      }
      if (match != null) {
        columns.add(match);
        start = matchEnd;
      } else {
        // Keep unknown columns as boundaries so an address/phone/comment
        // cannot get appended to the preceding name or identifier.
        columns.add(_Column('_unmapped_$start', line[start].x));
      }
    }
    return columns;
  }

  // Allow a single missed/extra/misread letter in longer headings only.
  // This never edits student names or identifiers.
  bool _headerMatches(String expected, String actual) {
    if (expected == actual) return true;
    if (expected.length < 6 ||
        actual.length < 6 ||
        (expected.length - actual.length).abs() > 1) {
      return false;
    }
    var a = 0, b = 0, edits = 0;
    while (a < expected.length && b < actual.length) {
      if (expected[a] == actual[b]) {
        a++;
        b++;
        continue;
      }
      if (++edits > 1) return false;
      if (expected.length >= actual.length) a++;
      if (actual.length >= expected.length) b++;
    }
    return edits + expected.length - a + actual.length - b <= 1;
  }

  List<List<_Word>> _lines(List<_Word> words) {
    final sorted = [...words]..sort((a, b) => a.center.compareTo(b.center));
    final lines = <List<_Word>>[];
    for (final word in sorted) {
      if (lines.isEmpty ||
          (word.center - _center(lines.last)).abs() >
              math.max(.003, word.height * .6)) {
        lines.add([word]);
      } else {
        lines.last.add(word);
      }
    }
    for (final line in lines) {
      line.sort((a, b) => a.x.compareTo(b.x));
    }
    return lines;
  }

  double _center(List<_Word> line) =>
      line.map((w) => w.center).reduce((a, b) => a + b) / line.length;
}

class _Column {
  final String field;
  final double x;
  _Column(this.field, this.x);
}

class _Word {
  final String text;
  final double x, y, width, height;
  final double? confidence;
  _Word.fromMap(Map<String, dynamic> map)
    : text = map['text'] as String,
      x = (map['x'] as num).toDouble(),
      y = (map['y'] as num).toDouble(),
      width = (map['width'] as num).toDouble(),
      height = (map['height'] as num).toDouble(),
      confidence = (map['confidence'] as num?)?.toDouble();
  double get center => y + height / 2;
}
