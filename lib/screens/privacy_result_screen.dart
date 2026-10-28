import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/services/media_save_service.dart';
import '../core/utils/file_utils.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/result_exit.dart';
import '../core/utils/toast_utils.dart';
import '../core/widgets/discard_dialog.dart';
import '../features/compression/logic/photo_inspector.dart';
import '../features/privacy/providers/privacy_provider.dart';
import '../features/privacy/widgets/privacy_report_view.dart';

/// The Privacy report. The layout is [PrivacyReportView]; this owns saving
/// and leaving — ✕ and New photos go home, the phone's Back steps back to
/// the strip screen, each asking first when the cleaned photos were neither
/// saved nor shared; their files go either way ([ResultExit]).
class PrivacyResultScreen extends ConsumerStatefulWidget {
  const PrivacyResultScreen({
    super.key,
    this.deleteFiles = FileUtils.deleteTempFiles,
  });

  /// How the cleaned photos are deleted when the report is left; a test's
  /// stand-in.
  final TempFileDeleter deleteFiles;

  @override
  ConsumerState<PrivacyResultScreen> createState() =>
      _PrivacyResultScreenState();
}

class _PrivacyResultScreenState extends ConsumerState<PrivacyResultScreen> {
  final PhotoInspector _photos = PhotoInspector();
  int _selectedIndex = 0;
  late final ResultExit _exit = ResultExit(delete: widget.deleteFiles);

  @override
  void initState() {
    super.initState();
    // Nobody has kept the cleaned photos yet: a tap on the home screen
    // widget only brings the app forward until somebody does.
    _exit.hold();
    HapticFeedback.mediumImpact();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final outputs = ref.read(privacyProvider).outputPaths;
      if (outputs.isNotEmpty) _inspect(outputs.first);
    });
  }

  @override
  void dispose() {
    _exit.release();
    super.dispose();
  }

  void _inspect(String path) => _photos.inspect(path, () {
    if (mounted) setState(() {});
  });

  /// Saves at once: an ad in front of Save made the user wait for their own
  /// photos (the ad comes when stripping starts instead).
  Future<void> _save(List<String> outputs) async {
    try {
      await MediaSaveService.saveImagesToGallery(outputs);
      _exit.markKept();
      HapticFeedback.mediumImpact();
      if (mounted) {
        ToastUtils.show(
          context,
          outputs.length > 1 ? '${outputs.length} photos saved' : 'Saved to gallery',
        );
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.show(context, 'Could not save: $e', isError: true);
      }
    }
  }

  Future<void> _share(List<String> outputs) async {
    if (await MediaSaveService.shareFiles(outputs)) _exit.markKept();
  }

  /// Home for ✕ and New photos; for the phone's Back, the strip screen it
  /// came from.
  Future<void> _leave({required bool home}) async {
    final state = ref.read(privacyProvider);
    final outputs = state.outputPaths;
    final leave = await _exit.leave(
      outputs: outputs,
      inputs: [for (final file in state.inputFiles) file.path],
      confirm: () =>
          confirmDiscard(context, isVideo: false, count: outputs.length),
    );
    if (!leave || !mounted) return;
    if (home || !context.canPop()) {
      context.go('/home');
    } else {
      context.pop();
    }
  }

  void _preview(int index) {
    final outputs = ref.read(privacyProvider).outputPaths;
    if (index < 0 || index >= outputs.length) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = index);
    _inspect(outputs[index]);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(privacyProvider);

    if (state.outputPaths.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryStart),
        ),
      );
    }

    final outputs = state.outputPaths;
    final index = _selectedIndex.clamp(0, outputs.length - 1);
    final path = outputs[index];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(home: false);
      },
      child: PrivacyReportView(
        state: state,
        photo: Image(
          key: ValueKey(path),
          image: _photos.imageFor(path),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
        photoAspectRatio: _photos.aspect[path],
        thumbnails: [
          for (final output in outputs)
            Image.file(
              File(output),
              key: ValueKey(output),
              fit: BoxFit.cover,
              cacheWidth: 160,
            ),
        ],
        previewIndex: index,
        onPreview: _preview,
        onClose: () => _leave(home: true),
        // Every cleaned photo, not only the one on screen: the old screen
        // saved just the shown one when there was a single result and all of
        // them otherwise, which is the same rule.
        onSave: () => _save(outputs),
        onShare: () => _share(outputs),
        onNew: () => _leave(home: true),
      ),
    );
  }
}
