import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/overlay_keyframes.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/editor_timeline.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';

/// Pins the engine's reading of a keyframed overlay to the editor's.
///
/// Three keyframed overlays are composed exactly as the editor sends them, and
/// their placement is resolved in Dart at seven progresses. The Kotlin
/// `OverlayMotionTest` parses the same wire maps with
/// `NativeTimelineOverlay.fromMap` and must land on the same numbers — so the
/// canvas and the file cannot drift apart without a test going red.
///
/// Like the animation fixtures, this catches *divergence tomorrow*, never a
/// wrong curve today: it is generated from the code it pins. After a
/// deliberate change, regenerate both copies with
///
///     UPDATE_OVERLAY_FIXTURE=1 flutter test <this file>
///
/// and run the Kotlin tests again.
void main() {
  const dartPath = 'test/fixtures/overlay_motion_fixture.json';
  const kotlinPath = 'android/app/src/test/resources/overlay_motion_fixture.json';

  test('keyframed overlays on the wire match the committed fixture', () {
    final generated =
        const JsonEncoder.withIndent('  ').convert(_fixture()).trim();

    if (Platform.environment['UPDATE_OVERLAY_FIXTURE'] == '1') {
      File(dartPath).writeAsStringSync('$generated\n');
      File(kotlinPath).writeAsStringSync('$generated\n');
    }

    String read(String path) =>
        File(path).readAsStringSync().replaceAll('\r\n', '\n').trim();
    expect(read(dartPath), generated,
        reason: 'The composer or the resolver changed. If that was meant, '
            'regenerate with UPDATE_OVERLAY_FIXTURE=1 and re-run the Kotlin '
            'tests.');
    expect(read(kotlinPath), generated,
        reason: 'The Kotlin copy has drifted from the Dart one.');
  });
}

/// Where each overlay is sampled: both ends, keyframe instants and the spaces
/// between them.
const _progresses = [0.0, 0.1, 0.25, 0.5, 0.6, 0.9, 1.0];

Map<String, dynamic> _fixture() {
  const canvas = Size(360, 640);

  // Every property moving, on a different curve each.
  const everything = OverlayKeyframes({
    OverlayProperty.x: [
      Keyframe(
        progress: 0,
        value: -60,
        interpolation: KeyframeInterpolation.cubicInOut,
      ),
      Keyframe(progress: 1, value: 90),
    ],
    OverlayProperty.y: [
      Keyframe(
        progress: 0.1,
        value: 40,
        interpolation: KeyframeInterpolation.quadOut,
      ),
      Keyframe(progress: 0.6, value: -120),
    ],
    OverlayProperty.scale: [
      Keyframe(progress: 0, value: 0.5),
      Keyframe(
        progress: 0.5,
        value: 2,
        interpolation: KeyframeInterpolation.bounceOut,
      ),
      Keyframe(progress: 1, value: 1),
    ],
    OverlayProperty.rotation: [
      Keyframe(progress: 0.25, value: -0.4),
      Keyframe(progress: 0.9, value: 1.1),
    ],
    OverlayProperty.opacity: [
      Keyframe(progress: 0, value: 0.2),
      Keyframe(progress: 1, value: 1),
    ],
  });

  // Only some properties keyframed — the rest must stay their bare numbers —
  // and a held segment.
  const partial = OverlayKeyframes({
    OverlayProperty.opacity: [
      Keyframe(
        progress: 0.25,
        value: 1,
        interpolation: KeyframeInterpolation.hold,
      ),
      Keyframe(progress: 0.6, value: 0.3),
    ],
    OverlayProperty.x: [
      Keyframe(progress: 0.5, value: 25),
      Keyframe(progress: 0.9, value: -35),
    ],
  });

  // One keyframe: a value held for the whole span, not the base.
  const single = OverlayKeyframes({
    OverlayProperty.y: [Keyframe(progress: 0.4, value: 80)],
    OverlayProperty.scale: [Keyframe(progress: 0.4, value: 1.75)],
  });

  final state = VideoEditorState(
    imageOverlays: [
      ImageOverlayModel(
        id: 'everything',
        imagePath: '/a.png',
        position: const Offset(10, 20),
        scale: 1.2,
        rotation: 0.1,
        opacity: 0.9,
        startTime: const Duration(milliseconds: 1250),
        endTime: const Duration(milliseconds: 5750),
        keyframes: everything,
      ),
      ImageOverlayModel(
        id: 'single',
        imagePath: '/c.png',
        position: const Offset(-40, 0),
        startTime: Duration.zero,
        endTime: const Duration(seconds: 2),
        laneIndex: 1,
        keyframes: single,
      ),
    ],
    videoOverlays: [
      VideoOverlayModel(
        id: 'partial',
        videoPath: '/b.mp4',
        position: const Offset(-15, 35),
        scale: 0.8,
        rotation: -0.25,
        opacity: 0.7,
        timelineStart: const Duration(seconds: 3),
        timelineEnd: const Duration(milliseconds: 9500),
        sourceStart: 2,
        sourceEnd: 12,
        laneIndex: 2,
        keyframes: partial,
      ),
    ],
  );

  final overlays = const VideoEditorTimelineComposer()
      .composeOverlays(state, previewCanvasSize: canvas);

  Map<String, dynamic> sample(EditorTimelineOverlay o, double p) => {
        'progress': p,
        'centerX': o.centerX.resolveAt(p),
        'centerY': o.centerY.resolveAt(p),
        'scale': o.scale.resolveAt(p),
        'rotation': o.rotation.resolveAt(p),
        'opacity': o.opacity.resolveAt(p),
      };

  return {
    'overlays': [
      for (final o in overlays)
        {
          'wire': o.toJson(),
          'samples': [for (final p in _progresses) sample(o, p)],
        },
    ],
  };
}
