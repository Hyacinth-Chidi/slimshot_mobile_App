import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A photo as the letterbox background.
///
/// The model half of the feature: the state carries a path and a third
/// background type, the draft persists it, and the timeline contract hands it
/// to the engine — which samples the photo wherever it used to paint the
/// colour, so preview and export agree by construction. The shader half is
/// GLSL and only a device can prove it.
void main() {
  VideoEditorNotifier notifierWith({String? draftId}) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(draftId: draftId);
  }

  group('the state', () {
    test('a photo is the third background type, kept as one undo step', () {
      final n = notifierWith();
      n.setBackgroundImage('/p/bg.jpg');

      expect(n.state.backgroundType, EditorBackgroundType.image);
      expect(n.state.backgroundImagePath, '/p/bg.jpg');

      n.undo();
      expect(n.state.backgroundType, EditorBackgroundType.black);
      expect(n.state.backgroundImagePath, isNull);
    });

    test('picking a colour keeps the photo for later', () {
      // Switching to a colour is not forgetting the photo: the tile still
      // shows it, and tapping it again uses it without another pick.
      final n = notifierWith();
      n.setBackgroundImage('/p/bg.jpg');
      n.setBackground(Colors.white);

      expect(n.state.backgroundType, EditorBackgroundType.color);
      expect(n.state.backgroundImagePath, '/p/bg.jpg');

      n.useBackgroundImage();
      expect(n.state.backgroundType, EditorBackgroundType.image);
    });

    test('using the photo with none chosen does nothing', () {
      final n = notifierWith();
      n.useBackgroundImage();
      expect(n.state.backgroundType, EditorBackgroundType.black);
      expect(n.state.canUndo, isFalse);
    });
  });

  group('importing a picked file', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('bg_test_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('copies it into the project\'s folder and uses it', () async {
      // The picker hands back a cache path the OS may reclaim; the project
      // keeps its own copy, named by draft and time like a cover is, so a
      // replaced photo never shows stale pixels through an image cache.
      final source = File('${tmp.path}/picked.png')..writeAsBytesSync([1, 2, 3]);
      final n = notifierWith(draftId: 'd1');

      final ok = await n.importBackgroundImage(source.path, destinationDir: tmp);

      expect(ok, isTrue);
      final path = n.state.backgroundImagePath!;
      expect(path, isNot(source.path));
      expect(path, contains('bg_d1_'));
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
      expect(n.state.backgroundType, EditorBackgroundType.image);
    });

    test('replacing a photo deletes the project\'s previous copy', () async {
      final n = notifierWith(draftId: 'd1');
      final first = File('${tmp.path}/a.png')..writeAsBytesSync([1]);
      final second = File('${tmp.path}/b.png')..writeAsBytesSync([2]);

      await n.importBackgroundImage(first.path, destinationDir: tmp);
      final firstCopy = n.state.backgroundImagePath!;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await n.importBackgroundImage(second.path, destinationDir: tmp);

      expect(n.state.backgroundImagePath, isNot(firstCopy));
      // Deletion is fire-and-forget; give it a turn.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(File(firstCopy).existsSync(), isFalse);
    });

    test('without a draft there is nowhere to keep it', () async {
      final n = notifierWith();
      final source = File('${tmp.path}/picked.png')..writeAsBytesSync([1]);
      expect(await n.importBackgroundImage(source.path, destinationDir: tmp),
          isFalse);
      expect(n.state.backgroundImagePath, isNull);
    });
  });

  group('the draft', () {
    test('round-trips the path, and omits it when there is none', () {
      DraftProject draft({String? path}) => DraftProject(
            id: 'd',
            sourceVideoPath: '/v.mp4',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            durationSeconds: 1,
            segments: const [],
            textOverlays: const [],
            imageOverlays: const [],
            videoOverlays: const [],
            audioTracks: const [],
            selectedRatioName: 'ratio9x16',
            customCropRect: const [0, 0, 1, 1],
            videoScale: 1,
            videoPanX: 0,
            videoPanY: 0,
            filterIntensity: 1,
            backgroundType: 'image',
            backgroundColorValue: 0xFF000000,
            backgroundBlurIntensity: 20,
            backgroundImagePath: path,
            isMuted: false,
          );

      final withPath = draft(path: '/p/bg.jpg').toJson();
      expect(withPath['backgroundImagePath'], '/p/bg.jpg');
      expect(DraftProject.fromJson(withPath).backgroundImagePath, '/p/bg.jpg');

      final without = draft().toJson();
      expect(without.containsKey('backgroundImagePath'), isFalse);
      expect(DraftProject.fromJson(without).backgroundImagePath, isNull);
    });
  });

  group('the timeline contract', () {
    const composer = VideoEditorTimelineComposer();
    VideoEditorState stateWith(EditorBackgroundType type, String? path) {
      return VideoEditorState(
        assets: const [
          MediaAsset(
            id: 'a',
            path: '/v.mp4',
            type: MediaAssetType.video,
            durationSeconds: 10,
            width: 1080,
            height: 1920,
            hasAudio: true,
          ),
        ],
        segments: [VideoSegment(id: 's', assetId: 'a', sourceStart: 0, sourceEnd: 4)],
        backgroundType: type,
        backgroundImagePath: path,
      );
    }

    test('carries the photo to the engine', () {
      final json = composer
          .compose(stateWith(EditorBackgroundType.image, '/p/bg.jpg'))
          .toJson();
      final canvas = json['canvas'] as Map<String, dynamic>;
      expect(canvas['backgroundType'], 'image');
      expect(canvas['backgroundImagePath'], '/p/bg.jpg');
    });

    test('writes nothing new for a project without one', () {
      // The key is absent, not null: a build that predates the feature reads
      // the same payload it always did.
      final json =
          composer.compose(stateWith(EditorBackgroundType.black, null)).toJson();
      final canvas = json['canvas'] as Map<String, dynamic>;
      expect(canvas.containsKey('backgroundImagePath'), isFalse);
    });
  });
}
