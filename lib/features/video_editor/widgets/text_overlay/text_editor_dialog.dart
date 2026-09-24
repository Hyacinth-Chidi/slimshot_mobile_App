import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/text_animation_catalog.dart';
import '../../logic/text_template_catalog.dart';
import '../../models/text_overlay_model.dart';
import '../../providers/video_editor_notifier.dart';
import '../../utils/font_utils.dart';
import 'text_animation_panel.dart';
import 'text_template_grid.dart';
import '../panels/editor_sheet.dart';

/// Opens the text editor sheet for [overlay].
///
/// When the sheet closes with the text still empty, the overlay is deleted:
/// an accidental "Add text" must not leave a ghost box behind that would end
/// up in the export.
Future<void> showTextEditor({
  required BuildContext context,
  required TextOverlayModel overlay,
  required WidgetRef ref,
  TextEditorTool initialTool = TextEditorTool.keyboard,
  List<TextTemplate> templates = kTextTemplates,
}) async {
  await showEditorSheet<void>(
    context,
    builder: (context) {
      return _TextEditorBottomSheet(
        overlay: overlay,
        ref: ref,
        initialTool: initialTool,
        templates: templates,
      );
    },
  );

  if (!ref.context.mounted) return;
  final state = ref.read(videoEditorProvider);
  TextOverlayModel? current;
  for (final t in state.textOverlays) {
    if (t.id == overlay.id) {
      current = t;
      break;
    }
  }
  if (current != null && current.text.trim().isEmpty) {
    final notifier = ref.read(videoEditorProvider.notifier);
    notifier.deleteTextOverlay(overlay.id);
    notifier.selectTextOverlay(null);
  }
}

enum TextEditorTool { keyboard, templates, style, font, animation }

/// The selected-text menu's entries that open this sheet, and the tab each
/// opens on.
///
/// They are doors into **this** sheet, not surfaces of their own: there stays
/// exactly one place text is styled, so nothing can drift from it. The ids
/// carry a `text_` prefix because the photo and video overlays' `animation`
/// opens `AnimationDrawer` — a text sent there would get the wrong animations.
/// A test pins the map to the menu declaration and to every tab.
const Map<String, TextEditorTool> kTextMenuSheetTools = {
  'text_edit': TextEditorTool.keyboard,
  'text_templates': TextEditorTool.templates,
  'text_style': TextEditorTool.style,
  'text_font': TextEditorTool.font,
  'text_animation': TextEditorTool.animation,
};

enum ColorTarget { text, background, outline, shadow }

/// A one-tap bundle of text styling — CapCut's "preset looks". Fonts are
/// deliberately not part of a preset: the look and the typeface are separate
/// choices, and a preset overwriting the chosen font would feel destructive.
class _TextPreset {
  const _TextPreset({
    required this.name,
    required this.color,
    this.strokeColor = Colors.transparent,
    this.strokeWidth = 0,
    this.backgroundColor = Colors.transparent,
    this.shadowColor = Colors.transparent,
    this.borderRadius = 6,
    this.backgroundPadding = 10,
  });

  final String name;
  final Color color;
  final Color strokeColor;
  final double strokeWidth;
  final Color backgroundColor;
  final Color shadowColor;
  final double borderRadius;
  final double backgroundPadding;
}

const List<_TextPreset> _kTextPresets = [
  _TextPreset(name: 'Classic', color: Colors.white),
  _TextPreset(
    name: 'Outline',
    color: Colors.white,
    strokeColor: Colors.black,
    strokeWidth: 4,
  ),
  _TextPreset(
    name: 'Caption',
    color: Colors.white,
    backgroundColor: Colors.black87,
    borderRadius: 4,
    backgroundPadding: 8,
  ),
  _TextPreset(
    name: 'Boxed',
    color: Colors.black,
    backgroundColor: Colors.white,
    borderRadius: 12,
  ),
  _TextPreset(
    name: 'Sunny',
    color: Colors.amber,
    strokeColor: Colors.black,
    strokeWidth: 3,
  ),
  _TextPreset(
    name: 'Neon',
    color: Colors.cyanAccent,
    shadowColor: Colors.cyanAccent,
  ),
  _TextPreset(
    name: 'Pop',
    color: Colors.white,
    backgroundColor: Colors.deepOrange,
  ),
  _TextPreset(
    name: 'Shadow',
    color: Colors.white,
    shadowColor: Colors.black,
  ),
];

