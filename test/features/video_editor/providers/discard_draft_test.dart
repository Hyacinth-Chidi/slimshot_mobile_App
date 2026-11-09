import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/core/services/draft_files.dart';
import 'package:slimshotai/core/services/draft_service.dart';
import 'package:slimshotai/features/video_editor/logic/leave_editor.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

class _Documents extends PathProviderPlatform {
  _Documents(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

DraftProject _draft(String id) => DraftProject(
      id: id,
      sourceVideoPath: '/v.mp4',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      durationSeconds: 30,
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
      backgroundType: 'black',
      backgroundColorValue: 0xFF000000,
      backgroundBlurIntensity: 20,
      isMuted: false,
    );

/// Leaving a new project: "Save as draft?" (the owner's call, 2026-11-09).
/// Don't save throws the project away entirely — its draft, every file made
/// for it, and nothing saved after. A project opened from Recent Edits is a
/// draft already and is never asked about.
void main() {
  const asset = MediaAsset(
    id: 'a',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 30,
    width: 1080,
    height: 1920,
    hasAudio: true,
  );

  late Directory documents;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    documents = Directory.systemTemp.createTempSync('discard_draft_');
    PathProviderPlatform.instance = _Documents(documents.path);
  });

  tearDown(() {
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });

  VideoEditorNotifier project(String id) => VideoEditorNotifier(VideoEditorService())
    ..state = VideoEditorState(
      draftId: id,
      assets: const [asset],
      segments: [VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5)],
    );

  test('a discarded project leaves no draft, no files, and saves nothing after', () async {
    final n = project('d1');
    await n.saveDraft(); // a cover or a background photo saves mid-session
    expect(await DraftService.getDraftById('d1'), isNotNull);
    final proxies = await DraftFiles.proxiesDir('d1');
    File('${proxies.path}/p.mp4').writeAsStringSync('x');
    final cover = File('${documents.path}/cover_d1_1.jpg')..writeAsStringSync('x');

    await n.discardDraft();

    expect(await DraftService.getDraftById('d1'), isNull);
    expect(proxies.existsSync(), isFalse);
    expect(cover.existsSync(), isFalse);
    // The editor's own save as it closes must not bring it back.
    await n.saveDraft();
    expect(await DraftService.getDraftById('d1'), isNull);
  });

  test('a project never saved is thrown away without complaint', () async {
    final n = project('d2');
    final audio = await DraftFiles.audioDir('d2');
    File('${audio.path}/voice.m4a').writeAsStringSync('x');

    await n.discardDraft();

    expect(audio.existsSync(), isFalse);
    await n.saveDraft();
    expect(await DraftService.getDraftById('d2'), isNull);
  });

  test('another draft is left alone', () async {
    await project('d10').saveDraft();
    await project('d1').discardDraft();
    expect(await DraftService.getDraftById('d10'), isNotNull);
  });

  group('who is asked', () {
    test('a project made from picked media is asked', () async {
      expect(await asksToSaveOnLeave(null), isTrue);
    });

    test('a draft built but never saved — a reaction opened the first time — is asked', () async {
      expect(await asksToSaveOnLeave(_draft('react_1')), isTrue);
    });

    test('an edit opened from Recent Edits is not asked: it is a draft already', () async {
      await DraftService.saveDraft(_draft('d3'));
      expect(await asksToSaveOnLeave(_draft('d3')), isFalse);
    });
  });
}
