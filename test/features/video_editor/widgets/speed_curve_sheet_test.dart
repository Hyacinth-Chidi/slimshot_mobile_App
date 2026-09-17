import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/speed/speed_curve.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/speed_curve_sheet.dart';

/// The Speed curve sheet: presets along the top, the curve editable below.
void main() {
  const asset = MediaAsset(
    id: 'a',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 30,
    width: 1920,
    height: 1080,
    hasAudio: true,
  );

  late VideoEditorNotifier notifier;

  Widget harness() {
    return ProviderScope(
      overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
      child: const MaterialApp(home: Scaffold(body: SpeedCurveSheet())),
    );
  }

  setUp(() {
    notifier = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        assets: const [asset],
        segments: [
          VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 10),
        ],
        selectedSegmentId: 'a',
        isClipSelected: true,
      );
  });

  testWidgets('every preset in the catalogue has a tile', (tester) async {
    await tester.pumpWidget(harness());
    for (final p in kSpeedCurvePresets) {
      expect(find.byKey(Key('speed_preset_${p.id}')), findsOneWidget,
          reason: p.id);
    }
    // Plus a Normal tile, which is no curve at all.
    expect(find.byKey(const Key('speed_preset_none')), findsOneWidget);
  });

  testWidgets('tapping a preset puts its curve on the clip', (tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.byKey(const Key('speed_preset_montage')));
    await tester.pump();

    final curve = notifier.state.segments.single.speedCurve;
    expect(curve, isNotNull);
    expect(curve!.presetId, 'montage');
  });

  testWidgets('Normal removes the curve and restores plain speed',
      (tester) async {
    notifier.state = notifier.state.copyWith(
      segments: [
        notifier.state.segments.single
            .copyWith(speedCurve: speedCurvePresetById('hero')!.curve),
      ],
    );
    await tester.pumpWidget(harness());
    await tester.tap(find.byKey(const Key('speed_preset_none')));
    await tester.pump();

    expect(notifier.state.segments.single.speedCurve, isNull);
    expect(notifier.state.segments.single.speed, 1.0);
  });

  testWidgets('the selected preset is the one the clip carries', (tester) async {
    notifier.state = notifier.state.copyWith(
      segments: [
        notifier.state.segments.single
            .copyWith(speedCurve: speedCurvePresetById('bullet')!.curve),
      ],
    );
    await tester.pumpWidget(harness());

    final editor = tester.widget<SpeedCurveEditor>(find.byType(SpeedCurveEditor));
    expect(editor.curve.presetId, 'bullet');
  });

  testWidgets('dragging a point up raises that point\'s speed', (tester) async {
    notifier.state = notifier.state.copyWith(
      segments: [
        notifier.state.segments.single
            .copyWith(speedCurve: speedCurvePresetById('custom')!.curve),
      ],
    );
    await tester.pumpWidget(harness());

    final before = notifier.state.segments.single.speedCurve!;
    expect(before.points[2].speed, closeTo(1.0, 1e-9));

    // The middle point of the flat custom curve sits at the graph's centre.
    final box = tester.getRect(find.byType(SpeedCurveEditor));
    await tester.dragFrom(box.center, const Offset(0, -40));
    await tester.pump();

    final after = notifier.state.segments.single.speedCurve!;
    expect(after.points[2].speed, greaterThan(before.points[2].speed));
    // Only the grabbed point moved, and the curve is no longer a preset.
    expect(after.points.first.speed, closeTo(before.points.first.speed, 1e-9));
    expect(after.presetId, isNull);
  });

  testWidgets('a whole drag is one undo step', (tester) async {
    notifier.state = notifier.state.copyWith(
      segments: [
        notifier.state.segments.single
            .copyWith(speedCurve: speedCurvePresetById('custom')!.curve),
      ],
    );
    await tester.pumpWidget(harness());

    final box = tester.getRect(find.byType(SpeedCurveEditor));
    final gesture = await tester.startGesture(box.center);
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(notifier.state.segments.single.speedCurve!.points[2].speed,
        greaterThan(1.0));
    notifier.undo();
    expect(notifier.state.segments.single.speedCurve!.points[2].speed,
        closeTo(1.0, 1e-9));
  });

  testWidgets('the duration readout reports the curved length', (tester) async {
    notifier.state = notifier.state.copyWith(
      segments: [
        notifier.state.segments.single
            .copyWith(speedCurve: speedCurvePresetById('hero')!.curve),
      ],
    );
    await tester.pumpWidget(harness());

    final expected = notifier.state.segments.single.duration;
    expect(
      find.text('${expected.toStringAsFixed(1)}s'),
      findsOneWidget,
    );
  });
}
