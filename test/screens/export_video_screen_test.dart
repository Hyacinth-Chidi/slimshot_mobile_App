import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:slimshotai/core/utils/held_work.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/services/export_ads.dart';
import 'package:slimshotai/features/video_editor/services/native_timeline_preview_service.dart';
import 'package:slimshotai/screens/export_video_screen.dart';

/// An exported video is the app's temporary file: leaving it throws it away,
/// and one nobody saved or shared is asked about first, as a compression's
/// result is.
void main() {
  const exported = '/cache/slimshot_export_1.mp4';
  late List<String> deleted;
  late _FakeExport engine;

  Future<void> record(Iterable<String> paths) async => deleted.addAll(paths);

  setUpAll(() => PathProviderPlatform.instance = _FakePathProvider());

  setUp(() {
    deleted = [];
    engine = _FakeExport();
  });

  /// The editor beneath, and the export screen pushed over it. While
  /// [exporting], its spinner never settles, so frames are pumped instead.
  Future<void> openExport(
    WidgetTester tester, {
    bool exporting = false,
    ExportAd? exportAd,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ExportVideoScreen(
                exportState: const VideoEditorState(),
                previewCanvasSize: const Size(720, 1280),
                targetHeight: 1080,
                targetFps: 30,
                preview: engine,
                deleteFiles: record,
                exportAd: exportAd ?? (_, _) async {},
              ),
            )),
            child: const Text('editor'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('editor'));
    if (exporting) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    } else {
      await tester.pumpAndSettle();
    }
  }

  group('a finished export', () {
    testWidgets('✕ asks when nobody kept it, and Cancel stays',
        (tester) async {
      await openExport(tester);
      await tester.tap(find.byKey(const Key('export_close')));
      await tester.pumpAndSettle();
      expect(find.text('Discard this video?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('discard_cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(ExportVideoScreen), findsOneWidget);
      expect(deleted, isEmpty);
    });

    testWidgets('Discard goes back to the editor and deletes the file',
        (tester) async {
      await openExport(tester);
      await tester.tap(find.byKey(const Key('export_close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discard_confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(ExportVideoScreen), findsNothing);
      expect(find.text('editor'), findsOneWidget);
      expect(deleted, [exported]);
    });

    testWidgets("the phone's Back asks the same", (tester) async {
      await openExport(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard this video?'), findsOneWidget);
    });

    testWidgets('a shared export leaves without asking', (tester) async {
      const share = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(share, (_) async => 'com.whatsapp');
      addTearDown(() => messenger.setMockMethodCallHandler(share, null));
      await openExport(tester);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export_close')));
      await tester.pumpAndSettle();
      expect(find.text('Discard this video?'), findsNothing);
      expect(find.byType(ExportVideoScreen), findsNothing);
      expect(deleted, [exported]);
    });
  });

  // A tap on the home screen widget only brings the app forward while an
  // export runs or a finished one nobody kept is on screen.
  group('holding the app where it is', () {
    const result = NativeExportResult(
      outputPath: exported,
      durationSeconds: 3,
      frameCount: 90,
      degradedTransitions: 0,
    );

    testWidgets('an export holds the app while it runs and until it is kept',
        (tester) async {
      const share = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(share, (_) async => 'com.whatsapp');
      addTearDown(() => messenger.setMockMethodCallHandler(share, null));
      engine.finish = Completer<NativeExportResult>();
      await openExport(tester, exporting: true);
      expect(HeldWork.instance.isHeld, isTrue);
      engine.finish!.complete(result);
      await tester.pumpAndSettle();
      expect(find.text('Share'), findsOneWidget);
      expect(HeldWork.instance.isHeld, isTrue);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(HeldWork.instance.isHeld, isFalse);
    });

    testWidgets('a failed export holds nothing', (tester) async {
      engine.finish = Completer<NativeExportResult>();
      await openExport(tester, exporting: true);
      engine.finish!.completeError(StateError('no encoder'));
      await tester.pumpAndSettle();
      expect(HeldWork.instance.isHeld, isFalse);
    });

    testWidgets('a cancelled export holds nothing', (tester) async {
      engine.finish = Completer<NativeExportResult>();
      await openExport(tester, exporting: true);
      await tester.tap(find.byKey(const Key('export_close')));
      await tester.pumpAndSettle();
      expect(find.byType(ExportVideoScreen), findsNothing);
      expect(HeldWork.instance.isHeld, isFalse);
    });
  });

  // The owner's call: an export's interstitial comes after it, before the
  // finished video — never during it, which would share the hardware video
  // codecs the export runs on, and never on Save.
  group("the export's ad", () {
    const result = NativeExportResult(
      outputPath: exported,
      durationSeconds: 3,
      frameCount: 90,
      degradedTransitions: 0,
    );

    testWidgets('the finished video appears only once the ad has closed',
        (tester) async {
      final ad = Completer<void>();
      int? height;
      bool Function()? wanted;
      engine.finish = Completer<NativeExportResult>();
      await openExport(tester, exporting: true, exportAd: (h, w) {
        height = h;
        wanted = w;
        return ad.future;
      });
      engine.finish!.complete(result);
      await tester.pump();
      await tester.pump();
      expect(height, 1080);
      expect(wanted!(), isTrue, reason: 'the screen is still there');
      expect(find.text('Share'), findsNothing, reason: 'the ad comes first');

      ad.complete();
      await tester.pumpAndSettle();
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('a failed export asks for no ad', (tester) async {
      var asked = 0;
      engine.finish = Completer<NativeExportResult>();
      await openExport(tester, exporting: true, exportAd: (_, _) async {
        asked++;
      });
      engine.finish!.completeError(StateError('no encoder'));
      await tester.pumpAndSettle();
      expect(asked, 0);
    });
  });

  testWidgets('Back during an export cancels it, as ✕ does, without asking',
      (tester) async {
    engine.finish = Completer<NativeExportResult>();
    await openExport(tester, exporting: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard this video?'), findsNothing);
    expect(engine.cancelled, isTrue);
    expect(find.byType(ExportVideoScreen), findsNothing);
  });
}

/// The engine, finishing at once unless [finish] is given.
class _FakeExport extends NativeTimelinePreviewService {
  Completer<NativeExportResult>? finish;
  bool cancelled = false;

  @override
  Stream<NativeTimelinePreviewEvent> get events => const Stream.empty();

  @override
  Future<NativeExportResult> exportVideo(
    VideoEditorState state, {
    required String outputPath,
    Size? previewCanvasSize,
    int frameRate = 30,
    int targetShortSidePx = 1080,
    void Function(String message)? onWarning,
  }) =>
      finish?.future ??
      Future.value(const NativeExportResult(
        outputPath: '/cache/slimshot_export_1.mp4',
        durationSeconds: 3,
        frameCount: 90,
        degradedTransitions: 0,
      ));

  @override
  Future<void> cancelExport() async => cancelled = true;
}

class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => '/cache';
}
