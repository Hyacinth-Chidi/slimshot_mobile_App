import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/preview_text/preview_text_rules.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';

TextOverlayModel _text(String id, double start, double end) => TextOverlayModel(
      id: id,
      text: id,
      startTime: Duration(milliseconds: (start * 1000).round()),
      endTime: Duration(milliseconds: (end * 1000).round()),
    );

void main() {
  group('textsNear', () {
    test('near keeps what is near and drops what is far', () {
      final texts = [
        _text('a', 0, 1),
        _text('b', 5, 6),
        _text('c', 9, 10),
        _text('d', 20, 21),
      ];
      expect(textsNear(texts, 5, behind: 2, ahead: 8), {'b', 'c'});
      expect(textsNear([_text('long', 0, 60)], 30, behind: 2, ahead: 8), {'long'});
    });

    test('the window edges', () {
      // Half-open like a text's own span: one that has ended by the window's
      // start is out, one starting on its far edge is in.
      expect(textsNear([_text('ended', 2, 3)], 5, behind: 2, ahead: 8), isEmpty);
      expect(textsNear([_text('starting', 13, 14)], 5, behind: 2, ahead: 8), {'starting'});
    });
  });

  test('live first, then ahead, then behind', () {
    final texts = [
      _text('E', 0, 1),
      _text('B', 7, 8),
      _text('D', 2, 3),
      _text('A', 4, 6),
      _text('C', 6.5, 7),
    ];
    expect(previewAtlasOrder(texts, 5), ['A', 'C', 'B', 'D', 'E']);
  });

  test('being edited is selected and paused', () {
    expect(isTextBeingEdited('a', selectedTextId: 'a', isPlaying: false), isTrue);
    expect(isTextBeingEdited('a', selectedTextId: 'a', isPlaying: true), isFalse);
    expect(isTextBeingEdited('a', selectedTextId: 'b', isPlaying: false), isFalse);
    expect(isTextBeingEdited('a', selectedTextId: null, isPlaying: false), isFalse);
  });

  test('preview raster scale', () {
    expect(
      previewRasterScale(textureSize: const Size(720, 1280), canvasSize: const Size(270, 480)),
      closeTo(8 / 3, 1e-12),
    );
    expect(
      previewRasterScale(textureSize: const Size(720, 1280), canvasSize: const Size(1000, 1800)),
      1.0,
    );
    expect(previewRasterScale(textureSize: const Size(720, 1280), canvasSize: Size.zero), 1.0);
  });

  test('entry ids round-trip', () {
    expect(previewTextEntryId('a'), 'text_a');
    expect(previewTextIdOf(previewTextEntryId('a')), 'a');
    expect(previewTextIdOf('img_1'), isNull);
  });
}
