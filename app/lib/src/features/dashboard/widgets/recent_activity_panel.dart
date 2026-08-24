import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class ActivityItem {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String timeAgo;
  const ActivityItem({required this.icon, required this.iconColor, required this.iconBgColor, required this.title, required this.timeAgo});
}

class RecentActivityPanel extends StatelessWidget {
  final List<ActivityItem>? items;
  const RecentActivityPanel({super.key, this.items});

  static const _default = [
    ActivityItem(icon: Icons.description_outlined, iconColor: AppColors.primary, iconBgColor: Color(0x1A0B5D3B), title: 'Mme. Njoh uploaded Form 4 Mathematics marks', timeAgo: '12 MINUTES AGO'),
    ActivityItem(icon: Icons.check_circle_outline_rounded, iconColor: Color(0xFF2E7D32), iconBgColor: Color(0xFFE8F5E9), title: 'Attendance record for 1ère C submitted', timeAgo: '45 MINUTES AGO'),
    ActivityItem(icon: Icons.access_time_rounded, iconColor: Color(0xFFD32F2F), iconBgColor: Color(0xFFFFEBEE), title: 'Discipline warning issued: Form 3 (A. Ambe)', timeAgo: '2 HOURS AGO'),
  ];

  @override
  Widget build(BuildContext context) {
    final list = items ?? _default;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Activity', style: TextStyle(fontFamily: 'Manrope', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
          const SizedBox(height: 4),
          Text('Real-time faculty and system updates', style: TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.7))),
          const SizedBox(height: 20),
          ...list.map((a) => _Tile(item: a)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {},
              child: const Text('VIEW ALL ACTIVITY',
                  style: TextStyle(fontFamily: 'Lexend', fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.primary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final ActivityItem item;
  const _Tile({required this.item});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: item.iconBgColor, borderRadius: BorderRadius.circular(8)),
            child: Icon(item.icon, size: 18, color: item.iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: const TextStyle(fontFamily: 'Lexend', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface, height: 1.4)),
                const SizedBox(height: 3),
                Text(item.timeAgo, style: TextStyle(fontFamily: 'Lexend', fontSize: 10.5, color: AppColors.onSurfaceVariant.withOpacity(0.55), letterSpacing: 0.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
