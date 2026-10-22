import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/clip_filmstrip.dart';

/// Which frame each filmstrip tile shows.
///
/// A tile showed the frame at its left edge rounded *down* to a 200 ms step,
/// 30–190 ms before the tile — and for a clip's first tile, a frame from
/// before the clip began, the other side of a split. On the phone the
/// extractor then moved to the nearest keyframe, which can lie across the cut
/// too. Now a tile shows its own middle, rounded to the nearest step and held
/// inside the clip, and a clip's first and last tiles ask for the exact frame.
void main() {
  late List<({List<int> times, bool exact})> requests;

  setUp(() {
    requests = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('slimshot_ai/video_thumbnails'),
      (call) async {
        if (call.method != 'getFrames') return null;
        final args = call.arguments as Map;
        final times = (args['timesMs'] as List).cast<int>();
        requests.add((times: [...times]..sort(), exact: args['exact'] == true));
        return List<Uint8List?>.filled(times.length, null);
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('slimshot_ai/video_thumbnails'), null);
  });

  Future<void> pumpStrip(WidgetTester tester, VideoSegment clip, {String path = '/v.mp4'}) async {
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: ClipFilmstrip(
          segment: clip,
          sourcePath: path,
          timelineStart: 0,
          pixelsPerSecond: 50,
          height: 48,
          visibleStartSeconds: 0,
          visibleEndSeconds: 6,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  }

  List<int> asked({required bool exact}) =>
      [for (final r in requests) if (r.exact == exact) ...r.times]..sort();

  testWidgets('each tile shows its own middle, and the clip ends are exact', (tester) async {
    // 48 px tiles at 50 px/s are 0.96 s each; the clip's source runs 2.15–8.15.
    await pumpStrip(tester, VideoSegment(id: 'c', sourceStart: 2.15, sourceEnd: 8.15));

    // Middles 3.59, 4.55, 5.51, 6.47, 7.43 s, to the nearest 200 ms.
    expect(asked(exact: false), [3600, 4600, 5600, 6400, 7400]);
    // The first tile's middle is 2.63 s; the last tile covers 7.91–8.15,
    // middle 8.03 s. Both exact: a keyframe there may lie across the cut.
    expect(asked(exact: true), [2600, 8000]);
  });

  testWidgets('a time rounded out of the clip stays inside it', (tester) async {
    // One tile, middle 2.35 s; the nearest step, 2.4 s, is past the clip's end.
    await pumpStrip(
      tester,
      VideoSegment(id: 'c', sourceStart: 2.31, sourceEnd: 2.39),
      path: '/short.mp4',
    );
    final all = [...asked(exact: false), ...asked(exact: true)];
    expect(all, hasLength(1));
    expect(all.single, inInclusiveRange(2310, 2389));
  });
}
