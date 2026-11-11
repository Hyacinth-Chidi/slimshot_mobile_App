import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/services/voice_sample_player.dart';

/// The editor lets the sample player go as soon as the sheet's route has
/// popped; the sheet's own teardown — which stops the sample — runs after the
/// sheet has slid away. So a stop, or a late play, after dispose must be
/// harmless.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a stop or a play after dispose does nothing', () async {
    final player = JustAudioSamplePlayer();
    await player.dispose();

    await player.stop();
    await player.play('https://cdn.test/eve.mp3');
    expect(player.playing.value, isNull);
  });
}
