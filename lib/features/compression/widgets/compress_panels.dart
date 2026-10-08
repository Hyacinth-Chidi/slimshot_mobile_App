import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../../core/widgets/frosted_glass.dart';

/// The pieces the compress screens are built from: Home's light and glass,
/// one look for every choice, so the video and photo screens cannot drift.

const Color _divider = Color(0x1AFFFFFF); // white10, the theme's divider

/// A glass back button on the left and the screen's name centred on the
/// screen — not in the space beside the button, which would sit it off
/// centre.
class CompressTopBar extends StatelessWidget {
  const CompressTopBar({
    super.key,
    required this.title,
    required this.onBack,
    this.icon = LucideIcons.chevronLeft,
    this.iconLabel = 'Back',
    this.badge,
    this.titleKey,
    this.backKey,
    this.trailing,
  });

  final String title;
  final VoidCallback onBack;

  /// The button's glyph: back by default, ✕ where the screen is a finish.
  final IconData icon;
  final String iconLabel;

  /// Drawn before the title and centred with it (the result's tick).
  final Widget? badge;
  final Key? titleKey;
  final Key? backKey;

  /// An action at the right end (Change photos). The title keeps clear of
  /// it as it does of the back button, so it stays centred.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Stack(alignment: Alignment.center, children: [
          // Clear of the button on both sides, so a long title cannot run
          // under it and stays centred.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 56),
            child: Row(
              key: titleKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (badge != null) ...[badge!, const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              label: iconLabel,
              child: GestureDetector(
                key: backKey,
                onTap: onBack,
                behavior: HitTestBehavior.opaque,
                child: FrostedGlass(
                  borderRadius: BorderRadius.circular(22),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(icon, color: AppColors.textPrimary, size: 22),
                  ),
                ),
              ),
            ),
          ),
          if (trailing != null)
            Align(alignment: Alignment.centerRight, child: trailing),
        ]),
      );
}

/// A round glass button with one glyph, the top bar's own shape — for an
/// action at its far end.
class CompressGlassIconAction extends StatelessWidget {
  const CompressGlassIconAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: FrostedGlass(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: AppColors.textPrimary, size: 20),
            ),
          ),
        ),
      );
}

class CompressSectionLabel extends StatelessWidget {
  const CompressSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      );
}

/// Rows on one pane of glass, divided by hairlines.
class CompressGroup extends StatelessWidget {
  const CompressGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => FrostedGlass(
        borderRadius: BorderRadius.circular(20),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: _divider),
            children[i],
          ],
        ]),
      );
}

/// One of several choices: an icon, a name, one line, and a tick. Rows, not
/// tiles, so a long name or large text wraps instead of squeezing.
class CompressChoiceRow extends StatelessWidget {
  const CompressChoiceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.tag,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// A soft label beside the name ("Recommended").
  final String? tag;

  /// A strong one ("PRO").
  final String? badge;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: selected ? AppColors.highlight : Colors.transparent,
              border: Border.all(
                color: selected ? AppColors.primaryStart : Colors.transparent,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      selected ? AppColors.primaryStart : AppColors.surfaceLight,
                ),
                child: Icon(
                  icon,
                  size: 19,
                  // White on purple, the theme's one exemption.
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (tag != null) _Tag(tag!),
                        if (badge != null) _Tag(badge!, strong: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Tick(selected: selected),
            ]),
          ),
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: strong
              ? AppColors.primaryStart
              : AppColors.primaryStart.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: strong ? Colors.white : AppColors.lilac,
          ),
        ),
      );
}

class _Tick extends StatelessWidget {
  const _Tick({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.primaryStart : null,
          border: selected
              ? null
              : Border.all(color: AppColors.textTertiary, width: 1.5),
        ),
        child: selected
            ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
            : null,
      );
}

/// An option with an icon, a label and whatever sets it; the whole row is
/// the tap target where the control is a switch.
class CompressOptionRow extends StatelessWidget {
  const CompressOptionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
            child: Row(children: [
              Icon(icon, size: 19, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              // The control sits beside its label while they fit, and drops
              // onto a line of its own when they do not — three format
              // segments on a narrow phone with large text.
              Expanded(
                child: OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowAlignment: OverflowBarAlignment.start,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    trailing,
                  ],
                ),
              ),
            ]),
          ),
        ),
      );
}