class _TextEditorBottomSheet extends StatefulWidget {
  final TextOverlayModel overlay;
  final WidgetRef ref;
  final TextEditorTool initialTool;

  const _TextEditorBottomSheet({
    required this.overlay,
    required this.ref,
    this.initialTool = TextEditorTool.keyboard,
    this.templates = kTextTemplates,
  });

  /// The Templates tab's catalog, unless a test supplies its own: the
  /// catalog's families are Google Fonts, which a widget test cannot load.
  final List<TextTemplate> templates;

  @override
  State<_TextEditorBottomSheet> createState() => _TextEditorBottomSheetState();
}

class _TextEditorBottomSheetState extends State<_TextEditorBottomSheet> {
  /// Every tab's panel is exactly this tall, so switching tabs never resizes
  /// the sheet — a sheet that jumps under the thumb reads as broken.
  static const double _panelHeight = 250.0;

  late TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();
  late TextEditorTool _activeTool;
  ColorTarget _activeColorTarget = ColorTarget.text;

  late String _fontFamily;
  late Color _textColor;
  late Color _strokeColor;
  late double _strokeWidth;
  late Color _backgroundColor;
  late Color _shadowColor;
  late double _shadowOpacity;
  late double _shadowBlur;
  late double _shadowDistance;
  late double _shadowAngle;
  late String _textAlign;
  late double _borderRadius;
  late double _backgroundPadding;

  // The animation slots and their speeds. Held here, like every other styling
  // field, because `_updateOverlay` rewrites the whole overlay from these
  // caches — a panel writing straight to the notifier would have its change
  // undone by the next keystroke in the Keyboard tab.
  late String _inAnimation;
  late String _outAnimation;
  late String _loopAnimation;
  late double _inAnimationSpeed;
  late double _outAnimationSpeed;
  late double _loopSpeed;

  /// Which preset was last applied, cleared the moment any individual style
  /// property is changed by hand — a tweaked preset is no longer that preset.
  int? _activePresetIndex;

  final List<String> _fonts = allFonts;

  final List<Color> _colors = [
    Colors.white,
    Colors.black,
    Colors.grey,
    Colors.blueGrey,
    Colors.brown,
    Colors.red,
    Colors.deepOrange,
    Colors.orange,
    Colors.amber,
    Colors.yellow,
    Colors.lime,
    Colors.lightGreen,
    Colors.green,
    Colors.teal,
    Colors.cyan,
    Colors.lightBlue,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.pink,
  ];

  @override
  void initState() {
    super.initState();
    _activeTool = widget.initialTool;
    _textController = TextEditingController(text: widget.overlay.text);
    _loadLook(widget.overlay);

    if (_activeTool == TextEditorTool.keyboard) {
      _focusNode.requestFocus();
    }
  }

  /// Takes [overlay]'s look into the sheet's own copies of it.
  ///
  /// The sheet rewrites the whole text from these copies on every edit
  /// ([_applyEdits]) — so anything that changes the look from outside them, a
  /// template, has to come back through here, or the next keystroke would put
  /// the old look back.
  void _loadLook(TextOverlayModel overlay) {
    _fontFamily = overlay.fontFamily;
    _textColor = overlay.color;
    _strokeColor = overlay.strokeColor;
    _strokeWidth = overlay.strokeWidth;
    _backgroundColor = overlay.backgroundColor;
    _shadowColor = overlay.shadowColor;
    _shadowOpacity = overlay.shadowOpacity;
    _shadowBlur = overlay.shadowBlurRadius;
    _shadowDistance = overlay.shadowDistance;
    _shadowAngle = overlay.shadowAngle;
    _textAlign = overlay.textAlign;
    _borderRadius = overlay.borderRadius;
    _backgroundPadding = overlay.backgroundPadding;
    _inAnimation = overlay.inAnimation;
    _outAnimation = overlay.outAnimation;
    _loopAnimation = overlay.loopAnimation;
    _inAnimationSpeed = overlay.animationInDuration;
    _outAnimationSpeed = overlay.animationOutDuration;
    _loopSpeed = overlay.loopSpeed;
  }

