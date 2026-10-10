import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/transitions/transition_preview_frames.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/transition_preview_provider.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/transitions_drawer.dart';

/// The transitions sheet: category pills over a grid of tiles that play the
/// real transition, a tap applying it and asking the canvas to play it.
void main() {
  // A 1x1 PNG: something an `Image.memory` can actually decode.
  final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );

  VideoEditorNotifier notifierWith({String? transition}) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: [
          VideoSegment(
            id: 'a',
            sourceStart: 0,
            sourceEnd: 5,
            transitionType: transition,
            transitionDuration: transition == null ? null : 0.8,
          ),
          VideoSegment(id: 'b', sourceStart: 0, sourceEnd: 5),
        ],
        selectedTransitionSegmentId: 'a',
      );
  }

  Future<void> pump(
    WidgetTester tester,
    VideoEditorNotifier n, {
    TransitionPreviewRenderer? render,
    ValueChanged<String>? onChosen,
  }) async {
    // Tall, so the sheet — held to a share of the screen — shows every tile.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoEditorProvider.overrideWith((ref) => n),
          transitionPreviewFramesProvider.overrideWithValue(
            TransitionPreviewFrames(render ?? (_) async => null),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: TransitionsDrawer(onTransitionChosen: onChosen),
            ),
          ),
        ),
      ),
    );
    // Never pumpAndSettle: the tiles loop for as long as the sheet is open.
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('offers only the categories that hold something', (tester) async {
    await pump(tester, notifierWith());
    for (final label in ['Basic', 'Motion', 'Blur']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Glitch'), findsNothing);
    expect(find.text('3D'), findsNothing);
  });

  testWidgets('opens on Basic with nothing applied, None first', (tester) async {
    await pump(tester, notifierWith());
    expect(find.text('None'), findsOneWidget);
    expect(find.text('Dissolve'), findsOneWidget);
    expect(find.text('Swirl'), findsNothing);
    final none = tester.getTopLeft(find.text('None'));
    final dissolve = tester.getTopLeft(find.text('Dissolve'));
    expect(none.dx < dissolve.dx || none.dy < dissolve.dy, isTrue);
  });

  testWidgets('opens on the category of the transition in use', (tester) async {
    await pump(tester, notifierWith(transition: 'defocus'));
    expect(find.text('Defocus'), findsOneWidget);
    expect(find.text('Dissolve'), findsNothing);
  });

  testWidgets('a pill shows its category', (tester) async {
    await pump(tester, notifierWith());
    await tester.tap(find.text('Motion'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Whip Pan'), findsOneWidget);
    expect(find.text('Dissolve'), findsNothing);
    // Every category leads with None, so a cut is one tap from anywhere.
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('a tile applies its transition and asks the canvas to play it',
      (tester) async {
    final n = notifierWith();
    final chosen = <String>[];
    await pump(tester, n, onChosen: chosen.add);
    await tester.tap(find.text('Motion'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Swirl'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(n.state.segments.first.transitionType, 'swirl');
    expect(chosen, ['a']);
  });

  testWidgets('None takes the transition off and plays nothing', (tester) async {
    final n = notifierWith(transition: 'dissolve');
    final chosen = <String>[];
    await pump(tester, n, onChosen: chosen.add);
    await tester.tap(find.text('None'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(n.state.segments.first.transitionType, isNull);
    expect(chosen, isEmpty);
  });

  testWidgets('a tile plays the frames the engine drew for it', (tester) async {
    final asked = <String>[];
    await pump(
      tester,
      notifierWith(),
      render: (name) async {
        asked.add(name);
        return [
          for (var i = 0; i < kTransitionPreviewFrameCount; i++)
            Uint8List.fromList(pixel),
        ];
      },
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Every transition on screen was asked for, and is drawn from its frames.
    expect(asked, contains('dissolve'));
    expect(asked, isNot(contains('swirl')));
    final images = find.descendant(
      of: find.byKey(const ValueKey('transition_tile_dissolve')),
      matching: find.byType(Image),
    );
    expect(images, findsOneWidget);
  });

  testWidgets('a tile the engine could not draw keeps its icon', (tester) async {
    await pump(tester, notifierWith());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final images = find.descendant(
      of: find.byKey(const ValueKey('transition_tile_dissolve')),
      matching: find.byType(Image),
    );
    expect(images, findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('transition_tile_dissolve')),
        matching: find.byType(Icon),
      ),
      findsOneWidget,
    );
  });
}
