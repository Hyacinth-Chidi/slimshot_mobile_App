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