  /// Type, then choose: puts [template] on this text — its words, timing and
  /// place kept, every part of the look replaced — as one undo step, and
  /// takes the new look into the sheet's copies ([_loadLook]).
  void _applyTemplate(TextTemplate template) {
    widget.ref.read(videoEditorProvider.notifier).updateTextOverlay(
          widget.overlay.id,
          (current) =>
              template.restyle(current.copyWith(text: _textController.text)),
        );
    setState(() {
      _activePresetIndex = null;
      _loadLook(_currentOverlay());
    });
  }

  TextOverlayModel _applyEdits(TextOverlayModel current) => current.copyWith(
        text: _textController.text,
        fontFamily: _fontFamily,
        color: _textColor,
        strokeColor: _strokeColor,
        strokeWidth: _strokeWidth,
        backgroundColor: _backgroundColor,
        shadowColor: _shadowColor,
        // The tuning is kept when the colour is cleared, so choosing a
        // colour again brings back the shadow as it was.
        shadowBlurRadius: _shadowBlur,
        shadowOpacity: _shadowOpacity,
        shadowDistance: _shadowDistance,
        shadowAngle: _shadowAngle,
        textAlign: _textAlign,
        borderRadius: _borderRadius,
        backgroundPadding: _backgroundPadding,
        inAnimation: _inAnimation,
        outAnimation: _outAnimation,
        loopAnimation: _loopAnimation,
        // Speeds, despite the field names — see `TextOverlayModel`.
        animationInDuration: _inAnimationSpeed,
        animationOutDuration: _outAnimationSpeed,
        loopSpeed: _loopSpeed,
      );

  void _updateOverlay() {
    widget.ref
        .read(videoEditorProvider.notifier)
        .updateTextOverlay(widget.overlay.id, _applyEdits);
  }

