import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models/history_item.dart';
import '../core/services/ad_service.dart';
import '../core/services/history_service.dart';
import '../core/services/media_save_service.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/toast_utils.dart';
import '../features/compression/logic/photo_inspector.dart';
import '../features/privacy/providers/privacy_provider.dart';
import '../features/privacy/widgets/privacy_report_view.dart';

/// The Privacy report. The layout is [PrivacyReportView]; this owns the
/// history entry and saving.
class PrivacyResultScreen extends ConsumerStatefulWidget {
  const PrivacyResultScreen({super.key});

  @override
  ConsumerState<PrivacyResultScreen> createState() =>
      _PrivacyResultScreenState();
}

class _PrivacyResultScreenState extends ConsumerState<PrivacyResultScreen> {
  final PhotoInspector _photos = PhotoInspector();
  int _selectedIndex = 0;
  bool _historySaved = false;

  @override
  void initState() {
    super.initState();
    AdService.loadInterstitialAd();
    HapticFeedback.mediumImpact();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _saveHistory();
      final outputs = ref.read(privacyProvider).outputPaths;
      if (outputs.isNotEmpty) _inspect(outputs.first);
    });
  }

  void _inspect(String path) => _photos.inspect(path, () {
        if (mounted) setState(() {});
      });

  Future<void> _saveHistory() async {
    if (_historySaved) return;
    _historySaved = true;

    final state = ref.read(privacyProvider);
    if (state.outputPaths.isEmpty) return;

    await HistoryService.addItem(
      HistoryItem(
        id: state.outputPaths.join('|'),
        title: state.outputPaths.length == 1
            ? 'Privacy-clean photo'
            : 'Privacy-cleaned ${state.outputPaths.length} photos',
        operation: 'Privacy Strip',
        mediaType: 'image',
        outputPaths: state.outputPaths,
        originalSize: state.originalSize,
        outputSize: state.strippedSize,
        detail: 'Metadata removed',
        createdAt: DateTime.now(),
      ),
    );
  }

  void _save(List<String> outputs) {
    AdService.showInterstitialAd(
      context,
      onAdDismissed: () async {
        try {
          await MediaSaveService.saveImagesToGallery(outputs);
          HapticFeedback.mediumImpact();
          if (mounted) {
            ToastUtils.show(
              context,
              outputs.length > 1
                  ? '${outputs.length} photos saved'
                  : 'Saved to gallery',
            );
          }
        } catch (e) {
          if (mounted) {
            ToastUtils.show(context, 'Could not save: $e', isError: true);
          }
        }
      },
    );
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

    return PrivacyReportView(
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
      onClose: () => context.go('/home'),
      // Every cleaned photo, not only the one on screen: the old screen
      // saved just the shown one when there was a single result and all of
      // them otherwise, which is the same rule.
      onSave: () => _save(outputs),
      onShare: () => MediaSaveService.shareFiles(outputs),
      onNew: () => context.go('/home'),
    );
  }
}
