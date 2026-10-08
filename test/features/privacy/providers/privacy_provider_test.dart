import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:slimshotai/features/privacy/logic/photo_metadata.dart';
import 'package:slimshotai/features/privacy/providers/privacy_provider.dart';
import 'package:slimshotai/features/privacy/services/photo_metadata_service.dart';

const _located = PhotoMetadata(latitude: 6.5, longitude: 3.4, camera: 'X');

/// Reads what [byPath] says a file holds; a path ending "-clean" holds
/// nothing unless [leaky] says otherwise.
class _FakeReader implements PhotoMetadataService {
  _FakeReader(this.byPath, {this.leaky = const {}});
  final Map<String, PhotoMetadata?> byPath;
  final Set<String> leaky;
  final reads = <String>[];

  @override
  Future<PhotoMetadata?> read(String path) async {
    reads.add(path);
    if (path.endsWith('-clean')) {
      final original = path.substring(0, path.length - '-clean'.length);
      return leaky.contains(original) ? byPath[original] : const PhotoMetadata();
    }
    return byPath[path];
  }
}

class _FakeStripper implements PhotoStripper {
  final stripped = <String>[];
  Completer<void>? hold;

  @override
  Future<String> strip(String inputPath) async {
    stripped.add(inputPath);
    if (hold != null) await hold!.future;
    final out = '$inputPath-clean';
    File(out).writeAsBytesSync(List.filled(90, 2));
    return out;
  }
}

void main() {
  late Directory dir;
  late List<XFile> files;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('privacy');
    files = [
      for (final name in ['a.jpg', 'b.heic'])
        XFile((File('${dir.path}/$name')..writeAsBytesSync(List.filled(100, 1))).path),
    ];
  });

  PrivacyNotifier notifier(_FakeReader reader, [_FakeStripper? stripper]) =>
      PrivacyNotifier(reader: reader, stripper: stripper ?? _FakeStripper());

  test('picking photos reads what each one carries', () async {
    final reader = _FakeReader({files[0].path: _located, files[1].path: null});
    final n = notifier(reader);
    await n.setInputFiles(files);
    expect(n.state.originalSize, 200);
    expect(n.state.found, [_located, null]);
  });

  test('stripping cleans every photo and reads each result again', () async {
    final reader = _FakeReader({files[0].path: _located, files[1].path: _located});
    final stripper = _FakeStripper();
    final n = notifier(reader, stripper);
    await n.setInputFiles(files);
    await n.stripMetadata();

    expect(stripper.stripped, [files[0].path, files[1].path]);
    expect(n.state.outputPaths, ['${files[0].path}-clean', '${files[1].path}-clean']);
    expect(reader.reads, containsAll(n.state.outputPaths));
    expect(n.state.remaining!.every((m) => m != null && m.isEmpty), isTrue);
    expect(n.state.isProcessing, isFalse);
  });

  test('what survived the strip is reported, never assumed gone', () async {
    final reader = _FakeReader(
      {files[0].path: _located, files[1].path: _located},
      leaky: {files[1].path},
    );
    final n = notifier(reader);
    await n.setInputFiles(files);
    await n.stripMetadata();
    expect(n.state.remaining![0]!.isEmpty, isTrue);
    expect(n.state.remaining![1]!.hasLocation, isTrue);
  });

  test('progress says which photo is being cleaned', () async {
    final stripper = _FakeStripper()..hold = Completer<void>();
    final n = notifier(_FakeReader({}), stripper);
    await n.setInputFiles(files);
    final run = n.stripMetadata();
    await Future<void>.delayed(Duration.zero);
    expect(n.state.isProcessing, isTrue);
    expect(n.state.currentProcessingIndex, 0);
    stripper.hold!.complete();
    await run;
    expect(n.state.progress, 100);
  });

  test('cancel stops the run and keeps the photos', () async {
    final stripper = _FakeStripper()..hold = Completer<void>();
    final n = notifier(_FakeReader({files[0].path: _located}), stripper);
    await n.setInputFiles(files);
    final run = n.stripMetadata();
    await Future<void>.delayed(Duration.zero);
    n.cancel();
    stripper.hold!.complete();
    await run;
    expect(n.state.isProcessing, isFalse);
    expect(n.state.outputPaths, isEmpty);
    expect(n.state.inputFiles, files);
    expect(n.state.found, isNotNull);
  });
}
