import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:slimshotai/core/utils/held_work.dart';
import 'package:slimshotai/features/compression/providers/compression_provider.dart';
import 'package:slimshotai/features/compression/services/image_compression_service.dart';
import 'package:slimshotai/features/compression/services/video_compression_service.dart';
import 'package:slimshotai/features/privacy/providers/privacy_provider.dart';
import 'package:slimshotai/features/privacy/services/photo_metadata_service.dart';
import 'package:slimshotai/features/privacy/services/photo_stripper.dart';
import 'package:slimshotai/screens/compress_image_screen.dart';
import 'package:slimshotai/screens/compress_video_screen.dart';
import 'package:slimshotai/screens/privacy_result_screen.dart';
import 'package:slimshotai/screens/privacy_screen.dart';
import 'package:slimshotai/screens/result_screen.dart';

/// A finished result's files are the app's own temporary copies: they go
/// when the result is left, and one nobody saved or shared is asked about
/// first. The photos a screen was handed — the picker's copies — go when
/// that screen closes.
void main() {
  const output = '/cache/slimshot_temp_out.jpg';
  const picked = '/cache/3f2a/IMG_20261028.jpg';
  late List<String> deleted;

  Future<void> record(Iterable<String> paths) async => deleted.addAll(paths);

  setUp(() => deleted = []);

  Future<GoRouter> pumpRouter(
    WidgetTester tester, {
    required String initial,
    required List<RouteBase> routes,
    List<Override> overrides = const [],
  }) async {
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
        ...routes,
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    return router;
  }

  Override compressed() => compressionProvider.overrideWith(
        (ref) => CompressionNotifier(
          VideoCompressionService(),
          ImageCompressionService(),
        )..state = CompressionState(
            inputFiles: [XFile(picked)],
            outputPaths: const [output],
            originalSize: 1000,
            compressedSize: 400,
          ),
      );

  Future<void> openResult(WidgetTester tester) => pumpRouter(
        tester,
        initial: '/result',
        routes: [
          GoRoute(
            path: '/result',
            builder: (_, __) => ResultScreen(deleteFiles: record),
          ),
        ],
        overrides: [compressed()],
      );

  group('a compression result', () {
    testWidgets('✕ on a result nobody kept asks, and Cancel stays',
        (tester) async {
      await openResult(tester);
      await tester.tap(find.byKey(const Key('result_close')));
      await tester.pumpAndSettle();
      expect(find.text('Discard this photo?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('discard_cancel')));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsNothing);
      expect(deleted, isEmpty);
    });

    testWidgets('Discard goes home and deletes the result, not the picked '
        'photo', (tester) async {
      await openResult(tester);
      await tester.tap(find.byKey(const Key('result_close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discard_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(deleted, [output]);
    });

    testWidgets("the phone's Back asks the same", (tester) async {
      await openResult(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard this photo?'), findsOneWidget);
    });

    testWidgets('a shared result leaves without asking', (tester) async {
      const share = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(share, (_) async => 'com.whatsapp');
      addTearDown(() => messenger.setMockMethodCallHandler(share, null));
      await openResult(tester);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('result_close')));
      await tester.pumpAndSettle();
      expect(find.text('Discard this photo?'), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(deleted, [output]);
    });

    // A tap on the home screen widget only brings the app forward while a
    // result nobody kept is on screen.
    testWidgets('a compression result holds the app until it is shared',
        (tester) async {
      const share = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(share, (_) async => 'com.whatsapp');
      addTearDown(() => messenger.setMockMethodCallHandler(share, null));
      await openResult(tester);
      expect(HeldWork.instance.isHeld, isTrue);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(HeldWork.instance.isHeld, isFalse);
    });
  });

  testWidgets("a strip's result holds the app until Discard takes it away",
      (tester) async {
    final router = await pumpRouter(
      tester,
      initial: '/strip',
      routes: [
        GoRoute(
          path: '/strip',
          builder: (_, __) => const Scaffold(body: Text('strip screen')),
        ),
        GoRoute(
          path: '/privacy/result',
          builder: (_, __) => PrivacyResultScreen(deleteFiles: record),
        ),
      ],
      overrides: [
        privacyProvider.overrideWith(
          (ref) => PrivacyNotifier(
            reader: ChannelPhotoMetadataService(),
            stripper: DefaultPhotoStripper(),
          )..state = PrivacyState(
              inputFiles: [XFile(picked)],
              outputPaths: const [output],
              originalSize: 1000,
              strippedSize: 900,
            ),
        ),
      ],
    );
    expect(HeldWork.instance.isHeld, isFalse);
    router.push('/privacy/result');
    await tester.pumpAndSettle();
    expect(HeldWork.instance.isHeld, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discard_confirm')));
    await tester.pumpAndSettle();
    expect(find.text('strip screen'), findsOneWidget);
    expect(HeldWork.instance.isHeld, isFalse);
  });

  // Back from the report steps back to the strip screen, as it always has;
  // what it leaves behind is the stripped copies, so it asks too.
  testWidgets('Back on a strip nobody kept asks, then steps back to the strip '
      'screen and deletes the stripped copy', (tester) async {
    final router = await pumpRouter(
      tester,
      initial: '/strip',
      routes: [
        GoRoute(
          path: '/strip',
          builder: (_, __) => const Scaffold(body: Text('strip screen')),
        ),
        GoRoute(
          path: '/privacy/result',
          builder: (_, __) => PrivacyResultScreen(deleteFiles: record),
        ),
      ],
      overrides: [
        privacyProvider.overrideWith(
          (ref) => PrivacyNotifier(
            reader: ChannelPhotoMetadataService(),
            stripper: DefaultPhotoStripper(),
          )..state = PrivacyState(
              inputFiles: [XFile(picked)],
              outputPaths: const [output],
              originalSize: 1000,
              strippedSize: 900,
            ),
        ),
      ],
    );
    router.push('/privacy/result');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard this photo?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('discard_confirm')));
    await tester.pumpAndSettle();
    expect(find.text('strip screen'), findsOneWidget);
    expect(deleted, [output]);
  });

  group('a screen handed picked files deletes them when it closes', () {
    for (final (name, screen) in [
      (
        'Compress photo',
        (List<XFile> photos) =>
            CompressImageScreen(initialImages: photos, deleteFiles: record),
      ),
      (
        'Privacy Strip',
        (List<XFile> photos) =>
            PrivacyScreen(initialImages: photos, deleteFiles: record),
      ),
      (
        'Compress video',
        (List<XFile> videos) =>
            CompressVideoScreen(initialVideos: videos, deleteFiles: record),
      ),
    ]) {
      testWidgets(name, (tester) async {
        final router = await pumpRouter(
          tester,
          initial: '/home',
          routes: [
            GoRoute(
              path: '/screen',
              builder: (_, __) => screen([XFile(picked)]),
            ),
          ],
        );
        router.push('/screen');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(deleted, isEmpty, reason: 'still in use while it is open');
        router.go('/home');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(deleted, [picked]);
      });
    }
  });

  testWidgets('Change photos deletes the photos it replaces, and the new ones '
      'go when the screen closes', (tester) async {
    const next = '/cache/9c1d/IMG_20261029.jpg';
    const picker = MethodChannel('plugins.flutter.io/image_picker');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      picker,
      (call) async => call.method == 'pickMultiImage' ? [next] : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(picker, null));
    final router = await pumpRouter(
      tester,
      initial: '/home',
      routes: [
        GoRoute(
          path: '/strip',
          builder: (_, __) =>
              PrivacyScreen(initialImages: [XFile(picked)], deleteFiles: record),
        ),
      ],
      overrides: [privacyProvider.overrideWith((ref) => _InstantPrivacy())],
    );
    router.push('/strip');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('privacy_change')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(deleted, [picked]);
    router.go('/home');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(deleted, [picked, next]);
  });
}

/// Takes its photos at once: the real one waits on reading their sizes,
/// file IO a widget test never lets finish.
class _InstantPrivacy extends PrivacyNotifier {
  _InstantPrivacy()
      : super(
          reader: ChannelPhotoMetadataService(),
          stripper: DefaultPhotoStripper(),
        );

  @override
  Future<void> setInputFiles(List<XFile> files) async =>
      state = PrivacyState(inputFiles: files);
}
