import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class DashboardDonutCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;
  final double progress;

  const DashboardDonutCard({
    super.key,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
    this.progress = 1,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = progress.clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            height: 74,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 0,
                    centerSpaceRadius: 25,
                    startDegreeOffset: -90,
                    sections: [
                      PieChartSectionData(
                        value: fraction,
                        color: color,
                        radius: 9,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        value: 1 - fraction + 0.0001,
                        color: color.withOpacity(0.12),
                        radius: 9,
                        showTitle: false,
                      ),
                    ],
                  ),
                  swapAnimationDuration: const Duration(milliseconds: 450),
                ),
                Icon(icon, size: 17, color: color),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 10,
                    color: AppColors.onSurfaceVariant.withOpacity(0.62),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
