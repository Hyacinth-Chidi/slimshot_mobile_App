import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/native_timeline_preview_service.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// "Mute clip audio" — CapCut's button beside the cover (the owner's ask,
/// 2026-11-10): the main track's own sound off, as one undo step, reaching
/// the engine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const asset = MediaAsset(
    id: 'v',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 5,
    width: 1080,
    height: 1920,
    hasAudio: true,
  );

  VideoEditorNotifier notifier() => VideoEditorNotifier(VideoEditorService())
    ..state = VideoEditorState(
      assets: const [asset],
      segments: [VideoSegment(id: 'a', assetId: 'v', sourceStart: 0, sourceEnd: 5)],
    );

  test('muting the clips is one undo step', () {
    final n = notifier();
    n.setClipAudioMuted(true);
    expect(n.state.isMuted, isTrue);
    expect(n.state.canUndo, isTrue);
    n.undo();
    expect(n.state.isMuted, isFalse);
  });

  test('asking for the state it is already in takes no undo step', () {
    final n = notifier();
    n.setClipAudioMuted(false);
    expect(n.state.canUndo, isFalse);
  });

  test('the composed timeline says the clips are muted', () {
    final n = notifier()..setClipAudioMuted(true);
    expect(const VideoEditorTimelineComposer().compose(n.state).isMuted, isTrue);
  });

  test('a mute reaches the engine: it changes the playback signature', () {
    // The editor pushes a timeline only when the signature changes, so a
    // field missing from it is an edit the engine never hears of.
    final service = NativeTimelinePreviewService();
    final n = notifier();
    final before = service.playbackSignature(n.state);
    n.setClipAudioMuted(true);
    expect(service.playbackSignature(n.state), isNot(before));
  });
}
