import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/chroma/chroma_key.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/chroma_key_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/value_ruler.dart';

/// The Chroma key sheet: an on/off, a colour to key, and three rulers.
void main() {
  VideoSegment clip(String id, {ChromaKey key = ChromaKey.none}) =>
      VideoSegment(id: id, sourceStart: 0, sourceEnd: 10, chromaKey: key);

  VideoEditorNotifier notifierWith(List<VideoSegment> segments,
          {String? selected}) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          segments: segments,
          selectedSegmentId: selected,
          isClipSelected: selected != null,
        );

  Future<void> pump(WidgetTester tester, VideoEditorNotifier n) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => n)],
        child: const MaterialApp(home: Scaffold(body: ChromaKeySheet())),
      ),
    );
  }

  testWidgets('opens off, with the preset colours offered', (tester) async {
    await pump(tester, notifierWith([clip('a')], selected: 'a'));
    expect(find.byKey(const Key('chroma_enabled')), findsOneWidget);
    for (final id in ['green', 'blue']) {
      expect(find.byKey(Key('chroma_colour_$id')), findsOneWidget);
    }
  });

  testWidgets('turning it on keys green by default', (tester) async {
    final n = notifierWith([clip('a')], selected: 'a');
    await pump(tester, n);

    await tester.tap(find.byKey(const Key('chroma_enabled')));
    await tester.pump();

    final key = n.state.segments.single.chromaKey;
    expect(key.enabled, isTrue);
    expect(key.keyG, 1.0);
    expect(key.keyR, 0.0);
  });

  testWidgets('choosing blue turns the key on and sets that colour',
      (tester) async {
    final n = notifierWith([clip('a')], selected: 'a');
    await pump(tester, n);

    await tester.tap(find.byKey(const Key('chroma_colour_blue')));
    await tester.pump();

    final key = n.state.segments.single.chromaKey;
    expect(key.enabled, isTrue);
    expect(key.keyB, 1.0);
    expect(key.keyG, 0.0);
  });

  testWidgets('the three rulers appear only once the key is on',
      (tester) async {
    final n = notifierWith([clip('a')], selected: 'a');
    await pump(tester, n);
    // Off: nothing to tune.
    expect(find.byType(ValueRuler), findsNothing);

    n.setClipChromaKey(const ChromaKey(enabled: true));
    await tester.pump();
    // Similarity, smoothness, spill — one shown at a time behind pills.
    expect(find.byType(ValueRuler), findsOneWidget);
    for (final name in ['Similarity', 'Smoothness', 'Spill']) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('a ruler drag writes the selected clip, live', (tester) async {
    final n = notifierWith(
      [clip('a', key: const ChromaKey(enabled: true, similarity: 0.4)), clip('b')],
      selected: 'a',
    );
    await pump(tester, n);

    await tester.drag(find.byType(ValueRuler), const Offset(40, 0));
    await tester.pumpAndSettle();

    expect(n.state.segments.first.chromaKey.similarity, greaterThan(0.4));
    // The other clip is untouched.
    expect(n.state.segments.last.chromaKey, ChromaKey.none);
  });

  testWidgets('a whole drag is one undo step', (tester) async {
    final n = notifierWith(
      [clip('a', key: const ChromaKey(enabled: true, similarity: 0.4))],
      selected: 'a',
    );
    await pump(tester, n);

    await tester.drag(find.byType(ValueRuler), const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(n.state.segments.single.chromaKey.similarity, greaterThan(0.4));

    n.undo();
    expect(n.state.segments.single.chromaKey.similarity, closeTo(0.4, 1e-9));
  });

  testWidgets('switching pills moves the ruler to that parameter',
      (tester) async {
    final n = notifierWith(
      [clip('a', key: const ChromaKey(enabled: true, spill: 0.2))],
      selected: 'a',
    );
    await pump(tester, n);

    await tester.tap(find.text('Spill'));
    await tester.pump();
    await tester.drag(find.byType(ValueRuler), const Offset(30, 0));
    await tester.pumpAndSettle();

    expect(n.state.segments.single.chromaKey.spill, greaterThan(0.2));
    // Similarity was not the one being dragged.
    expect(n.state.segments.single.chromaKey.similarity, closeTo(0.4, 1e-9));
  });

  testWidgets('turning it off keeps the settings for when it comes back',
      (tester) async {
    final n = notifierWith(
      [clip('a', key: const ChromaKey(enabled: true, similarity: 0.7))],
      selected: 'a',
    );
    await pump(tester, n);

    await tester.tap(find.byKey(const Key('chroma_enabled')));
    await tester.pump();

    final key = n.state.segments.single.chromaKey;
    expect(key.enabled, isFalse);
    // The tuning survives, so toggling is not destructive.
    expect(key.similarity, closeTo(0.7, 1e-9));
  });
}
