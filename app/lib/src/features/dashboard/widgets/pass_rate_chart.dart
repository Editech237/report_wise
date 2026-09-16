import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer.dart';

/// Static pass-rate chart — mouse interactivity disabled to avoid
/// fl_chart 0.69 + Flutter 3.44 mouse_tracker re-entrancy bug.
///
/// Previously used `touchCallback -> setState` which triggered
/// `!_debugDuringDeviceUpdate` when hovering over bars inside a
/// SingleChildScrollView/Row+Expanded layout. The deferred
/// `addPostFrameCallback` helped in tests but still queued many
/// rebuilds under rapid mouse movement. Disabling touch eliminates
/// the crash and keeps the dashboard fully clickable.
class PassRateChart extends StatelessWidget {
  final Map<String, int>? data; // label → pass rate %
  final bool loading;

  const PassRateChart({super.key, this.data, this.loading = false});

  List<_Entry> get _entries {
    if (data != null && data!.isNotEmpty) {
      return data!.entries.map((e) => _Entry(e.key, e.value)).toList();
    }
    return const [];
  }

  static const _target = 75.0;
  static const _barColor = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ShimmerBlock(height: 18, width: 300),
            const SizedBox(height: 8),
            const ShimmerBlock(height: 12, width: 200),
            const SizedBox(height: 24),
            const ShimmerBlock(height: 300),
          ],
        ),
      );
    }

    final entries = _entries;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pass Rate per Class',
                        style: TextStyle(fontFamily: 'Manrope', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                    SizedBox(height: 4),
                    Text('Latest sequence results · pass mark 10/20',
                        style: TextStyle(fontFamily: 'Lexend', fontSize: 12, color: Color(0xFF7A7A8A))),
                  ],
                ),
              ),
              Row(children: [
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF1B5E20), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text('Target Met', style: TextStyle(fontFamily: 'Lexend', fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.onSurfaceVariant)),
              ]),
            ],
          ),
          const SizedBox(height: 24),
          if (entries.isEmpty)
            Container(
              height: 220,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.surfaceLow, borderRadius: BorderRadius.circular(12)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bar_chart_rounded, size: 32, color: AppColors.onSurfaceVariant),
                  const SizedBox(height: 8),
                  const Text('No results yet',
                      style: TextStyle(fontFamily: 'Manrope', fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Compute class results (Academic → Results) to see real pass rates.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.7))),
                ],
              ),
            )
          else
          // Isolate chart repaint; fixed height avoids unbounded constraints inside Row+Expanded
          RepaintBoundary(
            child: SizedBox(
              height: 220,
              // AbsorbPointer ensures no mouseTracker registration for the chart at all
              child: AbsorbPointer(
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: 100,
                    minY: 0,
                    barTouchData: BarTouchData(enabled: false),
                    titlesData: FlTitlesData(
                      show: true,
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          interval: 25,
                          getTitlesWidget: (v, m) {
                            if (v == 0 || v == m.max) return const SizedBox.shrink();
                            return Text('${v.toInt()}%', style: TextStyle(fontFamily: 'Lexend', fontSize: 10, color: AppColors.onSurfaceVariant.withOpacity(0.5)));
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (v, m) {
                            final i = v.toInt();
                            if (i < 0 || i >= entries.length) return const SizedBox.shrink();
                            return Padding(padding: const EdgeInsets.only(top: 8), child: Text(entries[i].label, style: TextStyle(fontFamily: 'Lexend', fontSize: 11, color: AppColors.onSurfaceVariant.withOpacity(0.7))));
                          },
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 25,
                      getDrawingHorizontalLine: (_) => FlLine(color: AppColors.border, strokeWidth: 1, dashArray: [4, 4]),
                    ),
                    borderData: FlBorderData(show: false),
                    extraLinesData: ExtraLinesData(horizontalLines: [
                      HorizontalLine(
                        y: _target,
                        color: Colors.orange.withOpacity(0.6),
                        strokeWidth: 1.5,
                        dashArray: [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          style: const TextStyle(fontFamily: 'Lexend', fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600),
                          labelResolver: (_) => 'Target ${_target.toInt()}%',
                        ),
                      )
                    ]),
                    barGroups: entries.asMap().entries.map((e) {
                      return BarChartGroupData(x: e.key, barRods: [
                        BarChartRodData(
                          toY: e.value.value.toDouble(),
                          color: _barColor,
                          width: 36,
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
                          backDrawRodData: BackgroundBarChartRodData(show: true, toY: 100, color: const Color(0xFFF5F5F5)),
                        )
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Entry {
  final String label;
  final int value;
  const _Entry(this.label, this.value);
}
