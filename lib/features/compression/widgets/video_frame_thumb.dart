import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../video_editor/services/video_thumbnail_service.dart';

/// A video's first moments as a still, through the filmstrip's extractor.
class VideoFrameThumb extends StatefulWidget {
  const VideoFrameThumb({super.key, required this.path});

  final String path;

  @override
  State<VideoFrameThumb> createState() => _VideoFrameThumbState();
}

class _VideoFrameThumbState extends State<VideoFrameThumb> {
  late final Future<Uint8List?> _frame = VideoThumbnailService.instance
      .singleFrame(path: widget.path, timeMs: 500, width: 160, height: 160);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: _frame,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          return bytes == null
              ? const ColoredBox(color: AppColors.surfaceLight)
              : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
        },
      );
}
