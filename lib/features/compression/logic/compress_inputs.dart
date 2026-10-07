import 'package:image_picker/image_picker.dart';

/// The files a compress route was opened with: one (the home screen's
/// picker) or several (shared from another app). Anything else is none.
///
/// The files travel in the route, never only in the provider: each compress
/// screen resets the provider when it opens, so files put there beforehand
/// were wiped and the screen closed itself on finding none.
List<XFile> compressInputsFromExtra(Object? extra) => switch (extra) {
      final XFile file => [file],
      final List<XFile> files => files,
      _ => const <XFile>[],
    };
