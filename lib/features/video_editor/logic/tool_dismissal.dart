/// How an open tool panel is dismissed by gestures other than its own ✓ or ✕.
///
/// A tool panel is modal in spirit: it replaces the toolbar and holds the
/// editor in one task until it is closed. Device-reported, twice, that it did
/// not behave like one — a tap on the canvas's empty space did nothing to it,
/// and the system Back button, pressed to close it the way Back closes a sheet,
/// left the editor for the home screen instead. Both now dismiss the panel,
/// **keeping** what the user set, the way a sheet's dismissal keeps its live
/// edits; the panel's ✕ remains the one explicit discard.
///
/// These are pure so the two rules can be pinned by a test rather than living
/// as conditions inside gesture handlers.
library;

/// Tools whose editing happens **on the canvas** — handles dragged there, or a
/// pinch on it. A tap on the canvas is part of using them, not a request to
/// leave, so empty-space dismissal does not apply.
const Set<String> kCanvasEditingTools = {'crop', 'clip_crop', 'zoom', 'mask'};

/// Whether a tap on the canvas's empty space dismisses the open [toolId].
bool toolClosesOnCanvasTap(String toolId) =>
    !kCanvasEditingTools.contains(toolId);

/// Tools whose panel has no ✕ / title / ✓ bar.
///
/// Mask's bar was two buttons that both just closed it — every Mask change
/// applies as it is made, and its ✕ had nothing to put back — plus the name of
/// the tool the user had just tapped. Its space went to the shapes (the user's
/// call, after CapCut). It closes with Back and with anything that leaves the
/// selection; a tap on the picture keeps it open, because that is where the
/// window is moved. Volume and Opacity keep their bar: their ✕ is the only way
/// to throw a drag away.
const Set<String> kHeaderlessTools = {'mask'};

/// Whether the open [toolId]'s panel carries the ✕ / title / ✓ bar.
bool toolPanelHasHeader(String toolId) => !kHeaderlessTools.contains(toolId);

/// What the system Back button does in the editor.
enum BackAction {
  /// A tool is open: close it, keeping its edits, and stay in the editor.
  closeTool,

  /// Nothing is open: save the draft and leave.
  leaveEditor,
}

/// Back closes an open tool — any tool, canvas-editing ones included, because
/// Back is an explicit "done here" where a canvas tap is not — and only with
/// none open does it leave the editor.
BackAction backActionFor({required String? activeToolId}) =>
    activeToolId == null ? BackAction.leaveEditor : BackAction.closeTool;
