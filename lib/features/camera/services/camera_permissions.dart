import 'package:permission_handler/permission_handler.dart';

/// Whether the camera may be used: allowed, refused (it can be asked
/// again), or refused for good (only the phone's settings can change it).
enum CameraAccess { granted, denied, blocked }

/// The phone's permission prompts as the camera screen needs them. The real
/// one is [PluginCameraPermissions]; widget tests answer for the user.
abstract class CameraPermissions {
  /// Asks where the phone still can, and says where things stand.
  Future<CameraAccess> requestCamera();

  /// Where things stand, without asking: read again when the user comes
  /// back from the phone's settings.
  Future<CameraAccess> cameraStatus();

  /// The microphone for a video's sound, asked at most once a screen: a
  /// second prompt in a row at the shutter is one too many. False records
  /// silently.
  Future<bool> allowMicrophone();

  /// Storage access, which Android 10 and older need for the camera to save
  /// into the gallery; asked at most once a screen, like the microphone.
  /// False keeps shots in SlimShot's own folder.
  Future<bool> allowStorage();

  Future<void> openSettings();
}

/// A prompt that cannot be shown reads as not allowed: the screen then says
/// access is off, rather than failing where nobody sees it.
class PluginCameraPermissions implements CameraPermissions {
  bool _micAsked = false;
  bool _storageAsked = false;

  @override
  Future<CameraAccess> requestCamera() async {
    try {
      return _accessFrom(await Permission.camera.request());
    } catch (_) {
      return CameraAccess.denied;
    }
  }

  @override
  Future<CameraAccess> cameraStatus() async {
    try {
      return _accessFrom(await Permission.camera.status);
    } catch (_) {
      return CameraAccess.denied;
    }
  }

  @override
  Future<bool> allowMicrophone() async {
    try {
      if (await Permission.microphone.isGranted) return true;
      if (_micAsked) return false;
      _micAsked = true;
      return (await Permission.microphone.request()).isGranted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> allowStorage() async {
    try {
      if (await Permission.storage.isGranted) return true;
      if (_storageAsked) return false;
      _storageAsked = true;
      return (await Permission.storage.request()).isGranted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await openAppSettings();
    } catch (_) {
      // No settings to open here.
    }
  }

  CameraAccess _accessFrom(PermissionStatus status) {
    if (status.isGranted || status.isLimited) return CameraAccess.granted;
    if (status.isPermanentlyDenied || status.isRestricted) return CameraAccess.blocked;
    return CameraAccess.denied;
  }
}
