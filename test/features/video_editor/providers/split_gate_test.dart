import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Whether the Split tool shows, and whether the split it offers succeeds.
///
/// The gate (`isSplitToolEnabledProvider`) used to answer with a rule of its
/// own, and it was wrong twice, both demonstrated before this was written:
///
/// - **Clips.** It compared the playhead — a *timeline* instant — against the
///   selected clip's *source* range. Those coincide only for a clip whose
///   source happens to start where it sits on the timeline, so a later clip
///   from another file hid its Split mid-clip.
/// - **Video overlays.** It required `isClipSelected`, which selecting an
///   overlay clears, so the overlay menu's Split had never shown at all.
///
/// Now every branch asks the same function its split cuts with, and the
/// sweeps below fail the moment a button and its action disagree.
void main() {
  bool splitOffered(VideoEditorNotifier n) {
    final container = ProviderContainer(
      overrides: [videoEditorProvider.overrideWith((ref) => n)],
    );
    addTearDown(container.dispose);
    return container.listen(isSplitToolEnabledProvider, (_, _) {}).read();
  }

  group('the Split tool on clips', () {
    /// Clip a: its file's 0–5s, on the timeline at 0–5. Clip b: **another**
    /// file's 0–8s, on the timeline at 5–13 — so b's source range and its
    /// timeline range do not coincide, which is the case the old rule got
    /// wrong.
    VideoEditorNotifier twoClips({required double playhead, bool select = true}) {
      final n = VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          segments: [
            VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 5),
            VideoSegment(id: 'b', sourceStart: 0, sourceEnd: 8),
          ],
        );
      if (select) n.selectSegment('b');
      n.state = n.state.copyWith(currentPlaybackPosition: playhead);
      return n;
    }

    test('is offered mid-clip on a later clip from another file', () {
      // 4s into clip b. The old gate asked whether 9.0 lay inside b's
      // *source* range, 0–8, and hid the tool.
      expect(splitOffered(twoClips(playhead: 9.0)), isTrue);
    });

    test('is withheld within the minimum of a seam or the end', () {
      expect(splitOffered(twoClips(playhead: 4.9)), isFalse);
      expect(splitOffered(twoClips(playhead: 5.1)), isFalse);
      expect(splitOffered(twoClips(playhead: 12.9)), isFalse);
    });

    test('is withheld with no clip selected', () {
      // Split is a clip-menu tool; with nothing selected it is not offered.
      expect(splitOffered(twoClips(playhead: 2.5, select: false)), isFalse);
    });

    test('is offered exactly where the blade cuts', () {
      for (final playhead in [
        0.1, 0.2, 2.5, 4.8, 4.9, 5.0, 5.1, 5.2, 9.0, 12.8, 12.9, 13.0, 14.0,
      ]) {
        final offered = splitOffered(twoClips(playhead: playhead));
        var cut = true;
        try {
          twoClips(playhead: playhead).splitAtPlayhead(playhead);
        } on Exception {
          cut = false;
        }
        expect(offered, cut, reason: 'at ${playhead}s');
      }
    });
  });

  VideoOverlayModel overlay({double speed = 1.0}) => VideoOverlayModel(
        id: 'v1',
        videoPath: '/v.mp4',
        timelineStart: const Duration(seconds: 2),
        timelineEnd: const Duration(seconds: 8),
        sourceStart: 1.0,
        sourceEnd: 13.0,
        speed: speed,
        animationIn: 'fade_in',
        animationOut: 'fade_out',
      );

  VideoEditorNotifier overlaySelected({
    double playhead = 5.0,
    double speed = 1.0,
  }) {
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: [VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 10)],
        videoOverlays: [overlay(speed: speed)],
      );
    n.selectVideoOverlay('v1');
    n.state = n.state.copyWith(currentPlaybackPosition: playhead);
    return n;
  }

  group('the Split tool on a video overlay', () {
    test('is offered while the playhead is inside the overlay', () {
      // It had never shown: the gate required a selected *clip*.
      expect(splitOffered(overlaySelected()), isTrue);
    });

    test('is offered exactly where the overlay split succeeds', () {
      for (final playhead in [
        1.0, 2.0, 2.1, 2.2, 5.0, 7.8, 7.9, 8.0, 9.0,
      ]) {
        final offered = splitOffered(overlaySelected(playhead: playhead));
        var cut = true;
        try {
          overlaySelected(playhead: playhead).splitVideoOverlay(playhead);
        } on Exception {
          cut = false;
        }
        expect(offered, cut, reason: 'at ${playhead}s');
      }
    });
  });

  group('splitting a video overlay', () {
    test('the entrance stays on the left half and the exit on the right', () {
      // Unreachable until now, and wrong: both halves kept both animations,
      // so the overlay would exit before the cut and enter again after it.
      final n = overlaySelected();
      n.splitVideoOverlay(5.0);

      final left = n.state.videoOverlays.firstWhere((v) => v.id == 'v1');
      final right = n.state.videoOverlays.firstWhere((v) => v.id != 'v1');
      expect(left.animationIn, 'fade_in');
      expect(left.animationOut, isNull);
      expect(right.animationIn, isNull);
      expect(right.animationOut, 'fade_out');
    });

    test('the source is cut where the engine plays, at the overlay\'s speed', () {
      // The engine maps timeline to source as sourceStart + offset × speed
      // (NativeTimelineOverlay.sourceAt). The split cut at the bare offset,
      // so at 2× the right half started three seconds early in the footage.
      final n = overlaySelected(speed: 2.0);
      n.splitVideoOverlay(5.0);

      final left = n.state.videoOverlays.firstWhere((v) => v.id == 'v1');
      final right = n.state.videoOverlays.firstWhere((v) => v.id != 'v1');
      // 3s into the overlay at 2× is 6s into its source, which starts at 1.
      expect(left.sourceEnd, closeTo(7.0, 1e-9));
      expect(right.sourceStart, closeTo(7.0, 1e-9));
      expect(left.timelineEnd, const Duration(seconds: 5));
      expect(right.timelineStart, const Duration(seconds: 5));
      expect(right.sourceEnd, 13.0);
    });

    test('refuses a sliver, leaving no undo entry', () {
      final n = overlaySelected(playhead: 2.1);
      expect(() => n.splitVideoOverlay(2.1), throwsException);
      expect(n.state.videoOverlays, hasLength(1));
      expect(n.state.canUndo, isFalse);
    });

    test('is one undo step', () {
      final n = overlaySelected();
      n.splitVideoOverlay(5.0);
      n.undo();

      expect(n.state.videoOverlays, hasLength(1));
      expect(n.state.videoOverlays.single.timelineEnd, const Duration(seconds: 8));
    });
  });
}
