import '../video_editor/logic/captions/caption_preset_catalog.dart';
import '../video_editor/logic/text_template_catalog.dart';
import 'font_names.dart';

/// Said once a session, when a font a project uses could not be fetched:
/// its texts draw in the System font until it can be.
const String kFontUnavailableMessage = "A font in this project couldn't be downloaded";

/// The fonts of [projectFonts] still to fetch: not drawable yet, and not
/// already asked for this session — so an edit that does not change a
/// text's font asks nothing.
Set<String> fontsToFetch(
  Iterable<String> projectFonts,
  Set<String> alreadyAsked,
  bool Function(String name) isAvailable,
) =>
    {
      for (final name in projectFonts)
        if (!alreadyAsked.contains(name) && !isAvailable(name)) name,
    };

/// The server fonts a grid of template tiles draws in.
Set<String> templateFontNames(Iterable<TextTemplate> templates) =>
    {for (final t in templates) if (!isLocalFontName(t.fontFamily)) t.fontFamily};

/// The server fonts a grid of caption style tiles draws in.
Set<String> captionPresetFontNames(Iterable<CaptionPreset> presets) => {
      for (final p in presets)
        if (!isLocalFontName(p.look.fontFamily)) p.look.fontFamily,
    };
