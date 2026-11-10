/// How blurred the "Blur" background is: 0 light .. 1 heavy, the background
/// sheet's slider.
///
/// **Halfway by default** — well past the old fixed blur, which read as a
/// mirror of the clip rather than a background (the owner's report,
/// 2026-11-10). Kotlin's `BackgroundBlur.DEFAULT_STRENGTH` is the same
/// number, and its `radiusFractionFor` is what a strength looks like.
const double kDefaultBackgroundBlurStrength = 0.5;

/// [value] held to the slider; anything unreadable is the default.
double clampBackgroundBlurStrength(double value) =>
    value.isFinite ? value.clamp(0.0, 1.0).toDouble() : kDefaultBackgroundBlurStrength;
