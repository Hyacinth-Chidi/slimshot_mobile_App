import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';

/// Swaps the editor's bottom area — toolbar, tool panel, context menu — with
/// the motion a sheet has.
///
/// A new child **slides up from fully below and fades in** on
/// [AppMotion.enterCurve] over [AppMotion.enter]; the old one slides back
/// down and fades on [AppMotion.exitCurve] over the shorter [AppMotion.exit].
/// The container grows or shrinks around them over [AppMotion.enter] on the
/// same curve, so the height lands exactly when the incoming child does —
/// on a different clock the edge arrives before or after the content, which
/// reads as a stutter. The old switcher nudged the child up from 40% of its
/// height on `easeOutCubic`; from fully below is what makes a panel read as
/// the same kind of thing as the sheets that open over it.
///
/// Children are stacked bottom-aligned during the swap, so a taller panel
/// replacing a shorter toolbar keeps its bottom edge on the screen edge while
/// the container above it grows.
class EditorPanelSwitcher extends StatelessWidget {
  const EditorPanelSwitcher({super.key, required this.child});

  /// The current bottom-area content. Give each distinct surface its own
  /// key so the switcher knows a swap from a rebuild.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppMotion.enter,
      curve: AppMotion.enterCurve,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: AppMotion.enter,
        reverseDuration: AppMotion.exit,
        switchInCurve: AppMotion.enterCurve,
        switchOutCurve: AppMotion.exitCurve,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.bottomCenter,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: child,
      ),
    );
  }
}
