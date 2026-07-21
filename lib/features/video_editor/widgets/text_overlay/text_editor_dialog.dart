import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/text_overlay_model.dart';
import '../../providers/video_editor_notifier.dart';
import '../../utils/font_utils.dart';

void showTextEditor({
  required BuildContext context,
  required TextOverlayModel overlay,
  required WidgetRef ref,
  TextEditorTool initialTool = TextEditorTool.keyboard,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    builder: (context) {
      return _TextEditorBottomSheet(overlay: overlay, ref: ref, initialTool: initialTool);
    },
  );
}

class _TextEditorBottomSheet extends StatefulWidget {
  final TextOverlayModel overlay;
  final WidgetRef ref;
  final TextEditorTool initialTool;

  const _TextEditorBottomSheet({
    required this.overlay,
    required this.ref,
    this.initialTool = TextEditorTool.keyboard,
  });

  @override
  State<_TextEditorBottomSheet> createState() => _TextEditorBottomSheetState();
}

enum TextEditorTool { keyboard, font, color, effects, animation }
enum ColorTarget { text, background, outline, shadow }

class _TextEditorBottomSheetState extends State<_TextEditorBottomSheet> {
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
  late String _textAlign;
  late double _borderRadius;
  late double _backgroundPadding;

  int _animationTabIndex = 0;
  late String _inAnimation;
  late String _outAnimation;
  late double _inAnimationDuration;
  late double _outAnimationDuration;

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
    _fontFamily = widget.overlay.fontFamily;
    _textColor = widget.overlay.color;
    _strokeColor = widget.overlay.strokeColor;
    _strokeWidth = widget.overlay.strokeWidth;
    _backgroundColor = widget.overlay.backgroundColor;
    _shadowColor = widget.overlay.shadowColor;
    _textAlign = widget.overlay.textAlign;
    _borderRadius = widget.overlay.borderRadius;
    _backgroundPadding = widget.overlay.backgroundPadding;
    _inAnimation = widget.overlay.inAnimation;
    _outAnimation = widget.overlay.outAnimation;
    _inAnimationDuration = widget.overlay.animationInDuration;
    _outAnimationDuration = widget.overlay.animationOutDuration;
    
