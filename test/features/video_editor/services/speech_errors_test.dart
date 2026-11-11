import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/video_editor/services/speech_errors.dart';
import 'package:slimshotai/features/video_editor/services/speech_service.dart';

/// Every way a voice run can end, in the one plain line the user sees — never
/// the server's or the provider's words.
void main() {
  String line(String code) => speechErrorMessage(SlimshotApiException(code, 'raw words'));

  test('each code to its line', () {
    expect(line('TTS_UNAVAILABLE'), 'Text to speech is unavailable right now.');
    expect(line('VOICE_NOT_FOUND'), 'That voice is no longer offered. Choose another.');
    expect(
      line('TEXT_TOO_LONG'),
      'That text is too long for one voice. Split it into shorter texts.',
    );
    expect(line(SlimshotApiException.network), 'No internet connection.');
    expect(line(kSpeechPollTimeout), 'Making the voice took too long. Try again.');
    expect(
      speechErrorMessage(const SpeechFailure(SpeechFailure.refunded)),
      'Making the voice failed. Your credits were returned.',
    );
    expect(line('PROVIDER_FAILED'), "Couldn't make the voice. Try again.");
    expect(
      speechErrorMessage(const SpeechJobFailed('TTS_UNAVAILABLE')),
      'Text to speech is unavailable right now.',
    );
  });

  test('the account cases say what to do', () {
    expect(line(SlimshotApiException.signInRequired), 'Sign in again to use Text to speech.');
    expect(line('ACCOUNT_SUSPENDED'), 'This account is suspended.');
    expect(line('NOT_FOUND'), 'The voice expired before it was saved. Try again.');
    expect(
      speechErrorMessage(const SlimshotApiException(
        'INSUFFICIENT_CREDITS',
        '',
        {'required': 12, 'balance': 3},
      )),
      'Needs 12 credits · You have 3',
    );
    expect(line('INSUFFICIENT_CREDITS'), 'Not enough credits for this voice.');
  });

  test('anything else is the plain fallback, never its own words', () {
    expect(
      speechErrorMessage(const FileSystemException('No space left on device', '/d/x.mp3')),
      "Couldn't make the voice. Try again.",
    );
    expect(speechErrorMessage(StateError('boom')), "Couldn't make the voice. Try again.");
  });
}
