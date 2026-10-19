import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/providers/account_providers.dart';
import 'data/catalog_cache.dart';
import 'data/catalog_client.dart';
import 'data/sound_library.dart';

/// The catalogue, over the app's one server client.
final catalogClientProvider = Provider<CatalogClient>(
  (ref) => CatalogClient(ref.watch(accountApiProvider)),
);

/// App-wide, not per sheet: a download started in one opening of the sheet
/// is shared with the next rather than fetched twice.
final soundLibraryProvider = Provider<SoundLibrary>((ref) => SoundLibrary());

/// One cache per library root, so music and effects keep their own pills.
final catalogCacheProvider = Provider.family<CatalogCache, String>(
  (ref, library) => CatalogCache(library: library),
);
