import 'dart:io';
import 'dart:typed_data';

/// How much of each end of a file is compared.
const int _kProbeBytes = 64 * 1024;

/// Whether [a] and [b] hold the same file.
///
/// The gallery hands back a fresh copy of a video on every pick, often under
/// a new name, so the path cannot say "the same video again". The length and
/// the first and last 64 KB can: a video's header and its index differ from
/// any other's, so two different videos agreeing on all three does not happen
/// in practice — and reading them costs nothing next to taking the sound out
/// again. A file that cannot be read is not the same as anything.
Future<bool> isSameFile(String a, String b) async {
  if (a == b) return true;
  try {
    final fileA = File(a);
    final fileB = File(b);
    final length = await fileA.length();
    if (length != await fileB.length()) return false;
    if (length <= _kProbeBytes * 2) {
      return _equal(await fileA.readAsBytes(), await fileB.readAsBytes());
    }
    for (final offset in [0, length - _kProbeBytes]) {
      if (!_equal(await _read(fileA, offset), await _read(fileB, offset))) {
        return false;
      }
    }
    return true;
  } on FileSystemException {
    return false;
  }
}

Future<Uint8List> _read(File file, int offset) async {
  final handle = await file.open();
  try {
    await handle.setPosition(offset);
    return await handle.read(_kProbeBytes);
  } finally {
    await handle.close();
  }
}

bool _equal(List<int> x, List<int> y) {
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
