import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'features/compression/logic/compress_inputs.dart';
import 'package:animations/animations.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/file_utils.dart';

import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/media_picker_service.dart';
import 'core/services/removed_features.dart';
import 'core/models/update_info.dart';
import 'core/models/draft_project.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'screens/compress_video_screen.dart';
import 'screens/compress_image_screen.dart';
import 'screens/result_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/update_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/privacy_result_screen.dart';
import 'screens/video_editor_screen.dart';
import 'screens/workspace_screen.dart';
import 'screens/main_shell_screen.dart';

import 'features/sharing/share_intent_service.dart';
import 'core/legal/third_party_licences.dart';
import 'core/utils/held_work.dart';
import 'core/widgets/launch_splash.dart';
import 'features/compression/providers/compression_provider.dart';
import 'features/home_widget/home_widget_sync.dart';
import 'features/home_widget/launch_actions.dart';
import 'features/privacy/providers/privacy_provider.dart';
import 'features/video_editor/providers/video_editor_notifier.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  // Use the system gallery sheet for picking rather than the Files app.
  MediaPickerService.enableAndroidPhotoPicker();
  // Notices for code the app ships that no package declares (the ported
  // transitions), on Flutter's licences page in Settings.
  registerThirdPartyLicences();
  // The ads SDK is not started here: whatever shows an ad starts it, after
  // Google's consent step (`AdsSdk`) — a screen with an ad placement when it
  // opens (`AdService.prepare`), credit ads on the first Watch an ad. A user
  // who never meets an ad never starts it.

  // The splash's pictures are decoded while the native splash still shows,
  // so the app's first frame can repeat it exactly (LaunchSplash).
  final (prefs, launchArt) = await (
    SharedPreferences.getInstance(),
    LaunchSplashArt.load(),
  ).wait;
  final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;
  final String initialRoute = hasSeenOnboarding ? '/home' : '/onboarding';

  initializeAppRouter(initialRoute);

  runApp(ProviderScope(child: SlimShotApp(launchArt: launchArt)));

  FlutterNativeSplash.remove();
  unawaited(FileUtils.cleanupStartup());
  unawaited(forgetRemovedFeatures(prefs));
}

late GoRouter appRouter;

void initializeAppRouter(String initialRoute) {
  appRouter = createAppRouter(initialRoute);
}

/// Creates a premium [CustomTransitionPage] using the Material Motion
/// SharedAxisTransition on the Z-axis for a layered, cinematic feel.
CustomTransitionPage<void> _buildTransitionPage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 400),
    reverseTransitionDuration: const Duration(milliseconds: 350),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: SharedAxisTransitionType.scaled,
        child: child,
      );
    },
  );
}

