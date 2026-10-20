import 'package:image_picker/image_picker.dart';

import '../../core/services/media_picker_service.dart';

const String kVideoAccessMessage = 'Allow access to your videos to take their sound';
const String kVideoPickFailedMessage = 'Your videos could not be opened';

/// One video from the gallery for Extract: its path, null when nothing was
/// picked, or — when the picker fails, a refused permission included — null
/// with one line through [onError]. The picker throws on a refusal, and an
/// error nothing catches is a tap that silently does nothing.
Future<String?> pickVideoPath(
  Future<XFile?> Function() pick, {
  required void Function(String message) onError,
}) async {
  try {
    return (await pick())?.path;
  } catch (e) {
    onError(
      MediaPickerService.isPermissionError(e) ? kVideoAccessMessage : kVideoPickFailedMessage,
    );
    return null;
  }
}
