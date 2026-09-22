import 'package:flutter/material.dart';
import '../../../../core/theme/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';

class VolumePanel extends StatelessWidget {
  const VolumePanel({
    super.key,
    required this.displayVolume,
    required this.onChanged,
    this.onChangeStart,
    this.emptyMessage,
  });

  final double displayVolume;
  final ValueChanged<double> onChanged;

  /// Fired once when a drag begins, so the caller takes **one** undo snapshot
  /// for the whole drag — the rule every gesture here follows, and the one the
  /// video-overlay volume path was missing: it wrote through
  /// `updateVideoOverlay` per frame, which snapshots the editor state each
  /// time, so Undo walked a drag back a pixel at a time.
  final VoidCallback? onChangeStart;

  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (emptyMessage != null) {
      return Center(
        child: Text(
          emptyMessage!,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(
              displayVolume == 0 ? LucideIcons.volumeX : LucideIcons.volume2,
              color: AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SliderTheme(
                data: const SliderThemeData(
                  activeTrackColor: AppColors.primaryStart,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: AppColors.textPrimary,
                  trackHeight: 4,
                ),
                child: Slider(
                  value: displayVolume,
                  min: 0.0,
                  max: 1.0,
                  onChangeStart:
                      onChangeStart == null ? null : (_) => onChangeStart!(),
                  onChanged: onChanged,
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              // Wide enough for "100%", matching the opacity panel beside it.
              width: 38,
              child: Text(
                // **A percentage, like every other level in the editor.** This
                // read 0-10 while Opacity — the adjacent tool, over the same
                // 0..1 model — read 0-100%, so the same drag showed two
                // different numbers depending on which tool was open.
                '${(displayVolume * 100).round()}%',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
