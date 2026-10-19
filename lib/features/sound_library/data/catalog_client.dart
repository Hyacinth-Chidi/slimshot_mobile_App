import 'package:http/http.dart' as http;

import '../../../core/services/slimshot_api.dart';
import 'catalog_models.dart';

/// The server's sound catalogue: pills, pages of sounds, and downloads.
///
/// Public — no sign-in — so every call goes out without a bearer. The kind is
/// `audio`; the root is a parameter, so music is the same client pointed at
/// `music`.
class CatalogClient {
  CatalogClient(this._api);

  final SlimshotApi _api;

  static const String _kind = 'audio';

  Uri _uri(String path, Map<String, String> query) =>
      _api.uri('/catalog$path').replace(queryParameters: query);

  /// The children of the top-level [root] category, in the dashboard's order.
  Future<List<CatalogCategory>> categories(String root) async {
    final envelope = await _api.sendPublicEnvelope(
      () => http.Request('GET', _uri('/categories', {'kind': _kind, 'root': root})),
    );
    return parseCategories(envelope.data);
  }

  /// One page of [category]'s sounds, its sub-categories included.
  Future<CatalogPage> sounds(
    String category, {
    String? cursor,
    int limit = 30,
  }) async {
    final envelope = await _api.sendPublicEnvelope(
      () => http.Request(
        'GET',
        _uri('/assets', {
          'kind': _kind,
          'category': category,
          'cursor': ?cursor,
          'limit': '$limit',
        }),
      ),
    );
    final next = envelope.meta['nextCursor'];
    return CatalogPage(parseSounds(envelope.data), next is String ? next : null);
  }

  /// Where to fetch sound [id] now. Counts as one download on the server.
  Future<DownloadTicket> download(String id) async {
    final envelope = await _api.sendPublicEnvelope(
      () => http.Request(
        'POST',
        _api.uri('/catalog/assets/${Uri.encodeComponent(id)}/download'),
      ),
    );
    final ticket = DownloadTicket.tryParse(envelope.data);
    if (ticket == null) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No download address.',
      );
    }
    return ticket;
  }
}

/// How long a rate-limited client must wait, when the server said.
int? retryAfterSeconds(SlimshotApiException e) => e.detailInt('retryAfterSeconds');
