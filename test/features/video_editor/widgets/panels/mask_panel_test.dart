import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/overlay_content_box.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/mask_panel.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/value_ruler.dart';

/// The Mask panel: a shape, a feather, an invert — the window itself is
/// placed on the canvas, which is why this is an in-place panel and not a
/// sheet.
void main() {
  VideoSegment clip() => VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 10);

  VideoEditorNotifier notifierWith(VideoSegment segment) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: [segment],
        selectedSegmentId: segment.id,
        isClipSelected: true,
        activeToolId: 'mask',
      );
  }

  Future<void> pump(WidgetTester tester, VideoEditorNotifier n, {double? width}) {
    // An unbounded height, as the tool panel lays every body out.
    return tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => n)],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [SizedBox(width: width, child: const MaskPanel())],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('offers the four shapes, None first', (tester) async {
    await pump(tester, notifierWith(clip()));
    for (final label in ['None', 'Rectangle', 'Circle', 'Linear']) {
      expect(find.text(label), findsOneWidget);
    }
    // With no mask there is nothing to feather or invert.
    expect(find.byType(ValueRuler), findsNothing);
  });

  testWidgets('choosing a shape places a default window, one undo step',
      (tester) async {
    final n = notifierWith(clip());
    await pump(tester, n);
    await tester.tap(find.text('Circle'));
    await tester.pumpAndSettle();

    final mask = n.state.segments.single.mask;
    expect(mask.shape, ClipMaskShape.circle);
    expect(mask.centerX, 0.5);
    expect(mask.centerY, 0.5);
    // Now there is a window, its feather and invert appear.
    expect(find.byType(ValueRuler), findsOneWidget);
    expect(find.byKey(const Key('mask_invert')), findsOneWidget);

    n.undo();
    expect(n.state.segments.single.mask, ClipMask.none);
  });

  testWidgets('switching shape keeps the window where it was', (tester) async {
    final n = notifierWith(clip().copyWith(
      mask: const ClipMask(shape: ClipMaskShape.rectangle, centerX: 0.3, centerY: 0.2, width: 0.4, height: 0.3),
    ));
    await pump(tester, n);
    await tester.tap(find.text('Rounded'));
    await tester.pumpAndSettle();
    final mask = n.state.segments.single.mask;
    expect(mask.shape, ClipMaskShape.roundedRectangle);
    expect(mask.centerX, 0.3);
    expect(mask.width, 0.4);
  });

  group('Circle is round on the picture it masks', () {
    // Device-reported as an oval: the window is fractions of the picture's
    // width and height, so equal fractions are unequal lengths on any picture
    // that is not square.
    testWidgets('on a tall clip', (tester) async {
      const asset = MediaAsset(
        id: 'tall',
        path: '/tall.mp4',
        type: MediaAssetType.video,
        durationSeconds: 10,
        width: 1080,
        height: 1920,
        hasAudio: false,
      );
      final n = VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          assets: const [asset],
          segments: [
            VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 10, assetId: 'tall'),
          ],
          selectedSegmentId: 'a',
          isClipSelected: true,
          activeToolId: 'mask',
        );
      await pump(tester, n);
      await tester.tap(find.text('Circle'));
      await tester.pumpAndSettle();

      final mask = n.state.segments.single.mask;
      expect(mask.shape, ClipMaskShape.circle);
      expect(mask.width * (1080 / 1920), closeTo(mask.height, 1e-9));
    });

    testWidgets("on a photo overlay, by the photo's own shape", (tester) async {
      // An overlay's window lives in the overlay's box, which has the
      // photo's shape — the one the canvas measured for it.
      OverlayContentBox.debugRememberAspect('/portrait.png', 3 / 4);
      final n = VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          segments: [clip()],
          imageOverlays: [ImageOverlayModel(id: 'o', imagePath: '/portrait.png')],
          selectedImageId: 'o',
          activeToolId: 'mask',
        );
      await pump(tester, n);
      await tester.tap(find.text('Circle'));
      await tester.pumpAndSettle();

      final mask = n.state.imageOverlays.single.mask;
      expect(mask.shape, ClipMaskShape.circle);
      expect(mask.width * (3 / 4), closeTo(mask.height, 1e-9));
    });
  });

  group('the shapes are tiles', () {
    testWidgets('a picture of the shape with its name small under it',
        (tester) async {
      await pump(tester, notifierWith(clip()));
      for (final shape in ClipMaskShape.values) {
        final tile = find.byKey(Key('mask_shape_${shape.name}'));
        final size = tester.getSize(tile);
        // Big enough to hit without aiming.
        expect(size.width, greaterThanOrEqualTo(48), reason: shape.name);
        expect(size.height, greaterThanOrEqualTo(48), reason: shape.name);
        final picture = tester.getRect(
          find.descendant(of: tile, matching: find.byType(CustomPaint)).first,
        );
        final name = find.descendant(of: tile, matching: find.byType(Text));
        expect(tester.getRect(name).top, greaterThanOrEqualTo(picture.bottom),
            reason: shape.name);
        expect(tester.widget<Text>(name).style!.fontSize, lessThanOrEqualTo(11),
            reason: shape.name);
      }
    });

    testWidgets('all six fit across a 360-wide phone', (tester) async {
      // 360 less the panel's 16 either side. A row that scrolled would hide
      // the last shape on the phones most people have.
      await pump(tester, notifierWith(clip()), width: 328);
      final panel = tester.getRect(find.byType(MaskPanel));
      for (final shape in ClipMaskShape.values) {
        final rect = tester.getRect(find.byKey(Key('mask_shape_${shape.name}')));
        expect(rect.right, lessThanOrEqualTo(panel.right + 0.01), reason: shape.name);
      }
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the feather ruler writes live, one undo step per drag',
      (tester) async {
    final n = notifierWith(clip().copyWith(
      mask: const ClipMask(shape: ClipMaskShape.rectangle, feather: 0.05),
    ));
    await pump(tester, n);
    await tester.drag(find.byType(ValueRuler), const Offset(50, 0));
    await tester.pumpAndSettle();
    expect(n.state.segments.single.mask.feather,
        closeTo(0.05 + 50 * kMaskFeatherPerPixel, 1e-6));
    n.undo();
    expect(n.state.segments.single.mask.feather, 0.05);
    expect(n.state.canUndo, isFalse);
  });

  testWidgets('every shape the model knows is offered', (tester) async {
    // The panel orders its own chips, so a shape added to the enum and not to
    // that order would never reach the user.
    await pump(tester, notifierWith(clip()));
    const labels = ['None', 'Rectangle', 'Circle', 'Linear', 'Mirror', 'Rounded'];
    expect(labels, hasLength(ClipMaskShape.values.length));
    for (final label in labels) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('Mirror sits right after Linear, and places a band', (tester) async {
    // The two line shapes side by side, as CapCut groups them; every other
    // chip keeps its place.
    final n = notifierWith(clip());
    await pump(tester, n);
    double left(String label) => tester.getRect(find.text(label)).left;
    expect(left('Rectangle'), lessThan(left('Circle')));
    expect(left('Circle'), lessThan(left('Linear')));
    expect(left('Linear'), lessThan(left('Mirror')));
    expect(left('Mirror'), lessThan(left('Rounded')));

    await tester.tap(find.text('Mirror'));
    await tester.pumpAndSettle();
    expect(n.state.segments.single.mask.shape, ClipMaskShape.mirror);
  });

  testWidgets('invert flips the window, None removes it', (tester) async {
    final n = notifierWith(clip().copyWith(
      mask: const ClipMask(shape: ClipMaskShape.linear),
    ));
    await pump(tester, n);
    await tester.tap(find.byKey(const Key('mask_invert')));
    await tester.pumpAndSettle();
    expect(n.state.segments.single.mask.inverted, isTrue);

    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(n.state.segments.single.mask, ClipMask.none);
  });
}
