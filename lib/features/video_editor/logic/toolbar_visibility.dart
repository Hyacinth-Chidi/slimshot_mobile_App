/// Which of a menu's declared tools the toolbar actually shows.
///
/// A menu declaration lists what a selection *can* do; this decides what is
/// offered for the selection as it stands. It is a pure function rather than
/// a filter inline in the screen because a filter there is invisible to the
/// menu tests, which read the declarations: a tool can be declared, pinned by
/// a test, and still never reach the user.
bool isToolbarToolVisible(
  String toolId, {
  required bool isSplitEnabled,
  required bool canDeleteSegment,
  required bool isClipSelected,
  required int clipCount,
  required bool hasTextSelected,
  required bool hasImageSelected,
  required bool hasVideoOverlaySelected,
}) {
  switch (toolId) {
    case 'delete':
      if (hasTextSelected || hasImageSelected || hasVideoOverlaySelected) {
        return true;
      }
      return canDeleteSegment;
    case 'split':
      return isSplitEnabled;
    case 'volume':
      // A selected video overlay is Volume's target, whatever the clips are
      // doing — selecting it deselects the clip, so the clip rule below hid
      // the overlay's Volume in every project with more than one clip.
      if (hasVideoOverlaySelected) return true;
      return clipCount <= 1 || isClipSelected;
    case 'speed':
      // With several clips and none selected, a slider would not know which
      // clip it moved; a lone clip is the only one it can mean.
      return clipCount <= 1 || isClipSelected;
  }
  // Animation used to be hidden for every video overlay — a rule from before
  // overlays were drawn by the engine, which animates them as it does photos.
  return true;
}
