import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/core/services/draft_service.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A caption is an ordinary text that also carries its words' timing.
void main() {
  const words = [
    CaptionWord(
      textStart: 0,
      textEnd: 5,
      start: Duration.zero,
      end: Duration(milliseconds: 320),
    ),
    CaptionWord(
      textStart: 6,
      textEnd: 11,
      start: Duration(milliseconds: 420),
      end: Duration(milliseconds: 800),
    ),
  ];

  group('CaptionWord', () {
    test('round-trips through JSON', () {
      for (final w in words) {
        expect(CaptionWord.fromJson(w.toJson(), 11), w);
      }
    });

    test('offsets are clamped into the text; an end never precedes its start',
        () {
      expect(
        CaptionWord.fromJson(
          {'from': -3, 'to': 99, 'startMs': -50, 'endMs': -80},
          5,
        ),
        const CaptionWord(
          textStart: 0,
          textEnd: 5,
          start: Duration.zero,
          end: Duration.zero,
        ),
      );
    });

    test('an entry with nothing left to place is dropped, never thrown', () {
      expect(
        CaptionWord.fromJson({'from': 7, 'to': 9, 'startMs': 0, 'endMs': 1}, 5),
        isNull,
      );
      expect(
        CaptionWord.fromJson(
          {'from': 'a', 'to': 2, 'startMs': 0, 'endMs': 1},
          5,
        ),
        isNull,
      );
      expect(CaptionWord.fromJson('junk', 5), isNull);
      expect(
        CaptionWord.listFromJson([words.first.toJson(), 'junk', null], 11),
        [words.first],
      );
      expect(CaptionWord.listFromJson('junk', 11), isNull);
    });
  });

  group('a text overlay as a caption', () {
    TextOverlayModel caption() => TextOverlayModel(
          id: 'c',
          text: 'Hello world',
          captionSetId: 'captions_1',
          captionWords: words,
        );

    test('ordinary text writes no caption keys', () {
      final json = TextOverlayModel(id: 't', text: 'hi').toJson();
      expect(json.containsKey('captionSetId'), isFalse);
      expect(json.containsKey('captionWords'), isFalse);
      final back = TextOverlayModel.fromJson(json);
      expect(back.isCaption, isFalse);
      expect(back.captionWords, isNull);
    });

    test('a caption keeps its set and its words through a draft', () {
      final back = TextOverlayModel.fromJson(caption().toJson());
      expect(back.captionSetId, 'captions_1');
      expect(back.captionWords, words);
      expect(back.isCaption, isTrue);
    });

    test('words out of reach of a hand-edited text are dropped on read', () {
      final json = caption().toJson()..['text'] = 'Hello';
      expect(TextOverlayModel.fromJson(json).captionWords, [words.first]);
    });

    test('copyWith keeps the caption; clearCaption drops set and words', () {
      expect(caption().copyWith(text: 'x').captionSetId, 'captions_1');
      final plain = caption().copyWith(clearCaption: true);
      expect(plain.captionSetId, isNull);
      expect(plain.captionWords, isNull);
    });
  });

  group('CaptionSettings', () {
    const settings = CaptionSettings(
      setId: 'captions_1',
      source: CaptionSource.all,
      language: 'yo',
      length: CaptionLength.line,
    );

    test('round-trips, and Auto detect writes no language', () {
      expect(CaptionSettings.fromJson(settings.toJson()), settings);
      const auto = CaptionSettings(setId: 's');
      expect(auto.toJson().containsKey('language'), isFalse);
      expect(CaptionSettings.fromJson(auto.toJson()), auto);
    });

    test('unknown names fall back to the defaults; no set id is no settings',
        () {
      expect(
        CaptionSettings.fromJson(
          {'setId': 's', 'source': 'radio', 'length': 'essay', 'language': 7},
        ),
        const CaptionSettings(setId: 's'),
      );
      expect(CaptionSettings.fromJson({'source': 'all'}), isNull);
      expect(CaptionSettings.fromJson('junk'), isNull);
    });

    test('each source names the sounds the native pass mixes', () {
      expect(CaptionSource.video.include, ['clips', 'overlays']);
      expect(CaptionSource.tracks.include, ['tracks']);
      expect(CaptionSource.all.include, ['clips', 'overlays', 'tracks']);
    });

    test('the lengths are the spec limits', () {
      expect(CaptionLength.word.maxWords, 1);
      expect(
        (CaptionLength.phrase.maxWords, CaptionLength.phrase.maxChars),
        (3, 20),
      );
      expect(
        (CaptionLength.line.maxWords, CaptionLength.line.maxChars),
        (7, 32),
      );
    });

    test('every language is a code the server accepts, listed once', () {
      final codes = kCaptionLanguages.map((l) => l.code).toList();
      expect(codes.every(RegExp(r'^[a-z]{2}$').hasMatch), isTrue);
      expect(codes.toSet(), hasLength(codes.length));
    });
  });

  group('the project', () {
    const asset = MediaAsset(
      id: 'a',
      path: '/v.mp4',
      type: MediaAssetType.video,
      durationSeconds: 30,
      width: 1080,
      height: 1920,
      hasAudio: true,
    );
    const settings = CaptionSettings(
      setId: 'captions_1',
      source: CaptionSource.all,
      language: 'yo',
      length: CaptionLength.line,
    );

    DraftProject draft({Map<String, dynamic>? captionSettings}) =>
        DraftProject(
          id: 'd1',
          sourceVideoPath: '/v.mp4',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          durationSeconds: 30,
          assets: [asset.toJson()],
          segments: [
            VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5)
                .toJson(),
          ],
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
          backgroundType: 'black',
          backgroundColorValue: 0xFF000000,
          backgroundBlurIntensity: 20,
          isMuted: false,
          captionSettings: captionSettings,
        );

    test('knows whether it has captions', () {
      expect(
        VideoEditorState(textOverlays: [TextOverlayModel(id: 't', text: 'hi')])
            .hasCaptions,
        isFalse,
      );
      expect(
        VideoEditorState(
          textOverlays: [
            TextOverlayModel(id: 'c', text: 'hi', captionSetId: 'captions_1'),
          ],
        ).hasCaptions,
        isTrue,
      );
    });

    test('a draft without captions writes no key', () {
      expect(draft().toJson().containsKey('captionSettings'), isFalse);
      expect(DraftProject.fromJson(draft().toJson()).captionSettings, isNull);
    });

    test('caption settings survive a save and a reopen', () async {
      SharedPreferences.setMockInitialValues({});
      final n = VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          draftId: 'd1',
          assets: const [asset],
          segments: [
            VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5),
          ],
          captionSettings: settings,
        );
      await n.saveDraft();
      final saved = await DraftService.getDraftById('d1');
      expect(saved?.captionSettings, settings.toJson());

      final reopened = VideoEditorNotifier(VideoEditorService());
      await reopened.loadDraft(saved!, rerenderMissingProxies: false);
      expect(reopened.state.captionSettings, settings);
    });

    test('a draft saved before captions reopens with none', () async {
      final n = VideoEditorNotifier(VideoEditorService());
      await n.loadDraft(draft(), rerenderMissingProxies: false);
      expect(n.state.captionSettings, isNull);
    });
  });
}
