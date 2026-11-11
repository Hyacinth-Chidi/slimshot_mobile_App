import '../../../../core/services/draft_files.dart';

/// The file a voice is saved as in the draft's audio folder: named for its
/// text, and with [DraftFiles.voiceFilePrefix], so the sweep at close takes
/// it once no track uses it. A text id is the app's own but not a file name,
/// so anything but letters, digits, `-` and `_` becomes `_`, and a long one
/// is cut.
String voiceFileName(String textId, DateTime now) {
  var safe = textId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  if (safe.length > 64) safe = safe.substring(0, 64);
  return '${DraftFiles.voiceFilePrefix}${safe}_${now.millisecondsSinceEpoch}.mp3';
}

/// One voice Text to speech made, ready for the timeline: its file, how long
/// it plays, and where its text started when Generate was tapped.
class VoiceClip {
  const VoiceClip({
    required this.textId,
    required this.filePath,
    required this.durationSeconds,
    required this.startSeconds,
  });

  /// The text it speaks; voicing that text again replaces this clip.
  final String textId;
  final String filePath;
  final double durationSeconds;
  final double startSeconds;
}
