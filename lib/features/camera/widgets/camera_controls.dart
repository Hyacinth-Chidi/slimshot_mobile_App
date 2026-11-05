import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_fonts.dart';
import '../../../core/theme/lucide_icons.dart';
import '../logic/camera_controller.dart';
import '../logic/camera_geometry.dart';

/// The camera's picture, covering [screen]: the texture laid out in the
/// shape it is shown in and turned or mirrored as [previewTurns] says.
class CameraPreviewTexture extends StatelessWidget {
  const CameraPreviewTexture({super.key, required this.info, required this.screen});

  final CameraInfo info;
  final Size screen;

  @override
  Widget build(BuildContext context) {
    final width = info.previewWidth;
    final height = info.previewHeight;
    if (width == null || height == null) return const SizedBox.shrink();
    final shown = displayedPreviewSize(width, height, info.rotation);
    final turns = previewTurns(
      cameraTransform: info.cameraTransform,
      rotation: info.rotation,
      mirrored: info.mirrored,
      displayRotation: info.displayRotation,
    );
    Widget picture = Texture(textureId: info.textureId);
    if (turns.quarterTurns != 0) picture = RotatedBox(quarterTurns: turns.quarterTurns, child: picture);
    // Mirrored after it is turned, in the screen's own axes.
    if (turns.mirror) picture = Transform.flip(flipX: true, child: picture);
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [Positioned.fromRect(rect: previewCoverRect(shown, screen), child: picture)],
    );
  }
}

/// A round button over the picture: a glyph on smoked black.
class CameraRoundButton extends StatelessWidget {
  const CameraRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 40,
    this.chosen = false,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;

  /// White on purple: the app's chosen state (the flash on).
  final bool chosen;

  /// A letter in the corner: the flash's A for auto.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: size + 8,
            height: size + 8,
            child: Center(
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chosen ? AppColors.primaryStart : AppColors.background.withValues(alpha: 0.45),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, size: size * 0.45, color: AppColors.textPrimary),
                    if (badge != null)
                      Positioned(
                        right: size * 0.16,
                        bottom: size * 0.14,
                        child: Text(
                          badge!,
                          style: TextStyle(
                            fontFamily: kInterfaceFontFamily,
                            fontSize: size * 0.24,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The shutter: a white ring around a white disc for a photo, a purple disc
/// for a video, and a white square — stop — while recording, the ring then
/// purple.
class CameraShutter extends StatelessWidget {
  const CameraShutter({
    super.key,
    required this.mode,
    required this.recording,
    required this.enabled,
    required this.onTap,
  });

  static const double size = 78;

  final CameraMode mode;
  final RecordingState recording;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isRecording = recording != RecordingState.idle;
    final double inner = isRecording ? 28 : (mode == CameraMode.photo ? 62 : 56);
    final innerColour = isRecording
        ? AppColors.textPrimary
        : (mode == CameraMode.photo ? AppColors.textPrimary.withValues(alpha: 0.92) : AppColors.primaryStart);
    final label = isRecording
        ? 'Stop recording'
        : (mode == CameraMode.photo ? 'Take photo' : 'Start recording');
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        key: const ValueKey('camera_shutter'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.5,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                width: 4,
                color: isRecording ? AppColors.primaryStart : AppColors.textPrimary,
              ),
            ),
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: inner,
              height: inner,
              decoration: BoxDecoration(
                color: innerColour,
                borderRadius: BorderRadius.circular(isRecording ? 7 : inner / 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// PHOTO · VIDEO: the chosen one white over a purple line.
class CameraModeSwitch extends StatelessWidget {
  const CameraModeSwitch({
    super.key,
    required this.mode,
    required this.enabled,
    required this.onSelect,
  });

  final CameraMode mode;
  final bool enabled;
  final ValueChanged<CameraMode> onSelect;

  static const _labels = {CameraMode.photo: 'PHOTO', CameraMode.video: 'VIDEO'};

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in _labels.entries)
          GestureDetector(
            key: ValueKey('camera_mode_${entry.key.name}'),
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => onSelect(entry.key) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.value,
                    style: TextStyle(
                      fontFamily: kInterfaceFontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: entry.key == mode
                          ? AppColors.textPrimary
                          : AppColors.textPrimary.withValues(alpha: 0.55),
                      shadows: [Shadow(color: AppColors.background.withValues(alpha: 0.4), blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: entry.key == mode ? 22 : 0,
                    height: 2,
                    decoration: BoxDecoration(
                      color: AppColors.primaryStart,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A small dark pill over the picture: the running time, the zoom.
class CameraPill extends StatelessWidget {
  const CameraPill({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: kInterfaceFontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The recording's running time, red dot while it records, a pause glyph
/// while it rests.
class CameraRecordingPill extends StatelessWidget {
  const CameraRecordingPill({super.key, required this.milliseconds, required this.paused});

  final int milliseconds;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    return CameraPill(
      key: const ValueKey('camera_recording_time'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (paused)
            const Icon(LucideIcons.pause, size: 12, color: AppColors.textPrimary)
          else
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(formatRecordingTime(milliseconds)),
        ],
      ),
    );
  }
}

/// Where a tap asked the camera to focus: a ring that settles and fades.
class CameraFocusRing extends StatelessWidget {
  const CameraFocusRing({super.key, required this.at});

  final Offset at;

  static const double size = 64;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: at.dx - size / 2,
      top: at.dy - size / 2,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1100),
          builder: (context, t, _) {
            final scale = t < 0.25 ? 1.25 - (t / 0.25) * 0.25 : 1.0;
            final opacity = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
            return Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.textPrimary, width: 1.5),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
