import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:slimshotai/features/privacy/logic/photo_metadata.dart';
import 'package:slimshotai/features/privacy/providers/privacy_provider.dart';
import 'package:slimshotai/features/privacy/widgets/privacy_report_view.dart';
import 'package:slimshotai/features/privacy/widgets/privacy_strip_view.dart';

final _full = PhotoMetadata(
  latitude: 6.5244,
  longitude: 3.3712,
  camera: 'Infinix X6833',
  taken: DateTime(2026, 10, 7, 14, 2),
);
const _clean = PhotoMetadata();
const _cameraOnly = PhotoMetadata(camera: 'Infinix X6833');

PrivacyState _state({
  int photos = 1,
  List<PhotoMetadata?>? found,
  bool processing = false,
  List<PhotoMetadata?>? remaining,
}) =>
    PrivacyState(
      inputFiles: [for (var i = 0; i < photos; i++) XFile('p$i.jpg')],
      originalSize: 4000000,
      found: found,
      isProcessing: processing,
      progress: 40,
      currentProcessingIndex: 1,
      outputPaths: remaining == null
          ? const []
          : [for (var i = 0; i < photos; i++) 'p$i-clean.jpg'],
      remaining: remaining,
    );

class _Calls {
  int back = 0, change = 0, strip = 0, cancel = 0;
  int close = 0, save = 0, share = 0, again = 0;
  final previews = <int>[];
}

