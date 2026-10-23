import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/compression/logic/status_plan.dart';

/// The FFmpeg command a status plan runs.
void main() {
  StatusPlan plan({
    bool copyOnly = false,
    int? width = 720,
    int? height = 1280,
    double frameRate = 30,
    bool toneMap = false,
    int audioChannels = 2,
  }) =>
      StatusPlan(
        copyOnly: copyOnly,
        width: width,
        height: height,
        frameRate: frameRate,
        toneMap: toneMap,
        audioChannels: audioChannels,
      );

  String command(StatusPlan p, {bool removeMetadata = false}) =>
      statusCommand(p, input: '/in.mp4', output: '/out.mp4', removeMetadata: removeMetadata);

  String chainOf(String cmd) => RegExp(r'-vf "([^"]+)"').firstMatch(cmd)!.group(1)!;

  void inOrder(String text, List<String> parts) {
    var at = -1;
    for (final part in parts) {
      final i = text.indexOf(part, at + 1);
      expect(i, greaterThan(at), reason: '"$part" after the one before, in: $text');
      at = i;
    }
  }

  test('a re-encode in the shape Status keeps', () {
    final cmd = command(plan());
    expect(cmd, startsWith('-y -i "/in.mp4" '));
    expect(cmd, contains('-map 0:v:0'));
    expect(cmd, contains('-map 0:a:0?'));
    expect(
      cmd,
      contains('-c:v libx264 -preset medium -profile:v high -level 3.1 '
          '-pix_fmt yuv420p -crf 21 -maxrate 2000k -bufsize 4000k'),
    );
    expect(cmd, contains('-color_primaries bt709 -color_trc bt709 -colorspace bt709'));
    expect(cmd, contains('-c:a aac -b:a 128k -ar 44100 -ac 2'));
    expect(cmd, contains('-movflags +faststart'));
    expect(cmd, endsWith('"/out.mp4"'));
  });

  test('denoise, then scale, square pixels, a constant rate, 8-bit', () {
    inOrder(chainOf(command(plan())), [
      'hqdn3d=',
      'scale=720:1280:flags=lanczos',
      'setsar=1',
      'fps=30',
      'format=yuv420p',
    ]);
  });

  test('HDR is tone-mapped before anything else', () {
    final chain = chainOf(command(plan(toneMap: true)));
    expect(chain, startsWith('zscale=t=linear'));
    inOrder(chain, ['tonemap=tonemap=hable', 'zscale=t=bt709:m=bt709:r=tv', 'hqdn3d=']);
    expect(chainOf(command(plan())), isNot(contains('zscale')));
  });

  test('an unknown size is fitted by FFmpeg, never enlarged', () {
    final chain = chainOf(command(plan(width: null, height: null)));
    expect(chain, contains('force_original_aspect_ratio=decrease'));
    expect(chain, contains('force_divisible_by=2'));
    expect(chain, contains('gte(iw,ih)'));
    expect(chain, contains('min(1280,iw)'));
    expect(chain, contains('min(720,ih)'));
    expect(chain, contains('min(720,iw)'));
    expect(chain, contains('min(1280,ih)'));
  });

  test('a fractional rate is written plainly', () {
    expect(chainOf(command(plan(frameRate: 30000 / 1001))), contains('fps=29.97'));
    expect(chainOf(command(plan(frameRate: 25))), contains('fps=25,'));
  });

  test('no sound track: no audio, and no failure on a missing one', () {
    final cmd = command(plan(audioChannels: 0));
    expect(cmd, contains('-an'));
    expect(cmd, isNot(contains('-c:a')));
    expect(cmd, isNot(contains('0:a')));
  });

  test('mono stays mono', () {
    expect(command(plan(audioChannels: 1)), contains('-ac 1'));
  });

  test('metadata is removed when asked', () {
    expect(command(plan(), removeMetadata: true), contains('-map_metadata -1'));
    expect(command(plan()), isNot(contains('-map_metadata')));
  });

  test('a ready file is copied, not encoded', () {
    final cmd = command(plan(copyOnly: true), removeMetadata: true);
    expect(cmd, contains('-c copy -movflags +faststart'));
    expect(cmd, contains('-map_metadata -1'));
    expect(cmd, isNot(contains('-vf')));
    expect(cmd, isNot(contains('libx264')));
    expect(cmd, endsWith('"/out.mp4"'));
  });
}
