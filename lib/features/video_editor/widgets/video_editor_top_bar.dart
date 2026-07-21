import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';

class VideoEditorTopBar extends StatelessWidget {
  const VideoEditorTopBar({
    super.key,
    required this.title,
    required this.durationLabel,
    required this.isExporting,
    required this.hasSourceVideo,
    required this.onExport,
    required this.currentResolutionLabel,
    required this.onResolutionTap,
    required this.resolutionButtonKey,
    required this.onBack,
  });

  final String title;
  final String durationLabel;
  final bool isExporting;
  final bool hasSourceVideo;
  final VoidCallback onExport;
  final String currentResolutionLabel;
  final VoidCallback onResolutionTap;
  final GlobalKey resolutionButtonKey;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                GestureDetector(
                  onTap: onBack,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                    ),
                    child: const Icon(
                      LucideIcons.arrowLeft,
                      color: AppColors.textPrimary,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '| $durationLabel',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          if (hasSourceVideo)
            Row(
              children: [
                if (!isExporting) ...[
                  GestureDetector(
                    key: resolutionButtonKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: onResolutionTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                      child: Row(
                        children: [
                          Text(
                            currentResolutionLabel,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(LucideIcons.chevronDown, color: AppColors.textSecondary, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                isExporting
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primaryStart,
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: onExport,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primaryStart, AppColors.primaryEnd],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Export',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(LucideIcons.chevronRight, color: Colors.white, size: 18),
                            ],
                          ),
                        ),
                      ),
              ],
            ),
        ],
      ),
    );
  }
}
