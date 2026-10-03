import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/new_text.dart';
import 'package:slimshotai/features/video_editor/logic/text_template_catalog.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/utils/font_utils.dart';

/// A new text: empty, at the playhead, and in the app's own default face.
void main() {
  const start = Duration(seconds: 2);
  const end = Duration(seconds: 5);
  const canvas = Size(400, 700);

  test('a new plain text starts in the bundled default face', () {
    final text = newText(id: 't', start: start, end: end, canvasSize: canvas);
    expect(text.fontFamily, kNewTextFontFamily);
    // Bundled, so it looks the same offline and on any phone.
    expect(customBundledFonts, contains(kNewTextFontFamily));
    expect(text.text, isEmpty);
    expect((text.startTime, text.endTime), (start, end));
    expect(text.referenceCanvasSize, canvas);
  });

  test('a template keeps its own face', () {
    final template = kTextTemplates.firstWhere((t) => t.fontFamily != kNewTextFontFamily);
    final text = newText(id: 't', start: start, end: end, canvasSize: canvas, template: template);
    expect(text.fontFamily, template.fontFamily);
    expect(template.isAppliedTo(text), isTrue);
    expect(text.text, isEmpty);
  });

  test('a draft that names no face still opens in the one it was made in', () {
    final json = TextOverlayModel(id: 'old', text: 'Old').toJson()..remove('fontFamily');
    expect(TextOverlayModel.fromJson(json).fontFamily, 'Roboto');
  });
}
