/// ReportWise academic engine — Cameroon coefficient-weighted grading.
///
/// A pure-Dart, UI-independent domain engine. It resolves academic rules
/// (coefficients, curriculum, assessment schemes) against a student's
/// academic context and computes subject averages, weighted points, general
/// averages, term/annual averages and rankings.
library;

export 'src/models/models.dart';
export 'src/rules/resolver.dart';
export 'src/rules/rules_engine.dart';
export 'src/calculation/rounding.dart';
export 'src/calculation/calculator.dart';
export 'src/calculation/ranking.dart';