GoRouter createAppRouter(String initialRoute) {
  return GoRouter(
    initialLocation: initialRoute,
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => initialRoute,
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => _buildTransitionPage(
          state: state,
          child: const OnboardingScreen(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShellScreen(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: HomeScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/workspace',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: WorkspaceScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: SettingsScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/compress/video',
        pageBuilder: (context, state) {
          return _buildTransitionPage(
            state: state,
            child: CompressVideoScreen(
              initialVideos: compressInputsFromExtra(state.extra),
            ),
          );
        },
      ),
      GoRoute(
        path: '/edit/video',
        pageBuilder: (context, state) {
          final extra = state.extra;
          final draft = extra is DraftProject ? extra : null;
          // A project can start from several photos and videos at once, so the
          // route accepts a list as well as the single-file and draft forms.
          final initialMedia = switch (extra) {
            final List<XFile> files => files,
            final XFile file => [file],
            _ => const <XFile>[],
          };
          return _buildTransitionPage(
            state: state,
            child: VideoEditorScreen(
              initialMedia: initialMedia,
              draft: draft,
            ),
          );
        },
      ),
      GoRoute(
        path: '/compress/image',
        pageBuilder: (context, state) {
          return _buildTransitionPage(
            state: state,
            child: CompressImageScreen(
              initialImages: compressInputsFromExtra(state.extra),
            ),
          );
        },
      ),
      GoRoute(
        path: '/result',
        pageBuilder: (context, state) => _buildTransitionPage(
          state: state,
          child: const ResultScreen(),
        ),
      ),

      GoRoute(
        path: '/privacy',
        pageBuilder: (context, state) {
          return _buildTransitionPage(
            state: state,
            child: PrivacyScreen(
              initialImages: compressInputsFromExtra(state.extra),
            ),
          );
        },
      ),
      GoRoute(
        path: '/privacy/result',
        pageBuilder: (context, state) => _buildTransitionPage(
          state: state,
          child: const PrivacyResultScreen(),
        ),
      ),

      GoRoute(
        path: '/update',
        pageBuilder: (context, state) {
          final info = state.extra as UpdateInfo?;
          final safeInfo = info ??
              const UpdateInfo(
                latestVersion: '2.0.0',
                latestBuildNumber: 2,
                forceUpdate: false,
                title: 'Update Available',
                releaseNotes: [],
                updateUrl: '',
                minSupportedVersion: '2.0.0',
              );
          return _buildTransitionPage(
            state: state,
            child: UpdateScreen(updateInfo: safeInfo),
          );
        },
      ),
    ],
  );
}

class SlimShotApp extends ConsumerStatefulWidget {
  final bool enableShareIntents;

  /// Keeps the home screen widget on the last edit and takes the taps on it
  /// and on the icon's menu. Where the platform has neither, nothing answers
  /// and nothing happens.
  final bool enableHomeWidget;

  /// The splash's pictures, decoded before the first frame; null shows no
  /// splash (tests, or pictures that failed to load).
  final LaunchSplashArt? launchArt;

  const SlimShotApp({
    super.key,
    this.enableShareIntents = true,
    this.enableHomeWidget = true,
    this.launchArt,
  });

  @override
  ConsumerState<SlimShotApp> createState() => _SlimShotAppState();
}

class _SlimShotAppState extends ConsumerState<SlimShotApp> {
  late final ShareIntentService _shareService;
  HomeWidgetSync? _homeWidget;
  LaunchChannel? _launches;

  @override
  void initState() {
    super.initState();
    if (widget.enableShareIntents) {
      _shareService = ShareIntentService(ref);
      _shareService.initialize();
    }
    if (widget.enableHomeWidget) {
      _homeWidget = HomeWidgetSync()..start();
      final router = LaunchRouter(
        busy: _holdsWork,
        openDraftId: () => ref.exists(videoEditorProvider)
            ? ref.read(videoEditorProvider).draftId
            : null,
        onboardingSeen: () async =>
            (await SharedPreferences.getInstance())
                .getBool('hasSeenOnboarding') ??
            false,
        // Explicit: the editor's own save as it closes runs a frame after the
        // screen has gone.
        saveOpenEdit: () async {
          if (ref.exists(videoEditorProvider)) {
            await ref.read(videoEditorProvider.notifier).saveDraft();
          }
        },
        goHome: () => appRouter.go('/home'),
        untilEditorGone: _untilEditorGone,
      );
      _launches = LaunchChannel(
        onAction: (action) => unawaited(router.handle(action)),
      );
      unawaited(_launches!.start());
    }
  }

  /// Whether going Home now would throw something away: an export, a
  /// compression or a strip under way, a result nobody kept, a caption run,
  /// a voice take ([HeldWork]) — or skip the update screen, which a forced
  /// update keeps on screen.
  bool _holdsWork() {
    if (HeldWork.instance.isHeld) return true;
    if (ref.exists(compressionProvider) &&
        ref.read(compressionProvider).isProcessing) {
      return true;
    }
    if (ref.exists(privacyProvider) &&
        ref.read(privacyProvider).isProcessing) {
      return true;
    }
    return appRouter.routerDelegate.currentConfiguration.uri.path ==
        '/update';
  }

  /// The editor leaves through its route's exit; its state goes with the
  /// last frame of it.
  Future<void> _untilEditorGone() async {
    for (var frame = 0;
        frame < 120 && ref.exists(videoEditorProvider);
        frame++) {
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  @override
  void dispose() {
    if (widget.enableShareIntents) {
      _shareService.dispose();
    }
    _homeWidget?.dispose();
    _launches?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SlimShotAI',
      theme: AppTheme.darkTheme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      // The native splash, then the app lighting it up over whatever the
      // router opened on, which builds underneath and is there for the fade.
      builder: (context, child) => LaunchSplash(
        art: widget.launchArt,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
