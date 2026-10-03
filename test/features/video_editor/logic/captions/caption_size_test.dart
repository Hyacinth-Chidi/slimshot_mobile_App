import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/overlay_keyframes.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_grouping.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_placement.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_preset_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

import '../../../../support/test_fonts.dart';

/// A caption's size is its Size — its letters, as a fraction of the frame —
/// and a set's Size is the set's.
void main() {
  const canvas = Size(360, 640);
  const drafts = [
    CaptionDraft(
      text: 'Hello there',
      start: Duration(milliseconds: 1000),
      end: Duration(milliseconds: 2000),
      words: [
        CaptionWord(textStart: 0, textEnd: 5, start: Duration.zero, end: Duration(milliseconds: 300)),
      ],
    ),
    CaptionDraft(
      text: 'Bye',
      start: Duration(milliseconds: 2000),
      end: Duration(milliseconds: 2600),
      words: [
        CaptionWord(textStart: 0, textEnd: 3, start: Duration.zero, end: Duration(milliseconds: 200)),
      ],
    ),
  ];

  final plain = TextOverlayModel(id: 'title', text: 'Title', fontSize: 120);

  VideoEditorNotifier withSet({double? size}) {
    final made = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(textOverlays: [plain])
      ..placeCaptions(
        drafts,
        const CaptionSettings(setId: 's'),
        canvasSize: canvas,
        fontSize: size ?? kCaptionTextSize,
      );
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        textOverlays: made.state.textOverlays,
        captionSettings: made.state.captionSettings,
      );
  }

  List<TextOverlayModel> captionsOf(VideoEditorNotifier n) =>
      n.state.textOverlays.where((t) => t.isCaption).toList();

  group('a new set', () {
    test('is Size 100 at scale 1, wrapping at 86% of the frame', () {
      final c = buildCaptionOverlays(
        drafts: drafts,
        setId: 's',
        lane: 0,
        canvasSize: canvas,
      ).first;
      expect(c.fontSize, kCaptionTextSize);
      expect(c.scale, 1);
      expect(c.boxWidth, closeTo(canvas.width * kCaptionWidthFraction, 1e-9));
      // The letters a tenth of the frame.
      expect(
        TextOverlayLayout.measure(c, canvas).inkScale * kTextOverlayFontSize,
        closeTo(canvas.shortestSide / 10, 1e-9),
      );
    });

    test('at a bigger Size it re-wraps inside the frame rather than run off it', () {
      final c = buildCaptionOverlays(
        drafts: const [
          CaptionDraft(
            text: 'extraordinary people are wonderful together',
            start: Duration.zero,
            end: Duration(seconds: 2),
            words: [],
          ),
        ],
        setId: 's',
        lane: 0,
        canvasSize: canvas,
        fontSize: 200,
      ).single.copyWith(fontFamily: kTestFontFamily);
      final layout = TextOverlayLayout.measure(c, canvas);
      expect(layout.boxSize.width * c.scale,
          lessThanOrEqualTo(canvas.width * kCaptionWidthFraction + 0.5));
    });
  });

  group('a regeneration', () {
    test("keeps the set's Size", () {
      final n = withSet(size: 140);
      expect(captionStyleForNewSet(n.state.textOverlays).fontSize, 140);
    });

    test("a project's first set is Size 100", () {
      expect(captionStyleForNewSet([plain]).fontSize, kCaptionTextSize);
    });

    test('places the new set at that Size', () {
      expect(captionsOf(withSet(size: 140)).map((c) => c.fontSize), everyElement(140));
    });
  });

  group('Size on one caption', () {
    test('reaches its set, in the same undo step', () {
      final n = withSet();
      final first = captionsOf(n).first;
      n.updateTextOverlay(first.id, (c) => c.copyWith(fontSize: 150));
      expect(captionsOf(n).map((c) => c.fontSize), everyElement(150));
      expect(n.state.textOverlays.firstWhere((t) => t.id == 'title').fontSize, 120);
      n.undo();
      expect(captionsOf(n).map((c) => c.fontSize), everyElement(kCaptionTextSize));
      expect(n.state.canUndo, isFalse);
    });

    test('stays on the caption it was made on with Apply to all off', () {
      final n = withSet()..setCaptionLookToAll(false);
      final first = captionsOf(n).first;
      n.updateTextOverlay(first.id, (c) => c.copyWith(fontSize: 150));
      expect(captionsOf(n).map((c) => c.fontSize), [150, kCaptionTextSize]);
    });
  });

  group('a set saved before Sizes', () {
    // How a caption was made then: its size in its scale (a tenth of the
    // width over the old 32 px letters), its wrap width divided by that.
    const oldScale = 360 * 0.10 / 32;
    TextOverlayModel legacy({OverlayKeyframes keyframes = OverlayKeyframes.none}) =>
        TextOverlayModel(
          id: 'old',
          text: 'Hello there my friend',
          fontFamily: kTestFontFamily,
          referenceCanvasSize: canvas,
          position: const Offset(0, 172.8),
          scale: oldScale,
          boxWidth: 360 * kCaptionWidthFraction / oldScale,
          backgroundColor: Colors.black,
          backgroundPadding: 10,
          strokeColor: Colors.black,
          strokeWidth: 4,
          captionSetId: 's',
          keyframes: keyframes,
        );

    test('reads as Size 100, and nothing on the canvas moves by a pixel', () {
      final old = legacy();
      final now = migrateLegacyCaptionSize(old);
      expect(now.fontSize, closeTo(kCaptionTextSize, 1e-9));
      expect(now.scale, 1);
      expect(now.position, old.position);

      final a = TextOverlayLayout.measure(old, canvas);
      final b = TextOverlayLayout.measure(now, canvas);
      // The old box was drawn scaled by its scale; the new one is drawn at 1.
      expect(b.boxSize.width, closeTo(a.boxSize.width * oldScale, 1e-6));
      expect(b.inkScale, closeTo(a.inkScale * oldScale, 1e-9));
      expect(b.outerPadding, closeTo(a.outerPadding * oldScale, 1e-9));
      expect(b.backgroundPaddingH, closeTo(a.backgroundPaddingH * oldScale, 1e-9));
      // The same line breaks: the text engine rounds each line's height at a
      // given font size, so heights at two sizes agree only to within about a
      // pixel a line — where a line break moving would be off by a whole line.
      expect(b.boxSize.height, closeTo(a.boxSize.height * oldScale, a.boxSize.height * oldScale * 0.02));
      expect(b.backgroundRect.width,
          closeTo(a.backgroundRect.width * oldScale, a.backgroundRect.width * oldScale * 0.02));
    });

    test('leaves alone what it cannot convert exactly', () {
      final words = TextOverlayModel(id: 't', text: 'Title', scale: 2, referenceCanvasSize: canvas);
      expect(migrateLegacyCaptionSize(words), same(words));
      final sized = legacy().copyWith(fontSize: 100);
      expect(migrateLegacyCaptionSize(sized), same(sized));
      final unanchored = TextOverlayModel(id: 'c', text: 'Hi', scale: 1.1, captionSetId: 's');
      expect(migrateLegacyCaptionSize(unanchored), same(unanchored));
      // A zoom keyframed in its scale cannot be folded into one Size.
      final zooming = legacy(
        keyframes: const OverlayKeyframes({
          OverlayProperty.scale: [
            Keyframe(progress: 0, value: 1.2),
            Keyframe(progress: 1, value: 1.8),
          ],
        }),
      );
      expect(migrateLegacyCaptionSize(zooming), same(zooming));
    });

    test('a draft opens converted', () async {
      final draft = DraftProject(
        id: 'd1',
        sourceVideoPath: '/v.mp4',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        durationSeconds: 30,
        assets: [
          const MediaAsset(
            id: 'a',
            path: '/v.mp4',
            type: MediaAssetType.video,
            durationSeconds: 30,
            width: 1080,
            height: 1920,
            hasAudio: true,
          ).toJson(),
        ],
        segments: [
          VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5).toJson(),
        ],
        textOverlays: [legacy().toJson(), plain.toJson()],
        imageOverlays: const [],
        videoOverlays: const [],
        audioTracks: const [],
        selectedRatioName: 'ratio9x16',
        customCropRect: const [0, 0, 1, 1],
        videoScale: 1,
        videoPanX: 0,
        videoPanY: 0,
        filterIntensity: 1,
        backgroundType: 'black',
        backgroundColorValue: 0xFF000000,
        backgroundBlurIntensity: 20,
        isMuted: false,
      );
      final n = VideoEditorNotifier(VideoEditorService());
      await n.loadDraft(draft, rerenderMissingProxies: false);
      final caption = n.state.textOverlays.firstWhere((t) => t.isCaption);
      expect(caption.fontSize, closeTo(kCaptionTextSize, 1e-6));
      expect(caption.scale, 1);
      expect(n.state.textOverlays.firstWhere((t) => t.id == 'title').fontSize, 120);
    });
  });
}
