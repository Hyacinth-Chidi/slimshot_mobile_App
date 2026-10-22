import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/slimshot_api.dart';
import '../account/providers/account_providers.dart';
import 'data/font_catalog_cache.dart';
import 'data/font_client.dart';
import 'data/font_library.dart';
import 'data/font_preview_cache.dart';
import 'font_service.dart';

/// Whether this build has a server to list fonts from — without one the
/// Font tab is the local fonts alone.
final fontServerConfiguredProvider = Provider<bool>((ref) => SlimshotApi.isConfigured);

/// The font catalogue, over the app's one server client.
final fontClientProvider = Provider<FontClient>(
  (ref) => FontClient(ref.watch(accountApiProvider)),
);

/// App-wide, not per sheet: a download started in one opening of the Font
/// tab is shared with the next rather than fetched twice.
final fontLibraryProvider = Provider<FontLibrary>((ref) => FontLibrary());

final fontCatalogCacheProvider = Provider<FontCatalogCache>((ref) => FontCatalogCache());

final fontPreviewCacheProvider = Provider<FontPreviewCache>((ref) => FontPreviewCache());

final fontServiceProvider = Provider<FontService>(
  (ref) => FontService(
    client: ref.watch(fontClientProvider),
    library: ref.watch(fontLibraryProvider),
    cache: ref.watch(fontCatalogCacheProvider),
  ),
);
