import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animations/animations.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/file_utils.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:media_kit/media_kit.dart';

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
import 'screens/history_screen.dart';
import 'screens/video_editor_screen.dart';
import 'screens/workspace_screen.dart';

import 'features/sharing/share_intent_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  MobileAds.instance.initialize();
  GoogleFonts.config.allowRuntimeFetching = true;

  String initialRoute = '/onboarding';
  try {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;
    initialRoute = hasSeenOnboarding ? '/home' : '/onboarding';
  } catch (e) {
    debugPrint('⚠️ SharedPreferences failed: $e');
  }

  initializeAppRouter(initialRoute);

  runApp(const ProviderScope(child: SlimShotApp()));

  FileUtils.cleanupStartup();
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
        path: '/onboarding',
        pageBuilder: (context, state) => _buildTransitionPage(
          state: state,
          child: const OnboardingScreen(),
        ),
      ),
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) => _buildTransitionPage(
          state: state,
          child: const HomeScreen(),
        ),
      ),
      GoRoute(
        path: '/compress/video',
        pageBuilder: (context, state) {
          final initialVideo = state.extra is XFile ? state.extra as XFile : null;
          return _buildTransitionPage(
            state: state,
            child: CompressVideoScreen(initialVideo: initialVideo),
          );
        },
      ),
      GoRoute(
        path: '/edit/video',
        pageBuilder: (context, state) {
          final extra = state.extra;
          final initialVideo = extra is XFile ? extra : null;
          final draft = extra is DraftProject ? extra : null;
          return _buildTransitionPage(
            state: state,
            child: VideoEditorScreen(
              initialVideo: initialVideo,
              draft: draft,
            ),
          );
        },
      ),
      GoRoute(
        path: '/compress/image',
        pageBuilder: (context, state) {
          final initialImages = state.extra as List<XFile>?;
          return _buildTransitionPage(
            state: state,
            child: CompressImageScreen(initialImages: initialImages),
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
        path: '/settings',
        pageBuilder: (context, state) => _buildTransitionPage(
          state: state,
          child: const SettingsScreen(),
        ),
      ),
      GoRoute(
        path: '/privacy',
        pageBuilder: (context, state) {
          final initialImages = state.extra as List<XFile>?;
          return _buildTransitionPage(
            state: state,
            child: PrivacyScreen(initialImages: initialImages),
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
        path: '/history',
        pageBuilder: (context, state) => _buildTransitionPage(
          state: state,
          child: const HistoryScreen(),
        ),
      ),
      GoRoute(
        path: '/workspace',
        pageBuilder: (context, state) => _buildTransitionPage(
          state: state,
          child: const WorkspaceScreen(),
        ),
      ),
      GoRoute(
        path: '/update',
        pageBuilder: (context, state) {
          final info = state.extra as UpdateInfo?;
          final safeInfo = info ??
              const UpdateInfo(
                latestVersion: '1.0.0',
                latestBuildNumber: 1,
                forceUpdate: false,
                title: 'Update Available',
                releaseNotes: [],
                updateUrl: '',
                minSupportedVersion: '1.0.0',
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

  const SlimShotApp({super.key, this.enableShareIntents = true});

  @override
  ConsumerState<SlimShotApp> createState() => _SlimShotAppState();
}

class _SlimShotAppState extends ConsumerState<SlimShotApp> {
  late final ShareIntentService _shareService;

  @override
  void initState() {
    super.initState();
    if (widget.enableShareIntents) {
      _shareService = ShareIntentService(ref);
      _shareService.initialize();
    }
  }

  @override
  void dispose() {
    if (widget.enableShareIntents) {
      _shareService.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SlimShotAI',
      theme: AppTheme.darkTheme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
