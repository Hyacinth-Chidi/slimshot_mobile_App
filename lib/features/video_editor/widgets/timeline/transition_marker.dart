import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';

/// The mark for "a transition lives here".
///
/// **`arrowLeftRight`, not `sparkles`.** Sparkles is the language of effects and
/// filters — something applied *to* a picture. A transition is two clips meeting
/// and exchanging, which is what the opposed arrows say. The same glyph is used
/// whether or not one is applied, because it names the *place*; only the
/// emphasis changes.
const IconData kTransitionIcon = LucideIcons.arrowLeftRight;

/// The seam between two clips, tappable to choose a transition.
///
/// Its own widget because it is drawn **over the filmstrip**, not on a panel,
/// so it cannot rely on the surface behind it being any particular colour — and
/// because the three states it carries are worth testing without standing up a
/// whole timeline.
class TransitionMarker extends StatelessWidget {
  const TransitionMarker({
    super.key,
    required this.hasTransition,
    required this.isSelected,
    required this.onTap,
  });

  /// Whether a transition is applied at this seam.
  final bool hasTransition;

  /// Whether this seam is the one the transition sheet is pointed at.
  final bool isSelected;

  final VoidCallback onTap;

  /// The mark's drawn size.
  static const double markSize = 24;

  /// The touch target, larger than the mark.
  ///
  /// A seam sits between two clips that are themselves draggable, so a target
  /// the size of the ink would be nearly unhittable — the same split the
  /// keyframe diamonds and the trim handles make.
  static const double hitSize = 36;

  @override
  Widget build(BuildContext context) {
    // **Every colour from `AppColors`.** The first version hard-coded Slate
    // (0xFF1E293B / 0xFF0F172A) beside the app's Zinc surfaces, which is why it
    // read as grey-blue against everything around it.
    //
    // The three states are carried by the *fill*, not by a border tint alone:
    // this is 24px over moving footage, and a ring is the first thing to become
    // illegible against a busy frame.
    final Color fill;
    final Color edge;
    final Color ink;

    if (isSelected) {
      // The app's selection language, as the effect tiles and keyframe
      // diamonds use it: the accent filled, ringed in white so it stays
      // distinct from a merely-applied transition.
      fill = AppColors.primaryStart;
      edge = Colors.white;
      ink = Colors.white;
    } else if (hasTransition) {
      // Applied but not selected. The accent-tinted fill is what carries the
      // state at a glance: an earlier version changed only the ring and the
      // ink, and a 1.5px ring is the first thing to disappear against a busy
      // frame — so "has a transition" and "empty" looked alike exactly where it
      // mattered.
      //
      // **Composited over `surface` rather than used raw.** `highlight` is the
      // accent at 15% alpha, which is right over a panel but not over video: a
      // bright frame would show straight through it and wash the tint out. Laid
      // over the same surface an empty seam uses, it is the identical colour a
      // selected effect tile shows, and opaque.
      fill = Color.alphaBlend(AppColors.highlight, AppColors.surface);
      edge = AppColors.primaryStart;
      ink = AppColors.primaryStart;
    } else {
      // An empty seam is an *invitation*, and should recede until wanted.
      fill = AppColors.surface;
      edge = AppColors.border;
      ink = AppColors.textSecondary;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: SizedBox(
        width: hitSize,
        height: hitSize,
        child: Center(
          child: Container(
            width: markSize,
            height: markSize,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(
                color: edge,
                width: isSelected ? 2 : 1.5,
              ),
              boxShadow: [
                // Not decoration: the mark sits on footage that may be any
                // brightness, and without a shadow a light frame swallows its
                // edge. Black rather than a tinted glow — a coloured halo on a
                // 24px mark reads as a rendering artefact.
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Icon(
              // An empty seam offers to add one; an applied seam names itself.
              hasTransition ? kTransitionIcon : LucideIcons.plus,
              color: ink,
              size: 13,
            ),
          ),
        ),
      ),
    );
  }
}
