import 'package:flutter/material.dart';
import '../../../../core/theme/lucide_icons.dart';

/// The single source of truth for every transition SlimShot supports.
///
/// Preview (native GL shaders), export (FFmpeg `xfade`), the transitions
/// drawer, and the timeline composer all read this list. Adding a transition
/// means adding one entry here plus one shader in `TransitionShaders.kt` —
/// nothing else should carry its own copy of the list.
///
/// [name] is the persisted identifier. It is written into `VideoSegment.
/// transitionType`, into saved drafts, and across the platform channel, so
/// these names must not be renamed without a draft migration.
enum EditorTransition {
  dissolve('Dissolve', 'fade', LucideIcons.infinity),
  fadeToBlack('Fade Black', 'fadeblack', LucideIcons.moon),
  fadeToWhite('Fade White', 'fadewhite', LucideIcons.sun),
  slide('Slide', 'slideleft', LucideIcons.arrowRightFromLine),
  push('Push', 'pushleft', LucideIcons.arrowRightSquare),
  wipe('Wipe', 'wipeleft', LucideIcons.removeFormatting),
  smoothLeft('Smooth L', 'smoothleft', LucideIcons.arrowLeft),
  smoothRight('Smooth R', 'smoothright', LucideIcons.arrowRight),
  smoothUp('Smooth U', 'smoothup', LucideIcons.arrowUp),
  smoothDown('Smooth D', 'smoothdown', LucideIcons.arrowDown),
  zoomIn('Zoom In', 'zoomin', LucideIcons.zoomIn);

  const EditorTransition(this.label, this.ffmpegXfadeName, this.icon);

  /// Human-readable name shown in the transitions drawer.
  final String label;

  /// The matching FFmpeg `xfade=transition=` value used by the export path.
  final String ffmpegXfadeName;

  /// Icon shown in the transitions drawer grid.
  final IconData icon;

  /// Resolves a persisted identifier back to a transition.
  ///
  /// Returns `null` for `null`, for the explicit "None" choice, and for any
  /// identifier this build no longer supports (drafts saved by an older
  /// version may still name `circleOpen`, `circleClose` or `radial`). Callers
  /// treat `null` as a hard cut, so retired transitions degrade to a cut
  /// instead of throwing.
  static EditorTransition? fromName(String? name) {
    if (name == null) return null;
    for (final transition in values) {
      if (transition.name == name) return transition;
    }
    return null;
  }

  static bool isSupported(String? name) => fromName(name) != null;
}

/// Duration a transition gets when the user first applies one.
const double kDefaultTransitionSeconds = 0.8;

/// Bounds of the duration slider in the transitions drawer.
const double kMinTransitionSeconds = 0.2;
const double kMaxTransitionSeconds = 2.0;

/// Hard floor used when clamping against short clips, below the slider minimum
/// so that very short clips still get *some* blend rather than a hard cut.
const double _kAbsoluteMinTransitionSeconds = 0.05;

/// Share of the shorter neighbouring clip a transition may occupy.
///
/// A transition overlaps both clips, so it must stay well under the shorter
/// one or that clip would be entirely consumed by the blend.
const double _kMaxClipShare = 0.45;

/// Clamps a requested transition duration against the clips it joins.
///
/// This is the only implementation. Preview, export, and the timeline composer
/// must all agree on the resulting duration or the preview playhead and the
/// exported file drift apart.
double resolveTransitionDuration({
  required double requestedSeconds,
  required double leftClipDuration,
  required double rightClipDuration,
}) {
  final shorterClip =
      leftClipDuration < rightClipDuration ? leftClipDuration : rightClipDuration;
  final maxSeconds = (shorterClip * _kMaxClipShare) < _kAbsoluteMinTransitionSeconds
      ? _kAbsoluteMinTransitionSeconds
      : shorterClip * _kMaxClipShare;

  return requestedSeconds
      .clamp(_kAbsoluteMinTransitionSeconds, maxSeconds)
      .toDouble();
}