    if (_activeTool == TextEditorTool.keyboard) {
      _focusNode.requestFocus();
    }
  }

  void _updateOverlay() {
    widget.ref.read(videoEditorProvider.notifier).updateTextOverlay(
      widget.overlay.id,
      (current) => current.copyWith(
        text: _textController.text,
        fontFamily: _fontFamily,
        color: _textColor,
        strokeColor: _strokeColor,
        strokeWidth: _strokeWidth,
        backgroundColor: _backgroundColor,
        shadowColor: _shadowColor,
        shadowBlurRadius: _shadowColor != Colors.transparent ? 8.0 : 0.0,
        textAlign: _textAlign,
        borderRadius: _borderRadius,
        backgroundPadding: _backgroundPadding,
        inAnimation: _inAnimation,
        outAnimation: _outAnimation,
        animationInDuration: _inAnimationDuration,
        animationOutDuration: _outAnimationDuration,
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF16181D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Actions & Drag Handle
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Copy / Duplicate
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.white, size: 22),
                      tooltip: 'Duplicate Text',
                      onPressed: () {
                        widget.ref.read(videoEditorProvider.notifier).duplicateTextOverlay(widget.overlay.id);
                        Navigator.pop(context);
                      },
                    ),
                    // Drag Handle
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                    // Delete
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent, size: 22),
                      tooltip: 'Delete Text',
                      onPressed: () {
                        widget.ref.read(videoEditorProvider.notifier).deleteTextOverlay(widget.overlay.id);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),

              // Toolbar
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildToolbarIcon(Icons.edit, TextEditorTool.keyboard),
                    _buildToolbarIcon(Icons.text_fields, TextEditorTool.font),
                    _buildToolbarIcon(Icons.color_lens, TextEditorTool.color),
                    // Alignment Cycler
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_textAlign == 'center') _textAlign = 'left';
                          else if (_textAlign == 'left') _textAlign = 'right';
                          else _textAlign = 'center';
                        });
                        _updateOverlay();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _textAlign == 'left' ? Icons.format_align_left : _textAlign == 'right' ? Icons.format_align_right : Icons.format_align_center,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    _buildToolbarIcon(Icons.auto_awesome, TextEditorTool.effects), // Effects
                    _buildToolbarIcon(Icons.animation, TextEditorTool.animation),
                  ],
                ),
              ),
              
              // Dynamic Content Area
              if (_activeTool == TextEditorTool.keyboard)
                _buildKeyboardPanel()
              else if (_activeTool == TextEditorTool.font)
                _buildFontPanel()
              else if (_activeTool == TextEditorTool.color)
                _buildColorPanel()
              else if (_activeTool == TextEditorTool.effects)
                _buildEffectsPanel()
              else if (_activeTool == TextEditorTool.animation)
                _buildAnimationPanel(),
                
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarIcon(IconData icon, TextEditorTool tool) {
    final isActive = _activeTool == tool;
    return GestureDetector(
      onTap: () => _setTool(tool),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: isActive ? Colors.black : Colors.white, size: 24),
      ),
    );
  }

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
          hintText: 'Enter text...',
          hintStyle: const TextStyle(color: Colors.white30),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.1),
          contentPadding: const EdgeInsets.all(16),
        ),
        textAlign: _textAlign == 'left' ? TextAlign.left : _textAlign == 'right' ? TextAlign.right : _textAlign == 'justify' ? TextAlign.justify : TextAlign.center,
        onChanged: (_) => _updateOverlay(),
      ),
    );
  }

  Widget _buildFontPanel() {
    return SizedBox(
      height: 250,
      child: GridView.builder(
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
                color: isSelected ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSelected ? Colors.white : Colors.transparent),
              ),
              child: Text(
                font,
                style: getFontStyle(font, color: Colors.white, fontSize: 16),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildColorPanel() {
    return SizedBox(
      height: 250,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          // Sub-menu for Color Target
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          // Dynamic Sliders based on target
          if (_activeColorTarget == ColorTarget.outline && _strokeColor != Colors.transparent) ...[
            _buildSliderRow('Thickness', _strokeWidth, 1, 10, (val) {
              setState(() => _strokeWidth = val);
              _updateOverlay();
            }),
            const SizedBox(height: 24),
          ],
          if (_activeColorTarget == ColorTarget.background && _backgroundColor != Colors.transparent) ...[
            _buildSliderRow('Radius', _borderRadius, 0, 50, (val) {
              setState(() => _borderRadius = val);
              _updateOverlay();
            }),
            const SizedBox(height: 8),
            _buildSliderRow('Padding', _backgroundPadding, 0, 64, (val) {
              setState(() => _backgroundPadding = val);
              _updateOverlay();
            }),
            const SizedBox(height: 24),
          ],

          // Unified Color Picker
          _buildColorPicker(
            selectedColor: _activeColorTarget == ColorTarget.text ? _textColor :
                          _activeColorTarget == ColorTarget.outline ? _strokeColor :
                          _activeColorTarget == ColorTarget.shadow ? _shadowColor : _backgroundColor,
            includeTransparent: _activeColorTarget != ColorTarget.text, // Text must always have a color
            onColorSelected: (c) {
              setState(() {
                if (_activeColorTarget == ColorTarget.text) {
                  _textColor = c;
                } else if (_activeColorTarget == ColorTarget.outline) {
                  _strokeColor = c;
                  if (c != Colors.transparent && _strokeWidth == 0) _strokeWidth = 3;
                  else if (c == Colors.transparent) _strokeWidth = 0;
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

  Widget _buildEffectsPanel() {
    return const SizedBox(
      height: 250,
      child: Center(
        child: Text(
          'Predesigned Text coming soon...',
          style: TextStyle(color: Colors.white54),
        ),
      ),
    );
  }

  static const _animationsList = ['none', 'fade', 'scale', 'slide_up', 'slide_down', 'slide_left', 'slide_right'];

  Widget _buildAnimationPanel() {
    return SizedBox(
      height: 250,
      child: Column(
        children: [
          // Sub-menu for In/Out
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(child: _buildAnimTargetBtn('In Animation', 0)),
                const SizedBox(width: 12),
                Expanded(child: _buildAnimTargetBtn('Out Animation', 1)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Duration Slider
          if ((_animationTabIndex == 0 && _inAnimation != 'none') ||
              (_animationTabIndex == 1 && _outAnimation != 'none'))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.timer, color: Colors.white54, size: 16),
                  Expanded(
                    child: SliderTheme(
                      data: const SliderThemeData(
                        activeTrackColor: AppColors.primaryStart,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: Colors.white,
                        trackHeight: 2,
                        overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
                      ),
                      child: Slider(
                        value: _animationTabIndex == 0 ? _inAnimationDuration : _outAnimationDuration,
                        min: 0.1,
                        max: 2.0,
                        onChanged: (val) {
                          setState(() {
                            if (_animationTabIndex == 0) {
                              _inAnimationDuration = val;
                            } else {
                              _outAnimationDuration = val;
                            }
                          });
                          _updateOverlay();
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${(_animationTabIndex == 0 ? _inAnimationDuration : _outAnimationDuration).toStringAsFixed(1)}s',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.5,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _animationsList.length,
              itemBuilder: (context, idx) {
                final anim = _animationsList[idx];
                final currentAnim = _animationTabIndex == 0 ? _inAnimation : _outAnimation;
                final isSelected = currentAnim == anim;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_animationTabIndex == 0) _inAnimation = anim;
                      else _outAnimation = anim;
                    });
                    _updateOverlay();
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      anim.toUpperCase().replaceAll('_', ' '),
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimTargetBtn(String label, int index) {
    final isActive = _animationTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _animationTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white54,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildFontPicker() {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                font,
                style: getFontStyle(font, color: isSelected ? Colors.black : Colors.white, fontSize: 14),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlignmentPicker() {
    final alignments = [
      {'val': 'left', 'icon': Icons.format_align_left},
      {'val': 'center', 'icon': Icons.format_align_center},
      {'val': 'right', 'icon': Icons.format_align_right},
      {'val': 'justify', 'icon': Icons.format_align_justify},
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: alignments.map((a) {
          final isSelected = _textAlign == a['val'];
          return GestureDetector(
            onTap: () {
              setState(() => _textAlign = a['val'] as String);
              _updateOverlay();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryStart : Colors.white12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(a['icon'] as IconData, color: isSelected ? Colors.white : Colors.white70, size: 20),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSliderRow(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              activeColor: AppColors.primaryStart,
              inactiveColor: Colors.white12,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker({required Color selectedColor, required Function(Color) onColorSelected, bool includeTransparent = false}) {
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
                color: isSelected ? Colors.white : (isTransparent ? Colors.white24 : Colors.transparent),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: isTransparent
                ? const Icon(Icons.block, color: Colors.white54, size: 20)
                : null,
          ),
        );
      },
    );
  }

  Widget _buildToggleBtn({required IconData icon, required String label, required bool isActive, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryStart.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: isActive ? AppColors.primaryStart : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isActive ? AppColors.primaryStart : Colors.white70, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.primaryStart : Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
