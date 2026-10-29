import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/video_editor/logic/captions/captions_mode.dart';
import 'package:slimshotai/features/video_editor/services/caption_errors.dart';

/// Captions mode — the editor with the Home screen's Auto captions face —
/// decides its step, its Back and what it keeps from these rules alone; the
/// screen only wires them.
void main() {
  test('a run is Generating; captions without one are Done; neither is Ready',
      () {
    expect(captionsStepFor(running: true, hasCaptions: false),
        CaptionsStep.generating);
    expect(captionsStepFor(running: true, hasCaptions: true),
        CaptionsStep.generating);
    expect(captionsStepFor(running: false, hasCaptions: true),
        CaptionsStep.done);
    expect(captionsStepFor(running: false, hasCaptions: false),
        CaptionsStep.ready);
  });

  // The spec's call: a set emptied through Edit words — Delete all, or every
  // caption's words removed — takes the screen back to Ready, where Generate
  // makes a new one.
  test('a set emptied through Edit words is Ready again', () {
    expect(captionsStepFor(running: false, hasCaptions: false),
        CaptionsStep.ready);
  });

  test('only a soundless video goes back to Ready', () {
    expect(
        runFailureReturnsToReady(
            const CaptionFailure(CaptionFailure.noSound)),
        isTrue);
    expect(
        runFailureReturnsToReady(
            const CaptionFailure(CaptionFailure.noSpeech)),
        isFalse);
    expect(
        runFailureReturnsToReady(
            const SlimshotApiException(SlimshotApiException.network)),
        isFalse);
    expect(runFailureReturnsToReady(null), isFalse);
  });

  test('Back leaves Ready, stops a run, and asks on Done until an export is '
      'kept', () {
    final session = CaptionsModeSession();
    expect(session.backAt(CaptionsStep.ready), CaptionsBack.leave);
    expect(session.backAt(CaptionsStep.generating), CaptionsBack.stopRun);
    expect(session.backAt(CaptionsStep.done), CaptionsBack.askDiscard);

    // An export whose file was saved or shared: the captions are in it.
    session.exportKept = true;
    expect(session.backAt(CaptionsStep.done), CaptionsBack.leave);
  });

  test('the app is held on Done until an export is kept, and never after ✎',
      () {
    final session = CaptionsModeSession();
    expect(session.holdsWorkAt(CaptionsStep.done), isTrue);
    expect(session.holdsWorkAt(CaptionsStep.ready), isFalse);
    // The run holds the app itself while it lasts.
    expect(session.holdsWorkAt(CaptionsStep.generating), isFalse);

    session.exportKept = true;
    expect(session.holdsWorkAt(CaptionsStep.done), isFalse);

    final opened = CaptionsModeSession()..openedInEditor = true;
    for (final step in CaptionsStep.values) {
      expect(opened.holdsWorkAt(step), isFalse, reason: step.name);
    }
  });

  test("leaving deletes the picks, unless ✎ made them an editor project's",
      () {
    const picks = ['/cache/a1/video.mp4'];
    final session = CaptionsModeSession();
    expect(session.picksToDeleteOnLeave(picks), picks);
    session.openedInEditor = true;
    expect(session.picksToDeleteOnLeave(picks), isEmpty);
  });
}
