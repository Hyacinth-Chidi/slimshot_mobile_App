import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/models/history_item.dart';
import '../core/services/history_service.dart';
import '../core/services/media_save_service.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/file_utils.dart';
import '../core/utils/toast_utils.dart';
import '../core/widgets/responsive_layout.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<HistoryItem>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _itemsFuture = HistoryService.getItems();
  }

  void _reload() {
    setState(() {
      _itemsFuture = HistoryService.getItems();
    });
  }

  Future<void> _deleteItem(HistoryItem item) async {
    for (final path in item.outputPaths) {
      if (path.contains(FileUtils.filePrefix)) {
        await FileUtils.deleteFile(path);
      }
    }
    await HistoryService.removeItem(item.id);
    _reload();
    if (mounted) {
      ToastUtils.show(context, 'History item deleted');
    }
  }

  Future<void> _saveItem(HistoryItem item) async {
    try {
      if (item.mediaType == 'video') {
        await MediaSaveService.saveOptimizedMediaToGallery(item.outputPaths);
      } else {
        await MediaSaveService.saveImagesToGallery(item.outputPaths);
      }
      if (mounted) {
        ToastUtils.show(context, 'Saved to gallery');
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.show(context, 'Error saving: $e', isError: true);
      }
    }
  }

  Future<void> _shareItem(HistoryItem item) async {
    try {
      await MediaSaveService.shareFiles(item.outputPaths);
    } catch (e) {
      if (mounted) {
        ToastUtils.show(context, 'Error sharing: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ResponsiveCenter(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(
                          LucideIcons.arrowLeft,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'History',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: -0.2, end: 0),
              Expanded(
                child: FutureBuilder<List<HistoryItem>>(
                  future: _itemsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryStart,
                        ),
                      );
                    }

                    final items = snapshot.data ?? const [];
                    if (items.isEmpty) {
                      return _EmptyHistory(onGoHome: () => context.go('/home'));
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _HistoryCard(
                          item: item,
                          onSave: () => _saveItem(item),
                          onShare: () => _shareItem(item),
                          onDelete: () => _confirmDelete(item),
                        ).animate().fadeIn(delay: (80 * index).ms).slideY(
                              begin: 0.1,
                              end: 0,
                            );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(HistoryItem item) {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Output?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'This clears the history item and removes SlimShotAI temp outputs when available.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteItem(item);
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryItem item;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _HistoryCard({
    required this.item,
    required this.onSave,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final icon = item.mediaType == 'video' ? LucideIcons.video : LucideIcons.image;
    final savedLabel = item.savedSpace
        ? '${item.savedPercent.clamp(0, 99).toStringAsFixed(0)}% saved'
        : 'Larger output';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryStart.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primaryStart, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${item.operation} - ${_formatDate(item.createdAt)}',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(
                  LucideIcons.trash2,
                  color: AppColors.textTertiary,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _MiniStat(
                label: 'Before',
                value: FileUtils.formatFileSize(item.originalSize),
              ),
              _MiniStat(
                label: 'After',
                value: FileUtils.formatFileSize(item.outputSize),
              ),
              _MiniStat(
                label: 'Result',
                value: savedLabel,
                highlight: item.savedSpace,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.detail,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.download,
                  label: 'Save',
                  onTap: onSave,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.share2,
                  label: 'Share',
                  onTap: onShare,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _MiniStat({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: highlight ? AppColors.success : AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surfaceLight.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  final VoidCallback onGoHome;

  const _EmptyHistory({required this.onGoHome});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.primaryStart.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.history,
                color: AppColors.primaryStart,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No history yet',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Compressed, converted, and privacy-cleaned outputs will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 22),
            _ActionButton(
              icon: LucideIcons.home,
              label: 'Go Home',
              onTap: onGoHome,
            ),
          ],
        ),
      ),
    );
  }
}
