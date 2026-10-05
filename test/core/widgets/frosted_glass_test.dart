import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/core/widgets/frosted_glass.dart';

void main() {
  Future<void> pump(WidgetTester tester, FrostedGlass glass) =>
      tester.pumpWidget(MaterialApp(home: Center(child: glass)));

  List<Color> sheen(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(FrostedGlass),
        matching: find.byType(DecoratedBox),
      ),
    );
    return ((box.decoration as BoxDecoration).gradient! as LinearGradient)
        .colors;
  }

  testWidgets('blurs what is behind it, and holds its child', (tester) async {
    await pump(
      tester,
      FrostedGlass(
        borderRadius: BorderRadius.circular(16),
        child: const SizedBox(width: 100, height: 60, child: Text('hi')),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('a pane its content covers skips the blur', (tester) async {
    await pump(
      tester,
      FrostedGlass(
        borderRadius: BorderRadius.circular(12),
        blurSigma: 0,
        child: const SizedBox(width: 100, height: 60),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('a tint colours the pane; none leaves the plain sheen',
      (tester) async {
    await pump(
      tester,
      FrostedGlass(
        borderRadius: BorderRadius.circular(16),
        child: const SizedBox(width: 100, height: 60),
      ),
    );
    expect(sheen(tester), [FrostedGlass.sheenTop, FrostedGlass.sheenBottom]);

    final purple = AppColors.primaryStart.withValues(alpha: 0.16);
    await pump(
      tester,
      FrostedGlass(
        borderRadius: BorderRadius.circular(16),
        tint: purple,
        child: const SizedBox(width: 100, height: 60),
      ),
    );
    expect(sheen(tester), [
      Color.alphaBlend(purple, FrostedGlass.sheenTop),
      Color.alphaBlend(purple, FrostedGlass.sheenBottom),
    ]);
  });
}
