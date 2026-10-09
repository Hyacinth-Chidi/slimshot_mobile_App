import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/mask/clip_mask.dart';
import '../providers/video_editor_notifier.dart';

/// The mask gesture inside an overlay's box, shared by the photo and video
/// layers so the two cannot place a window differently.
///
/// The layers' detectors sit inside the overlay's own transforms, so a
/// gesture's **local** focal point is already in the box's own axes — turned
/// and scaled with the overlay. A drag across a turned overlay therefore moves
/// the window along the overlay's x and y, which is what the window is
/// authored in, with no rotation arithmetic here. The rest is the clip's own
/// rule: [maskAfterGesture], anchor-based, one undo snapshot per gesture.
class OverlayMaskGesture {
  ClipMask? _start;
  Offset _focalStart = Offset.zero;

  /// Whether this gesture has turned the window — when the readout shows.
  bool twisting = false;

  bool get active => _start != null;

  void begin(WidgetRef ref, ClipMask mask, ScaleStartDetails details) {
    _start = mask;
    _focalStart = details.localFocalPoint;
    twisting = false;
    // One undo step for the whole gesture.
    ref.read(videoEditorProvider.notifier).saveStateForUndo();
  }

  /// [box] is the overlay's box in the detector's own (unscaled) pixels.
  void update(WidgetRef ref, ScaleUpdateDetails details, Size box) {
    final start = _start;
    if (start == null || box.width <= 0 || box.height <= 0) return;
    final moved = details.localFocalPoint - _focalStart;
    if (details.rotation.abs() >= kMaskTwistRadians) twisting = true;
    final next = maskAfterGesture(
      start,
      pan: Offset(moved.dx / box.width, moved.dy / box.height),
      scale: details.scale,
      rotationRadians: details.rotation,
    );
    ref.read(videoEditorProvider.notifier).setMaskOnSelection(next, takeUndoSnapshot: false);
  }

  /// Ends the gesture; true when the readout was showing and must go.
  bool end() {
    _start = null;
    final wasTwisting = twisting;
    twisting = false;
    return wasTwisting;
  }
}
