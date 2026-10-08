import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../core/services/media_picker_service.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/toast_utils.dart';
import '../core/widgets/permission_dialog.dart';
import '../features/compression/logic/photo_inspector.dart';
import '../features/privacy/providers/privacy_provider.dart';
import '../features/privacy/widgets/privacy_strip_view.dart';

/// Remove the personal details from one photo or several. The layout is
/// [PrivacyStripView]; this owns the provider, the picker and each photo's
/// shape.
class PrivacyScreen extends ConsumerStatefulWidget {
  final List<XFile>? initialImages;

  const PrivacyScreen({super.key, this.initialImages});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  final MediaPickerService _picker = MediaPickerService();
  final PhotoInspector _photos = PhotoInspector();

  /// Which of several photos is on screen.
  int _previewIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(privacyProvider.notifier).reset();
      final images = widget.initialImages;
      if (images != null && images.isNotEmpty) {
        _use(images);
      } else {
        _leave();
      }
    });
  }

  void _use(List<XFile> images) {
    setState(() => _previewIndex = 0);
    ref.read(privacyProvider.notifier).setInputFiles(images);
    _inspect(images.first.path);
  }

  void _inspect(String path) => _photos.inspect(path, () {
        if (mounted) setState(() {});
      });

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

  Future<void> _changePhotos() async {
    try {
      final images = await _picker.pickImages();
      if (images.isNotEmpty && mounted) _use(images);
    } catch (e) {
      if (!mounted) return;
      if (MediaPickerService.isPermissionError(e)) {
        PermissionDialog.showGalleryAccessRequired(
          context: context,
          message: 'SlimShotAI needs access to your gallery to select photos.',
          onCancel: () {},
        );
      } else {
        ToastUtils.show(context, 'Could not open the gallery: $e', isError: true);
      }
    }
  }

  void _preview(int index) {
    final files = ref.read(privacyProvider).inputFiles;
    if (index < 0 || index >= files.length) return;
    setState(() => _previewIndex = index);
    _inspect(files[index].path);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(privacyProvider);
    final notifier = ref.read(privacyProvider.notifier);

    ref.listen<PrivacyState>(privacyProvider, (previous, next) {
      if (previous?.isProcessing == true &&
          !next.isProcessing &&
          next.outputPaths.isNotEmpty &&
          next.error == null) {
        context.push('/privacy/result');
      }
      if (next.error != null && previous?.error == null && mounted) {
        ToastUtils.show(context, next.error!, isError: true);
      }
    });

    if (state.inputFiles.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryStart),
        ),
      );
    }

    final files = state.inputFiles;
    // While stripping, the photo being worked on.
    final shown = state.isProcessing
        ? state.currentProcessingIndex.clamp(0, files.length - 1)
        : _previewIndex.clamp(0, files.length - 1);
    final path = files[shown].path;

    return PrivacyStripView(
      state: state,
      photo: Image(
        key: ValueKey(path),
        image: _photos.imageFor(path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
      photoAspectRatio: _photos.aspect[path],
      photoInfo: _photos.info[path],
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
      onChangePhotos: _changePhotos,
      onStrip: () {
        HapticFeedback.mediumImpact();
        notifier.stripMetadata();
      },
      onCancel: notifier.cancel,
    );
  }
}
