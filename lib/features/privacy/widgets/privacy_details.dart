import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../../core/widgets/frosted_glass.dart';
import '../../compression/widgets/compress_panels.dart';
import '../logic/photo_metadata.dart';

/// The kinds of personal detail the privacy screens speak of, in the order
/// they are listed — location first, the one that matters most.
enum PrivacyDetail { location, camera, taken, author }

/// One line of what was found: which detail, and what it says — the value
/// itself for one photo, a count ("In 3 of 5") for several.
class PrivacyDetailLine {
  const PrivacyDetailLine(this.detail, this.value);

  final PrivacyDetail detail;
  final String value;

  IconData get icon => switch (detail) {
        PrivacyDetail.location => LucideIcons.mapPin,
        PrivacyDetail.camera => LucideIcons.smartphone,
        PrivacyDetail.taken => LucideIcons.calendar,
        PrivacyDetail.author => LucideIcons.user,
      };

  String get label => switch (detail) {
        PrivacyDetail.location => 'Location',
        PrivacyDetail.camera => 'Camera',
        PrivacyDetail.taken => 'Taken',
        PrivacyDetail.author => 'Author',
      };
}

/// What [photos] carry, one line per kind present. Unread photos (null)
/// count toward "of N" and contribute nothing.
List<PrivacyDetailLine> privacyDetailLines(List<PhotoMetadata?> photos) {
  if (photos.length == 1) {
    final m = photos.single;
    if (m == null) return const [];
    return [
      if (m.hasLocation)
        PrivacyDetailLine(PrivacyDetail.location,
            formatCoordinates(m.latitude!, m.longitude!)),
      if (m.hasCamera) PrivacyDetailLine(PrivacyDetail.camera, m.camera!),
      if (m.hasTaken)
        PrivacyDetailLine(PrivacyDetail.taken, formatTaken(m.taken!)),
      if (m.hasAuthor) PrivacyDetailLine(PrivacyDetail.author, m.author!),
    ];
  }
  final s = MetadataSummary.of(photos);
  return [
    for (final (detail, count) in [
      (PrivacyDetail.location, s.location),
      (PrivacyDetail.camera, s.camera),
      (PrivacyDetail.taken, s.taken),
      (PrivacyDetail.author, s.author),
    ])
      if (count > 0) PrivacyDetailLine(detail, foundInLabel(count, s.total)),
  ];
}

/// How many of [photos] still carry [detail].
int privacyDetailCount(List<PhotoMetadata?> photos, PrivacyDetail detail) {
  final s = MetadataSummary.of(photos);
  return switch (detail) {
    PrivacyDetail.location => s.location,
    PrivacyDetail.camera => s.camera,
    PrivacyDetail.taken => s.taken,
    PrivacyDetail.author => s.author,
  };
}

/// Where a line stands: found (before), removed and confirmed, or still
/// there after the strip.
enum PrivacyDetailState { found, removed, survived }

class PrivacyDetailRow extends StatelessWidget {
  const PrivacyDetailRow(this.line, {super.key, this.state = PrivacyDetailState.found});

  final PrivacyDetailLine line;
  final PrivacyDetailState state;

  @override
  Widget build(BuildContext context) {
    final Widget value = switch (state) {
      PrivacyDetailState.survived => const Text(
          'Still there',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.warning,
          ),
        ),
      _ => Text(
          line.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: state == PrivacyDetailState.removed
                ? AppColors.textTertiary
                // Location is the one that matters most.
                : line.detail == PrivacyDetail.location
                    ? AppColors.lilac
                    : AppColors.textSecondary,
            decoration: state == PrivacyDetailState.removed
                ? TextDecoration.lineThrough
                : null,
            decorationColor: AppColors.textTertiary,
          ),
        ),
    };
    return CompressOptionRow(
      icon: line.icon,
      label: line.label,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: value),
        if (state == PrivacyDetailState.removed) ...[
          const SizedBox(width: 8),
          Container(
            key: const Key('privacy_removed_tick'),
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success,
            ),
            child: const Icon(LucideIcons.check, size: 13, color: Colors.white),
          ),
        ],
        if (state == PrivacyDetailState.survived) ...[
          const SizedBox(width: 8),
          const Icon(LucideIcons.alertTriangle, size: 18, color: AppColors.warning),
        ],
        const SizedBox(width: 6),
      ]),
    );
  }
}

/// A glass card with one line and an icon: nothing found, still reading.
class PrivacyNote extends StatelessWidget {
  const PrivacyNote({super.key, required this.text, this.leading});

  final String text;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => FrostedGlass(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            leading ??
                const Icon(LucideIcons.shieldCheck,
                    size: 20, color: AppColors.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ]),
        ),
      );
}
