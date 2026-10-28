import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';

/// One tab of a [FloatingNavBar].
class FloatingNavItem {
  const FloatingNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// The shell's floating tab bar: glass holding the tabs, the chosen one in a
/// lit pill with its name beside its icon.
///
/// **One pill, travelling** (the owner's ask, 2026-10-28: smoother, more
/// premium). The highlight is a single shape that glides to the tab chosen.
/// Before, the old tab's tint faded out while the new one's faded in, the
/// name was inserted in one frame, and every icon jumped sideways to make
/// room for it.
///
/// - **The pill moves on springs, its leading edge quicker than its trailing
///   one**, so it stretches toward where it is going and settles onto the
///   tab with the smallest bounce. Springs rather than curves, so a second
///   tap mid-glide turns the pill from where it is, at the speed it has.
/// - **Its edges are springs in tab units, not pixels** ([_left], [_right]):
///   a whole number is exactly that tab's box in the current layout, so at
///   rest the pill is glued to its tab even while the tab is still widening.
/// - **Names unfold and fold** ([_open]): a tab grows as its name is revealed
///   and the other icons slide to make room. A name is drawn only inside the
///   pill, so it can never show beside it, and leaving is quicker than
///   arriving, as everywhere in the app.
/// - A press squeezes the tab a little; a tap anywhere between two tabs
///   chooses the nearer; with animations off everything moves at once.
/// - **Never wider than the bar**: the padding narrows first, then the names
///   scale down, so a 320dp phone with large text still fits every tab.
class FloatingNavBar extends StatefulWidget {
  const FloatingNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  }) : assert(items.length > 0);

  final List<FloatingNavItem> items;
  final int currentIndex;

  /// Called with the tab tapped — the chosen one too, which takes its branch
  /// back to its first page.
  final ValueChanged<int> onTap;

  static const Key indicatorKey = Key('nav_indicator');
  static Key itemKey(int i) => ValueKey('nav_item_$i');
  static Key iconKey(int i) => ValueKey('nav_icon_$i');
  static Key labelKey(int i) => ValueKey('nav_label_$i');

  @override
  State<FloatingNavBar> createState() => _FloatingNavBarState();
}

const double _kTabHeight = 50;
const double _kIconSize = 26;
const double _kIconLabelGap = 8;
const double _kMaxTabPadding = 20;
const double _kMinTabPadding = 10;
const double _kBarInset = 8;
const double _kBarRadius = 24;
const double _kPillRadius = 16;

/// A name grows with the phone's text size only so far: it is chrome, and
/// past this it would crowd the other tabs off the bar.
const double _kMaxLabelTextScale = 1.3;

/// The smallest a name is drawn to fit a narrow bar.
const double _kMinLabelScale = 0.5;

/// How far a tab is unfolded before its name starts to show.
const double _kNameShowsFrom = 0.4;

const double _kPressedScale = 0.9;

/// Whole in itself, not merged into the ambient text style: the names are
/// measured with exactly this, and an ambient style can carry decoration —
/// without a `Material` above, Flutter's fallback underlines text in yellow.
const TextStyle _kLabelStyle = TextStyle(
  inherit: false,
  fontFamily: kInterfaceFontFamily,
  fontSize: 14,
  fontWeight: FontWeight.bold,
  color: AppColors.lilac,
  decoration: TextDecoration.none,
  textBaseline: TextBaseline.alphabetic,
);

/// The pill's leading edge: quick, landing with the smallest bounce.
final SpringDescription _kLeadingEdge = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 320),
  bounce: 0.15,
);

/// The trailing edge: softer, so the pill stretches, then catches up.
final SpringDescription _kTrailingEdge =
    SpringDescription.withDurationAndBounce(
      duration: const Duration(milliseconds: 450),
    );

/// How long the trailing edge holds before it follows: the moment the pill
/// peels away from the tab it is leaving. Tuned against a model of the bar
/// for every pair of tabs: a move to a narrower or farther tab stretches the
/// pill 1.15–1.6×, one to a wider neighbour hardly at all (the pill is
/// growing into it anyway), and all of it settles within about 0.6s.
const Duration _kTrailingEdgeHold = Duration(milliseconds: 40);

/// Close enough to call a spring settled: a fifth of a pixel, and slower than
/// anything an eye follows. The default kept the springs ticking for most of
/// a second on motion nobody could see.
const Tolerance _kSettled = Tolerance(distance: 0.002, velocity: 0.05);

/// A name arriving.
final SpringDescription _kUnfold = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 420),
);

/// How long a tab waits before it widens for its name, so the room opens as
/// the pill comes rather than ahead of it.
const Duration _kUnfoldHold = Duration(milliseconds: 60);

