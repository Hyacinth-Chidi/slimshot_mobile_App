import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/tile_preview_store.dart';
import 'package:slimshotai/features/video_editor/logic/transitions/transition_preview_frames.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/transition_preview_provider.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/transitions_drawer.dart';

import '../../../../support/memory_tile_store.dart';

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
    TilePreviewStore? store,
    ValueChanged<String>? onChosen,
    double width = 400,
    double textScale = 1.0,
    bool settle = true,
  }) async {
    // Tall, so the sheet — held to a share of the screen — shows every tile.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoEditorProvider.overrideWith((ref) => n),
          transitionPreviewFramesProvider.overrideWithValue(
            TransitionPreviewFrames(render ?? (_) async => null, store: store),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
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
    if (settle) await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('offers every category, in order', (tester) async {
    await pump(tester, notifierWith());
    final labels = ['Basic', 'Motion', 'Blur', 'Light', 'Glitch', '3D'];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }
    for (var k = 1; k < labels.length; k++) {
      expect(
        tester.getTopLeft(find.text(labels[k - 1])).dx <
            tester.getTopLeft(find.text(labels[k])).dx,
        isTrue,
        reason: labels[k],
      );
    }
  });

  testWidgets('all six pills fit a small phone with large text, no scrolling',
      (tester) async {
    await pump(tester, notifierWith(), width: 360, textScale: 1.3);
    final pills = ['Basic', 'Motion', 'Blur', 'Light', 'Glitch', '3D'];
    for (final label in pills) {
      final box = tester.getRect(find.text(label));
      expect(box.left, greaterThanOrEqualTo(0), reason: label);
      expect(box.right, lessThanOrEqualTo(360), reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the 3D pill shows the revolves and cubes', (tester) async {
    await pump(tester, notifierWith());
    await tester.tap(find.text('3D'));
    await tester.pump(const Duration(milliseconds: 50));
    for (final label in ['Revolve L', 'Revolve R', 'Cube L', 'Cube R']) {
      expect(find.text(label), findsOneWidget);
    }
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

  List<Uint8List> sixteenPixels() => [
        for (var i = 0; i < kTransitionPreviewFrameCount; i++)
          Uint8List.fromList(pixel),
      ];

  Finder inTile(String name, Type type) => find.descendant(
        of: find.byKey(ValueKey('transition_tile_$name')),
        matching: find.byType(type),
      );

  // Kept on the phone from an earlier launch: the icon is for a transition
  // the engine has yet to draw, and this one needs no drawing.
  testWidgets('a tile kept from an earlier launch shows its picture, never '
      'its icon, and is not drawn again', (tester) async {
    final store = MemoryTileStore();
    store.saved[TilePreviewKind.transitions]!['dissolve'] =
        packTransitionFrames(sixteenPixels());
    final asked = <String>[];
    await pump(
      tester,
      notifierWith(),
      store: store,
      render: (name) async {
        asked.add(name);
        return null;
      },
      settle: false,
    );
    expect(inTile('dissolve', Icon), findsNothing,
        reason: 'the bare stage while it is read back');
    await tester.pump(const Duration(milliseconds: 50));
    expect(inTile('dissolve', Image), findsOneWidget);
    expect(inTile('dissolve', Icon), findsNothing);
    expect(asked, isNot(contains('dissolve')));
  });

  // Drawn by the engine for the first time: the picture fades in over the
  // icon that stood in for it, rather than switching in.
  testWidgets('a tile drawn for the first time fades its picture in over the '
      'icon', (tester) async {
    final gate = Completer<List<Uint8List>?>();
    await pump(
      tester,
      notifierWith(),
      render: (name) => name == 'dissolve' ? gate.future : Future.value(null),
    );
    expect(inTile('dissolve', Icon), findsOneWidget);
    gate.complete(sixteenPixels());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(inTile('dissolve', Image), findsOneWidget);
    expect(inTile('dissolve', Icon), findsOneWidget,
        reason: 'fading out under the picture');
    await tester.pump(const Duration(milliseconds: 120));
    expect(inTile('dissolve', Icon), findsNothing);
    expect(inTile('dissolve', Image), findsOneWidget);
  });

  testWidgets('a cut has no curve to set', (tester) async {
    await pump(tester, notifierWith());
    expect(find.byKey(const Key('transition_easing')), findsNothing);
  });

  testWidgets('the curve opens the keyframe easing sheet, and a choice '
      'applies and plays', (tester) async {
    final n = notifierWith(transition: 'dissolve');
    final chosen = <String>[];
    await pump(tester, n, onChosen: chosen.add);

    await tester.tap(find.byKey(const Key('transition_easing')));
    // Let the sheet slide fully up; the tiles loop for ever, so never settle.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Quadratic'), findsOneWidget);

    await tester.tap(find.text('Quadratic'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Ease'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(n.state.segments.first.transitionEasing, KeyframeInterpolation.quadInOut);
    expect(chosen, ['a']);
  });
}
