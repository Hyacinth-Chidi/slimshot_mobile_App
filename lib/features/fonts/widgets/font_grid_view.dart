import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../../core/utils/toast_utils.dart';
import '../font_grid.dart';
import '../providers.dart';

/// The text editor's Font tab: a search field over one grid — System, the
/// bundled fonts, then the server's Trending and More fonts.
///
/// A tap on a font on the phone applies it at once; a tap on one that is
/// not downloads it (a ring on the tile) and applies it when it lands,
/// unless another font was chosen meanwhile. Pull down to fetch the lists
/// again.
class FontGridView extends ConsumerStatefulWidget {
  const FontGridView({
    super.key,
    required this.selectedName,
    required this.onSelected,
  });

  /// The font the text wears now, as it stores it.
  final String selectedName;
  final ValueChanged<String> onSelected;

  @override
  ConsumerState<FontGridView> createState() => _FontGridViewState();
}

class _FontGridViewState extends ConsumerState<FontGridView> {
  static const double _kEdge = 16;
  static const double _kGap = 8;

  late final FontGridController _controller;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = FontGridController(
      service: ref.read(fontServiceProvider),
      client: ref.read(fontClientProvider),
      cache: ref.read(fontCatalogCacheProvider),
      library: ref.read(fontLibraryProvider),
      previews: ref.read(fontPreviewCacheProvider),
      serverConfigured: ref.read(fontServerConfiguredProvider),
    )..addListener(_changed);
    _controller.open();
  }

  void _changed() {
    if (!mounted) return;
    final notice = _controller.takeNotice();
    if (notice != null) ToastUtils.show(context, notice, isError: true);
    setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _controller.entries;
    return Column(
      children: [
        _searchField(),
        const SizedBox(height: 10),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _controller.refresh,
            color: AppColors.primaryStart,
            backgroundColor: AppColors.surface,
            child: GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(_kEdge, 0, _kEdge, _kEdge),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.6,
                crossAxisSpacing: _kGap,
                mainAxisSpacing: _kGap,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) => _tile(entries[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _searchField() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kEdge),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(LucideIcons.search, color: AppColors.textSecondary, size: 18),
              ),
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (value) => _controller.query = value,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _tile(FontEntry entry) {
    final selected = entry.name.toLowerCase() == widget.selectedName.toLowerCase();
    final state = _controller.stateOf(entry);
    return GestureDetector(
      key: ValueKey('font:${entry.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _controller.choose(entry, widget.onSelected),
      child: Container(
        key: const ValueKey('font-tile-box'),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primaryStart : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Center(child: _face(entry)),
              ),
            ),
            if (_badge(state) case final badge?)
              Positioned(top: 4, left: 4, child: badge),
          ],
        ),
      ),
    );
  }

  /// What the tile shows of the font itself.
  Widget _face(FontEntry entry) {
    switch (entry.source) {
      case FontSource.system:
        return const Text(
          'SYSTEM',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
          ),
        );
      case FontSource.bundled:
        return _label(entry.label, fontFamily: entry.name);
      case FontSource.server:
        final url = entry.font?.previewUrl;
        final file = url == null ? null : _controller.previews.fileFor(url);
        if (file == null) return _label(entry.label);
        return LayoutBuilder(
          builder: (context, constraints) => Image.file(
            file,
            cacheWidth: (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).round(),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _label(entry.label),
          ),
        );
    }
  }

  Widget _label(String text, {String? fontFamily}) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontFamily: fontFamily,
        ),
      );

  /// The corner mark: an arrow for a font not on the phone, a ring while
  /// it downloads.
  Widget? _badge(FontTileState state) => switch (state) {
        FontNotOnPhone() || FontFailed() =>
          const Icon(LucideIcons.download, color: AppColors.textSecondary, size: 12),
        FontDownloading(:final progress) => SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(
              value: progress <= 0 ? null : progress,
              strokeWidth: 1.5,
              color: AppColors.primaryStart,
              backgroundColor: AppColors.border,
            ),
          ),
        FontReady() => null,
      };
}
