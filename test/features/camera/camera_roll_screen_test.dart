import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/features/camera/logic/camera_roll.dart';
import 'package:slimshotai/features/camera/screens/camera_roll_screen.dart';

RollShot shot(String name, {bool video = false}) => RollShot(
      path: '/g/$name',
      uri: 'content://media/$name',
      isVideo: video,
      durationMs: video ? 3000 : 0,
      takenAt: DateTime(2026, 11, 5),
    );

void main() {
  late CameraRoll roll;
  late List<RollShot> deleted;
  late List<String> shared;
  late bool deleteWorks;
  late RollShot? answer;
  late bool closed;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    roll = CameraRoll();
    await roll.add(shot('old.jpg'));
    await roll.add(shot('mid.mp4', video: true));
    await roll.add(shot('new.jpg'));
    deleted = [];
    shared = [];
    deleteWorks = true;
    answer = null;
    closed = false;
  });

  Future<void> pumpViewer(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                answer = await Navigator.of(context).push<RollShot>(MaterialPageRoute(
                  builder: (_) => CameraRollScreen(
                    roll: roll,
                    deleteShot: (shot) async {
                      deleted.add(shot);
                      return deleteWorks;
                    },
                    share: (path) async {
                      shared.add(path);
                      return true;
                    },
                    videoView: (path, foot) => Text('video $path'),
                    loadFrame: (_) async => null,
                  ),
                ));
                closed = true;
              },
              child: const Text('camera'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('camera'));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  Future<void> swipeLeft(WidgetTester tester) async {
    await tester.drag(key('camera_roll_pages'), const Offset(-500, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the newest shot, with every shot in the strip', (tester) async {
    await pumpViewer(tester);
    expect(key('camera_roll_photo_/g/new.jpg'), findsOneWidget);
    expect(key('camera_roll_tile_0'), findsOneWidget);
    expect(key('camera_roll_tile_2'), findsOneWidget);
  });

  testWidgets('swiping left goes to older shots; a video plays', (tester) async {
    await pumpViewer(tester);
    await swipeLeft(tester);
    expect(find.text('video /g/mid.mp4'), findsOneWidget);
    await swipeLeft(tester);
    expect(key('camera_roll_photo_/g/old.jpg'), findsOneWidget);
    expect(closed, isFalse);
  });

  testWidgets('one more swipe past the oldest goes back to the camera', (tester) async {
    await pumpViewer(tester);
    await swipeLeft(tester);
    await swipeLeft(tester);
    await swipeLeft(tester);
    expect(closed, isTrue);
    expect(answer, isNull);
    expect(find.text('camera'), findsOneWidget);
  });

  testWidgets('swiping right on the newest stays', (tester) async {
    await pumpViewer(tester);
    await tester.drag(key('camera_roll_pages'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    expect(key('camera_roll_photo_/g/new.jpg'), findsOneWidget);
  });

  testWidgets('a tap in the strip shows that shot', (tester) async {
    await pumpViewer(tester);
    await tester.tap(key('camera_roll_tile_2'));
    await tester.pumpAndSettle();
    expect(key('camera_roll_photo_/g/old.jpg'), findsOneWidget);
  });

  testWidgets('Edit is offered on a video only, with the scissors, and hands it on', (tester) async {
    await pumpViewer(tester);
    expect(key('camera_roll_edit'), findsNothing, reason: 'a photo has no Edit');

    await swipeLeft(tester);
    expect(
      find.descendant(of: key('camera_roll_edit'), matching: find.byIcon(LucideIcons.scissors)),
      findsOneWidget,
    );
    expect(find.byIcon(LucideIcons.pencil), findsNothing);
    await tester.tap(key('camera_roll_edit'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(answer!.path, '/g/mid.mp4');
  });

  testWidgets('Delete asks first, and Cancel keeps the shot', (tester) async {
    await pumpViewer(tester);
    await tester.tap(key('camera_roll_delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this photo?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
    expect(roll.shots, hasLength(3));
  });

  testWidgets('Delete takes the shot from the gallery and the roll, and shows the next', (tester) async {
    await pumpViewer(tester);
    await tester.tap(key('camera_roll_delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted.single.path, '/g/new.jpg');
    expect(roll.shots.map((s) => s.path), ['/g/mid.mp4', '/g/old.jpg']);
    expect(find.text('video /g/mid.mp4'), findsOneWidget);
    expect(closed, isFalse);
  });

  testWidgets('a delete the phone refused keeps the shot and says so', (tester) async {
    deleteWorks = false;
    await pumpViewer(tester);
    await tester.tap(key('camera_roll_delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(roll.shots, hasLength(3));
    expect(find.text(kDeleteFailedMessage), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('deleting the only shot goes back to the camera', (tester) async {
    await roll.remove(roll.shots[0]);
    await roll.remove(roll.shots[0]);
    await pumpViewer(tester);
    await tester.tap(key('camera_roll_delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(roll.shots, isEmpty);
    expect(closed, isTrue);
  });

  testWidgets('Share hands over the shot on screen', (tester) async {
    await pumpViewer(tester);
    await swipeLeft(tester);
    await tester.tap(key('camera_roll_share'));
    await tester.pumpAndSettle();
    expect(shared, ['/g/mid.mp4']);
  });

  testWidgets('Back and the cross go back to the camera', (tester) async {
    await pumpViewer(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(closed, isTrue);

    closed = false;
    await tester.tap(find.text('camera'));
    await tester.pumpAndSettle();
    await tester.tap(key('camera_roll_close'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('the foot fits a small phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.3)),
      child: MaterialApp(home: CameraRollScreen(roll: roll, loadFrame: (_) async => null)),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
