import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../main.dart';
import '../compression/providers/compression_provider.dart';

class ShareIntentService {
  final WidgetRef ref;
  StreamSubscription? _intentDataStreamSubscription;

  ShareIntentService(this.ref);

  void initialize() {
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      _handleSharedMedia(value);
    }, onError: (err) {
      debugPrint("ReceiveSharingIntent: getMediaStream error: $err");
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      _handleSharedMedia(value);
    }).catchError((err) {
      debugPrint("ReceiveSharingIntent: getInitialMedia error: $err");
    });
  }

  void _handleSharedMedia(List<SharedMediaFile> sharedFiles) {
    if (sharedFiles.isEmpty) return;

    final List<XFile> videoFiles = [];
    final List<XFile> imageFiles = [];

    for (var file in sharedFiles) {
      if (file.type == SharedMediaType.video) {
        videoFiles.add(XFile(file.path));
      } else if (file.type == SharedMediaType.image) {
        imageFiles.add(XFile(file.path));
      }
    }

    if (videoFiles.isNotEmpty) {
      ref.read(compressionProvider.notifier).setInputFiles(videoFiles);
      appRouter.go('/compress/video');
    } else if (imageFiles.isNotEmpty) {
      ref.read(compressionProvider.notifier).setInputFiles(imageFiles);
      appRouter.go('/compress/image');
    }
    
    ReceiveSharingIntent.instance.reset();
  }

  void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}
