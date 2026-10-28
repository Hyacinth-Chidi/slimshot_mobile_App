import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/tile_preview_store.dart';

/// The sheets' tile drawings kept on the phone: drawn once per build of the
/// app, found by every later launch, never shown by another build.
void main() {
  late Directory support;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('tile_store_test');
  });

  tearDown(() async {
    if (await support.exists()) await support.delete(recursive: true);
  });

  TilePreviewStore storeFor(String? version) => TilePreviewStore(
        version: () async => version,
        supportDirectory: () async => support,
      );

  String folder(String version) =>
      '${support.path}/tile_previews/$version';

  final drawing = Uint8List.fromList([0xFF, 0xD8, 7, 0xFF, 0xD9]);
  const effects = TilePreviewKind.effects;
  const transitions = TilePreviewKind.transitions;

  test('a drawing kept by one launch is found by the next', () async {
    final first = storeFor('7-100');
    await first.write(effects, 'vignette', drawing);
    await first.flush();

    final next = storeFor('7-100');
    expect(next.has(effects, 'vignette'), isFalse,
        reason: 'nothing is known before the folder is read');
    await next.prepare();
    expect(next.has(effects, 'vignette'), isTrue);
    expect(await next.read(effects, 'vignette'), drawing);
  });

  test('a transition and an effect of one name are kept apart', () async {
    final store = storeFor('7-100');
    await store.write(effects, 'swirl', drawing);
    await store.flush();
    expect(store.has(effects, 'swirl'), isTrue);
    expect(store.has(transitions, 'swirl'), isFalse);
    expect(await store.read(transitions, 'swirl'), isNull);
  });

  test('nothing is found that was never kept', () async {
    final store = storeFor('7-100');
    await store.prepare();
    expect(store.has(effects, 'vignette'), isFalse);
    expect(await store.read(effects, 'vignette'), isNull);
  });

  test("another build's drawings are never shown, and are cleared away",
      () async {
    final old = storeFor('7-100');
    await old.write(effects, 'vignette', drawing);
    await old.flush();
    expect(Directory(folder('7-100')).existsSync(), isTrue);

    final updated = storeFor('8-200');
    await updated.prepare();
    expect(updated.has(effects, 'vignette'), isFalse);
    expect(await updated.read(effects, 'vignette'), isNull);
    expect(Directory(folder('7-100')).existsSync(), isFalse,
        reason: 'a phone keeps one build of drawings, not one per update');
  });

  test('without a build to keep them against, nothing is kept or shown',
      () async {
    final store = storeFor(null);
    await store.write(effects, 'vignette', drawing);
    await store.flush();
    expect(store.has(effects, 'vignette'), isFalse);
    expect(Directory('${support.path}/tile_previews').existsSync(), isFalse);
  });

  test('a phone that will not keep them draws each launch, and never throws',
      () async {
    final store = TilePreviewStore(
      version: () async => '7-100',
      supportDirectory: () async =>
          throw const FileSystemException('no support directory'),
    );
    await store.write(effects, 'vignette', drawing);
    await store.flush();
    expect(store.has(effects, 'vignette'), isFalse);
    expect(await store.read(effects, 'vignette'), isNull);
  });

  test('a drawing a launch died part-way through writing is not found, and '
      'is cleared away', () async {
    final first = storeFor('7-100');
    await first.prepare();
    final part = File('${folder('7-100')}/effects/vignette.bin.part')
      ..writeAsBytesSync(drawing);

    final next = storeFor('7-100');
    await next.prepare();
    expect(next.has(effects, 'vignette'), isFalse);
    expect(part.existsSync(), isFalse);
  });

  test('a forgotten drawing is gone, from this launch and the next', () async {
    final store = storeFor('7-100');
    await store.write(effects, 'vignette', drawing);
    await store.flush();
    await store.forget(effects, 'vignette');
    expect(store.has(effects, 'vignette'), isFalse);

    final next = storeFor('7-100');
    await next.prepare();
    expect(next.has(effects, 'vignette'), isFalse);
  });

  test('a name that is not a plain id is never kept', () async {
    final store = storeFor('7-100');
    await store.write(effects, '../escape', drawing);
    await store.flush();
    expect(store.has(effects, '../escape'), isFalse);
    expect(File('${folder('7-100')}/escape.bin').existsSync(), isFalse);
  });
}