/// A name leaving, quicker than one arrives.
final SpringDescription _kFold = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 280),
);

class _FloatingNavBarState extends State<FloatingNavBar>
    with TickerProviderStateMixin {
  /// The pill's edges, in tab units: 1.0 is the second tab's own edge.
  late final AnimationController _left;
  late final AnimationController _right;

  /// How far each tab is unfolded: 0 an icon alone, 1 icon and name.
  late List<AnimationController> _open;
  late Listenable _motion;

  /// The tab under a finger, squeezed until it lifts.
  int? _pressed;

  List<double>? _labelWidths;
  Object? _labelWidthsKey;

  int get _index => widget.currentIndex.clamp(0, widget.items.length - 1);

  @override
  void initState() {
    super.initState();
    _left = AnimationController.unbounded(vsync: this, value: _index * 1.0);
    _right = AnimationController.unbounded(vsync: this, value: _index * 1.0);
    _open = _openControllers();
    _motion = Listenable.merge([_left, _right, ..._open]);
  }

  List<AnimationController> _openControllers() => [
    for (var i = 0; i < widget.items.length; i++)
      AnimationController.unbounded(vsync: this, value: i == _index ? 1 : 0),
  ];

  @override
  void didUpdateWidget(FloatingNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.items, oldWidget.items)) _labelWidths = null;
    if (widget.items.length != oldWidget.items.length) {
      for (final open in _open) {
        open.dispose();
      }
      _open = _openControllers();
      _motion = Listenable.merge([_left, _right, ..._open]);
      _left.value = _right.value = _index * 1.0;
    } else if (widget.currentIndex != oldWidget.currentIndex) {
      _moveTo(_index);
    }
  }

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    for (final open in _open) {
      open.dispose();
    }
    super.dispose();
  }

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _moveTo(int index) {
    final to = index.toDouble();
    if (_still) {
      _left.value = _right.value = to;
      for (var i = 0; i < _open.length; i++) {
        _open[i].value = i == index ? 1 : 0;
      }
      return;
    }
    // The edge on the side it travels toward leads, from wherever the pill
    // is now — mid-glide included.
    final rightward = to > (_left.value + _right.value) / 2;
    final leading = rightward ? _right : _left;
    final trailing = rightward ? _left : _right;
    _spring(leading, to, _kLeadingEdge);
    _spring(trailing, to, _kTrailingEdge, hold: _kTrailingEdgeHold);
    for (var i = 0; i < _open.length; i++) {
      if (i == index) {
        _spring(_open[i], 1, _kUnfold, hold: _kUnfoldHold);
      } else {
        _spring(_open[i], 0, _kFold);
      }
    }
  }

  static void _spring(
    AnimationController controller,
    double to,
    SpringDescription spring, {
    Duration hold = Duration.zero,
  }) {
    if (controller.value == to && !controller.isAnimating) return;
    final simulation = SpringSimulation(
      spring,
      controller.value,
      to,
      controller.velocity,
      snapToEnd: true,
      tolerance: _kSettled,
    );
    // Held only from rest: a hold taken mid-glide would stop an edge dead.
    final held =
        hold > Duration.zero && controller.velocity.abs() < _kSettled.velocity;
    controller.animateWith(held ? _Held(simulation, hold) : simulation);
  }

  void _release() {
    if (_pressed != null && mounted) setState(() => _pressed = null);
  }

  /// The names' natural widths, measured with the very style and scale they
  /// are drawn with, and kept until either changes.
  List<double> _measureLabels(TextStyle style, TextScaler scaler) {
    final key = scaler.scale(style.fontSize ?? 14);
    if (_labelWidths != null && _labelWidthsKey == key) return _labelWidths!;
    _labelWidthsKey = key;
    return _labelWidths = [
      for (final item in widget.items) _widthOf(item.label, style, scaler),
    ];
  }

  static double _widthOf(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: _kMaxLabelTextScale);
    const style = _kLabelStyle;
    final labelWidths = _measureLabels(style, scaler);
    return ClipRRect(
      borderRadius: BorderRadius.circular(_kBarRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(_kBarInset),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(_kBarRadius),
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: SizedBox(
            height: _kTabHeight,
            child: LayoutBuilder(
              builder: (context, constraints) => AnimatedBuilder(
                animation: _motion,
                builder: (context, _) => _tabs(
                  _TabLayout(
                    width: constraints.maxWidth,
                    labelWidths: labelWidths,
                    open: [for (final o in _open) o.value.clamp(0.0, 1.0)],
                  ),
                  style,
                  scaler,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabs(_TabLayout layout, TextStyle style, TextScaler scaler) {
    final n = widget.items.length;
    final pillLeft = layout
        .edgeAt(layout.lefts, _left.value)
        .clamp(2 - _kBarInset, layout.width + _kBarInset - 2);
    final pillRight = math.max(
      pillLeft,
      layout
          .edgeAt(layout.rights, _right.value)
          .clamp(2 - _kBarInset, layout.width + _kBarInset - 2),
    );
    final still = _still;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: pillLeft,
          width: pillRight - pillLeft,
          top: 0,
          height: _kTabHeight,
          child: DecoratedBox(
            key: FloatingNavBar.indicatorKey,
            decoration: BoxDecoration(
              // Lit from above, like the glass it sits on.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primaryStart.withValues(alpha: 0.30),
                  AppColors.primaryStart.withValues(alpha: 0.16),
                ],
              ),
              borderRadius: BorderRadius.circular(_kPillRadius),
              border: Border.all(
                color: AppColors.primaryStart.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
        // The names, each shown only inside the pill and inside its own tab:
        // it unfolds as the tab widens and can never show beside the pill.
        // Read out by the tabs' own semantics, not here.
        Positioned.fill(
          child: ExcludeSemantics(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < n; i++)
                  _label(i, layout, pillLeft, pillRight, style, scaler, still),
              ],
            ),
          ),
        ),
        for (var i = 0; i < n; i++) _tab(i, layout, still),
      ],
    );
  }

  Widget _label(
    int i,
    _TabLayout layout,
    double pillLeft,
    double pillRight,
    TextStyle style,
    TextScaler scaler,
    bool still,
  ) {
    final left = layout.labelLeft(i);
    final width = layout.labelWidth(i);
    final shownFrom = math.max(pillLeft, layout.lefts[i]) - left;
    final shownTo = math.min(pillRight, layout.rights[i]) - left;
    return Positioned(
      left: left,
      top: 0,
      width: width,
      height: _kTabHeight,
      child: ClipRect(
        clipper: _Window(shownFrom, shownTo),
        child: Opacity(
          key: FloatingNavBar.labelKey(i),
          opacity:
              _nameOpacity(layout.open[i]) *
              _iconCovered(layout, i, pillLeft, pillRight),
          child: _squeeze(
            i,
            _originFor(layout.centerOf(i) - left, width),
            still,
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: width,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.items[i].label,
                    style: style,
                    textScaler: scaler,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A tab's icon and the whole of its share of the bar as a tap target:
  /// the space between two tabs is split at its middle, so no tap is lost.
  Widget _tab(int i, _TabLayout layout, bool still) {
    final n = layout.lefts.length;
    final hitLeft = i == 0 ? 0.0 : (layout.rights[i - 1] + layout.lefts[i]) / 2;
    final hitRight = i == n - 1
        ? layout.width
        : (layout.rights[i] + layout.lefts[i + 1]) / 2;
    final iconLeft = layout.padding;
    return Positioned(
      left: hitLeft,
      width: math.max(0.0, hitRight - hitLeft),
      top: 0,
      height: _kTabHeight,
      child: Semantics(
        container: true,
        button: true,
        selected: i == _index,
        label: widget.items[i].label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = i),
          onTapUp: (_) => _release(),
          onTapCancel: _release,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap(i);
          },
          child: ExcludeSemantics(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: layout.lefts[i] - hitLeft,
                  top: 0,
                  width: layout.widths[i],
                  height: _kTabHeight,
                  child: SizedBox(
                    key: FloatingNavBar.itemKey(i),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: iconLeft,
                          top: (_kTabHeight - _kIconSize) / 2,
                          width: _kIconSize,
                          height: _kIconSize,
                          child: _squeeze(
                            i,
                            _originFor(
                              layout.widths[i] / 2 - iconLeft,
                              _kIconSize,
                            ),
                            still,
                            Icon(
                              widget.items[i].icon,
                              key: FloatingNavBar.iconKey(i),
                              size: _kIconSize,
                              color: _iconColor(layout.open[i]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A press squeezes the tab about its own middle — down quickly, back with
  /// a little give.
  Widget _squeeze(int i, Alignment origin, bool still, Widget child) {
    final pressed = _pressed == i;
    return AnimatedScale(
      scale: pressed && !still ? _kPressedScale : 1,
      alignment: origin,
      duration: still
          ? Duration.zero
          : Duration(milliseconds: pressed ? 90 : 260),
      curve: pressed ? Curves.easeOut : Curves.easeOutBack,
      child: child,
    );
  }

  /// The [Alignment] of the point [at] across a box [extent] wide.
  static Alignment _originFor(double at, double extent) =>
      extent <= 0 ? Alignment.center : Alignment(at / extent * 2 - 1, 0);

  static double _nameOpacity(double open) =>
      ((open - _kNameShowsFrom) / (1 - _kNameShowsFrom)).clamp(0.0, 1.0);

  /// How much of tab [i]'s icon the pill covers, eased: a name shows only as
  /// the pill reaches its icon, so text never arrives ahead of its tab.
  static double _iconCovered(
    _TabLayout layout,
    int i,
    double pillLeft,
    double pillRight,
  ) {
    final from = layout.lefts[i] + layout.padding;
    final covered =
        math.min(from + _kIconSize, pillRight) - math.max(from, pillLeft);
    return Curves.easeOut.transform((covered / _kIconSize).clamp(0.0, 1.0));
  }

  static Color _iconColor(double open) {
    if (open >= 1) return AppColors.lilac;
    if (open <= 0) return AppColors.textSecondary;
    return Color.lerp(AppColors.textSecondary, AppColors.lilac, open)!;
  }
}

/// Where every tab sits, for one width of bar and one moment of the motion.
class _TabLayout {
  _TabLayout({
    required this.width,
    required this.labelWidths,
    required this.open,
  }) {
    final n = labelWidths.length;
    final widest = labelWidths.fold<double>(0, math.max);
    double need(double padding) =>
        n * (2 * padding + _kIconSize) + _kIconLabelGap + widest;
    if (need(_kMaxTabPadding) <= width) {
      padding = _kMaxTabPadding;
      labelScale = 1;
    } else {
      padding = (((width - _kIconLabelGap - widest) / n - _kIconSize) / 2)
          .clamp(_kMinTabPadding, _kMaxTabPadding);
      final room = width - n * (2 * padding + _kIconSize) - _kIconLabelGap;
      labelScale = need(padding) <= width || widest <= 0
          ? 1
          : (room / widest).clamp(_kMinLabelScale, 1.0);
    }
    final collapsed = 2 * padding + _kIconSize;
    widths = [
      for (var i = 0; i < n; i++)
        collapsed + open[i] * (_kIconLabelGap + labelWidth(i)),
    ];
    final spare = width - widths.fold<double>(0, (a, b) => a + b);
    final spacing = n > 1 ? math.max(0.0, spare / (n - 1)) : 0.0;
    var x = n > 1 ? 0.0 : math.max(0.0, spare / 2);
    lefts = [];
    for (final w in widths) {
      lefts.add(x);
      x += w + spacing;
    }
    rights = [for (var i = 0; i < n; i++) lefts[i] + widths[i]];
  }

  final double width;
  final List<double> labelWidths;
  final List<double> open;

  /// Each tab's space either side of its icon.
  late final double padding;

  /// How far the names are drawn down to fit a narrow bar.
  late final double labelScale;
  late final List<double> widths;
  late final List<double> lefts;
  late final List<double> rights;

  double labelWidth(int i) => labelWidths[i] * labelScale;
  double labelLeft(int i) => lefts[i] + padding + _kIconSize + _kIconLabelGap;
  double centerOf(int i) => lefts[i] + widths[i] / 2;

  /// A pill edge at [at], in tab units, over the tabs' [edges]: a whole
  /// number is that tab's own edge, a fraction lies between two tabs, and
  /// past either end it carries on at the last step's pace — a landing
  /// bounce, a few pixels into the bar's inset.
  double edgeAt(List<double> edges, double at) {
    final n = edges.length;
    if (n == 1) return edges.first + at * widths.first;
    if (at <= 0) return edges[0] + at * (edges[1] - edges[0]);
    if (at >= n - 1) {
      return edges[n - 1] + (at - (n - 1)) * (edges[n - 1] - edges[n - 2]);
    }
    final i = at.floor();
    return edges[i] + (at - i) * (edges[i + 1] - edges[i]);
  }
}

/// [then], after holding where it starts for [hold].
class _Held extends Simulation {
  _Held(this.then, Duration hold)
    : _hold = hold.inMicroseconds / Duration.microsecondsPerSecond,
      super(tolerance: then.tolerance);

  final Simulation then;
  final double _hold;

  @override
  double x(double time) => then.x(math.max(0, time - _hold));

  @override
  double dx(double time) => time < _hold ? 0 : then.dx(time - _hold);

  @override
  bool isDone(double time) => time >= _hold && then.isDone(time - _hold);
}

/// A name's visible window: from [from] to [to] across its own box.
class _Window extends CustomClipper<Rect> {
  const _Window(this.from, this.to);

  final double from;
  final double to;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(from, 0, math.max(from, to), size.height);

  @override
  bool shouldReclip(_Window oldClipper) =>
      oldClipper.from != from || oldClipper.to != to;
}
