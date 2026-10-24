import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_fonts.dart';
import '../core/theme/lucide_icons.dart';
import '../core/theme/sound_effect_icon.dart';
import '../core/widgets/colour_field_backdrop.dart';

/// One page: a picture, a headline whose last word is lit, one line.
class _OnboardPage {
  const _OnboardPage({
    required this.lead,
    required this.accent,
    required this.line,
    required this.visual,
  });

  final String lead;
  final String accent;
  final String line;
  final Widget visual;
}

/// The first launch: three pages, one thing the app does best on each —
/// editing (the editor's own timeline, the owner's pick), WhatsApp-sharp
/// compression, auto captions — then Home.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  static const List<_OnboardPage> _pages = [
    _OnboardPage(
      lead: 'Edit like a ',
      accent: 'pro',
      line: 'Clips, text, effects, sound and music, layered on one timeline.',
      visual: _TimelineVisual(),
    ),
    _OnboardPage(
      lead: 'Clear on ',
      accent: 'WhatsApp Status',
      line: 'Compressed in the shape Status keeps, so your video never blurs.',
      visual: _StatusVisual(),
    ),
    _OnboardPage(
      lead: 'Captions in ',
      accent: 'one tap',
      line: "Every word on time, lit up as it's spoken.",
      visual: _CaptionsVisual(),
    ),
  ];

  bool get _isLast => _page == _pages.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasSeenOnboarding', true);
    } catch (e) {
      debugPrint('⚠️ Prefs failed: $e');
    }
    if (mounted) context.go('/home');
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: ColourFieldBackdrop()),
          SafeArea(
            child: Center(
              // A tablet gets the phone's column, centred.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    _TopBar(
                      page: _page,
                      count: _pages.length,
                      onSkip: _isLast ? null : _finish,
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _pages.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, i) => _PageBody(page: _pages[i]),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                      child: _PrimaryButton(
                        label: _isLast ? 'Get started' : 'Continue',
                        purple: _isLast,
                        onTap: _next,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three steps lit up to the current page, and Skip beside them.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.page, required this.count, this.onSkip});

  final int page;
  final int count;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (var i = 0; i < count; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedContainer(
                        key: Key('onboarding_step_$i'),
                        duration: const Duration(milliseconds: 300),
                        height: 3,
                        decoration: BoxDecoration(
                          color: i <= page
                              ? AppColors.textPrimary
                              : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Kept the same width on the last page, so the steps do not jump.
            SizedBox(
              width: 64,
              height: 40,
              child: onSkip == null
                  ? null
                  : TextButton(
                      onPressed: onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                      ),
                      child: const Text(
                        'Skip',
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: kInterfaceFontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      );
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.page});

  final _OnboardPage page;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The picture takes what the words leave, and shrinks to fit it on
          // a short phone rather than overflowing.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: FittedBox(fit: BoxFit.scaleDown, child: page.visual),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: page.lead),
                      TextSpan(
                        text: page.accent,
                        style: const TextStyle(color: AppColors.lilac),
                      ),
                    ],
                  ),
                  style: const TextStyle(
                    fontFamily: kInterfaceFontFamily,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  page.line,
                  style: const TextStyle(
                    fontFamily: kInterfaceFontFamily,
                    fontSize: 15,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.purple,
    required this.onTap,
  });

  final String label;
  final bool purple;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: purple ? null : AppColors.textPrimary,
            gradient: purple ? AppColors.primaryGradient : null,
            borderRadius: BorderRadius.circular(27),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontFamily: kInterfaceFontFamily,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: purple ? Colors.white : AppColors.background,
            ),
          ),
        ),
      );
}

const _left = 'assets/home/new_video_left.webp';
const _middle = 'assets/home/new_video_middle.webp';
const _right = 'assets/home/new_video_right.webp';

/// A photo for these pictures: decoded small, never at its full 1672.
Widget _photo(String asset, {double cacheHeight = 480}) => Image.asset(
      asset,
      fit: BoxFit.cover,
      cacheHeight: cacheHeight.round(),
    );

/// A caption as the editor draws one: heavy white words, one of them on a
/// purple pill.
class _Caption extends StatelessWidget {
  const _Caption(this.words, {required this.lit, this.size = 15});

