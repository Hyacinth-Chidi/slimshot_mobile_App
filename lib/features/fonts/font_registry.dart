import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'data/font_library.dart';
import 'font_names.dart';

/// Hands font files to Flutter's text engine, under the names texts use.
///
/// A family registered in a session cannot be replaced in it, so a name is
/// registered once; a newer version of a font on the phone is used from the
/// next app start. Registering is reading a local file — milliseconds — and
/// never throws: a file the engine refuses leaves its texts in the System
/// font, and the next request tries again.
class FontRegistry {
  FontRegistry({Future<void> Function(Uint8List bytes, String name)? loader})
      : _loader = loader ?? _loadIntoEngine;

  /// The app's one registry: what the painters listen to.
  static final FontRegistry instance = FontRegistry();

  final Future<void> Function(Uint8List bytes, String name) _loader;
  final Set<String> _registered = {};
  final Map<String, Future<bool>> _inFlight = {};
  final ChangeNotifier _changes = ChangeNotifier();

  /// Notifies after each new registration, so anything that lays text out
  /// itself (a painter, a preview tile) measures again in the real font.
  Listenable get changes => _changes;

  /// Whether text in [name] draws in its own font now: System, a bundled
  /// font, or one registered this session.
  bool isAvailable(String name) => isLocalFontName(name) || _registered.contains(name);

  /// Registers the font file at [path] under [name]. True when [name] is
  /// available afterwards.
  Future<bool> registerFile(String name, String path) {
    if (isAvailable(name)) return Future.value(true);
    // A block body: an arrow would hand `whenComplete` this very future.
    return _inFlight[name] ??= _register(name, path).whenComplete(() {
      _inFlight.remove(name);
    });
  }

  Future<bool> _register(String name, String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      await _loader(await file.readAsBytes(), name);
    } catch (_) {
      return false;
    }
    _registered.add(name);
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    _changes.notifyListeners();
    return true;
  }

  static Future<void> _loadIntoEngine(Uint8List bytes, String name) =>
      ui.loadFontFromList(bytes, fontFamily: name);
}

/// Registers every font in [names] that is on the phone and not yet
/// registered — what a project opening and an export starting both need.
Future<void> registerFontsOnPhone(
  Iterable<String> names, {
  FontLibrary? library,
  FontRegistry? registry,
}) async {
  final fonts = registry ?? FontRegistry.instance;
  final wanted = {for (final name in names) if (!fonts.isAvailable(name)) name};
  if (wanted.isEmpty) return;
  final files = library ?? FontLibrary();
  await files.load();
  for (final name in wanted) {
    final entry = files.find(name);
    if (entry != null) await fonts.registerFile(name, entry.filePath);
  }
}
