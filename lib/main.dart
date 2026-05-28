import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/file_utils.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'core/models/update_info.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'screens/compress_video_screen.dart';
import 'screens/compress_image_screen.dart';
import 'screens/result_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/update_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/privacy_result_screen.dart';
import 'screens/convert_screen.dart';
import 'screens/convert_result_screen.dart';

import 'features/sharing/share_intent_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  _initRouter(initialRoute);

  runApp(const ProviderScope(child: SlimShotApp()));

  FileUtils.cleanupStartup();
}

late final GoRouter appRouter;

void _initRouter(String initialRoute) {
  appRouter = GoRouter(
    initialLocation: initialRoute,
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/compress/video',
        builder: (context, state) => const CompressVideoScreen(),
      ),
      GoRoute(
        path: '/compress/image',
        builder: (context, state) => const CompressImageScreen(),
      ),
      GoRoute(
        path: '/result',
        builder: (context, state) => const ResultScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const PrivacyScreen(),
      ),
      GoRoute(
        path: '/privacy/result',
        builder: (context, state) => const PrivacyResultScreen(),
      ),
      GoRoute(
        path: '/convert',
        builder: (context, state) => const ConvertScreen(),
      ),
      GoRoute(
        path: '/convert/result',
        builder: (context, state) => const ConvertResultScreen(),
      ),
      GoRoute(
        path: '/update',
        builder: (context, state) {
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
          return UpdateScreen(updateInfo: safeInfo);
        },
      ),
    ],
  );
}

class SlimShotApp extends ConsumerStatefulWidget {
  const SlimShotApp({super.key});

  @override
  ConsumerState<SlimShotApp> createState() => _SlimShotAppState();
}

class _SlimShotAppState extends ConsumerState<SlimShotApp> {
  late final ShareIntentService _shareService;

  @override
  void initState() {
    super.initState();
    _shareService = ShareIntentService(ref);
    _shareService.initialize();
  }

  @override
  void dispose() {
    _shareService.dispose();
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