  final List<String> words;
  final int lit;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: kInterfaceFontFamily,
      fontSize: size,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
      shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: size * 0.3,
      children: [
        for (var i = 0; i < words.length; i++)
          i == lit
              ? Container(
                  padding: EdgeInsets.symmetric(horizontal: size * 0.25),
                  decoration: BoxDecoration(
                    color: AppColors.primaryStart,
                    borderRadius: BorderRadius.circular(size * 0.3),
                  ),
                  child: Text(words[i], style: style.copyWith(shadows: [])),
                )
              : Text(words[i], style: style),
      ],
    );
  }
}

/// A photo in the New Video card's white frame.
class _Framed extends StatelessWidget {
  const _Framed({
    required this.width,
    required this.height,
    required this.child,
  });

  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.textPrimary, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: child,
        ),
      );
}

// ── Page 1: the timeline ────────────────────────────────────────────────────

/// The editor's own timeline, drawn: a preview with a caption on it, then a
/// ruler, three clips with transitions on their seams, a bar of each kind on
/// the lanes in the editor's colours, and the playhead through them. Laid out
/// on a 360-wide phone and scaled to fit.
class _TimelineVisual extends StatelessWidget {
  const _TimelineVisual();

  static const double _width = 360;
  static const double _rulerH = 16;
  static const double _filmH = 56;
  static const double _laneH = 33;
  static const double _gap = 8;
  static const double _playheadX = 180;

  // Timeline seconds are 33 px apart, starting 13 px in.
  static const double _origin = 13;
  static const double _perTwoSeconds = 66;

