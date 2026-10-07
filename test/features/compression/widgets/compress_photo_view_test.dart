import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:slimshotai/features/compression/logic/compression_presets.dart';
import 'package:slimshotai/features/compression/providers/compression_provider.dart';
import 'package:slimshotai/features/compression/widgets/compress_photo_view.dart';

const _mb = 1024 * 1024;

CompressionState _state({
  int photos = 1,
  bool processing = false,
  double progress = 0,
  int index = 0,
}) =>
    CompressionState(
      inputFiles: [for (var i = 0; i < photos; i++) XFile('p$i.heic')],
      originalSize: photos == 1 ? (3.8 * _mb).round() : (21.4 * _mb).round(),
      selectedPreset: CompressionPresets.imagePresets[1],
      isProcessing: processing,
      progress: progress,
      currentProcessingIndex: index,
    );

class _Calls {
  final presets = <String>[];
  final formats = <String>[];
  final previews = <int>[];
  int location = 0;
  int compress = 0;
  int cancel = 0;
}

void main() {
  late _Calls calls;

  setUp(() => calls = _Calls());

  Future<void> pump(
    WidgetTester tester,
    CompressionState state, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            size: size, textScaler: TextScaler.linear(textScale)),
        child: CompressPhotoView(
          state: state,
          photo: const ColoredBox(color: Colors.blueGrey),
          photoAspectRatio: 3 / 4,
          photoInfo: 'HEIC · 12 MP',
          thumbnails: [
            for (var i = 0; i < state.inputFiles.length; i++)
              const ColoredBox(color: Colors.grey),
          ],
          previewIndex: 0,
          onPreview: calls.previews.add,
          onBack: () {},
          onSelectPreset: (p) => calls.presets.add(p.id),
          onToggleRemoveLocation: () => calls.location++,
          onFormat: calls.formats.add,
          onCompress: () => calls.compress++,
          onCancel: () => calls.cancel++,
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('one photo: its details, the qualities and the options',
      (tester) async {
    await pump(tester, _state());
    expect(find.text('Compress photo'), findsOneWidget);
    expect(find.text('HEIC · 12 MP'), findsOneWidget);
    expect(find.text('3.8 MB'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    for (final preset in CompressionPresets.imagePresets) {
      expect(find.byKey(Key('compress_preset_${preset.id}')), findsOneWidget);
    }
    expect(find.text('Remove location'), findsOneWidget);
    expect(find.text('JPG'), findsOneWidget);
    expect(find.text('PNG'), findsOneWidget);
    expect(find.text('WebP'), findsOneWidget);
    // Photos have no WhatsApp option: the photo compressor has none.
    expect(find.text('WhatsApp ready'), findsNothing);
    expect(find.text('PRO'), findsNothing);
    expect(find.byKey(const Key('compress_thumb_0')), findsNothing);
  });

  testWidgets('the title sits at the centre of the screen', (tester) async {
    await pump(tester, _state());
    expect(tester.getCenter(find.text('Compress photo')).dx,
        closeTo(390 / 2, 1));
  });

  testWidgets('each control reports its own choice', (tester) async {
    await pump(tester, _state());
    await tester.ensureVisible(find.byKey(const Key('compress_preset_smallest')));
    await tester.tap(find.byKey(const Key('compress_preset_smallest')));
    await tester.ensureVisible(find.byKey(const Key('compress_format_webp')));
    await tester.tap(find.byKey(const Key('compress_remove_location')));
    await tester.tap(find.byKey(const Key('compress_format_webp')));
    await tester.tap(find.byKey(const Key('compress_start')));
    expect(calls.presets, ['smallest']);
    expect(calls.location, 1);
    expect(calls.formats, ['webp']);
    expect(calls.compress, 1);
  });

  testWidgets('several photos: the count, the total, a thumbnail each',
      (tester) async {
    await pump(tester, _state(photos: 5));
    expect(find.text('Compress photos'), findsOneWidget);
    expect(find.text('5 photos'), findsOneWidget);
    expect(find.text('21.4 MB'), findsOneWidget);
    await tester.tap(find.byKey(const Key('compress_thumb_2')));
    expect(calls.previews, [2]);
  });

  testWidgets('compressing: the progress on the photo, and Cancel',
      (tester) async {
    await pump(tester, _state(photos: 5, processing: true, progress: 40, index: 1));
    expect(find.text('Compressing'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('2 of 5'), findsOneWidget);
    expect(find.byKey(const Key('compress_preset_smart')), findsNothing);
    await tester.tap(find.byKey(const Key('compress_cancel')));
    expect(calls.cancel, 1);
  });

  testWidgets('a small phone with large text lays out without overflow',
      (tester) async {
    await pump(tester, _state(photos: 5),
        size: const Size(320, 600), textScale: 1.3);
    expect(tester.takeException(), isNull);
    // The three format segments are the widest row on the screen.
    await tester.ensureVisible(find.byKey(const Key('compress_format_webp')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide screen puts the photo beside the settings',
      (tester) async {
    await pump(tester, _state(), size: const Size(1000, 640));
    expect(tester.takeException(), isNull);
    final photo = tester.getRect(find.byKey(const Key('compress_preview')));
    final quality =
        tester.getRect(find.byKey(const Key('compress_preset_best_quality')));
    expect(photo.right, lessThanOrEqualTo(quality.left));
  });
}
