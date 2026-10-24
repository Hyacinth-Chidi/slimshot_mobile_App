import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/features/compression/widgets/compress_panels.dart';
import 'package:slimshotai/features/compression/widgets/compress_result_view.dart';

const _mb = 1024 * 1024;

class _Calls {
  int close = 0;
  int save = 0;
  int share = 0;
  final previews = <int>[];
}

void main() {
  late _Calls calls;

  setUp(() => calls = _Calls());

  Future<void> pump(
    WidgetTester tester, {
    bool video = true,
    int count = 1,
    int before = (48.2 * _mb) ~/ 1,
    int after = (12.1 * _mb) ~/ 1,
    bool keptAsItWas = false,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
        child: CompressResultView(
          isVideo: video,
          count: count,
          beforeBytes: before,
          afterBytes: after,
          keptAsItWas: keptAsItWas,
          preview: const ColoredBox(color: Colors.black),
          previewAspectRatio: video ? 16 / 9 : 3 / 4,
          thumbnails: [
            for (var i = 0; i < count; i++) const ColoredBox(color: Colors.grey),
          ],
          previewIndex: 0,
          onPreview: calls.previews.add,
          onClose: () => calls.close++,
          onSave: () => calls.save++,
          onShare: () => calls.share++,
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a video: done, the real sizes and two buttons — nothing more to do',
      (tester) async {
    // It read as another step: a details list and three buttons. The
    // export screen's picture, title and two buttons is the model.
    await pump(tester);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('48.2 MB'), findsOneWidget);
    expect(find.text('12.1 MB'), findsOneWidget);
    expect(find.text('75% smaller'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Details'), findsNothing);
    expect(find.text('New video'), findsNothing);
    expect(find.byKey(const Key('result_new')), findsNothing);
    expect(find.byKey(const Key('result_thumb_0')), findsNothing);
  });

  testWidgets('Save and Share sit side by side, Share the purple one', (tester) async {
    await pump(tester);
    final save = tester.getRect(find.byKey(const Key('result_save')));
    final share = tester.getRect(find.byKey(const Key('result_share')));
    expect(save.center.dy, closeTo(share.center.dy, 1));
    expect(save.width, closeTo(share.width, 1));
    expect(save.right, lessThan(share.left));
    expect(tester.widget(find.byKey(const Key('result_share'))), isA<CompressPrimaryButton>());
  });

  testWidgets('each action reaches its callback', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('result_close')));
    await tester.tap(find.byKey(const Key('result_save')));
    await tester.tap(find.byKey(const Key('result_share')));
    expect((calls.close, calls.save, calls.share), (1, 1, 1));
  });

  testWidgets("the phone's Back closes it too, as ✕ does", (tester) async {
    // Back only stepped back to the Compress screen.
    await pump(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(calls.close, 1);
  });

  testWidgets('several photos: totals for all, a thumbnail each',
      (tester) async {
    await pump(tester,
        video: false, count: 5, before: (18.6 * _mb) ~/ 1, after: (4.2 * _mb) ~/ 1);
    expect(find.text('Save 5'), findsOneWidget);
    expect(find.text('New photos'), findsNothing);
    expect(find.text('All 5 photos'), findsOneWidget);
    expect(find.text('77% smaller'), findsOneWidget);
    await tester.tap(find.byKey(const Key('result_thumb_3')));
    expect(calls.previews, [3]);
  });

  testWidgets('kept as it was: no saving claimed, and it says why',
      (tester) async {
    await pump(tester, after: (48.2 * _mb) ~/ 1, keptAsItWas: true);
    expect(find.textContaining('smaller'), findsNothing);
    expect(find.text('Already as small as it gets — kept as it was.'),
        findsOneWidget);
  });

  testWidgets('a file that did not shrink claims no saving', (tester) async {
    await pump(tester, after: (50 * _mb) ~/ 1);
    expect(find.textContaining('smaller'), findsNothing);
  });

  testWidgets('the title sits at the centre of the screen', (tester) async {
    await pump(tester);
    final title = tester.getRect(find.byKey(const Key('result_title')));
    expect(title.center.dx, closeTo(390 / 2, 1));
  });

  testWidgets('a small phone with large text lays out without overflow',
      (tester) async {
    await pump(tester, size: const Size(320, 600), textScale: 1.3);
    expect(tester.takeException(), isNull);
    await pump(tester,
        video: false, count: 5, size: const Size(320, 600), textScale: 1.3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide screen puts the picture beside the sizes',
      (tester) async {
    await pump(tester, size: const Size(1000, 640));
    expect(tester.takeException(), isNull);
    final preview = tester.getRect(find.byKey(const Key('result_preview')));
    final sizes = tester.getRect(find.byKey(const Key('result_sizes')));
    expect(preview.right, lessThanOrEqualTo(sizes.left));
  });

  testWidgets('the title has no green tick beside it', (tester) async {
    await pump(tester);
    expect(find.text('Done'), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsNothing);
  });

  testWidgets('a photo is labelled once: the slider already says Before and After',
      (tester) async {
    // The frame laid its own Before / After over the slider's, a few pixels
    // apart — two pairs, one on the other.
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 300,
        height: 400,
        child: ResultPhotoFrame(
          compare: const Stack(children: [Text('Before'), Text('After')]),
          onFullScreen: () {},
        ),
      ),
    ));
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);
  });
}
