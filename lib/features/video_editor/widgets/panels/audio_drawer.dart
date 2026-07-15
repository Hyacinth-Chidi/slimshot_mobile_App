import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:uuid/uuid.dart';

import '../../providers/video_editor_notifier.dart';
import '../../models/audio_track_model.dart';

class AudioDrawer extends ConsumerStatefulWidget {
  const AudioDrawer({super.key});

  @override
  ConsumerState<AudioDrawer> createState() => _AudioDrawerState();
}

class _AudioDrawerState extends ConsumerState<AudioDrawer> {
  int _selectedTabIndex = 0;
  final List<String> _tabs = [
    'For you',
    'Saved',
    'Trending',
    'Original audio',
    'Romance',
  ];

  bool _isImporting = false;

  Future<void> _importAudio() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.audio,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final player = AudioPlayer();
        final duration = await player.setFilePath(path);
        await player.dispose();

        if (duration != null) {
          final newTrack = AudioTrackModel(
            id: const Uuid().v4(),
            filePath: path,
            sourceDuration: duration.inMilliseconds / 1000.0,
            sourceStart: 0.0,
            sourceEnd: duration.inMilliseconds / 1000.0,
            timelineStart: 0.0, // Default to 0:00 for imported music
          );
          
          ref.read(videoEditorProvider.notifier).addAudioTrack(newTrack);
          if (mounted) {
            Navigator.of(context).pop(); // Close drawer
          }
        }
      }
    } catch (e) {
      debugPrint("Error importing audio: $e");
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E121A), // Dark background matching the theme
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      child: SafeArea(
        child: Column(
          children: [
            // Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            
            // Search Bar & Import Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12.0),
                            child: Icon(LucideIcons.search, color: Colors.white54, size: 18),
                          ),
                          Expanded(
                            child: TextField(
                              style: TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Search...',
                                hintStyle: TextStyle(color: Colors.white54, fontSize: 14),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _importAudio,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          if (_isImporting)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          else
                            const Icon(LucideIcons.music, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          const Text(
                            'Import',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Tab Bar
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _tabs.length,
                itemBuilder: (context, index) {
                  final isSelected = _selectedTabIndex == index;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTabIndex = index),
                    child: Container(
                      margin: const EdgeInsets.only(right: 20),
                      padding: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        border: isSelected
                            ? const Border(bottom: BorderSide(color: Colors.white, width: 2))
                            : null,
                      ),
                      child: Text(
                        _tabs[index],
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white54,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            // Divider
            const Divider(height: 1, color: Colors.white10),
            
            // Content Area (Loading Spinner)
            Expanded(
              child: Center(
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
