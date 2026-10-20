import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late List<String> extracted;
  late List<String> attempts;
  var peaksFail = false;
  Future<bool> Function(String a, String b)? sameVideo;
  ExtractChoice? result;
  var closed = false;

  Future<void> openSheet(WidgetTester tester, {String video = '/v1.mp4'}) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    player = _FakePreview();
    peaksAskedFor = [];
    discarded = [];
    extracted = [];
    attempts = [];
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
                    extract: (path) async {
                      attempts.add(path);
                      if (path == '/broken.mp4') {
                        throw const FileSystemException('read-only');
                      }
                      extracted.add(path);
                      return sounds[path];
                    },
                    isSameVideo: sameVideo,
                    peaks: (path) async {
                      peaksAskedFor.add(path);
                      if (peaksFail) {
                        throw PlatformException(code: 'peaks_failed');
                      }
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

  setUp(() {
    picks = [];
    // These paths are not files: compared by name, as the real comparison
    // (file bytes, `same_file_test.dart`) would for one path.
    sameVideo = (a, b) async => a == b;
    peaksFail = false;
  });

  testWidgets('the player it opened is the one it closes, however often it is rebuilt',
      (tester) async {
    // Device-reported: closed without using it, the sound played on and
    // looped until the app was closed. The editor builds the sheet inside a
    // route builder, which runs again whenever the route rebuilds — handing
    // the sheet a fresh, never-opened player each time. Closing disposed the
    // fresh one, and the one playing looped for ever.
    final first = _FakePreview();
    final second = _FakePreview();
    Widget sheet(ExtractPreviewPlayer player) => MaterialApp(
          home: Scaffold(
            body: ExtractAudioSheet(
              initialVideoPath: '/v1.mp4',
              pickVideo: () async => null,
              extract: (path) async => sounds[path],
              peaks: (_) async => const [],
              player: player,
            ),
          ),
        );
    await tester.pumpWidget(sheet(first));
    await tester.pump();
    await tester.pumpWidget(sheet(second));
    await tester.pump();
    final width = tester.getSize(find.byKey(const ValueKey('extract-waveform'))).width;
    await tester.drag(
      find.byKey(const ValueKey('extract-handle-end')),
      Offset(-width / 2, 0),
    );
    await tester.pump();
    expect(first.ranges.last.$2, closeTo(5.0, 0.3),
        reason: 'the handles still steer the player that is playing');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(first.opened, ['/v1.mp4']);
    expect(first.disposed, isTrue);
    expect(second.opened, isEmpty);
  });

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

  testWidgets('dragging the selected part slides it along, keeping its length',
      (tester) async {
    await openSheet(tester);
    final width = tester.getSize(find.byKey(const ValueKey('extract-waveform'))).width;
    await tester.drag(
      find.byKey(const ValueKey('extract-handle-end')),
      Offset(-width / 2, 0),
    );
    await settle(tester);
    await tester.drag(
      find.byKey(const ValueKey('extract-selection')),
      Offset(width / 4, 0),
    );
    await settle(tester);
    final (start, end) = player.ranges.last;
    expect(start, closeTo(2.5, 0.3));
    expect(end - start, closeTo(5.0, 0.3), reason: 'the length is kept');
  });

  testWidgets('a slide follows the finger the moment it moves', (tester) async {
    // Anchored on pointer-down: no travel is lost to the touch slop, so the
    // part moves with the finger from the first pixel.
    await openSheet(tester);
    final width = tester.getSize(find.byKey(const ValueKey('extract-waveform'))).width;
    await tester.drag(
      find.byKey(const ValueKey('extract-handle-end')),
      Offset(-width / 2, 0),
    );
    await settle(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('extract-selection'))),
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(width / 40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final readout = tester.widget<Text>(find.textContaining(' – ')).data!;
    expect(readout, startsWith('0:02.'), reason: 'a quarter of 10s moved, live');
    await gesture.up();
    await settle(tester);
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

  testWidgets('picking the same video again keeps its sound and handles', (tester) async {
    await openSheet(tester);
    final width = tester.getSize(find.byKey(const ValueKey('extract-waveform'))).width;
    await tester.drag(
      find.byKey(const ValueKey('extract-handle-end')),
      Offset(-width / 2, 0),
    );
    await settle(tester);
    picks = ['/v1.mp4'];
    await tester.tap(find.text('Change video'));
    await settle(tester);
    expect(extracted, ['/v1.mp4'], reason: 'not taken out a second time');
    expect(player.opened, ['/v1.mp4']);
    expect(discarded, isEmpty);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(result!.sound.path, '/a1.m4a');
    expect(result!.selection.end, closeTo(5.0, 0.3), reason: 'the trim is kept');
  });

  testWidgets('a fresh copy of the same video is the same video', (tester) async {
    // The gallery hands back a new copy, under a new name, on every pick.
    sameVideo = (a, b) async => true;
    await openSheet(tester);
    picks = ['/cache/image_picker_42.mp4'];
    await tester.tap(find.text('Change video'));
    await settle(tester);
    expect(extracted, ['/v1.mp4']);
    expect(discarded, isEmpty);
  });

  testWidgets('after a failure the same video is tried again', (tester) async {
    await openSheet(tester, video: '/broken.mp4');
    expect(find.text(kExtractFailedMessage), findsOneWidget);
    picks = ['/broken.mp4'];
    await tester.tap(find.text('Change video'));
    await settle(tester);
    expect(attempts, ['/broken.mp4', '/broken.mp4']);
  });

  testWidgets('a waveform that cannot be read leaves the sound usable', (tester) async {
    peaksFail = true;
    await openSheet(tester);
    expect(find.byKey(const ValueKey('extract-waveform')), findsOneWidget);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(result!.sound.path, '/a1.m4a');
  });

  testWidgets('a sound that cannot be saved says so', (tester) async {
    await openSheet(tester, video: '/broken.mp4');
    expect(find.text(kExtractFailedMessage), findsOneWidget);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(closed, isFalse, reason: 'Done waits for a sound');
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
