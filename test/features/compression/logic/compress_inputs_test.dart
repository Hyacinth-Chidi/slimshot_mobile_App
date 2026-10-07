import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:slimshotai/features/compression/logic/compress_inputs.dart';

void main() {
  test('a compress route takes one file or several', () {
    final one = XFile('a.mp4');
    expect(compressInputsFromExtra(one).map((f) => f.path), ['a.mp4']);
    // Shared from another app: several at once (the share sheet).
    expect(
      compressInputsFromExtra([XFile('a.mp4'), XFile('b.mp4')])
          .map((f) => f.path),
      ['a.mp4', 'b.mp4'],
    );
    expect(compressInputsFromExtra(null), isEmpty);
    expect(compressInputsFromExtra('junk'), isEmpty);
  });
}
