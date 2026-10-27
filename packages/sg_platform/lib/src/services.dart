/// Time source, so tests and the demo can control "now".
abstract interface class ClockService {
  DateTime now();
}

/// Short sounds the gate plays.
enum Earcon { success, failure }

/// Pre-recorded phrases (ADR-0016). The clip is chosen by phrase + language.
enum Phrase { markedIn, markedOut, notRecognised, alreadyMarked }

abstract interface class VoiceService {
  Future<void> playEarcon(Earcon earcon);
  Future<void> playPhrase(Phrase phrase, String languageCode);

  /// Speaks a worker's name with text-to-speech.
  Future<void> speakName(String name, String languageCode);

  /// Reads the privacy notice aloud (design 13).
  Future<void> readNotice(String text, String languageCode);
}

/// What the phone can do, for the "This device" card (design 06).
final class DeviceInfo {
  const new({
    required this.cameraMegapixels,
    required this.memoryGb,
    required this.systemName,
  });

  final int cameraMegapixels;
  final int memoryGb;
  final String systemName;

  bool get cameraOk => cameraMegapixels >= 5;
  bool get memoryOk => memoryGb >= 3;
  bool get ready => cameraOk && memoryOk;
}

abstract interface class DeviceCheckService {
  Future<DeviceInfo> check();
}

/// Keeps the screen on at the gate and dims it when nobody is in view
/// (ADR-0018).
abstract interface class ScreenService {
  Future<void> setKeepAwake({required bool enabled});
  Future<void> setDimmed({required bool dimmed});
}

abstract interface class ShareService {
  /// Opens the OS share sheet for the file at [path].
  Future<void> shareFile(String path, {String? text});
}

enum BiometricKind { none, fingerprint, face }

/// OS biometrics (`local_auth`). SyncGate never stores biometric data.
abstract interface class BiometricService {
  Future<BiometricKind> availableKind();
  Future<bool> authenticate({required String reason});
}

/// Reads a QR code with the camera (the licence step's "Scan QR on invoice").
/// Open question P-1: `mobile_scanner` or the native vision camera.
abstract interface class QrScanService {
  /// Returns the scanned text, or `null` if the user cancelled.
  Future<String?> scan();
}