  @override
  Widget build(BuildContext context) {
    const timelineH = _rulerH + _gap + _filmH + 3 * (_gap + _laneH);
    return SizedBox(
      width: _width,
      height: 200 + 18 + timelineH,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // The preview, with a caption on it.
          Positioned(
            left: (_width - 140) / 2,
            top: 0,
            child: _Framed(
              width: 140,
              height: 200,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _photo(_middle),
                  const Positioned(
                    left: 6,
                    right: 6,
                    bottom: 18,
                    child: _Caption(['LEVEL', 'UP'], lit: 1),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            top: 218,
            height: timelineH,
            child: _Timeline(),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline();

  @override
  Widget build(BuildContext context) {
    const s = _TimelineVisual._perTwoSeconds;
    const o = _TimelineVisual._origin;
    const filmTop = _TimelineVisual._rulerH + _TimelineVisual._gap;
    double laneTop(int i) =>
        filmTop +
        _TimelineVisual._filmH +
        _TimelineVisual._gap +
        i * (_TimelineVisual._laneH + _TimelineVisual._gap);
    const lastLaneBottom = _TimelineVisual._rulerH +
        _TimelineVisual._gap +
        _TimelineVisual._filmH +
        3 * (_TimelineVisual._gap + _TimelineVisual._laneH);

    return Stack(
      key: const Key('onboarding_timeline'),
      clipBehavior: Clip.hardEdge,
      children: [
        // The ruler.
        for (var i = 0; i < 5; i++)
          Positioned(
            left: o + i * s - 2,
            top: 0,
            child: Text(
              '00:0${i * 2}',
              style: const TextStyle(
                fontFamily: kInterfaceFontFamily,
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        // Three clips, the last running off the edge.
        for (final (left, width, asset) in [
          (o, 2.08 * s, _left),
          (o + 2.14 * s, 1.74 * s, _middle),
          (o + 3.94 * s, 2.0 * s, _right),
        ])
          Positioned(
            left: left,
            top: filmTop,
            width: width,
            height: _TimelineVisual._filmH,
            child: _Filmstrip(asset: asset),
          ),
        for (final x in [o + 2.11 * s, o + 3.91 * s])
          Positioned(
            left: x - 13,
            top: filmTop + (_TimelineVisual._filmH - 26) / 2,
            child: const _Seam(),
          ),
        // A bar of each kind, in the editor's colours.
        Positioned(
          left: o + 0.55 * s,
          top: laneTop(0),
          child: const _Bar(
            width: 147,
            color: AppColors.border,
            icon: Icon(LucideIcons.type, size: 13, color: AppColors.textPrimary),
            label: 'LEVEL UP',
          ),
        ),
        Positioned(
          left: o + 2.95 * s,
          top: laneTop(0),
          child: const _Bar(
            width: 115,
            color: AppColors.effectTrack,
            icon: Icon(LucideIcons.sparkles,
                size: 13, color: AppColors.textPrimary),
            label: 'Glow',
          ),
        ),
        Positioned(
          left: o + 1.3 * s,
          top: laneTop(1),
          child: const _Bar(
            width: 92,
            color: AppColors.photoTrack,
            icon: Icon(LucideIcons.image, size: 13, color: AppColors.textPrimary),
            label: 'Photo',
          ),
        ),
        Positioned(
          left: o + 3.3 * s,
          top: laneTop(1),
          child: const _Bar(
            width: 92,
            color: AppColors.soundEffect,
            icon: SoundEffectIcon(size: 14, color: AppColors.textPrimary),
            label: 'Whoosh',
          ),
        ),
        Positioned(
          left: o,
          top: laneTop(2),
          width: 400,
          height: _TimelineVisual._laneH,
          child: const _MusicBar(),
        ),
        // The playhead, from the ruler down to the music and no further.
        const Positioned(
          key: Key('onboarding_playhead'),
          left: _TimelineVisual._playheadX - 7,
          top: 0,
          width: 14,
          height: lastLaneBottom,
          child: _Playhead(),
        ),
      ],
    );
  }
}

class _Filmstrip extends StatelessWidget {
  const _Filmstrip({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: LayoutBuilder(
          // Tiles laid in a stack, so the last one can run past the clip's
          // end and be cut there, as the timeline cuts it.
          builder: (context, box) => Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (var i = 0; i < (box.maxWidth / 36).ceil(); i++)
                Positioned(
                  left: i * 36.0,
                  top: 0,
                  bottom: 0,
                  width: 36,
                  child: _photo(asset, cacheHeight: 168),
                ),
            ],
          ),
        ),
      );
}

/// A transition on a seam, as the timeline draws one.
class _Seam extends StatelessWidget {
  const _Seam();

  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Color.alphaBlend(AppColors.highlight, AppColors.surface),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.primaryStart, width: 1.5),
        ),
        child: const Icon(
          LucideIcons.arrowLeftRight,
          size: 13,
          color: AppColors.lilac,
        ),
      );
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.width,
    required this.color,
    required this.icon,
    required this.label,
  });

  final double width;
  final Color color;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: _TimelineVisual._laneH,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: const TextStyle(
                  fontFamily: kInterfaceFontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Music: a purple bar carrying its waveform, running off the edge.
class _MusicBar extends StatelessWidget {
  const _MusicBar();

  // A fixed shape, so the picture is the same on every launch.
  static const List<double> _peaks = [
    .40, .70, .55, .85, .45, .65, .90, .50, .75, .40, .60, .80, .55, .70, //
    .45, .85, .60, .50, .75, .40, .65, .85, .55, .70, .45, .60, .80, .50, //
    .70, .45, .65, .85, .55, .70, .45, .60, .80, .50, .75, .40, .65, .85,
  ];

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.primaryEnd,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (var i = 0; i < _peaks.length; i++)
              Positioned(
                left: i * 8.5,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 2.5,
                    height: _TimelineVisual._laneH * _peaks[i] * 0.8,
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _Playhead extends StatelessWidget {
  const _Playhead();

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 4,
            bottom: 0,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textPrimary.withValues(alpha: 0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.textPrimary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      );
}

// ── Page 2: sharp on WhatsApp Status ────────────────────────────────────────

/// The same picture twice: blurred as WhatsApp shrinks an ordinary upload,
/// sharp as SlimShot's Status file arrives.
class _StatusVisual extends StatelessWidget {
  const _StatusVisual();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 360,
        height: 380,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _side(
              blurred: true,
              tag: 'Blurred',
              tagColor: AppColors.border,
            ),
            const SizedBox(width: 16),
            _side(blurred: false, tag: 'Sharp', tagColor: AppColors.success),
          ],
        ),
      );

  Widget _side({
    required bool blurred,
    required String tag,
    required Color tagColor,
  }) =>
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Framed(
            width: 148,
            height: 290,
            child: blurred
                ? ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: _photo(_middle),
                  )
                : _photo(_middle),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: tagColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              tag,
              style: const TextStyle(
                fontFamily: kInterfaceFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      );
}

// ── Page 3: captions ────────────────────────────────────────────────────────

class _CaptionsVisual extends StatelessWidget {
  const _CaptionsVisual();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 360,
        height: 380,
        child: Center(
          child: _Framed(
            width: 210,
            height: 350,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _photo(_right, cacheHeight: 720),
                const Positioned(
                  left: 10,
                  right: 10,
                  bottom: 40,
                  child: _Caption(["LET'S", 'DANCE', 'NOW'], lit: 1, size: 16),
                ),
              ],
            ),
          ),
        ),
      );
}
