import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/compression/logic/compression_presets.dart';

/// What the probe reads from ffprobe's JSON — everything the WhatsApp Status
/// plan decides from.
void main() {
  Map<String, dynamic> probe({
    List<Map<String, dynamic>> streams = const [],
    Map<String, dynamic> format = const {},
  }) =>
      {'streams': streams, 'format': format};

  Map<String, dynamic> video([Map<String, dynamic> extra = const {}]) => {
        'codec_type': 'video',
        'codec_name': 'h264',
        'width': 1280,
        'height': 720,
        'r_frame_rate': '30/1',
        'avg_frame_rate': '30/1',
        'pix_fmt': 'yuv420p',
        ...extra,
      };

  test('reads a phone video stored sideways', () {
    final m = VideoMetadata.fromProbe(probe(streams: [
      video({
        'width': 1920,
        'height': 1080,
        'bit_rate': '9000000',
        'side_data_list': [
          {'side_data_type': 'Display Matrix', 'rotation': -90},
        ],
      }),
    ]));
    expect(m.rotation, 90);
    expect(m.displayWidth, 1080);
    expect(m.displayHeight, 1920);
    expect(m.bitrateKbps, 9000);
    expect(m.frameRate, 30);
    expect(m.codec, 'h264');
  });

  test("an older file's rotate tag counts too", () {
    final m = VideoMetadata.fromProbe(probe(streams: [
      video({
        'tags': {'rotate': '90'},
      }),
    ]));
    expect(m.rotation, 90);
    expect(m.displayWidth, 720);
    expect(m.displayHeight, 1280);
  });

  test('HDR and bit depth', () {
    final m = VideoMetadata.fromProbe(probe(streams: [
      video({'pix_fmt': 'yuv420p10le', 'color_transfer': 'arib-std-b67'}),
    ]));
    expect(m.bitDepth, 10);
    expect(m.colorTransfer, 'arib-std-b67');
    final sdr = VideoMetadata.fromProbe(probe(streams: [video()]));
    expect(sdr.bitDepth, 8);
    expect(sdr.colorTransfer, isNull);
  });

  test('fractional and variable rates', () {
    final m = VideoMetadata.fromProbe(probe(streams: [
      video({'r_frame_rate': '30000/1001', 'avg_frame_rate': '0/0'}),
    ]));
    expect(m.frameRate, closeTo(29.97, 0.01));
    expect(m.avgFrameRate, 0);
  });

  test('the audio stream', () {
    final m = VideoMetadata.fromProbe(probe(streams: [
      video(),
      {'codec_type': 'audio', 'codec_name': 'aac', 'channels': 6},
    ]));
    expect(m.audioCodec, 'aac');
    expect(m.audioChannels, 6);
    final silent = VideoMetadata.fromProbe(probe(streams: [video()]));
    expect(silent.audioCodec, isNull);
    expect(silent.audioChannels, 0);
  });

  test("falls back to the container's bitrate, and reads its duration", () {
    final m = VideoMetadata.fromProbe(probe(
      streams: [video()],
      format: {'bit_rate': '2400000', 'duration': '35.5'},
    ));
    expect(m.bitrateKbps, 2400);
    expect(m.durationSecs, 35.5);
  });

  test('numbers may arrive as numbers or strings', () {
    final m = VideoMetadata.fromProbe(probe(
      streams: [
        video({'width': '640', 'height': 360, 'bit_rate': 800000}),
      ],
      format: {'duration': 12},
    ));
    expect(m.width, 640);
    expect(m.height, 360);
    expect(m.bitrateKbps, 800);
    expect(m.durationSecs, 12);
  });

  test('no video stream reads as width 0', () {
    final m = VideoMetadata.fromProbe(probe(streams: [
      {'codec_type': 'audio', 'codec_name': 'aac', 'channels': 2},
    ]));
    expect(m.width, 0);
  });
}