  /// One frame of a continuous gesture — the speed slider — with **no undo
  /// snapshot**.
  ///
  /// Going through [_updateOverlay] per frame pushes an entry per pixel of the
  /// drag, so "undo" walks the slider back rather than putting it where it
  /// was. The snapshot is taken once when the drag starts, the same split the
  /// canvas handles use.
  void _updateOverlayLive() {
    widget.ref
        .read(videoEditorProvider.notifier)
        .updateTextOverlayLive(widget.overlay.id, _applyEdits);
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setTool(TextEditorTool tool) {
    setState(() => _activeTool = tool);
    if (tool == TextEditorTool.keyboard) {
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
    }
  }

  void _applyPreset(int index) {
    final preset = _kTextPresets[index];
    setState(() {
      _activePresetIndex = index;
      _textColor = preset.color;
      _strokeColor = preset.strokeColor;
      _strokeWidth = preset.strokeWidth;
      _backgroundColor = preset.backgroundColor;
      _shadowColor = preset.shadowColor;
      // A preset is a complete look, shadow included: the tuning goes back to
      // what every new shadow starts as.
      _shadowOpacity = kTextShadowDefaultOpacity;
      _shadowBlur = kTextShadowDefaultBlur;
      _shadowDistance = kTextShadowDefaultDistance;
      _shadowAngle = kTextShadowDefaultAngle;
      _borderRadius = preset.borderRadius;
      _backgroundPadding = preset.backgroundPadding;
    });
    _updateOverlay();
  }

  /// Any hand edit to a style property means the preset no longer describes
  /// the look.
  void _markCustomized() {
    _activePresetIndex = null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 10),

              // Tabs on the left, one explicit way out on the right. The old
              // sheet could only be dismissed by tapping outside — which is
              // also how you would try to touch the text itself.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildTab(
                              LucideIcons.keyboard,
                              'Keyboard',
                              TextEditorTool.keyboard,
                            ),
                            // Right after the words: type, then choose.
                            _buildTab(
                              LucideIcons.layoutTemplate,
                              'Templates',
                              TextEditorTool.templates,
                            ),
                            _buildTab(
                              LucideIcons.palette,
                              'Style',
                              TextEditorTool.style,
                            ),
                            _buildTab(
                              LucideIcons.type,
                              'Font',
                              TextEditorTool.font,
                            ),
                            _buildTab(
                              LucideIcons.playCircle,
                              'Animation',
                              TextEditorTool.animation,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.primaryStart,
                              AppColors.primaryEnd,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          LucideIcons.check,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // The three styling tabs share one fixed height so switching
              // between them never resizes the sheet. The keyboard tab is
              // deliberately *not* boxed: the IME already occupies the space
              // below, and padding the field to the styling height stacked
              // dead space on top of the keyboard and crushed the preview.
              if (_activeTool == TextEditorTool.keyboard)
                _buildKeyboardPanel()
              else
                SizedBox(
                  height: _panelHeight,
                  child: switch (_activeTool) {
                    TextEditorTool.keyboard => const SizedBox.shrink(),
                    TextEditorTool.templates => _buildTemplatesPanel(),
                    TextEditorTool.style => _buildStylePanel(),
                    TextEditorTool.font => _buildFontPanel(),
                    TextEditorTool.animation => _buildAnimationPanel(),
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(IconData icon, String label, TextEditorTool tool) {
    final isActive = _activeTool == tool;
    return GestureDetector(
      onTap: () => _setTool(tool),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isActive ? Colors.black : Colors.white70,
              size: 15,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.black : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- keyboard

  Widget _buildKeyboardPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
          controller: _textController,
          focusNode: _focusNode,
          style: getFontStyle(_fontFamily, color: _textColor, fontSize: 24),
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Type something…',
            hintStyle: const TextStyle(color: Colors.white30),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1),
            contentPadding: const EdgeInsets.all(16),
          ),
          textAlign: _textAlign == 'left'
              ? TextAlign.left
              : _textAlign == 'right'
                  ? TextAlign.right
                  : _textAlign == 'justify'
                      ? TextAlign.justify
                      : TextAlign.center,
          onChanged: (_) => _updateOverlay(),
        ),
    );
  }

  // ---------------------------------------------------------------- style

