import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/utils/held_work.dart';
import 'package:slimshotai/features/camera/logic/camera_roll.dart';
import 'package:slimshotai/features/camera/screens/camera_screen.dart';
import 'package:slimshotai/features/camera/services/camera_permissions.dart';
import 'package:slimshotai/features/camera/widgets/shot_views.dart';

import '../../support/fake_camera.dart';

class FakePermissions implements CameraPermissions {
  FakePermissions({this.access = CameraAccess.granted});

  CameraAccess access;
  int cameraAsks = 0;
  int settingsOpened = 0;

  @override
  Future<CameraAccess> requestCamera() async {
    cameraAsks++;
    return access;
  }

  @override
  Future<CameraAccess> cameraStatus() async => access;

  @override
  Future<bool> allowMicrophone() async => true;

  @override
  Future<bool> allowStorage() async => true;

  @override
  Future<void> openSettings() async => settingsOpened++;
}

void main() {
  late FakeCamera camera;
  late FakePermissions permissions;
  late List<CameraRoll> opened;
  late RollShot? answer;
  late List<RollShot> edited;
  var paths = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    camera = FakeCamera()..recordedMs = 2500;
    permissions = FakePermissions();
    opened = [];
    answer = null;
    edited = [];
    paths = 0;
  });

  Future<void> pumpCamera(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        backend: camera,
        permissions: permissions,
        newPath: (extension) async => '/shots/${++paths}.$extension',
        openRoll: (context, roll) async {
          opened.add(roll);
          return answer;
        },
        onEdit: (context, shot) => edited.add(shot),
        loadFrame: (_) async => null,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(ValueKey(name));

  Future<void> recordAVideo(WidgetTester tester) async {
    await tester.tap(key('camera_mode_video'));
    await tester.pumpAndSettle();
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens the camera once access is given, and shows its picture', (tester) async {
    await pumpCamera(tester);
    expect(camera.calls.first, 'open back photo');
    expect(find.byType(Texture), findsOneWidget);
    expect(key('camera_notice'), findsNothing);
  });

  testWidgets('refused, it says so and asks again on a tap', (tester) async {
    permissions.access = CameraAccess.denied;
    await pumpCamera(tester);
    expect(find.text('Camera access is off.'), findsOneWidget);
    expect(camera.calls, isEmpty, reason: 'no camera is opened without access');

    permissions.access = CameraAccess.granted;
    await tester.tap(find.text('Allow camera'));
    await tester.pumpAndSettle();
    expect(permissions.cameraAsks, 2);
    expect(camera.calls.first, 'open back photo');
    expect(key('camera_notice'), findsNothing);
  });

  testWidgets('refused for good, it offers the phone\'s settings', (tester) async {
    permissions.access = CameraAccess.blocked;
    await pumpCamera(tester);
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    expect(permissions.settingsOpened, 1);
  });

  testWidgets('a camera that will not open says why and can be tried again', (tester) async {
    camera.failOpen = true;
    await pumpCamera(tester);
    expect(find.text('The camera is in use.'), findsOneWidget);
    camera.failOpen = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byType(Texture), findsOneWidget);
  });

  testWidgets('a photo is kept at once and lands on the pile, no screen in between', (tester) async {
    await pumpCamera(tester);
    expect(key('camera_roll_pile'), findsNothing, reason: 'no shots yet, no pile');

    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    expect(camera.lastGallery, isTrue, reason: 'saved to the gallery as it is taken');
    expect(opened, isEmpty, reason: 'nothing asks to save or discard');
    expect(key('camera_roll_pile'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString(kCameraRollKey)!) as List;
    expect(stored.single['path'], '/shots/1.jpg');
    expect(stored.single['uri'], 'content://media//shots/1.jpg');
  });

  testWidgets('the pile is three cards at most', (tester) async {
    await pumpCamera(tester);
    for (var i = 0; i < 5; i++) {
      await tester.tap(key('camera_shutter'));
      await tester.pumpAndSettle();
    }
    expect(
      find.descendant(of: key('camera_roll_pile'), matching: find.byType(ShotThumbnail)),
      findsNWidgets(CameraRollPile.maxCards),
    );
  });

  testWidgets('shots taken before are on the pile when the camera opens', (tester) async {
    SharedPreferences.setMockInitialValues({
      kCameraRollKey: jsonEncode([
        {'path': 'test/fixtures/does_not_matter.jpg', 'video': false},
      ]),
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: CameraScreen(
          backend: camera,
          permissions: permissions,
          newPath: (extension) async => '/shots/x.$extension',
          openRoll: (context, roll) async => null,
          loadFrame: (_) async => null,
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    // Kept only while its file is there: this one never was.
    expect(key('camera_roll_pile'), findsNothing);
  });

  testWidgets('while recording only stop, pause and the time are offered', (tester) async {
    await pumpCamera(tester);
    await tester.tap(key('camera_mode_video'));
    await tester.pumpAndSettle();
    expect(camera.calls, contains('configure back video off'));

    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    expect(key('camera_pause'), findsOneWidget);
    expect(key('camera_recording_time'), findsOneWidget);
    expect(key('camera_flip'), findsNothing);
    expect(key('camera_close'), findsNothing);
    expect(key('camera_roll_pile'), findsNothing, reason: 'pause takes its place');
    expect(HeldWork.instance.isHeld, isTrue, reason: 'a home-widget tap must not end a take');

    await tester.tap(key('camera_pause'));
    await tester.pumpAndSettle();
    expect(camera.calls.last, 'pause');

    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    expect(HeldWork.instance.isHeld, isFalse);
    expect(key('camera_flip'), findsOneWidget);
    expect(key('camera_roll_pile'), findsOneWidget, reason: 'the video is on the pile');
  });

  testWidgets('Back while recording stops the take and keeps it', (tester) async {
    await pumpCamera(tester);
    await tester.tap(key('camera_mode_video'));
    await tester.pumpAndSettle();
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(camera.calls, contains('stop'));
    expect(key('camera_roll_pile'), findsOneWidget);
    expect(find.byType(CameraScreen), findsOneWidget, reason: 'the camera stays for the next shot');
  });

  testWidgets('the pile opens the viewer on the camera\'s shots', (tester) async {
    await pumpCamera(tester);
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    await tester.tap(key('camera_roll_pile'));
    await tester.pumpAndSettle();
    expect(opened.single.shots.single.path, '/shots/1.jpg');
    expect(edited, isEmpty);
  });

  testWidgets('a video chosen for Edit in the viewer goes to the editor', (tester) async {
    await pumpCamera(tester);
    await recordAVideo(tester);
    answer = RollShot(path: '/shots/1.mp4', isVideo: true, durationMs: 2500, takenAt: DateTime(2026));
    await tester.tap(key('camera_roll_pile'));
    await tester.pumpAndSettle();
    expect(edited.single.path, '/shots/1.mp4');
  });

  testWidgets('the flash is offered only on a lens that has one', (tester) async {
    await pumpCamera(tester);
    expect(key('camera_flash'), findsOneWidget);
    await tester.tap(key('camera_flip'));
    await tester.pumpAndSettle();
    expect(camera.calls, contains('configure front photo off'));
    expect(key('camera_flash'), findsNothing);
  });

  testWidgets('the lens is remembered for next time', (tester) async {
    await pumpCamera(tester);
    await tester.tap(key('camera_flip'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kCameraLensKey), 'front');
  });

  testWidgets('a swipe across the picture changes mode', (tester) async {
    await pumpCamera(tester);
    await tester.drag(key('camera_picture'), const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(camera.calls, contains('configure back video off'));

    await tester.drag(key('camera_picture'), const Offset(160, 0));
    await tester.pumpAndSettle();
    expect(camera.calls.last, 'configure back photo off');
  });

  testWidgets('a tap on the picture focuses there', (tester) async {
    await pumpCamera(tester);
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 50));
    expect(camera.calls.any((c) => c.startsWith('focus ')), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('nothing overflows on a small phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.3)),
      child: MaterialApp(
        home: CameraScreen(
          backend: camera,
          permissions: permissions,
          newPath: (extension) async => '/shots/x.$extension',
          openRoll: (context, roll) async => null,
          loadFrame: (_) async => null,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('camera_shutter')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
