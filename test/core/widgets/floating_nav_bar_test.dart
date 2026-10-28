import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/core/widgets/floating_nav_bar.dart';

const _tabs = [
  FloatingNavItem(icon: Icons.home_rounded, label: 'Home'),
  FloatingNavItem(icon: Icons.space_dashboard_rounded, label: 'Workspace'),
  FloatingNavItem(icon: Icons.settings_rounded, label: 'Settings'),
];

/// The bar as the shell holds it — at most 400 wide, 24 in from each side —
/// choosing whatever is tapped, as `goBranch` does.
class _Shell extends StatefulWidget {
  const _Shell({required this.taps});

  final List<int> taps;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: FloatingNavBar(
          items: _tabs,
          currentIndex: _index,
          onTap: (index) {
            widget.taps.add(index);
            setState(() => _index = index);
          },
        ),
      ),
    ),
  );
}

void main() {
  late List<int> taps;

  setUp(() => taps = []);

  Future<void> pumpBar(
    WidgetTester tester, {
    double width = 360,
    double textScale = 1,
    bool animationsOff = false,
  }) async {
    tester.view.physicalSize = Size(width * 3, 760 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: animationsOff,
            ),
            child: Scaffold(body: _Shell(taps: taps)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect pill(WidgetTester tester) =>
      tester.getRect(find.byKey(FloatingNavBar.indicatorKey));
  Rect tab(WidgetTester tester, int i) =>
      tester.getRect(find.byKey(FloatingNavBar.itemKey(i)));
  double labelOpacity(WidgetTester tester, int i) =>
      tester.widget<Opacity>(find.byKey(FloatingNavBar.labelKey(i))).opacity;

  Future<void> choose(WidgetTester tester, int i) async {
    await tester.tap(find.byKey(FloatingNavBar.itemKey(i)));
    await tester.pump();
  }

  /// What [read] answers on every frame for [over], at 60 a second.
  Future<List<T>> everyFrame<T>(
    WidgetTester tester,
    T Function() read, {
    Duration over = const Duration(milliseconds: 700),
  }) async {
    const frame = Duration(milliseconds: 16);
    final seen = <T>[];
    for (var t = Duration.zero; t < over; t += frame) {
      await tester.pump(frame);
      seen.add(read());
    }
    return seen;
  }

  double largestStep(List<double> values) {
    var step = 0.0;
    for (var i = 1; i < values.length; i++) {
      step = math.max(step, (values[i] - values[i - 1]).abs());
    }
    return step;
  }

  testWidgets('the pill glides from one tab to the next, never jumps', (
    tester,
  ) async {
    await pumpBar(tester);
    final start = pill(tester);
    await choose(tester, 1);
    await tester.pump(const Duration(milliseconds: 80));
    final midway = pill(tester);
    await tester.pumpAndSettle();
    final end = pill(tester);
    expect(end.center.dx, greaterThan(start.center.dx + 40));
    expect(midway.center.dx, greaterThan(start.center.dx + 1));
    expect(midway.center.dx, lessThan(end.center.dx - 1));
  });

  // Settings to Home: two tabs away and to a narrower one, where the stretch
  // is plainest — a move to a wider neighbour hardly stretches, the pill
  // growing into it anyway.
  testWidgets(
    'it stretches toward where it is going, then settles on the tab',
    (tester) async {
      await pumpBar(tester);
      await choose(tester, 2);
      await tester.pumpAndSettle();
      final start = pill(tester);
      await choose(tester, 0);
      await tester.pump(const Duration(milliseconds: 48));
      final peeling = pill(tester);
      expect(
        start.left - peeling.left,
        greaterThan(start.right - peeling.right),
        reason: 'the edge it travels toward leaves first',
      );
      final widths = await everyFrame(tester, () => pill(tester).width);
      final end = pill(tester);
      expect(widths.reduce(math.max), greaterThan(end.width * 1.25));
      expect(end.left, closeTo(tab(tester, 0).left, 0.5));
      expect(end.right, closeTo(tab(tester, 0).right, 0.5));
    },
  );

  testWidgets('nothing jumps: every icon moves a little on every frame', (
    tester,
  ) async {
    await pumpBar(tester);
    await choose(tester, 2);
    final xs = await everyFrame(
      tester,
      () => [for (var i = 0; i < _tabs.length; i++) tab(tester, i).left],
    );
    for (var i = 0; i < _tabs.length; i++) {
      final path = [for (final frame in xs) frame[i]];
      expect(largestStep(path), lessThan(20), reason: 'tab $i');
    }
  });

  testWidgets('the labels fold and unfold rather than pop', (tester) async {
    await pumpBar(tester);
    await choose(tester, 1);
    final opacities = await everyFrame(
      tester,
      () => (labelOpacity(tester, 0), labelOpacity(tester, 1)),
    );
    bool fades(Iterable<double> o) =>
        o.where((v) => v > 0.05 && v < 0.95).length >= 2;
    expect(fades(opacities.map((o) => o.$1)), isTrue, reason: 'Home folding');
    expect(
      fades(opacities.map((o) => o.$2)),
      isTrue,
      reason: 'Workspace unfolding',
    );
    expect(labelOpacity(tester, 0), 0);
    expect(labelOpacity(tester, 1), 1);
  });

  // Seen in rendered frames: the name faded in inside the pill while the
  // pill had not yet reached its icon, text arriving ahead of its tab.
  testWidgets('a name never shows before the pill reaches its icon', (
    tester,
  ) async {
    await pumpBar(tester);
    await choose(tester, 2);
    await tester.pumpAndSettle();
    await choose(tester, 0);
    final frames = await everyFrame(
      tester,
      () => (
        opacity: labelOpacity(tester, 0),
        pillLeft: pill(tester).left,
        icon: tester.getRect(find.byKey(FloatingNavBar.iconKey(0))),
      ),
    );
    for (final f in frames.where((f) => f.opacity > 0.05)) {
      expect(
        f.pillLeft,
        lessThanOrEqualTo(f.icon.center.dx),
        reason: 'Home showing at ${f.opacity.toStringAsFixed(2)}',
      );
    }
  });

  testWidgets('the chosen tab ends inside the pill, label and all', (
    tester,
  ) async {
    await pumpBar(tester);
    await choose(tester, 1);
    await tester.pumpAndSettle();
    final p = pill(tester);
    final label = tester.getRect(find.byKey(FloatingNavBar.labelKey(1)));
    expect(p.left, closeTo(tab(tester, 1).left, 0.5));
    expect(p.right, closeTo(tab(tester, 1).right, 0.5));
    expect(label.left, greaterThanOrEqualTo(p.left));
    expect(label.right, lessThanOrEqualTo(p.right));
  });

  testWidgets('a tap in the space between two tabs chooses the nearer one', (
    tester,
  ) async {
    await pumpBar(tester);
    final home = tab(tester, 0);
    final workspace = tab(tester, 1);
    expect(
      workspace.left - home.right,
      greaterThan(8),
      reason: 'there is a space between them to tap',
    );
    final nearerWorkspace = home.right + (workspace.left - home.right) * 0.75;
    await tester.tapAt(Offset(nearerWorkspace, home.center.dy));
    await tester.pumpAndSettle();
    expect(taps, [1]);
  });

  testWidgets('tapping the chosen tab still reports it, for its first page', (
    tester,
  ) async {
    await pumpBar(tester);
    await choose(tester, 0);
    expect(taps, [0]);
  });

  testWidgets('a narrow phone with large text fits every tab', (tester) async {
    await pumpBar(tester, width: 320, textScale: 1.3);
    for (final i in [1, 2, 0]) {
      await choose(tester, i);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'tab $i chosen');
      final bar = tester.getRect(find.byType(FloatingNavBar));
      for (var k = 0; k < _tabs.length; k++) {
        expect(tab(tester, k).left, greaterThanOrEqualTo(bar.left));
        expect(tab(tester, k).right, lessThanOrEqualTo(bar.right));
      }
    }
  });

  testWidgets('with animations off it moves at once', (tester) async {
    await pumpBar(tester, animationsOff: true);
    await choose(tester, 2);
    expect(pill(tester).left, closeTo(tab(tester, 2).left, 0.5));
    expect(pill(tester).right, closeTo(tab(tester, 2).right, 0.5));
    expect(labelOpacity(tester, 2), 1);
    expect(labelOpacity(tester, 0), 0);
  });

  testWidgets('chosen again mid-glide, it turns from where it is', (
    tester,
  ) async {
    await pumpBar(tester);
    await choose(tester, 2);
    await tester.pump(const Duration(milliseconds: 90));
    final before = pill(tester);
    await choose(tester, 1);
    final edges = await everyFrame(
      tester,
      () => (pill(tester).left, pill(tester).right),
    );
    expect((edges.first.$1 - before.left).abs(), lessThan(30));
    expect((edges.first.$2 - before.right).abs(), lessThan(30));
    expect(largestStep([for (final e in edges) e.$1]), lessThan(30));
    expect(largestStep([for (final e in edges) e.$2]), lessThan(30));
    expect(pill(tester).left, closeTo(tab(tester, 1).left, 0.5));
    expect(pill(tester).right, closeTo(tab(tester, 1).right, 0.5));
  });

  testWidgets('each tab is a button that says its name and whether it is '
      'chosen', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpBar(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Workspace')),
      isSemantics(isButton: true, isSelected: false, hasTapAction: true),
    );
    await choose(tester, 1);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Workspace')),
      isSemantics(isButton: true, isSelected: true),
    );
    semantics.dispose();
  });

  testWidgets("the colours are the app's: lilac when chosen, grey when not", (
    tester,
  ) async {
    await pumpBar(tester);
    final chosen = tester.widget<Icon>(find.byKey(FloatingNavBar.iconKey(0)));
    final other = tester.widget<Icon>(find.byKey(FloatingNavBar.iconKey(1)));
    expect(chosen.color, AppColors.lilac);
    expect(other.color, AppColors.textSecondary);
  });

  testWidgets('a press gives a tap a small squeeze, released on lift', (
    tester,
  ) async {
    await pumpBar(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(FloatingNavBar.iconKey(1))),
    );
    // The press is built on this frame; its squeeze runs from the next.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final pressed = tester.getRect(find.byKey(FloatingNavBar.iconKey(1)));
    await gesture.up();
    await tester.pumpAndSettle();
    final released = tester.getRect(find.byKey(FloatingNavBar.iconKey(1)));
    expect(pressed.width, lessThan(released.width * 0.97));
    expect(released.width, closeTo(26, 0.01));
  });
}
