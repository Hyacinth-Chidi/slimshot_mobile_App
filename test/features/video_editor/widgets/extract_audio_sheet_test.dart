import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/audio_tools/audio_tools_service.dart';
import 'package:slimshotai/features/audio_tools/extract_preview_player.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/extract_audio_sheet.dart';

class _FakePreview implements ExtractPreviewPlayer {
  final opened = <String>[];
  final ranges = <(double, double)>[];
  bool disposed = false;

  @override
  Future<void> open(String videoPath) async => opened.add(videoPath);

  @override
  Future<void> playRange(double start, double end) async => ranges.add((start, end));

  @override
  Future<void> pause() async {}

  @override
  Future<void> dispose() async => disposed = true;

  @override
  Widget view() => const SizedBox(key: ValueKey('fake-video'), width: 100, height: 100);
}

/// Extract's sheet: the video, its sound's waveform between two handles,
/// Change video and Done.
void main() {
  const sounds = {
    '/v1.mp4': ExtractedSound(path: '/a1.m4a', durationSeconds: 10),
    '/v2.mp4': ExtractedSound(path: '/a2.m4a', durationSeconds: 6),
  };

  late _FakePreview player;
  late List<String> peaksAskedFor;
  late List<String> discarded;
  late List<String?> picks;
  ExtractChoice? result;
  var closed = false;

  Future<void> openSheet(WidgetTester tester, {String video = '/v1.mp4'}) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    player = _FakePreview();
    peaksAskedFor = [];
    discarded = [];
    result = null;
    closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await showEditorSheet<ExtractChoice>(
                  context,
                  builder: (_) => ExtractAudioSheet(
                    initialVideoPath: video,
                    pickVideo: () async => picks.removeAt(0),
                    extract: (path) async => sounds[path],
                    peaks: (path) async {
                      peaksAskedFor.add(path);
                      return List.generate(50, (i) => (i % 10) / 10);
                    },
                    discardSound: discarded.add,
                    player: player,
                  ),
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  setUp(() => picks = []);

  testWidgets('shows the video and the waveform once peaks arrive', (tester) async {
    await openSheet(tester);
    expect(find.byKey(const ValueKey('fake-video')), findsOneWidget);
    expect(find.byKey(const ValueKey('extract-waveform')), findsOneWidget);
    expect(player.opened, ['/v1.mp4']);
    expect(peaksAskedFor, ['/a1.m4a']);
    expect(player.ranges.last, (0.0, 10.0));
  });

  testWidgets('dragging a handle trims and the player plays only the range', (tester) async {
    await openSheet(tester);
    final width = tester.getSize(find.byKey(const ValueKey('extract-waveform'))).width;
    await tester.drag(
      find.byKey(const ValueKey('extract-handle-end')),
      Offset(-width / 2, 0),
    );
    await settle(tester);
    final (start, end) = player.ranges.last;
    expect(start, 0.0);
    expect(end, closeTo(5.0, 0.3));
  });

  testWidgets('Done returns the sound and the selection', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(closed, isTrue);
    expect(result!.sound.path, '/a1.m4a');
    expect((result!.selection.start, result!.selection.end), (0.0, 10.0));
    expect(discarded, isEmpty, reason: 'the chosen sound is the track');
    expect(player.disposed, isTrue);
  });

  testWidgets('closing adds nothing and throws the sound away', (tester) async {
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('extract-close')));
    await settle(tester);
    expect(closed, isTrue);
    expect(result, isNull);
    expect(discarded, ['/a1.m4a']);
    expect(player.disposed, isTrue);
  });

  testWidgets('Change video swaps the video and resets the handles', (tester) async {
    await openSheet(tester);
    final width = tester.getSize(find.byKey(const ValueKey('extract-waveform'))).width;
    await tester.drag(
      find.byKey(const ValueKey('extract-handle-end')),
      Offset(-width / 2, 0),
    );
    await settle(tester);
    picks = ['/v2.mp4'];
    await tester.tap(find.text('Change video'));
    await settle(tester);
    expect(player.opened, ['/v1.mp4', '/v2.mp4']);
    expect(discarded, ['/a1.m4a']);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(result!.sound.path, '/a2.m4a');
    expect((result!.selection.start, result!.selection.end), (0.0, 6.0));
  });

  testWidgets('cancelling Change video keeps the current video', (tester) async {
    await openSheet(tester);
    picks = [null];
    await tester.tap(find.text('Change video'));
    await settle(tester);
    expect(player.opened, ['/v1.mp4']);
    expect(discarded, isEmpty);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(result!.sound.path, '/a1.m4a');
  });

  testWidgets('a video with no sound says so and returns nothing', (tester) async {
    await openSheet(tester, video: '/silent.mp4');
    expect(find.text('This video has no sound'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(closed, isFalse, reason: 'Done waits for a sound');
    await tester.tap(find.byKey(const ValueKey('extract-close')));
    await settle(tester);
    expect(result, isNull);
  });
}
