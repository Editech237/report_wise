/// Display rounding (section 32). Internal calculations keep full precision;
/// rounding applies only at presentation boundaries.
library;

import 'package:academic_engine/src/models/models.dart';

/// Round `value` to `precision.decimals` using the configured mode.
double displayRound(double value, DisplayPrecision precision) {
  if (precision.mode == RoundingMode.halfAwayFromZero) {
    final factor = _factor(precision.decimals);
    return (value * factor).round() / factor;
  }
  // half-up (round half toward positive infinity)
  final factor = _factor(precision.decimals);
  final scaled = value * factor;
  final rounded = scaled >= 0 ? scaled.floorToDouble() + _half(scaled) : 0.0;
  return rounded / factor;
}

double _factor(int decimals) {
  var f = 1.0;
  for (var i = 0; i < decimals; i++) {
    f *= 10;
  }
  return f;
}

/// 1 when the fractional part is >= 0.5, else 0. Works for positive numbers.
/// A tiny epsilon absorbs binary floating-point representation error
/// (e.g. 1.005 * 100 == 100.4999999...).
double _half(double scaled) {
  final frac = scaled - scaled.truncateToDouble();
  return frac >= 0.5 - 1e-9 ? 1.0 : 0.0;
}
