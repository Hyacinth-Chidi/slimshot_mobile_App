import '../../../core/services/slimshot_api.dart';
import '../../account/logic/account_copy.dart';
import 'speech_service.dart';

/// A reason the voice run ended that the app decided, not the server.
class SpeechFailure implements Exception {
  const SpeechFailure(this.code);

  final String code;

  /// A paid job the server failed; its credits are already back.
  static const String refunded = 'REFUNDED';
}

/// The one line the user sees for [error] — no title, no code, never the
/// server's or the provider's own words.
String speechErrorMessage(Object error) {
  if (error is SlimshotApiException && error.code == 'INSUFFICIENT_CREDITS') {
    final needed = error.detailInt('required');
    final balance = error.detailInt('balance');
    // The balance moved between the price and the request: say by how much.
    if (needed != null && balance != null) return shortfallLine(needed, balance);
  }
  final code = switch (error) {
    SlimshotApiException(:final code) => code,
    SpeechFailure(:final code) => code,
    _ => '',
  };
  return switch (code) {
    SlimshotApiException.network => 'No internet connection.',
    SlimshotApiException.signInRequired =>
      'Sign in again to use Text to speech.',
    'INSUFFICIENT_CREDITS' => 'Not enough credits for this voice.',
    'ACCOUNT_SUSPENDED' => 'This account is suspended.',
    'TTS_UNAVAILABLE' || 'UNAUTHENTICATED' =>
      'Text to speech is unavailable right now.',
    'VOICE_NOT_FOUND' => 'That voice is no longer offered. Choose another.',
    'TEXT_TOO_LONG' =>
      'That text is too long for one voice. Split it into shorter texts.',
    'NOT_FOUND' => 'The voice expired before it was saved. Try again.',
    kSpeechPollTimeout => 'Making the voice took too long. Try again.',
    SpeechFailure.refunded =>
      'Making the voice failed. Your credits were returned.',
    _ => "Couldn't make the voice. Try again.",
  };
}
