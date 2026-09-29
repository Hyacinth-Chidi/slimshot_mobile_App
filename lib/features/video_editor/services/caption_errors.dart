import 'package:flutter/services.dart';

import '../../../core/services/slimshot_api.dart';

/// Polling ran for [CaptionService.pollLimit] without an answer.
const String kCaptionPollTimeout = 'POLL_TIMEOUT';

/// Auto captions stopped because the user cancelled — never shown as an error.
class CaptionCancelled implements Exception {
  const CaptionCancelled();
}

/// A reason auto captions ended that the app decided, not the server.
class CaptionFailure implements Exception {
  const CaptionFailure(this.code);

  final String code;

  /// The chosen sources hold nothing audible.
  static const String noSound = 'NO_SOUND';

  /// The server heard no words.
  static const String noSpeech = 'NO_SPEECH';

  /// The native audio pass failed.
  static const String renderFailed = 'RENDER_FAILED';
}

/// The one line the user sees for [error] — no title, no code.
String captionErrorMessage(Object error) {
  final code = switch (error) {
    SlimshotApiException(:final code) => code,
    CaptionFailure(:final code) => code,
    PlatformException() => CaptionFailure.renderFailed,
    _ => '',
  };
  return switch (code) {
    SlimshotApiException.network =>
      'No connection. Check your internet and try again.',
    'CAPTIONS_UNAVAILABLE' || 'UNAUTHENTICATED' =>
      'Auto captions are unavailable right now.',
    'PAYLOAD_TOO_LARGE' => 'This video is too long for auto captions.',
    'NOT_FOUND' => 'Captions expired before they arrived. Try again.',
    kCaptionPollTimeout => 'Captions took too long. Try again.',
    CaptionFailure.noSpeech => 'No speech found.',
    CaptionFailure.noSound => 'No sound to caption.',
    CaptionFailure.renderFailed =>
      "Couldn't read this project's sound. Try again.",
    _ => "Couldn't transcribe this audio. Try again.",
  };
}
