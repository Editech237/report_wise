import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer.dart';
import '../../../data/repositories/academic_repository.dart';

class RecentActivityPanel extends StatelessWidget {
  final List<ActivityEvent>? items;
  final bool loading;

  const RecentActivityPanel({super.key, this.items, this.loading = false});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBlock(height: 18, width: 200),
            SizedBox(height: 8),
            ShimmerBlock(height: 12, width: 200),
            SizedBox(height: 20),
            ShimmerBlock(height: 48),
            SizedBox(height: 12),
            ShimmerBlock(height: 48),
            SizedBox(height: 12),
            ShimmerBlock(height: 48),
          ],
        ),
      );
    }

    final list = items ?? const <ActivityEvent>[];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Activity',
              style: TextStyle(fontFamily: 'Manrope', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
          const SizedBox(height: 4),
          Text('Latest school & system updates',
              style: TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.7))),
          const SizedBox(height: 20),
          if (list.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surfaceLow, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  const Icon(Icons.history_rounded, size: 28, color: AppColors.onSurfaceVariant),
                  const SizedBox(height: 6),
                  const Text('No activity yet',
                      style: TextStyle(fontFamily: 'Manrope', fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Enroll students, enter marks or change settings and it will show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Lexend', fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.7))),
                ],
              ),
            )
          else
            ...list.take(5).map((a) => _Tile(item: a)),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final ActivityEvent item;
  const _Tile({required this.item});

  (IconData, Color) get _visual {
    switch (item.kind) {
      case 'enrollment':
        return (Icons.person_add_alt_1_rounded, const Color(0xFF2E7D32));
      case 'mark':
        return (Icons.edit_note_rounded, AppColors.primary);
      case 'config':
        return (Icons.tune_rounded, const Color(0xFFF57F17));
      default:
        return (Icons.notifications_outlined, AppColors.onSurfaceVariant);
    }
  }

  String get _timeAgo {
    final diff = DateTime.now().difference(item.createdAt);
    if (diff.inMinutes < 1) return 'JUST NOW';
    if (diff.inMinutes < 60) return '${diff.inMinutes} MIN AGO';
    if (diff.inHours < 24) return '${diff.inHours} H AGO';
    if (diff.inDays < 7) return '${diff.inDays} D AGO';
    return '${item.createdAt.day}/${item.createdAt.month}/${item.createdAt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _visual;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Lexend', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface, height: 1.4)),
                const SizedBox(height: 3),
                Text(_timeAgo,
                    style: TextStyle(fontFamily: 'Lexend', fontSize: 10.5, color: AppColors.onSurfaceVariant.withOpacity(0.55), letterSpacing: 0.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}