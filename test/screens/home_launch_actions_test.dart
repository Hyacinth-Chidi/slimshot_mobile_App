import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/core/services/draft_service.dart';
import 'package:slimshotai/core/utils/held_work.dart';
import 'package:slimshotai/features/home_widget/home_widget_sync.dart';
import 'package:slimshotai/features/home_widget/launch_actions.dart';
import 'package:slimshotai/main.dart';
import 'package:slimshotai/screens/home_screen.dart';

/// The gallery, scripted, counting what each of Home's buttons asks for.
class _FakePicker extends ImagePickerPlatform {
  int mediaPicks = 0;
  int videoPicks = 0;
  XFile? video;

  /// What "New video" asks for: videos and photos together.
  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async {
    mediaPicks++;
    return const [];
  }

  /// What "Compress video" asks for.
  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    videoPicks++;
    return video;
  }
}

Future<void> _settle(WidgetTester tester) async {
  // The home screen has looping animations, so it never settles by itself.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

DraftProject _draft(String id) => DraftProject(
      id: id,
      sourceVideoPath: '/v.mp4',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      durationSeconds: 30,
      segments: const [],
      textOverlays: const [],
      imageOverlays: const [],
      videoOverlays: const [],
      audioTracks: const [],
      selectedRatioName: 'ratio9x16',
      customCropRect: const [0, 0, 1, 1],
      videoScale: 1,
      videoPanX: 0,
      videoPanY: 0,
      filterIntensity: 1,
      backgroundType: 'black',
      backgroundColorValue: 0xFF000000,
      backgroundBlurIntensity: 20,
      isMuted: false,
    );

/// A tap on the home screen widget or the icon's menu runs the handler
/// Home's own button runs — so the gallery, its permission dialog and its
/// error toasts are exactly Home's — and never over work in progress.
void main() {
  late _FakePicker picker;

  setUp(() {
    SharedPreferences.setMockInitialValues({'hasSeenOnboarding': true});
    picker = _FakePicker();
    ImagePickerPlatform.instance = picker;
    LaunchActions.instance.take();
  });

  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  group('Home runs the action', () {
    Future<void> pumpHome(WidgetTester tester) async {
      phoneSize(tester);
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(
            path: '/edit/video',
            builder: (_, state) => Scaffold(
              body: Text(switch (state.extra) {
                final DraftProject draft => 'editor ${draft.id}',
                _ => 'editor new',
              }),
            ),
          ),
          GoRoute(
            path: '/compress/video',
            builder: (_, __) => const Scaffold(body: Text('compress')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await _settle(tester);
    }

    testWidgets('New video opens the gallery, as its card does',
        (tester) async {
      await pumpHome(tester);
      LaunchActions.instance.post(const NewVideo());
      await _settle(tester);
      expect(picker.mediaPicks, 1);
      expect(LaunchActions.instance.pending, isNull);
    });

    testWidgets('Compress video opens the videos, as its card does',
        (tester) async {
      picker.video = XFile('/cache/v.mp4');
      await pumpHome(tester);
      LaunchActions.instance.post(const CompressVideo());
      await _settle(tester);
      expect(picker.videoPicks, 1);
      expect(find.text('compress'), findsOneWidget);
    });

    testWidgets('Continue opens that edit', (tester) async {
      await tester.runAsync(() => DraftService.saveDraft(_draft('d1')));
      await pumpHome(tester);
      LaunchActions.instance.post(const ContinueEdit('d1'));
      await _settle(tester);
      expect(find.text('editor d1'), findsOneWidget);
    });

    testWidgets('Continue on a deleted edit says so and stays Home',
        (tester) async {
      await pumpHome(tester);
      LaunchActions.instance.post(const ContinueEdit('gone'));
      await _settle(tester);
      expect(find.text('That edit was deleted.'), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.textContaining('editor'), findsNothing);
    });

    testWidgets('an action posted before Home is up runs once it appears, '
        'once', (tester) async {
      LaunchActions.instance.post(const NewVideo());
      await pumpHome(tester);
      expect(picker.mediaPicks, 1);
      await _settle(tester);
      expect(picker.mediaPicks, 1);
    });
  });

  group('the app takes the taps', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel(kHomeWidgetChannel);
    late List<(String, Object?)> calls;
    Object? startAction;

    setUp(() {
      calls = [];
      startAction = null;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add((call.method, call.arguments));
        return call.method == 'takeLaunchAction' ? startAction : null;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> pumpApp(WidgetTester tester) async {
      phoneSize(tester);
      initializeAppRouter('/home');
      await tester.pumpWidget(
        const ProviderScope(child: SlimShotApp(enableShareIntents: false)),
      );
      await _settle(tester);
    }

    Future<void> tap(WidgetTester tester, Map<String, Object?> action) async {
      await messenger.handlePlatformMessage(
        kHomeWidgetChannel,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall('launchAction', action)),
        (_) {},
      );
      await _settle(tester);
    }

    testWidgets('the action the app started with runs on Home',
        (tester) async {
      startAction = {'action': 'new_video', 'draftId': null};
      await pumpApp(tester);
      expect(picker.mediaPicks, 1);
    });

    testWidgets('a later tap runs on Home too', (tester) async {
      await pumpApp(tester);
      await tap(tester, {'action': 'new_video', 'draftId': null});
      expect(picker.mediaPicks, 1);
    });

    testWidgets('the widget is told the last edit at launch', (tester) async {
      await pumpApp(tester);
      final sent = calls.where((c) => c.$1 == 'setLastEdit').toList();
      expect(sent, hasLength(1));
      expect(sent.single.$2, isNull);
    });

    testWidgets('while work is held, a tap only brings the app forward',
        (tester) async {
      final work = Object();
      HeldWork.instance.hold(work);
      addTearDown(() => HeldWork.instance.release(work));
      await pumpApp(tester);
      await tap(tester, {'action': 'new_video', 'draftId': null});
      expect(picker.mediaPicks, 0);
      expect(LaunchActions.instance.pending, isNull);
    });
  });
}