  Widget _buildStylePanel() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        _buildSectionLabel('Presets'),
        SizedBox(
          height: 56,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _kTextPresets.length,
            itemBuilder: (context, index) =>
                _buildPresetTile(index, _kTextPresets[index]),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionLabel('Alignment'),
        _buildAlignmentPicker(),
        const SizedBox(height: 16),
        _buildSectionLabel('Colors'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildColorTargetBtn('Text', ColorTarget.text),
                const SizedBox(width: 8),
                _buildColorTargetBtn('Background', ColorTarget.background),
                const SizedBox(width: 8),
                _buildColorTargetBtn('Outline', ColorTarget.outline),
                const SizedBox(width: 8),
                _buildColorTargetBtn('Shadow', ColorTarget.shadow),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_activeColorTarget == ColorTarget.outline &&
            _strokeColor != Colors.transparent) ...[
          _buildSliderRow('Thickness', _strokeWidth, 1, 10,
              (val) => _strokeWidth = val),
          const SizedBox(height: 8),
        ],
        if (_activeColorTarget == ColorTarget.background &&
            _backgroundColor != Colors.transparent) ...[
          _buildSliderRow('Radius', _borderRadius, 0, 50,
              (val) => _borderRadius = val),
          const SizedBox(height: 8),
          _buildSliderRow('Padding', _backgroundPadding, 0, 64,
              (val) => _backgroundPadding = val),
          const SizedBox(height: 8),
        ],
        // The rest of the shadow, under its colour like Thickness under
        // Outline. The angle is the direction it falls, clockwise from right.
        if (_activeColorTarget == ColorTarget.shadow &&
            _shadowColor != Colors.transparent) ...[
          _buildSliderRow('Opacity', _shadowOpacity, 0, 1,
              (val) => _shadowOpacity = val),
          const SizedBox(height: 8),
          _buildSliderRow('Blur', _shadowBlur, 0, kTextShadowMaxBlur,
              (val) => _shadowBlur = val),
          const SizedBox(height: 8),
          _buildSliderRow('Distance', _shadowDistance, 0,
              kTextShadowMaxDistance, (val) => _shadowDistance = val),
          const SizedBox(height: 8),
          _buildSliderRow('Angle', _shadowAngle, 0, 360,
              (val) => _shadowAngle = val),
          const SizedBox(height: 8),
        ],
        _buildColorPicker(
          selectedColor: _activeColorTarget == ColorTarget.text
              ? _textColor
              : _activeColorTarget == ColorTarget.outline
                  ? _strokeColor
                  : _activeColorTarget == ColorTarget.shadow
                      ? _shadowColor
                      : _backgroundColor,
          // Text must always have a colour.
          includeTransparent: _activeColorTarget != ColorTarget.text,
          onColorSelected: (c) {
            setState(() {
              _markCustomized();
              if (_activeColorTarget == ColorTarget.text) {
                _textColor = c;
              } else if (_activeColorTarget == ColorTarget.outline) {
                _strokeColor = c;
                if (c != Colors.transparent && _strokeWidth == 0) {
                  _strokeWidth = 3;
                } else if (c == Colors.transparent) {
                  _strokeWidth = 0;
                }
              } else if (_activeColorTarget == ColorTarget.shadow) {
                _shadowColor = c;
              } else if (_activeColorTarget == ColorTarget.background) {
                _backgroundColor = c;
              }
            });
            _updateOverlay();
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPresetTile(int index, _TextPreset preset) {
    final isSelected = _activePresetIndex == index;

    // The tile shows the preset's own pixels — background, stroke, shadow —
    // so the user can tell the looks apart before applying one.
    final sample = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: preset.backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Stack(
        children: [
          if (preset.strokeWidth > 0)
            Text(
              'Aa',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = preset.strokeWidth
                  ..color = preset.strokeColor,
              ),
            ),
          Text(
            'Aa',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: preset.color,
              shadows: preset.shadowColor != Colors.transparent
                  ? [Shadow(color: preset.shadowColor, blurRadius: 8)]
                  : null,
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: () => _applyPreset(index),
      child: Container(
        width: 56,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: sample,
      ),
    );
  }

  Widget _buildColorTargetBtn(String label, ColorTarget target) {
    final isActive = _activeColorTarget == target;
    return GestureDetector(
      onTap: () => setState(() => _activeColorTarget = target),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.black : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ templates

  /// Every template, previewed in this text's own words, the one it is
  /// wearing highlighted. A tap puts it on; another tap swaps it.
  Widget _buildTemplatesPanel() {
    final current = _currentOverlay();
    String? wearing;
    for (final t in widget.templates) {
      if (t.isAppliedTo(current)) {
        wearing = t.id;
        break;
      }
    }
    return TextTemplateGrid(
      templates: widget.templates,
      text: _textController.text,
      selectedId: wearing,
      onSelected: _applyTemplate,
    );
  }

  // ----------------------------------------------------------------- font

  Widget _buildFontPanel() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _fonts.length,
      itemBuilder: (context, index) {
        final font = _fonts[index];
        final isSelected = _fontFamily == font;
        return GestureDetector(
          onTap: () {
            setState(() => _fontFamily = font);
            _updateOverlay();
          },
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
              ),
            ),
            child: Text(
              font,
              style: getFontStyle(font, color: Colors.white, fontSize: 16),
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------ animation

  /// The Animation tab, delegated to [TextAnimationPanel].
  ///
  /// The panel lists the animation catalog — **no list lives here**. The tab
  /// used to hold a hardcoded seven names, which is how the engine came to
  /// play thirty animations while the user could only pick from seven.
  Widget _buildAnimationPanel() {
    return TextAnimationPanel(
      // The panel previews the user's *current* styling and highlights the
      // slot as it stands now, so it reads the live overlay from the notifier
      // rather than the one the sheet opened on.
      overlay: _currentOverlay(),
      onSelect: _selectAnimation,
      // One snapshot per drag, then live writes — see [_updateOverlayLive].
      onSpeedChangeStart: () =>
          widget.ref.read(videoEditorProvider.notifier).saveStateForUndo(),
      onSpeedChanged: _setAnimationSpeed,
    );
  }

  /// The overlay as the notifier currently holds it, falling back to the one
  /// the sheet was opened with if it has since been deleted.
  TextOverlayModel _currentOverlay() {
    final overlays = widget.ref.read(videoEditorProvider).textOverlays;
    for (final t in overlays) {
      if (t.id == widget.overlay.id) return t;
    }
    return widget.overlay;
  }

  /// Writes a catalog id (or null, for None) into [category]'s slot.
  ///
  /// `'none'` rather than an empty string, because that is the sentinel every
  /// reader of these fields — the catalog's resolver, the composer and the
  /// Kotlin port — already recognises.
  void _selectAnimation(TextAnimationCategory category, String? id) {
    final value = id ?? 'none';
    setState(() {
      switch (category) {
        case TextAnimationCategory.inAnim:
          _inAnimation = value;
        case TextAnimationCategory.outAnim:
          _outAnimation = value;
        case TextAnimationCategory.loop:
          _loopAnimation = value;
      }
    });
    // One tap, one undo entry.
    _updateOverlay();
  }

  /// A frame of the Speed slider: a **multiplier**, not seconds.
  void _setAnimationSpeed(TextAnimationCategory category, double speed) {
    setState(() {
      switch (category) {
        // **Both in and out, always.** The two are expected to be equal: the
        // renderer resolves both windows from one of them, because the
        // proportional compression that fits them into a short overlay is a
        // single rule that must not exist twice across the Dart/Kotlin
        // boundary. Writing only the active tab's field would let them
        // diverge, and the out window would then quietly follow the in slider.
        case TextAnimationCategory.inAnim:
        case TextAnimationCategory.outAnim:
          _inAnimationSpeed = speed;
          _outAnimationSpeed = speed;
        // A loop's cycle length is no part of that compression, so its speed
        // is genuinely its own.
        case TextAnimationCategory.loop:
          _loopSpeed = speed;
      }
    });
    _updateOverlayLive();
  }

  // -------------------------------------------------------------- shared

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildAlignmentPicker() {
    final alignments = [
      (value: 'left', icon: LucideIcons.alignLeft),
      (value: 'center', icon: LucideIcons.alignCenter),
      (value: 'right', icon: LucideIcons.alignRight),
      (value: 'justify', icon: LucideIcons.alignJustify),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: alignments.map((a) {
          final isSelected = _textAlign == a.value;
          return GestureDetector(
            onTap: () {
              setState(() => _textAlign = a.value);
              _updateOverlay();
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryStart : Colors.white12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                a.icon,
                color: isSelected ? Colors.white : Colors.white70,
                size: 20,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// A labelled slider over one style value. [write] stores the value; the
  /// row does the rest: **one undo snapshot when the drag starts**, then a
  /// live write per frame, so a drag is one undo step. Each frame used to go
  /// through [_updateOverlay], which snapshots per call — Undo walked a drag
  /// back a frame at a time.
  Widget _buildSliderRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> write,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              activeColor: AppColors.primaryStart,
              inactiveColor: Colors.white12,
              onChangeStart: (_) => widget.ref
                  .read(videoEditorProvider.notifier)
                  .saveStateForUndo(),
              onChanged: (val) {
                setState(() {
                  write(val);
                  _markCustomized();
                });
                _updateOverlayLive();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker({
    required Color selectedColor,
    required Function(Color) onColorSelected,
    bool includeTransparent = false,
  }) {
    final colors = includeTransparent ? [Colors.transparent, ..._colors] : _colors;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: colors.length,
      itemBuilder: (context, index) {
        final color = colors[index];
        final isSelected = selectedColor == color;
        final isTransparent = color == Colors.transparent;

        return GestureDetector(
          onTap: () => onColorSelected(color),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: isSelected
                    ? Colors.white
                    : (isTransparent ? Colors.white24 : Colors.transparent),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: isTransparent
                ? const Icon(LucideIcons.ban, color: Colors.white54, size: 20)
                : null,
          ),
        );
      },
    );
  }
}
