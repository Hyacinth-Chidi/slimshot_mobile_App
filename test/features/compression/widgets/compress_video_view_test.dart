import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:slimshotai/features/compression/logic/compression_presets.dart';
import 'package:slimshotai/features/compression/providers/compression_provider.dart';
import 'package:slimshotai/features/compression/widgets/compress_video_view.dart';

const _mb = 1024 * 1024;

final _smart = CompressionPresets.videoPresets[1];

CompressionState _state({
  int videos = 1,
  bool processing = false,
  double progress = 0,
  int index = 0,
  CompressionPreset? preset,
  bool optimized = false,
}) =>
    CompressionState(
      inputFiles: [for (var i = 0; i < videos; i++) XFile('v$i.mp4')],
      originalSize: videos == 1 ? (48.2 * _mb).round() : 312 * _mb,
      selectedPreset: preset ?? _smart,
      isProcessing: processing,
      progress: progress,
      currentProcessingIndex: index,
      videoMetadata: VideoMetadata(
        width: 1920,
        height: 1080,
        bitrateKbps: optimized ? 1000 : 9000,
        codec: 'h264',
        durationSecs: 42,
      ),
    );

class _Calls {
  final presets = <String>[];
  final formats = <String>[];
  int whatsApp = 0;
  int location = 0;
  int compress = 0;
  int cancel = 0;
  final previews = <int>[];
}

void main() {
  late _Calls calls;

  setUp(() => calls = _Calls());

  Future<void> pump(
    WidgetTester tester,
    CompressionState state, {
    Size size = const Size(390, 844),
    double textScale = 1,
    int previewIndex = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: CompressVideoView(
          state: state,
          preview: const ColoredBox(color: Colors.black),
          previewAspectRatio: 16 / 9,
          onBack: () {},
          onSelectPreset: (p) => calls.presets.add(p.id),
          onToggleWhatsApp: () => calls.whatsApp++,
          onToggleRemoveLocation: () => calls.location++,
          onFormat: calls.formats.add,
          onCompress: () => calls.compress++,
          onCancel: () => calls.cancel++,
          thumbnails: [
            for (var i = 0; i < state.inputFiles.length; i++)
              const ColoredBox(color: Colors.grey),
          ],
          previewIndex: previewIndex,
          onPreview: calls.previews.add,
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('ready: the video, its sizes, the qualities and the options',
      (tester) async {
    await pump(tester, _state());
    expect(find.text('Compress video'), findsOneWidget);
    expect(find.text('1080p · 0:42'), findsOneWidget);
    expect(find.text('48.2 MB'), findsWidgets);
    // Smart: 50–80% smaller.
    expect(find.text('≈ 9.6–24 MB'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    for (final preset in CompressionPresets.videoPresets) {
      expect(find.byKey(Key('compress_preset_${preset.id}')), findsOneWidget);
    }
    expect(find.text('WhatsApp ready'), findsOneWidget);
    expect(find.text('Remove location'), findsOneWidget);
    expect(find.text('MP4'), findsOneWidget);
    expect(find.text('WebM'), findsOneWidget);
  });

  testWidgets('no PRO badge while ads are off: there is nothing to unlock',
      (tester) async {
    await pump(tester, _state());
    expect(find.text('PRO'), findsNothing);
  });

  testWidgets('the estimate follows the chosen quality', (tester) async {
    await pump(tester, _state(preset: CompressionPresets.videoPresets[2]));
    expect(find.text('≈ 4.8–14 MB'), findsOneWidget); // 70–90% smaller
  });

  testWidgets('best quality on a video already optimised says no change',
      (tester) async {
    await pump(tester,
        _state(preset: CompressionPresets.videoPresets[0], optimized: true));
    expect(find.text('No change'), findsOneWidget);
  });

  testWidgets('each control reports its own choice', (tester) async {
    await pump(tester, _state());
    await tester.ensureVisible(find.byKey(const Key('compress_preset_smallest')));
    await tester.tap(find.byKey(const Key('compress_preset_smallest')));
    await tester.ensureVisible(find.byKey(const Key('compress_format_webm')));
    await tester.tap(find.byKey(const Key('compress_whatsapp')));
    await tester.tap(find.byKey(const Key('compress_remove_location')));
    await tester.tap(find.byKey(const Key('compress_format_webm')));
    await tester.tap(find.byKey(const Key('compress_start')));
    expect(calls.presets, ['smallest']);
    expect((calls.whatsApp, calls.location), (1, 1));
    expect(calls.formats, ['webm']);
    expect(calls.compress, 1);
  });

  testWidgets('compressing: the progress on the picture, and Cancel',
      (tester) async {
    await pump(tester, _state(processing: true, progress: 64));
    expect(find.text('Compressing'), findsOneWidget);
    expect(find.text('64%'), findsOneWidget);
    expect(find.byKey(const Key('compress_preset_smart')), findsNothing);
    await tester.tap(find.byKey(const Key('compress_cancel')));
    expect(calls.cancel, 1);
  });

  testWidgets('several videos: the count, the total, and which one is going',
      (tester) async {
    await pump(tester, _state(videos: 5));
    expect(find.text('5 videos'), findsOneWidget);
    expect(find.text('312 MB'), findsWidgets);

    await pump(tester, _state(videos: 5, processing: true, progress: 30, index: 1));
    expect(find.text('2 of 5'), findsOneWidget);
  });

  testWidgets('several videos: a thumbnail each, and a tap previews that one',
      (tester) async {
    await pump(tester, _state(videos: 5), previewIndex: 0);
    for (var i = 0; i < 5; i++) {
      expect(find.byKey(Key('compress_thumb_$i')), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('compress_thumb_2')));
    expect(calls.previews, [2]);
    // The one already shown is not asked for again.
    await tester.tap(find.byKey(const Key('compress_thumb_0')));
    expect(calls.previews, [2]);
  });

  testWidgets('one video has no thumbnail row', (tester) async {
    await pump(tester, _state());
    expect(find.byKey(const Key('compress_thumb_0')), findsNothing);
  });

  testWidgets('a small phone with large text lays out without overflow',
      (tester) async {
    await pump(tester, _state(videos: 5),
        size: const Size(320, 600), textScale: 1.3);
    expect(tester.takeException(), isNull);
    await pump(tester, _state(processing: true, progress: 10),
        size: const Size(320, 600), textScale: 1.3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide screen puts the video beside the settings',
      (tester) async {
    await pump(tester, _state(), size: const Size(1000, 640));
    expect(tester.takeException(), isNull);
    final preview = tester.getRect(find.byKey(const Key('compress_preview')));
    final sizes = tester.getRect(find.byKey(const Key('compress_size_card')));
    expect(preview.right, lessThanOrEqualTo(sizes.left));
    expect(preview.top, lessThan(sizes.bottom));
  });
}
