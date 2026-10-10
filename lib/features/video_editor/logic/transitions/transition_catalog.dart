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
  dissolve('Dissolve', 'fade', LucideIcons.infinity, TransitionCategory.basic),
  fadeToBlack('Fade Black', 'fadeblack', LucideIcons.moon, TransitionCategory.basic),
  fadeToWhite('Fade White', 'fadewhite', LucideIcons.sun, TransitionCategory.basic),
  slide('Slide', 'slideleft', LucideIcons.arrowRightFromLine, TransitionCategory.motion),
  push('Push', 'pushleft', LucideIcons.arrowRightSquare, TransitionCategory.motion),
  wipe('Wipe', 'wipeleft', LucideIcons.removeFormatting, TransitionCategory.basic),
  smoothLeft('Smooth L', 'smoothleft', LucideIcons.arrowLeft, TransitionCategory.basic),
  smoothRight('Smooth R', 'smoothright', LucideIcons.arrowRight, TransitionCategory.basic),
  smoothUp('Smooth U', 'smoothup', LucideIcons.arrowUp, TransitionCategory.basic),
  smoothDown('Smooth D', 'smoothdown', LucideIcons.arrowDown, TransitionCategory.basic),
  zoomIn('Zoom In', 'zoomin', LucideIcons.zoomIn, TransitionCategory.motion),

  /// CrossZoom from gl-transitions.com, the first *layered* transition: the
  /// engine draws each clip once into a layer and the transition reads only
  /// the layers (`TransitionShaders.isLayered`). The tutorial's zoom blur.
  zoomBlur('Zoom Blur', 'zoomin', LucideIcons.focus, TransitionCategory.blur),

  // Part 2a — every one layered, ported from gl-transitions.com (MIT) or our
  // own, in `LayeredTransitions.kt`. The xfade names are nearest neighbours
  // for the record only; export is native and draws the shader itself.
  slideScaleLeft('Slide & Scale L', 'slideleft', LucideIcons.arrowLeft, TransitionCategory.motion),
  slideScaleRight('Slide & Scale R', 'slideright', LucideIcons.arrowRight, TransitionCategory.motion),
  slideScaleUp('Slide & Scale U', 'slideup', LucideIcons.arrowUp, TransitionCategory.motion),
  slideScaleDown('Slide & Scale D', 'slidedown', LucideIcons.arrowDown, TransitionCategory.motion),
  splitIn('Split In', 'vertclose', LucideIcons.foldHorizontal, TransitionCategory.motion),
  splitOut('Split Out', 'vertopen', LucideIcons.unfoldHorizontal, TransitionCategory.motion),
  bounce('Bounce', 'slidedown', LucideIcons.arrowUpDown, TransitionCategory.motion),
  swirl('Swirl', 'radial', LucideIcons.tornado, TransitionCategory.motion),
  spinAway('Spin Away', 'radial', LucideIcons.rotateCw, TransitionCategory.motion),
  zoomInOut('Zoom In-Out', 'zoomin', LucideIcons.scaling, TransitionCategory.motion),
  whipPan('Whip Pan', 'slideleft', LucideIcons.wind, TransitionCategory.motion),
  shake('Shake', 'fade', LucideIcons.vibrate, TransitionCategory.motion),
  zoomBounce('Zoom Bounce', 'zoomin', LucideIcons.maximize2, TransitionCategory.motion),
  dreamyZoom('Dreamy Zoom', 'zoomin', LucideIcons.sparkles, TransitionCategory.blur),
  motionBlur('Motion Blur', 'hblur', LucideIcons.moveHorizontal, TransitionCategory.blur),
  defocus('Defocus', 'fade', LucideIcons.aperture, TransitionCategory.blur);

  const EditorTransition(this.label, this.ffmpegXfadeName, this.icon, this.category);

  /// Human-readable name shown in the transitions drawer.
  final String label;

  /// The matching FFmpeg `xfade=transition=` value used by the export path.
  final String ffmpegXfadeName;

  /// Icon shown in the transitions drawer grid.
  final IconData icon;

  /// Which pill of the transitions sheet lists it.
  final TransitionCategory category;

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

/// The pills of the transitions sheet, in the order they are shown.
///
/// Light, Glitch and 3D are declared before they hold anything so the order is
/// fixed now; [offeredTransitionCategories] leaves out an empty one, so the
/// sheet never shows a pill that opens on nothing.
enum TransitionCategory {
  basic('Basic'),
  motion('Motion'),
  blur('Blur'),
  light('Light'),
  glitch('Glitch'),
  threeD('3D');

  const TransitionCategory(this.label);

  final String label;
}

/// [category]'s transitions, in catalog order.
List<EditorTransition> transitionsIn(TransitionCategory category) => [
      for (final transition in EditorTransition.values)
        if (transition.category == category) transition,
    ];

/// The categories the sheet shows: every one that holds a transition.
List<TransitionCategory> offeredTransitionCategories() => [
      for (final category in TransitionCategory.values)
        if (transitionsIn(category).isNotEmpty) category,
    ];

/// The category the sheet opens on for a seam carrying [transitionName] —
/// Basic for none, or for a name this build no longer knows.
TransitionCategory categoryForTransition(String? transitionName) =>
    EditorTransition.fromName(transitionName)?.category ??
    TransitionCategory.basic;

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
