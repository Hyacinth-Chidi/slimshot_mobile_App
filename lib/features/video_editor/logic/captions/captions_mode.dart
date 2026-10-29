import '../../services/caption_errors.dart';

/// Where the captions screen is: choosing (Ready), waiting for the words
/// (Generating), or styling and exporting them (Done).
enum CaptionsStep { ready, generating, done }

/// The step is read off the work, never stored: a run under way is
/// Generating; captions with no run are Done; neither is Ready — which is
/// also where a set emptied through Edit words lands.
CaptionsStep captionsStepFor({
  required bool running,
  required bool hasCaptions,
}) {
  if (running) return CaptionsStep.generating;
  return hasCaptions ? CaptionsStep.done : CaptionsStep.ready;
}

/// Whether a failed run goes back to Ready with its line rather than
/// offering Try again: only a video with no sound, where nothing was uploaded
/// and trying again cannot help.
bool runFailureReturnsToReady(Object? failure) =>
    failure is CaptionFailure && failure.code == CaptionFailure.noSound;

/// What Back does.
enum CaptionsBack {
  /// Leave the screen.
  leave,

  /// Stop the run and go back to Ready, as Cancel does.
  stopRun,

  /// Ask "Discard these captions?" first.
  askDiscard,
}

/// What captions mode remembers about the work beside the project itself.
///
/// It never saves a draft, so what protects captions someone paid for is
/// this: until an export of them is kept, Back asks and a tap on the home
/// screen widget only brings the app forward.
class CaptionsModeSession {
  /// An export of the captions was saved or shared — they are in a file.
  /// One discarded on the export screen does not count.
  bool exportKept = false;

  /// ✎ made the work an ordinary editor project, saved as any is.
  bool openedInEditor = false;

  /// A new set landed — a set emptied through Edit words and generated
  /// again was paid for again, so an export of the old one keeps nothing.
  void newSetPlaced() => exportKept = false;

  /// Back at [step].
  CaptionsBack backAt(CaptionsStep step) => switch (step) {
        CaptionsStep.ready => CaptionsBack.leave,
        CaptionsStep.generating => CaptionsBack.stopRun,
        CaptionsStep.done =>
          exportKept ? CaptionsBack.leave : CaptionsBack.askDiscard,
      };

  /// Whether the screen must not be torn down from outside at [step]. The
  /// run holds the app itself while it lasts, so only Done is this
  /// session's.
  bool holdsWorkAt(CaptionsStep step) =>
      !openedInEditor && step == CaptionsStep.done && !exportKept;

  /// The picked files to delete as the screen goes: all of them, unless ✎
  /// made them an editor project's, whose draft plays from them.
  List<String> picksToDeleteOnLeave(List<String> picks) =>
      openedInEditor ? const [] : picks;
}