/// A switch for a [CompressOptionRow]: one tap on the row or the switch.
class CompressSwitchRow extends StatelessWidget {
  const CompressSwitchRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onToggle,
  });

  final IconData icon;
  final String label;
  final bool value;
  final VoidCallback onToggle;

  void _toggle() {
    HapticFeedback.selectionClick();
    onToggle();
  }

  @override
  Widget build(BuildContext context) => CompressOptionRow(
        icon: icon,
        label: label,
        onTap: _toggle,
        trailing: Switch(
          value: value,
          onChanged: (_) => _toggle(),
          activeTrackColor: AppColors.primaryStart,
          activeThumbColor: Colors.white,
          inactiveTrackColor: AppColors.surfaceLight,
          inactiveThumbColor: AppColors.textSecondary,
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      );
}

/// Two or three short values side by side ("MP4 | WebM"). Each segment is
/// keyed `compress_format_<value>`.
class CompressSegmented extends StatelessWidget {
  const CompressSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(String value, String label)> options;
  final String value;
  final ValueChanged<String> onChanged;

  // Scales down — the last resort, after the option row has already moved
  // it onto a line of its own — rather than overflow a narrow phone with
  // large text.
  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: _segments(),
      );

  Widget _segments() => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, label) in options)
            GestureDetector(
              key: Key('compress_format_$v'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (v == value) return;
                HapticFeedback.selectionClick();
                onChanged(v);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                constraints: const BoxConstraints(minHeight: 36),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: v == value ? AppColors.primaryStart : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: v == value ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
        ]),
      );
}

/// A file's size before and after, with the after's share of the before
/// drawn as a bar and the saving as a tag. Where nothing was saved the bar
/// stays grey and no saving is claimed.
class CompressBeforeAfterCard extends StatelessWidget {
  const CompressBeforeAfterCard({
    super.key,
    required this.before,
    required this.after,
    required this.beforeBytes,
    required this.afterBytes,
    this.caption,
  });

  final String before;
  final String after;
  final int beforeBytes;
  final int afterBytes;
  final String? caption;

  /// Whole percent saved, or null where the file did not get smaller.
  int? get savedPercent {
    if (beforeBytes <= 0 || afterBytes >= beforeBytes) return null;
    final percent = ((1 - afterBytes / beforeBytes) * 100).round();
    return percent <= 0 ? null : percent;
  }

  static const _small = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  @override
  Widget build(BuildContext context) {
    final saved = savedPercent;
    final share =
        beforeBytes <= 0 ? 1.0 : (afterBytes / beforeBytes).clamp(0.0, 1.0);
    return FrostedGlass(
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Before', style: _small),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        before,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(LucideIcons.arrowRight,
                    size: 18, color: AppColors.textSecondary),
              ),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('After', style: _small),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        after,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => Stack(children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    if (saved != null)
                      Container(
                        height: 8,
                        width: c.maxWidth * share,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ]),
                ),
              ),
              if (saved != null) ...[
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$saved% smaller',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ]),
            if (caption != null) ...[
              const SizedBox(height: 10),
              Text(
                caption!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A label and its value, for a [CompressGroup] of details.
class CompressValueRow extends StatelessWidget {
  const CompressValueRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => CompressOptionRow(
        icon: icon,
        label: label,
        trailing: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
}

/// A secondary action with an icon, on glass (Share, New video).
class CompressGlassIconButton extends StatelessWidget {
  const CompressGlassIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onPressed();
          },
          child: FrostedGlass(
            borderRadius: BorderRadius.circular(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18, color: AppColors.textPrimary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// A small dark label over a picture.
class CompressInfoChip extends StatelessWidget {
  const CompressInfoChip(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: AppColors.textPrimary),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ]),
      );
}

/// The screen's one action, pinned under the content, which fades out
/// behind it as it scrolls.
class CompressBottomBar extends StatelessWidget {
  const CompressBottomBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.background.withValues(alpha: 0),
              AppColors.background.withValues(alpha: 0.92),
            ],
            stops: const [0, 0.35],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: child,
        ),
      );
}

/// The primary action: the brand gradient, white on purple.
class CompressPrimaryButton extends StatelessWidget {
  const CompressPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                onPressed!();
              }
            : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: enabled ? 1 : 0.45,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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
}

/// A secondary action on glass (Cancel).
class CompressGlassButton extends StatelessWidget {
  const CompressGlassButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: GestureDetector(
          onTap: onPressed,
          child: FrostedGlass(
            borderRadius: BorderRadius.circular(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
