import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/text_overlay_model.dart';

class TextStylePanel extends StatefulWidget {
  final TextOverlayModel? textModel;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<Color> onBackgroundColorChanged;
  final ValueChanged<Color> onStrokeColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<Color> onShadowColorChanged;
  final ValueChanged<double> onShadowBlurChanged;

  const TextStylePanel({
    super.key,
    required this.textModel,
    required this.onColorChanged,
    required this.onBackgroundColorChanged,
    required this.onStrokeColorChanged,
    required this.onStrokeWidthChanged,
    required this.onShadowColorChanged,
    required this.onShadowBlurChanged,
  });

  @override
  State<TextStylePanel> createState() => _TextStylePanelState();
}

class _TextStylePanelState extends State<TextStylePanel> {
  int _activeTabIndex = 0;
  final _tabs = ['Color', 'Background', 'Outline', 'Shadow'];

  static const _colors = [
    Colors.white,
    Colors.black,
    Colors.grey,
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.pink,
  ];

  Widget _buildColorSelector(Color currentColor, ValueChanged<Color> onChanged) {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _colors.length + 1,
        itemBuilder: (context, idx) {
          if (idx == 0) {
            return GestureDetector(
              onTap: () => onChanged(Colors.transparent),
              child: Container(
                width: 40,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: currentColor == Colors.transparent ? AppColors.primaryStart : Colors.white24,
                    width: currentColor == Colors.transparent ? 2 : 1,
                  ),
                ),
                child: const Icon(Icons.block, color: Colors.white54, size: 20),
              ),
            );
          }
          final color = _colors[idx - 1];
          final isSelected = currentColor == color;
          return GestureDetector(
            onTap: () => onChanged(color),
            child: Container(
              width: 40,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primaryStart : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveTabContent() {
    final model = widget.textModel!;
    switch (_activeTabIndex) {
      case 0: // Color
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Text Color', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 12),
              _buildColorSelector(model.color, widget.onColorChanged),
            ],
          ),
        );
      case 1: // Background
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Background Color', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 12),
              _buildColorSelector(model.backgroundColor, widget.onBackgroundColorChanged),
            ],
          ),
        );
      case 2: // Outline
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text('Outline Color', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 12),
            _buildColorSelector(model.strokeColor, widget.onStrokeColorChanged),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Thickness', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: model.strokeWidth,
                    min: 0,
                    max: 10,
                    activeColor: AppColors.primaryStart,
                    onChanged: widget.onStrokeWidthChanged,
                  ),
                ),
              ],
            ),
          ],
        ));
      case 3: // Shadow
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text('Shadow Color', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 12),
            _buildColorSelector(model.shadowColor, widget.onShadowColorChanged),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Blur', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: model.shadowBlurRadius,
                    min: 0,
                    max: 20,
                    activeColor: AppColors.primaryStart,
                    onChanged: widget.onShadowBlurChanged,
                  ),
                ),
              ],
            ),
          ],
        ));
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.textModel == null) {
      return const Center(child: Text('Select a text clip to edit style', style: TextStyle(color: Colors.white54)));
    }

    return Column(
      children: [
        // Tabs
        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _tabs.length,
            itemBuilder: (context, index) {
              final isSelected = _activeTabIndex == index;
              return GestureDetector(
                onTap: () => setState(() => _activeTabIndex = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white12 : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _tabs[index],
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white54,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        // Active Content
        Expanded(
          child: _buildActiveTabContent(),
        ),
      ],
    );
  }
}

class TextFontPanel extends StatelessWidget {
  final TextOverlayModel? textModel;
  final ValueChanged<String> onFontChanged;

  const TextFontPanel({
    super.key,
    required this.textModel,
    required this.onFontChanged,
  });

  static const _fonts = ['Roboto', 'Arial', 'Courier New', 'Times New Roman', 'Georgia', 'Impact', 'Comic Sans MS'];

  @override
  Widget build(BuildContext context) {
    if (textModel == null) {
      return const Center(child: Text('Select a text clip to edit font', style: TextStyle(color: Colors.white54)));
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: _fonts.length,
      itemBuilder: (context, idx) {
        final font = _fonts[idx];
        final isSelected = textModel!.fontFamily == font;
        return GestureDetector(
          onTap: () => onFontChanged(font),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primaryStart : Colors.white12,
              borderRadius: BorderRadius.circular(12),
              border: isSelected ? Border.all(color: Colors.white24, width: 1) : null,
            ),
            child: Text(
              font,
              style: TextStyle(
                color: Colors.white,
                fontFamily: font,
                fontSize: 18,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );
  }
}

class TextAnimationPanel extends StatefulWidget {
  final TextOverlayModel? textModel;
  final ValueChanged<String> onInAnimationChanged;
  final ValueChanged<String> onOutAnimationChanged;

  const TextAnimationPanel({
    super.key,
    required this.textModel,
    required this.onInAnimationChanged,
    required this.onOutAnimationChanged,
  });

  @override
  State<TextAnimationPanel> createState() => _TextAnimationPanelState();
}

class _TextAnimationPanelState extends State<TextAnimationPanel> {
  int _activeTabIndex = 0;
  final _tabs = ['In Animation', 'Out Animation'];

  static const _animations = ['none', 'fade', 'scale', 'slide_up', 'slide_down', 'slide_left', 'slide_right'];

  Widget _buildAnimationSelector(String currentAnim, ValueChanged<String> onChanged) {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _animations.length,
        itemBuilder: (context, idx) {
          final anim = _animations[idx];
          final isSelected = currentAnim == anim;
          return GestureDetector(
            onTap: () => onChanged(anim),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              margin: const EdgeInsets.only(right: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryStart : Colors.white12,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                anim.toUpperCase().replaceAll('_', ' '),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.textModel == null) {
      return const Center(child: Text('Select a text clip to edit animation', style: TextStyle(color: Colors.white54)));
    }

    final model = widget.textModel!;

    return Column(
      children: [
        // Tabs
        Row(
          children: List.generate(_tabs.length, (index) {
            final isSelected = _activeTabIndex == index;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _activeTabIndex = index),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isSelected ? AppColors.primaryStart : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    _tabs[index],
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white54,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 20),
        // Active Content
        _activeTabIndex == 0
            ? _buildAnimationSelector(model.inAnimation, widget.onInAnimationChanged)
            : _buildAnimationSelector(model.outAnimation, widget.onOutAnimationChanged),
      ],
    );
  }
}
