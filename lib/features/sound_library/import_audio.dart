import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:uuid/uuid.dart';

import '../video_editor/models/audio_track_model.dart';

/// The user's own audio file, picked from the phone, as a track from 0:00
/// at its full length — what the music sheet's Import has always made.
/// Null when nothing was picked or the file will not open. Plugin code,
/// exercised on a device.
Future<AudioTrackModel?> pickAudioTrack() async {
  try {
    final result = await FilePicker.pickFiles(type: FileType.audio);
    final path = result?.files.single.path;
    if (path == null) return null;
    final player = AudioPlayer();
    try {
      final duration = await player.setFilePath(path);
      if (duration == null) return null;
      final seconds = duration.inMilliseconds / 1000.0;
      return AudioTrackModel(
        id: const Uuid().v4(),
        filePath: path,
        sourceDuration: seconds,
        sourceStart: 0.0,
        sourceEnd: seconds,
        timelineStart: 0.0,
      );
    } finally {
      await player.dispose();
    }
  } catch (e) {
    debugPrint('Error importing audio: $e');
    return null;
  }
}
