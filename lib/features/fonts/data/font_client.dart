import 'package:http/http.dart' as http;

import '../../../core/services/slimshot_api.dart';
import 'font_models.dart';

/// The server's font catalogue: the lists, one font by id or by family, and
/// downloads. Public — no sign-in — so every call goes out without a bearer.
class FontClient {
  FontClient(this._api);

  final SlimshotApi _api;

  /// Every published font, in the owner's order. One list, no paging, no
  /// categories: a font the owner publishes is listed.
  Future<List<ServerFont>> list() async {
    final envelope = await _api.sendPublicEnvelope(
      () => http.Request('GET', _api.uri('/catalog/fonts')),
    );
    return parseServerFonts(envelope.data);
  }

  /// Any published font, listed or not.
  Future<ServerFont> byId(String id) async {
    final envelope = await _api.sendPublicEnvelope(
      () => http.Request('GET', _api.uri('/catalog/fonts/${Uri.encodeComponent(id)}')),
    );
    return _font(envelope.data);
  }

  /// The published Regular face of [familyName], spelled exactly.
  Future<ServerFont> byFamily(String familyName) async {
    final envelope = await _api.sendPublicEnvelope(
      () => http.Request(
        'GET',
        _api.uri('/catalog/fonts/by-family/${Uri.encodeComponent(familyName)}'),
      ),
    );
    return _font(envelope.data);
  }

  /// Where to fetch font [id] now. Counts as one download on the server.
  Future<FontDownloadTicket> download(String id) async {
    final envelope = await _api.sendPublicEnvelope(
      () => http.Request(
        'POST',
        _api.uri('/catalog/assets/${Uri.encodeComponent(id)}/download'),
      ),
    );
    final ticket = FontDownloadTicket.tryParse(envelope.data);
    if (ticket == null) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No download address.',
      );
    }
    return ticket;
  }

  static ServerFont _font(Object? data) {
    final font = ServerFont.tryParse(data);
    if (font == null) {
      throw const SlimshotApiException(SlimshotApiException.badResponse, 'Not a font.');
    }
    return font;
  }
}
