import 'dart:math' as math;

import 'compression_presets.dart';

/// The most video bitrate, in kbps, a WhatsApp Status file may carry.
///
/// Instagram's, copied: the owner's edit downloaded back from Instagram stayed
/// sharp on Status, and its busiest second carried 1366 kbps. Held for every
/// second (`bufsize` = this), not averaged over two: a 2 Mbps cap with a 4 Mb
/// buffer let bursts run near 4 Mbps, and a file came back soft.
///
/// **Still provisional.** WhatsApp does not publish what it leaves untouched; the
/// measurement in `docs/superpowers/specs/2026-10-23-whatsapp-status-compression-design.md`
/// (posting variants and reading back what WhatsApp delivered) sets it. Above
/// it a file is re-encoded by WhatsApp; this is the ceiling we encode under.
const int kStatusMaxVideoKbps = 1500;

/// x264's quality target under that ceiling: easy content (an app screen)
/// comes out small, hard content (camera, motion) rides the ceiling.
const int kStatusCrf = 21;

/// `medium` took minutes on a low-end phone; under a tight bitrate ceiling
/// `veryfast` gives most of its quality at a few times the speed.
const String kStatusX264Preset = 'veryfast';

/// A keyframe every 5 s at 30 fps, as Instagram's file has: fewer keyframes
/// leave more of the ceiling for the picture.
const int _kKeyframeInterval = 150;

/// The box WhatsApp Status keeps, portrait; landscape swaps it.
const int _kShortSide = 720;
const int _kLongSide = 1280;

/// What a WhatsApp Status compression makes of one input.
class StatusPlan {
  const StatusPlan({
    required this.copyOnly,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.toneMap,
    required this.audioChannels,
  });

  /// Already in the shape Status keeps: copied, not encoded, so no picture
  /// is touched.
  final bool copyOnly;

  /// The output size as the probe read it: what decides [copyOnly]. The
  /// command does **not** size from it — FFmpeg fits the upright frames
  /// itself, because a rotation label the probe missed would make a portrait
  /// video read as landscape.
  final int? width;
  final int? height;

  /// A constant output rate.
  final double frameRate;

  /// PQ or HLG — HDR — converted to ordinary SDR colour first.
  final bool toneMap;

  /// 0 for no sound track, else 1 or 2.
  final int audioChannels;
}

/// The plan for [source], or a status-shaped plan from nothing when the probe
/// could not read it.
StatusPlan statusPlan(VideoMetadata? source) {
  if (source == null || source.width <= 0 || source.height <= 0) {
    return const StatusPlan(
      copyOnly: false,
      width: null,
      height: null,
      frameRate: 30,
      toneMap: false,
      audioChannels: 2,
    );
  }
  final w = source.displayWidth;
  final h = source.displayHeight;
  final (outW, outH) = _fit(w, h);
  final sourceRate =
      source.avgFrameRate > 0 ? source.avgFrameRate : source.frameRate;
  final variable = source.frameRate > 0 &&
      source.avgFrameRate > 0 &&
      (source.frameRate - source.avgFrameRate).abs() > 0.5;
  final toneMap = _isHdr(source.colorTransfer);
  // A track whose channel count could not be read is still sound: stereo,
  // never dropped.
  final audioChannels = source.audioCodec == null
      ? 0
      : source.audioChannels <= 0
          ? 2
          : math.min(source.audioChannels, 2);

  final copyOnly = source.codec.toLowerCase() == 'h264' &&
      (source.audioCodec == null || source.audioCodec!.toLowerCase() == 'aac') &&
      source.audioChannels <= 2 &&
      source.bitDepth == 8 &&
      !toneMap &&
      source.rotation == 0 &&
      outW == w &&
      outH == h &&
      sourceRate > 0 &&
      sourceRate <= 30 &&
      !variable &&
      source.bitrateKbps > 0 &&
      source.bitrateKbps <= kStatusMaxVideoKbps;

  return StatusPlan(
    copyOnly: copyOnly,
    width: outW,
    height: outH,
    frameRate: statusFrameRate(sourceRate),
    toneMap: toneMap,
    audioChannels: audioChannels,
  );
}

