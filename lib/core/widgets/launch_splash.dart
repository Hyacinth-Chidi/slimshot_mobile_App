import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';

/// The splash: the system's, then the app's (the owner's pick of three).
///
/// Android draws the native splash — on 12 and newer it allows nothing but
/// a centred icon on a flat colour — so the native one shows only the logo,
/// dim. The app's first frame repeats it exactly, then lights it: a glow
/// blooms behind it, the three bars light one by one, the name rises under
/// it, and it all fades into the app, which has been building underneath.

/// The logo as the native splash draws it: `logo.png` (399×487) is the
/// generator's 4x picture, so it lands on screen at a quarter of its pixels.
/// The app must draw it at exactly this size, or it jumps at the hand-over.
const Size kLaunchLogoSize = Size(399 / 4, 487 / 4);

/// How bright the logo is before the app lights it — on the native splash
/// and on the app's first frame alike.
const double kLaunchLogoRestingOpacity = 0.35;

const Duration kLaunchSplashDuration = Duration(milliseconds: 880);

/// With animations turned off in the phone's settings: only a short fade.
const Duration kLaunchSplashReducedDuration = Duration(milliseconds: 200);

/// How far the logo rises to make room for the name under it, so the two
/// sit centred together.
const double kLaunchLogoLift = 24;

/// The gap between the logo and the name.
const double _kNameGap = 14;

/// How far below its place the name starts rising from.
const double _kNameRise = 10;

/// The logo in four layers, cut from `logo.png` by
/// `test/launch_splash_art_test.dart`: the white body and each purple bar,
/// so the bars can light one at a time.
const List<String> kLaunchSplashLayers = [
  'assets/splash/body.png',
  'assets/splash/bar_0.png',
  'assets/splash/bar_1.png',
  'assets/splash/bar_2.png',
];

/// The layers, decoded before the first frame: an `Image.asset` would still
/// be decoding when the first frame went out, and the logo would blink off
/// at the hand-over.
class LaunchSplashArt {
  LaunchSplashArt({required this.body, required this.bars});

  final ui.Image body;
  final List<ui.Image> bars;

  /// Null when a layer cannot be had; the app then opens without its own
  /// splash rather than not at all.
  static Future<LaunchSplashArt?> load([AssetBundle? bundle]) async {
    final source = bundle ?? rootBundle;
    final images = <ui.Image>[];
    try {
      for (final path in kLaunchSplashLayers) {
        final data = await source.load(path);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        images.add((await codec.getNextFrame()).image);
        codec.dispose();
      }
      return LaunchSplashArt(body: images.first, bars: images.sublist(1));
    } catch (error) {
      for (final image in images) {
        image.dispose();
      }
      debugPrint('Launch splash unavailable: $error');
      return null;
    }
  }

  void dispose() {
    body.dispose();
    for (final bar in bars) {
      bar.dispose();
    }
  }
}

/// One moment of the splash.
class LaunchSplashFrame {
  const LaunchSplashFrame({
    required this.glow,
    required this.body,
    required this.bars,
    required this.name,
    required this.lift,
    required this.scale,
    required this.fade,
  });

  /// The purple glow behind the logo, 0..1.
  final double glow;

  /// The logo's white body, from the resting opacity to 1.
  final double body;

  /// Each bar, top first, from the resting opacity to 1.
  final List<double> bars;

  /// The name under the logo, 0..1 — its opacity and how far it has risen.
  final double name;

  /// How much of [kLaunchLogoLift] the logo has risen, 0..1.
  final double lift;

  /// The logo's size as it fades into the app, 1 and up.
  final double scale;

  /// The whole splash's opacity over the app, 1 down to 0.
  final double fade;
}

/// Where everything is at [elapsed], as a pure function the tests read.
LaunchSplashFrame launchSplashFrameAt(
  Duration elapsed, {
  bool reduced = false,
}) {
  final ms = elapsed.inMicroseconds / 1000;
  double phase(double start, double end, Curve curve) {
    if (ms <= start) return 0;
    if (ms >= end) return 1;
    return curve.transform((ms - start) / (end - start));
  }

  // Lands exactly on [to], so "lit" means 1 and not 0.9999999.
  double ramp(double from, double to, double t) =>
      t >= 1 ? to : from + (to - from) * t;

  const rest = kLaunchLogoRestingOpacity;
  if (reduced) {
    return LaunchSplashFrame(
      glow: 0,
      body: rest,
      bars: const [rest, rest, rest],
      name: 0,
      lift: 0,
      scale: 1,
      fade: ramp(
        1,
        0,
        phase(0, kLaunchSplashReducedDuration.inMilliseconds.toDouble(),
            Curves.easeOut),
      ),
    );
  }

  const lit = Curves.easeOutCubic;
  final fading = phase(700, 880, Curves.easeInCubic);
  return LaunchSplashFrame(
    glow: phase(0, 380, lit),
    body: ramp(rest, 1, phase(40, 360, lit)),
    // Top first, 90ms apart.
    bars: [
      for (var i = 0; i < 3; i++)
        ramp(rest, 1, phase(120 + 90.0 * i, 280 + 90.0 * i, lit)),
    ],
    name: phase(500, 700, lit),
    lift: phase(470, 690, Curves.easeInOutCubic),
    scale: ramp(1, 1.04, fading),
    fade: ramp(1, 0, fading),
  );
}

