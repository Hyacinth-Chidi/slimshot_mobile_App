import 'package:image_picker/image_picker.dart';

class MediaPickerService {
  MediaPickerService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<List<XFile>> pickImages() {
    return _picker.pickMultiImage();
  }

  Future<XFile?> pickVideo() {
    return _picker.pickVideo(source: ImageSource.gallery);
  }

  static bool isPermissionError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('photo_access_denied') ||
        message.contains('permission_denied') ||
        message.contains('access_denied');
  }
}