/// A constant rate for [source]: the largest even division of it between 24
/// and 30 (60 → 30, 50 → 25, 120 → 30), else the source capped at 30. An
/// unknown rate is 30.
double statusFrameRate(double source) {
  if (source <= 0) return 30;
  for (var n = 1; source / n >= 24; n++) {
    if (source / n <= 30) return source / n;
  }
  return math.min(source, 30);
}

bool _isHdr(String? transfer) =>
    transfer == 'smpte2084' || transfer == 'arib-std-b67';

/// [w]×[h] fitted inside the Status box, aspect kept, both sides even, never
/// larger than the source.
(int, int) _fit(int w, int h) {
  final landscape = w > h;
  final boxW = landscape ? _kLongSide : _kShortSide;
  final boxH = landscape ? _kShortSide : _kLongSide;
  final scale = [1.0, boxW / w, boxH / h].reduce(math.min);
  int side(int source, int box) {
    final nearestEven = ((source * scale) / 2).round() * 2;
    final limit = math.min(box, (source ~/ 2) * 2);
    return math.max(2, math.min(nearestEven, limit));
  }

  return (side(w, boxW), side(h, boxH));
}

/// HDR to SDR, FFmpeg's standard recipe: to linear light, into BT.709
/// primaries, tone-mapped, back to BT.709's curve in limited range.
const String _kToneMap = 'zscale=t=linear:npl=100,format=gbrpf32le,'
    'zscale=p=bt709,tonemap=tonemap=hable:desat=0,'
    'zscale=t=bt709:m=bt709:r=tv,format=yuv420p';


/// The FFmpegKit argument string that makes [plan] of [input] at [output].
String statusCommand(
  StatusPlan plan, {
  required String input,
  required String output,
  required bool removeMetadata,
}) {
  final cmd = StringBuffer('-y -i "$input" ');
  if (removeMetadata) cmd.write('-map_metadata -1 ');
  if (plan.copyOnly) {
    cmd.write('-map 0:v:0 -map 0:a:0? -c copy -movflags +faststart "$output"');
    return cmd.toString();
  }

  // FFmpeg fits the frames it actually has — turned upright already — so a
  // rotation label the probe missed cannot squash a portrait picture into a
  // landscape box. Never larger than the source.
  const scale = "scale=w='if(gte(iw,ih),min($_kLongSide,iw),min($_kShortSide,iw))'"
      ":h='if(gte(iw,ih),min($_kShortSide,ih),min($_kLongSide,ih))'"
      ':force_original_aspect_ratio=decrease:force_divisible_by=2:flags=lanczos';
  final chain = [
    if (plan.toneMap) _kToneMap,
    // No denoise: measured on the owner's videos it was 35% of all the work
    // and lowered quality (SSIM 0.9945 against 0.9950 without).
    scale,
    'setsar=1',
    'fps=${_rate(plan.frameRate)}',
    'format=yuv420p',
  ].join(',');

  cmd
    ..write('-map 0:v:0 ')
    ..write(plan.audioChannels > 0 ? '-map 0:a:0? ' : '')
    ..write('-vf "$chain" ')
    ..write('-c:v libx264 -preset $kStatusX264Preset -profile:v high -level 3.1 '
        '-pix_fmt yuv420p -crf $kStatusCrf '
        '-maxrate ${kStatusMaxVideoKbps}k -bufsize ${kStatusMaxVideoKbps}k '
        '-g $_kKeyframeInterval ')
    ..write('-color_primaries bt709 -color_trc bt709 -colorspace bt709 ')
    ..write(plan.audioChannels > 0
        ? '-c:a aac -b:a 128k -ar 44100 -ac ${plan.audioChannels} '
        : '-an ')
    ..write('-movflags +faststart "$output"');
  return cmd.toString();
}

/// 29.97002997… → "29.97", 25.0 → "25".
String _rate(double fps) {
  final fixed = fps.toStringAsFixed(2);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}
