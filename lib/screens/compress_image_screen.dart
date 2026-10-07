import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../core/services/ad_service.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/toast_utils.dart';
import '../features/compression/logic/compress_labels.dart';
import '../features/compression/logic/compression_presets.dart';
import '../features/compression/providers/compression_provider.dart';
import '../features/compression/widgets/compress_photo_view.dart';

/// Compress one photo, or several. The layout is [CompressPhotoView]; this
/// owns the provider and reads each photo's shape and size.
class CompressImageScreen extends ConsumerStatefulWidget {
  const CompressImageScreen({super.key, this.initialImages});

  final List<XFile>? initialImages;

  @override
  ConsumerState<CompressImageScreen> createState() =>
      _CompressImageScreenState();
}

class _CompressImageScreenState extends ConsumerState<CompressImageScreen> {
  /// Which of several photos is on screen.
  int _previewIndex = 0;

  /// Width over height as the photo is shown — read from the decoded image,
  /// which has already applied the camera's rotation flag. A phone stores
  /// most portrait photos sideways with that flag, so the file's own header
  /// would give them the wrong shape.
  final Map<String, double> _aspect = {};

  /// "HEIC · 12 MP", from the file's header: width × height is the same
  /// whichever way round the photo is stored.
  final Map<String, String> _info = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(compressionProvider.notifier).reset();
      final images = widget.initialImages;
      if (images != null && images.isNotEmpty) {
        ref.read(compressionProvider.notifier).setInputFiles(
              images,
              defaultPreset: CompressionPresets.imagePresets[1],
            );
        _inspect(images.first.path);
      } else {
        _leave();
      }
    });
  }

  /// Back where the user came from — or home, when the screen was opened
  /// from the share sheet and has nothing beneath it.
  void _leave() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  ImageProvider _imageFor(String path) => ResizeImage(
        FileImage(File(path)),
        width: 1600,
        policy: ResizeImagePolicy.fit,
      );

  Future<void> _inspect(String path) async {
    if (!_aspect.containsKey(path)) {
      final stream = _imageFor(path).resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener((image, _) {
        stream.removeListener(listener);
        final width = image.image.width;
        final height = image.image.height;
        if (mounted && width > 0 && height > 0) {
          setState(() => _aspect[path] = width / height);
        }
      }, onError: (_, __) => stream.removeListener(listener));
      stream.addListener(listener);
    }
    if (!_info.containsKey(path)) {
      int? width;
      int? height;
      try {
        final buffer = await ui.ImmutableBuffer.fromFilePath(path);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        width = descriptor.width;
        height = descriptor.height;
        descriptor.dispose();
        buffer.dispose();
      } catch (_) {
        // A format the platform cannot read: the label keeps the format.
      }
      if (mounted) {
        setState(() => _info[path] = photoInfoLabel(path, width, height));
      }
    }
  }

  void _preview(int index) {
    final files = ref.read(compressionProvider).inputFiles;
    if (index < 0 || index >= files.length) return;
    setState(() => _previewIndex = index);
    _inspect(files[index].path);
  }

  Future<void> _handleCompress() async {
    await ref.read(compressionProvider.notifier).compressImage();

    if (!mounted) return;
    final state = ref.read(compressionProvider);
    if (state.inputFiles.isEmpty) return;
    if (state.outputPaths.isNotEmpty &&
        !state.isProcessing &&
        state.error == null) {
      context.push('/result');
    } else if (state.error != null) {
      ToastUtils.show(context, state.error!, isError: true);
    }
  }

  void _selectPreset(CompressionPreset preset) {
    final notifier = ref.read(compressionProvider.notifier);
    final selected = ref.read(compressionProvider).selectedPreset;
    if (preset.isPro && selected?.id != preset.id) {
      // With ads off this grants at once (`AdService.enabled`).
      AdService.showRewardedAd(
        context,
        onRewardEarned: () {
          if (mounted) notifier.selectPreset(preset);
        },
        onFailed: () {
          if (mounted) {
            ToastUtils.show(
              context,
              'Check your connection to unlock ${preset.name}.',
              isWarning: true,
            );
          }
        },
      );
    } else {
      notifier.selectPreset(preset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(compressionProvider);
    final notifier = ref.read(compressionProvider.notifier);

    if (state.inputFiles.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryStart),
        ),
      );
    }

    final files = state.inputFiles;
    // While compressing, the photo being worked on.
    final shown = state.isProcessing
        ? state.currentProcessingIndex.clamp(0, files.length - 1)
        : _previewIndex.clamp(0, files.length - 1);
    final path = files[shown].path;

    return CompressPhotoView(
      state: state,
      photo: Image(
        key: ValueKey(path),
        image: _imageFor(path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
      photoAspectRatio: _aspect[path],
      photoInfo: _info[path],
      thumbnails: [
        for (final file in files)
          Image.file(
            File(file.path),
            key: ValueKey(file.path),
            fit: BoxFit.cover,
            cacheWidth: 160,
          ),
      ],
      previewIndex: shown,
      onPreview: _preview,
      onBack: _leave,
      onSelectPreset: _selectPreset,
      onToggleRemoveLocation: notifier.toggleRemoveMetadata,
      onFormat: notifier.setTargetImageFormat,
      onCompress: _handleCompress,
      onCancel: notifier.cancelCompression,
    );
  }
}
