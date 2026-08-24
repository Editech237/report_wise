import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class DashboardStatusBar extends StatelessWidget {
  final String statusLabel;
  final String deadlineLabel;
  const DashboardStatusBar({super.key, this.statusLabel = 'In Session: Sequence 2 Evaluation', this.deadlineLabel = 'General Assembly: Friday, 10th Oct'});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SCHOOL STATUS',
                    style: TextStyle(fontFamily: 'Lexend', fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.6), letterSpacing: 1.2)),
                const SizedBox(height: 6),
                Row(children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF69F0AE), shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Flexible(child: Text(statusLabel, style: const TextStyle(fontFamily: 'Manrope', fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white))),
                ]),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white.withOpacity(0.15), margin: const EdgeInsets.symmetric(horizontal: 20)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('UPCOMING DEADLINE',
                    style: TextStyle(fontFamily: 'Lexend', fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.6), letterSpacing: 1.2)),
                const SizedBox(height: 6),
                Text(deadlineLabel, style: const TextStyle(fontFamily: 'Manrope', fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Text('System Health', style: TextStyle(fontFamily: 'Lexend', fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(width: 8),
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF69F0AE), shape: BoxShape.circle)),
            ]),
          ),
        ],
      ),
    );
  }
}
