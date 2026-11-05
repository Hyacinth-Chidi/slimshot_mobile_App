import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/utils/held_work.dart';
import 'package:slimshotai/features/camera/logic/camera_controller.dart';
import 'package:slimshotai/features/camera/screens/camera_review_screen.dart';
import 'package:slimshotai/features/camera/screens/camera_screen.dart';

void main() {
  late List<String> deleted;
  late List<String> saved;
  late bool shareGoesThrough;
  late CameraReviewOutcome? outcome;
  late bool popped;

  setUp(() {
    deleted = [];
    saved = [];
    shareGoesThrough = true;
    outcome = null;
    popped = false;
  });

  /// The review pushed over a page, as the camera pushes it.
  Future<void> pumpReview(WidgetTester tester, CameraShot shot) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                outcome = await Navigator.of(context).push<CameraReviewOutcome>(
                  MaterialPageRoute(
                    builder: (_) => CameraReviewScreen(
                      shot: shot,
                      deleteShot: (paths) async => deleted.addAll(paths),
                      videoView: (path) => Text('video $path'),
                      save: (path) async => saved.add(path),
                      share: (path) async => shareGoesThrough,
                    ),
                  ),
                );
                popped = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(ValueKey(name));

  testWidgets('a photo is shown', (tester) async {
    await pumpReview(tester, const PhotoShot('/c/IMG_1.jpg'));
    expect(key('camera_review_photo'), findsOneWidget);
  });

  testWidgets('a video plays', (tester) async {
    await pumpReview(tester, const VideoShot('/c/VID_1.mp4', durationMs: 3000));
    expect(find.text('video /c/VID_1.mp4'), findsOneWidget);
    expect(key('camera_review_photo'), findsNothing);
  });

  testWidgets('Retake asks first about a shot nobody kept, and Cancel stays', (tester) async {
    await pumpReview(tester, const PhotoShot('/c/IMG_1.jpg'));
    expect(HeldWork.instance.isHeld, isTrue, reason: 'an unsaved shot holds the app');

    await tester.tap(key('camera_review_retake'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this photo?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(popped, isFalse);
    expect(deleted, isEmpty);
  });

  testWidgets('Retake, discarded, deletes the shot and goes back to the camera', (tester) async {
    await pumpReview(tester, const VideoShot('/c/VID_1.mp4', durationMs: 3000));
    await tester.tap(key('camera_review_retake'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this video?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(deleted, ['/c/VID_1.mp4']);
    expect(outcome, CameraReviewOutcome.retake);
    expect(HeldWork.instance.isHeld, isFalse);
  });

  testWidgets('Back is Retake', (tester) async {
    await pumpReview(tester, const PhotoShot('/c/IMG_1.jpg'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard this photo?'), findsOneWidget);
  });

  testWidgets('once saved, Retake asks nothing and lets the app\'s copy go', (tester) async {
    await pumpReview(tester, const PhotoShot('/c/IMG_1.jpg'));
    await tester.tap(key('camera_review_save'));
    await tester.pump();
    expect(saved, ['/c/IMG_1.jpg']);
    expect(HeldWork.instance.isHeld, isFalse);
    await tester.pump(const Duration(seconds: 3));

    await tester.tap(key('camera_review_retake'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this photo?'), findsNothing);
    expect(deleted, ['/c/IMG_1.jpg']);
    expect(outcome, CameraReviewOutcome.retake);
  });

  testWidgets('a share closed unused still asks; one sent does not', (tester) async {
    shareGoesThrough = false;
    await pumpReview(tester, const PhotoShot('/c/IMG_1.jpg'));
    await tester.tap(key('camera_review_share'));
    await tester.pumpAndSettle();
    await tester.tap(key('camera_review_retake'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this photo?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    shareGoesThrough = true;
    await tester.tap(key('camera_review_share'));
    await tester.pumpAndSettle();
    await tester.tap(key('camera_review_retake'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this photo?'), findsNothing);
    expect(outcome, CameraReviewOutcome.retake);
  });

  testWidgets('Edit keeps the file for the editor', (tester) async {
    await pumpReview(tester, const VideoShot('/c/VID_1.mp4', durationMs: 3000));
    await tester.tap(key('camera_review_edit'));
    await tester.pumpAndSettle();
    expect(outcome, CameraReviewOutcome.edit);
    expect(deleted, isEmpty);
    expect(HeldWork.instance.isHeld, isFalse);
  });

  testWidgets('the actions fit a small phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.3)),
      child: MaterialApp(home: CameraReviewScreen(shot: PhotoShot('/c/IMG_1.jpg'))),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
