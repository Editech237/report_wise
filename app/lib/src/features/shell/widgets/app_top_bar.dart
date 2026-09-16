import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String? schoolName;
  final VoidCallback? onGenerateReports;
  final VoidCallback? onSearchTap;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onHelpTap;
  final String? schoolLogoUrl;
  final String? userName;
  final VoidCallback? onProfileTap;

  const AppTopBar({
    super.key,
    this.schoolName,
    this.onGenerateReports,
    this.onSearchTap,
    this.onSearchChanged,
    this.onNotificationsTap,
    this.onHelpTap,
    this.schoolLogoUrl,
    this.userName,
    this.onProfileTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Search
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLow,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: AppColors.onSurfaceVariant.withOpacity(0.5),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        onTap: onSearchTap,
                        onChanged: onSearchChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search students, classes, or subjects…',
                          hintStyle: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13,
                            color: AppColors.onSurfaceVariant.withOpacity(0.55),
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Icons
          _IconBtn(
            icon: Icons.notifications_outlined,
            badge: true,
            onTap: onNotificationsTap ?? () {},
          ),
          _IconBtn(icon: Icons.help_outline_rounded, onTap: onHelpTap ?? () {}),

          // CTA — flexible to prevent Row overflow on narrow windows
          Flexible(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 38),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text(
                'Generate Reports (PDF)',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              onPressed:
                  onGenerateReports ??
                  () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Report generation — coming soon'),
                      ),
                    );
                  },
            ),
          ),
          const SizedBox(width: 30),

          // Avatar + name
          InkWell(
            onTap: onProfileTap,
            borderRadius: BorderRadius.circular(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primary.withOpacity(0.10),
                  backgroundImage:
                      schoolLogoUrl == null || schoolLogoUrl!.isEmpty
                      ? null
                      : NetworkImage(schoolLogoUrl!),
                  child: schoolLogoUrl == null || schoolLogoUrl!.isEmpty
                      ? const Icon(
                          Icons.school_rounded,
                          color: AppColors.primary,
                          size: 20,
                        )
                      : null,
                ),
                if (userName != null) ...[
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName!,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        'Administrator',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 10.5,
                          color: AppColors.onSurfaceVariant.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final bool badge;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, this.badge = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(icon, size: 22, color: AppColors.onSurfaceVariant),
          onPressed: onTap,
          splashRadius: 20,
        ),
        if (badge)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.accentRed,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}
