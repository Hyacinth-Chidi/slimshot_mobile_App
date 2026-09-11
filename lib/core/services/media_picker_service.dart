import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

class MediaPickerService {
  MediaPickerService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Switches Android over to the system **Photo Picker** — the gallery sheet
  /// that slides up over the app.
  ///
  /// Without this, `image_picker` falls back to an `ACTION_GET_CONTENT` intent.
  /// For a single video that usually lands in the gallery app and looks fine,
  /// but a multi-select across mixed photo *and* video types is handled by the
  /// Documents UI, which throws the user out into the Files app. Same plugin,
  /// completely different experience.
  ///
  /// Android 13+ uses the Photo Picker by default; 12 and below need this
  /// opt-in, which is backported through Google Play services.
  ///
  /// Call once during startup, before anything picks.
  static void enableAndroidPhotoPicker() {
    final implementation = ImagePickerPlatform.instance;
    if (implementation is ImagePickerAndroid) {
      implementation.useAndroidPhotoPicker = true;
    }
  }

  Future<List<XFile>> pickImages() {
    return _picker.pickMultiImage();
  }

  Future<XFile?> pickVideo() {
    return _picker.pickVideo(source: ImageSource.gallery);
  }

  /// Opens the gallery for photos **and** videos together, allowing several.
  ///
  /// This is the picker the editor uses both to start a project and to add to
  /// one, so importing behaves the same way everywhere — including how
  /// permission refusals surface through [isPermissionError].
  ///
  /// Files come back in selection order, which becomes clip order.
  Future<List<XFile>> pickMedia() {
    return _picker.pickMultipleMedia();
  }

  static bool isPermissionError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('photo_access_denied') ||
        message.contains('permission_denied') ||
        message.contains('access_denied');
  }
}