/// The point the native splash centres its logo on, in the view's own
/// coordinates.
///
/// The native splash is centred on the whole display. The app's view can
/// stop short of it by a system bar — on many Android phones the view does
/// not draw behind the navigation bar — so on each axis where the view is
/// the display less at most a bar's worth, the display's centre is used: the
/// view starts at the display's top-left, so that is where the native logo
/// sits. Anything else (split screen, a window) uses the view's own centre.
Offset launchLogoCentre(Size view, Size display) {
  double axis(double viewLength, double displayLength) {
    final shortBy = displayLength - viewLength;
    if (shortBy >= 0 && shortBy <= displayLength * 0.12) {
      return displayLength / 2;
    }
    return viewLength / 2;
  }

  return Offset(axis(view.width, display.width), axis(view.height, display.height));
}

/// Draws the glow and the four layers of the logo.
class LaunchSplashPainter extends CustomPainter {
  LaunchSplashPainter({
    required this.art,
    required this.frame,
    required this.logoRect,
  });

  final LaunchSplashArt art;
  final LaunchSplashFrame frame;

  /// Where the logo is drawn this frame: [kLaunchLogoSize] at the native
  /// splash's centre on the first frame, then lifted and, at the end,
  /// grown a little.
  final Rect logoRect;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.glow > 0) {
      final radius = 150 * (0.6 + 0.4 * frame.glow);
      canvas.drawCircle(
        logoRect.center,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(
            logoRect.center,
            radius,
            [
              AppColors.primaryStart.withValues(alpha: 0.45 * frame.glow),
              AppColors.primaryStart.withValues(alpha: 0.16 * frame.glow),
              AppColors.primaryStart.withValues(alpha: 0),
            ],
            const [0, 0.45, 1],
          ),
      );
    }
    void layer(ui.Image image, double opacity) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        logoRect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(255, 255, 255, opacity),
      );
    }

    layer(art.body, frame.body);
    for (var i = 0; i < art.bars.length; i++) {
      layer(art.bars[i], frame.bars[math.min(i, frame.bars.length - 1)]);
    }
  }

  @override
  bool shouldRepaint(LaunchSplashPainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.logoRect != logoRect;
}

/// The app's half of the splash, over the app until it has played.
class LaunchSplash extends StatefulWidget {
  const LaunchSplash({super.key, required this.art, required this.child});

  /// Null: no splash, the app straight away.
  final LaunchSplashArt? art;

  final Widget child;

  @override
  State<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends State<LaunchSplash>
    with SingleTickerProviderStateMixin {
  // `preserve`: the controller would otherwise run at 5% of its duration
  // with animations turned off, and the splash already answers that setting
  // itself, with its own short fade.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
  );

  /// Animations turned off in the phone's settings; read on the first build.
  bool? _reduced;
  late bool _done = widget.art == null;

  @override
  void initState() {
    super.initState();
    _clock.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done || _reduced != null) return;
    final reduced = _reduced = MediaQuery.disableAnimationsOf(context);
    _clock
      ..duration = reduced ? kLaunchSplashReducedDuration : kLaunchSplashDuration
      ..forward();
  }

  void _finish() {
    if (_done) return;
    setState(() => _done = true);
    // A picture already recorded keeps its own hold on them.
    widget.art?.dispose();
  }

  @override
  void dispose() {
    _clock.dispose();
    if (!_done) widget.art?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final art = widget.art;
    if (_done || art == null) return widget.child;
    final view = View.of(context);
    final display = view.display.size / view.devicePixelRatio;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        Positioned.fill(
          key: const Key('launch_splash'),
          // The app underneath is not on screen yet; a tap must not reach it.
          child: AbsorbPointer(
            child: LayoutBuilder(
              builder: (context, box) {
                final centre = launchLogoCentre(box.biggest, display);
                return AnimatedBuilder(
                  animation: _clock,
                  builder: (context, _) {
                    final frame = launchSplashFrameAt(
                      (_clock.duration ?? Duration.zero) * _clock.value,
                      reduced: _reduced ?? false,
                    );
                    final logoCentre =
                        centre - Offset(0, kLaunchLogoLift * frame.lift);
                    final logoRect = Rect.fromCenter(
                      center: logoCentre,
                      width: kLaunchLogoSize.width * frame.scale,
                      height: kLaunchLogoSize.height * frame.scale,
                    );
                    return Opacity(
                      opacity: frame.fade,
                      child: ColoredBox(
                        color: AppColors.background,
                        child: Stack(
                          textDirection: TextDirection.ltr,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                key: const Key('launch_splash_paint'),
                                painter: LaunchSplashPainter(
                                  art: art,
                                  frame: frame,
                                  logoRect: logoRect,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: logoCentre.dy +
                                  kLaunchLogoSize.height / 2 +
                                  _kNameGap +
                                  _kNameRise * (1 - frame.name),
                              child: Opacity(
                                key: const Key('launch_splash_name'),
                                opacity: frame.name,
                                child: const Center(child: _Wordmark()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The name as Home's header writes it, so the splash hands over to the
/// same wordmark.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [AppColors.textPrimary, AppColors.textSecondary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: const Text(
        'SlimShot AI',
        textDirection: TextDirection.ltr,
        style: TextStyle(
          fontFamily: kInterfaceFontFamily,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: AppColors.textPrimary,
          // Above the app's Material there is no text theme; this says
          // plainly what would otherwise be inherited.
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}
