import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/core/services/draft_refresh_notifier.dart';
import 'package:slimshotai/features/home_widget/home_widget_sync.dart';

/// The home screen widget shows the last edit: whichever draft was saved
/// last, sent to it whenever the drafts change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(kHomeWidgetChannel);
  late List<(String, Object?)> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add((call.method, call.arguments));
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  DraftProject draft({
    required String id,
    DateTime? updatedAt,
    String? thumbnailPath,
    int clips = 1,
    double? editedSeconds,
  }) =>
      DraftProject(
        id: id,
        sourceVideoPath: '/v.mp4',
        createdAt: DateTime(2026),
        updatedAt: updatedAt ?? DateTime(2026, 10, 28, 9),
        durationSeconds: 30,
        editedSeconds: editedSeconds,
        thumbnailPath: thumbnailPath,
        segments: [
          for (var i = 0; i < clips; i++) <String, dynamic>{'id': 's$i'},
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
      );

  test('the last edit is the latest saved, whatever the list order', () {
    final older = draft(id: 'a', updatedAt: DateTime(2026, 10, 1));
    final newer = draft(id: 'b', updatedAt: DateTime(2026, 10, 2));
    expect(lastEditOf([older, newer])!.draftId, 'b');
    expect(lastEditOf([newer, older])!.draftId, 'b');
  });

  test('it carries the cover, the clip count and the saved length', () {
    final edit = lastEditOf([
      draft(id: 'a', thumbnailPath: '/c.jpg', clips: 3, editedSeconds: 42),
    ])!;
    expect(
      (edit.coverPath, edit.clips, edit.lengthSeconds),
      ('/c.jpg', 3, 42.0),
    );
  });

  test('an old draft has no length, and no drafts is no edit', () {
    expect(lastEditOf([draft(id: 'a')])!.lengthSeconds, isNull);
    expect(lastEditOf(const []), isNull);
  });

  test('sync sends the edit, and null when there is none', () async {
    final d = draft(id: 'a', thumbnailPath: '/c.jpg', clips: 3, editedSeconds: 42);
    await HomeWidgetSync(channel: channel, drafts: () async => [d]).sync();
    await HomeWidgetSync(channel: channel, drafts: () async => const []).sync();
    expect(calls.map((c) => c.$1), ['setLastEdit', 'setLastEdit']);
    expect(calls[0].$2, {
      'draftId': 'a',
      'coverPath': '/c.jpg',
      'editedAtMillis': d.updatedAt.millisecondsSinceEpoch,
      'clips': 3,
      'lengthSeconds': 42.0,
    });
    expect(calls[1].$2, isNull);
  });

  test('every draft change sends again, the same cover included, until '
      'disposed', () async {
    final sync = HomeWidgetSync(
      channel: channel,
      drafts: () async => [draft(id: 'a', thumbnailPath: '/c.jpg')],
    )..start();
    await pumpEventQueue();
    DraftRefreshNotifier.instance.refresh();
    await pumpEventQueue();
    sync.dispose();
    DraftRefreshNotifier.instance.refresh();
    await pumpEventQueue();
    expect(calls.map((c) => (c.$2 as Map)['coverPath']), ['/c.jpg', '/c.jpg']);
  });

  test('an older read never overwrites a newer one', () async {
    final reads = [
      Completer<List<DraftProject>>(),
      Completer<List<DraftProject>>(),
    ];
    var next = 0;
    final sync =
        HomeWidgetSync(channel: channel, drafts: () => reads[next++].future);
    final older = sync.sync();
    final newer = sync.sync();
    reads[1].complete([draft(id: 'new')]);
    await newer;
    reads[0].complete([draft(id: 'old')]);
    await older;
    expect(calls.map((c) => (c.$2 as Map)['draftId']), ['new']);
  });

  test('a phone without the channel is no error', () async {
    await HomeWidgetSync(
      channel: const MethodChannel('nowhere'),
      drafts: () async => [draft(id: 'a')],
    ).sync();
  });

  test('drafts that cannot be read are no error', () async {
    await HomeWidgetSync(
      channel: channel,
      drafts: () async => throw StateError('no preferences'),
    ).sync();
    expect(calls, isEmpty);
  });
}
