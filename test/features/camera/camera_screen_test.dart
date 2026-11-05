import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/utils/held_work.dart';
import 'package:slimshotai/features/camera/logic/camera_controller.dart';
import 'package:slimshotai/features/camera/screens/camera_screen.dart';
import 'package:slimshotai/features/camera/services/camera_permissions.dart';

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
  Future<void> openSettings() async => settingsOpened++;
}

void main() {
  late FakeCamera camera;
  late FakePermissions permissions;
  late List<CameraShot> reviewed;
  late CameraReviewOutcome? answer;
  late List<CameraShot> edited;
  var paths = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    camera = FakeCamera()..recordedMs = 2500;
    permissions = FakePermissions();
    reviewed = [];
    answer = CameraReviewOutcome.retake;
    edited = [];
    paths = 0;
  });

  Future<void> pumpCamera(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        backend: camera,
        permissions: permissions,
        newPath: (extension) async => '/shots/${++paths}.$extension',
        review: (context, shot) async {
          reviewed.add(shot);
          return answer;
        },
        onEdit: (context, shot) => edited.add(shot),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(ValueKey(name));

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

  testWidgets('a photo goes to the review', (tester) async {
    await pumpCamera(tester);
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    expect(reviewed.single, isA<PhotoShot>());
    expect(reviewed.single.path, '/shots/1.jpg');
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
    expect(HeldWork.instance.isHeld, isTrue, reason: 'a home-widget tap must not end a take');

    await tester.tap(key('camera_pause'));
    await tester.pumpAndSettle();
    expect(camera.calls.last, 'pause');

    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    expect(reviewed.single, isA<VideoShot>());
    expect(HeldWork.instance.isHeld, isFalse);
    expect(key('camera_flip'), findsOneWidget);
  });

  testWidgets('Back while recording stops the take and reviews it', (tester) async {
    await pumpCamera(tester);
    await tester.tap(key('camera_mode_video'));
    await tester.pumpAndSettle();
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(camera.calls, contains('stop'));
    expect(reviewed.single, isA<VideoShot>());
    expect(find.byType(CameraScreen), findsOneWidget, reason: 'the camera stays for the next shot');
  });

  testWidgets('Edit in the review hands the shot to the editor', (tester) async {
    answer = CameraReviewOutcome.edit;
    await pumpCamera(tester);
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    expect(edited.single.path, '/shots/1.jpg');
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
          review: (context, shot) async => null,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
