import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class EditorPlaybackControls extends StatelessWidget {
  const EditorPlaybackControls({
    super.key,
    required this.isPlaying,
    required this.timelineLabel,
    required this.canUndo,
    required this.canRedo,
    required this.onTogglePreview,
    required this.onUndo,
    required this.onRedo,
    this.onExpandPreview,
  });

  final bool isPlaying;
  final String timelineLabel;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onTogglePreview;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback? onExpandPreview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: onTogglePreview,
            child: Icon(
              isPlaying ? LucideIcons.pause : LucideIcons.play,
              color: Colors.white,
              size: 24,
            ),
          ),
          Text(
            timelineLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: onExpandPreview,
                child: const Icon(
                  LucideIcons.maximize2,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: canUndo ? onUndo : null,
                child: Icon(
                  LucideIcons.undo2,
                  color: canUndo ? Colors.white70 : Colors.white24,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: canRedo ? onRedo : null,
                child: Icon(
                  LucideIcons.redo2,
                  color: canRedo ? Colors.white70 : Colors.white24,
                  size: 20,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