void main() {
  late _Calls calls;
  setUp(() => calls = _Calls());

  Future<void> host(WidgetTester tester, Widget view,
      {Size size = const Size(390, 844), double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
        child: view,
      ),
    ));
    await tester.pump();
  }

  Widget strip(PrivacyState state) => PrivacyStripView(
        state: state,
        photo: const ColoredBox(color: Colors.blueGrey),
        photoAspectRatio: 3 / 4,
        photoInfo: 'JPG · 12 MP',
        thumbnails: [
          for (var i = 0; i < state.inputFiles.length; i++)
            const ColoredBox(color: Colors.grey),
        ],
        onPreview: calls.previews.add,
        onBack: () => calls.back++,
        onChangePhotos: () => calls.change++,
        onStrip: () => calls.strip++,
        onCancel: () => calls.cancel++,
      );

  Widget report(PrivacyState state) => PrivacyReportView(
        state: state,
        photo: const ColoredBox(color: Colors.blueGrey),
        photoAspectRatio: 3 / 4,
        thumbnails: [
          for (var i = 0; i < state.outputPaths.length; i++)
            const ColoredBox(color: Colors.grey),
        ],
        onPreview: calls.previews.add,
        onClose: () => calls.close++,
        onSave: () => calls.save++,
        onShare: () => calls.share++,
        onNew: () => calls.again++,
      );

  group('PrivacyStripView', () {
    testWidgets('one photo: what it really carries', (tester) async {
      await host(tester, strip(_state(found: [_full])));
      expect(find.text('Privacy strip'), findsOneWidget);
      expect(find.text('Found in this photo'), findsOneWidget);
      expect(find.text('6.52° N, 3.37° E'), findsOneWidget);
      expect(find.text('Infinix X6833'), findsOneWidget);
      expect(find.text('7 Oct 2026, 14:02'), findsOneWidget);
      // Only what is there: this photo has no author.
      expect(find.text('Author'), findsNothing);
      expect(find.text('Remove details'), findsOneWidget);
    });

    testWidgets('several photos: how many carry each kind', (tester) async {
      await host(tester, strip(_state(photos: 5, found: [_full, _full, _full, _cameraOnly, _clean])));
      expect(find.text('Found in these photos'), findsOneWidget);
      expect(find.text('In 3 of 5'), findsNWidgets(2)); // location, taken
      expect(find.text('In 4 of 5'), findsOneWidget); // camera
      expect(find.text('Remove from 5 photos'), findsOneWidget);
      await tester.tap(find.byKey(const Key('privacy_thumb_2')));
      expect(calls.previews, [2]);
    });

    testWidgets('nothing personal in it says so', (tester) async {
      await host(tester, strip(_state(found: [_clean])));
      expect(find.text('No location, camera or date in this photo.'), findsOneWidget);
      await host(tester, strip(_state(photos: 2, found: [_clean, null])));
      expect(find.text('No location, camera or date in these photos.'), findsOneWidget);
    });

    testWidgets('while the photos are still being read', (tester) async {
      await host(tester, strip(_state()));
      expect(find.byKey(const Key('privacy_reading')), findsOneWidget);
    });

    testWidgets('its actions', (tester) async {
      await host(tester, strip(_state(found: [_full])));
      await tester.tap(find.byKey(const Key('privacy_change')));
      await tester.tap(find.byKey(const Key('privacy_strip')));
      expect((calls.change, calls.strip), (1, 1));
    });

    testWidgets('removing: progress on the photo, and Cancel', (tester) async {
      await host(tester, strip(_state(photos: 5, processing: true, found: [_full])));
      expect(find.text('Removing details'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('2 of 5'), findsOneWidget);
      expect(find.byKey(const Key('privacy_change')), findsNothing);
      await tester.tap(find.byKey(const Key('privacy_cancel')));
      expect(calls.cancel, 1);
    });

    testWidgets('the title sits at the centre of the screen', (tester) async {
      await host(tester, strip(_state(found: [_full])));
      expect(tester.getCenter(find.text('Privacy strip')).dx, closeTo(195, 1));
    });

    testWidgets('a small phone with large text, and a wide screen', (tester) async {
      await host(tester, strip(_state(photos: 5, found: [_full, _full, _full, _full, _full])),
          size: const Size(320, 600), textScale: 1.3);
      expect(tester.takeException(), isNull);
      await host(tester, strip(_state(found: [_full])), size: const Size(1000, 640));
      expect(tester.takeException(), isNull);
      final photo = tester.getRect(find.byKey(const Key('privacy_preview')));
      final row = tester.getRect(find.text('Location'));
      expect(photo.right, lessThanOrEqualTo(row.left));
    });
  });

  group('PrivacyReportView', () {
    testWidgets('what was there, struck through and ticked', (tester) async {
      await host(tester, report(_state(found: [_full], remaining: [_clean])));
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Removed'), findsOneWidget);
      expect(find.text('Details removed'), findsOneWidget);
      final location = tester.widget<Text>(find.text('6.52° N, 3.37° E'));
      expect(location.style!.decoration, TextDecoration.lineThrough);
      expect(find.byKey(const Key('privacy_removed_tick')), findsNWidgets(3));
      expect(find.text('Save to gallery'), findsOneWidget);
    });

    testWidgets('a detail that survived is said, never ticked', (tester) async {
      await host(tester,
          report(_state(found: [_full], remaining: [const PhotoMetadata(latitude: 6.5, longitude: 3.3)])));
      expect(find.text('Still there'), findsOneWidget);
      expect(find.byKey(const Key('privacy_removed_tick')), findsNWidgets(2));
      expect(find.text('Details removed'), findsNothing);
    });

    testWidgets('several photos: the counts, and Save all', (tester) async {
      await host(tester, report(_state(
          photos: 5,
          found: [_full, _full, _full, _cameraOnly, _clean],
          remaining: List.filled(5, _clean))));
      expect(find.text('In 3 of 5'), findsNWidgets(2));
      expect(find.text('Save 5 to gallery'), findsOneWidget);
      expect(find.text('New photos'), findsOneWidget);
    });

    testWidgets('a photo that had nothing to remove says so', (tester) async {
      await host(tester, report(_state(found: [_clean], remaining: [_clean])));
      expect(find.text('No location, camera or date was in this photo.'), findsOneWidget);
    });

    testWidgets('its actions', (tester) async {
      await host(tester, report(_state(found: [_full], remaining: [_clean])));
      await tester.tap(find.byKey(const Key('privacy_close')));
      await tester.tap(find.byKey(const Key('privacy_save')));
      await tester.tap(find.byKey(const Key('privacy_share')));
      await tester.tap(find.byKey(const Key('privacy_new')));
      expect((calls.close, calls.save, calls.share, calls.again), (1, 1, 1, 1));
    });

    testWidgets('a small phone with large text', (tester) async {
      await host(tester,
          report(_state(photos: 5, found: List.filled(5, _full), remaining: List.filled(5, _clean))),
          size: const Size(320, 600), textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });
}
