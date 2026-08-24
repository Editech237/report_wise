import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

enum StatTrend { positive, warning, neutral }

class DashboardStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String label;
  final String value;
  final String subtitle;
  final StatTrend trend;

  const DashboardStatCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.label,
    required this.value,
    required this.subtitle,
    this.trend = StatTrend.neutral,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(height: 16),
          Text(label, style: TextStyle(fontFamily: 'Lexend', fontSize: 13, color: AppColors.onSurfaceVariant.withOpacity(0.85))),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontFamily: 'Manrope', fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
          const SizedBox(height: 8),
          _buildSubtitle(),
        ],
      ),
    );
  }

  Widget _buildSubtitle() {
    switch (trend) {
      case StatTrend.positive:
        return Row(children: [
          const Icon(Icons.trending_up_rounded, size: 14, color: Color(0xFF2E7D32)),
          const SizedBox(width: 4),
          Flexible(child: Text(subtitle, style: const TextStyle(fontFamily: 'Lexend', fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.w500))),
        ]);
      case StatTrend.warning:
        return Row(children: [
          const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFFD32F2F)),
          const SizedBox(width: 4),
          Flexible(child: Text(subtitle, style: const TextStyle(fontFamily: 'Lexend', fontSize: 12, color: Color(0xFFD32F2F), fontWeight: FontWeight.w500))),
        ]);
      case StatTrend.neutral:
        return Text(subtitle, style: TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.6)));
    }
  }
}
