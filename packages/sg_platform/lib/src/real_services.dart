import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sg_platform/src/kiosk_service.dart';
import 'package:sg_platform/src/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// The method channel implemented by `MainActivity.kt` for the things Flutter
/// has no plugin for: screen pinning and a hardware check.
const MethodChannel _channel = MethodChannel('in.syncgate.app/platform');

/// Opens the OS share sheet for a file (an export or a backup).
class SharePlusShareService implements ShareService {
  const new();

  @override
  Future<void> shareFile(String path, {String? text}) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: text),
    );
  }
}

/// Keeps the gate screen on. Dimming needs a brightness plugin and is not
/// done yet; the call is accepted and ignored.
class WakelockScreenService implements ScreenService {
  const new();

  @override
  Future<void> setKeepAwake({required bool enabled}) =>
      WakelockPlus.toggle(enable: enabled);

  @override
  Future<void> setDimmed({required bool dimmed}) async {}
}

/// Speaks worker names and notices with the phone's text-to-speech voice, and
/// plays the system alert sounds for success and failure. Recorded Hindi clips
/// (ADR-0016) are not bundled yet, so phrases are spoken too.
class TtsVoiceService implements VoiceService {
  new() : _tts = FlutterTts();

  final FlutterTts _tts;

  static const Map<String, String> _locales = {
    'en': 'en-IN',
    'hi': 'hi-IN',
    'gu': 'gu-IN',
    'ta': 'ta-IN',
    'pa': 'pa-IN',
    'mr': 'mr-IN',
  };

  static const Map<String, Map<Phrase, String>> _phrases = {
    'en': {
      Phrase.markedIn: 'Marked in',
      Phrase.markedOut: 'Marked out',
      Phrase.notRecognised: 'Not recognised',
      Phrase.alreadyMarked: 'Already marked',
    },
    'hi': {
      Phrase.markedIn: 'अंदर दर्ज',
      Phrase.markedOut: 'बाहर दर्ज',
      Phrase.notRecognised: 'पहचान नहीं हुई',
      Phrase.alreadyMarked: 'पहले ही दर्ज है',
    },
  };

  @override
  Future<void> playEarcon(Earcon earcon) => SystemSound.play(
    earcon == Earcon.success ? SystemSoundType.click : SystemSoundType.alert,
  );

  @override
  Future<void> playPhrase(Phrase phrase, String languageCode) {
    final text =
        (_phrases[languageCode] ?? _phrases['en']!)[phrase] ?? phrase.name;
    return _speak(text, languageCode);
  }

  @override
  Future<void> speakName(String name, String languageCode) =>
      _speak(name, languageCode);

  @override
  Future<void> readNotice(String text, String languageCode) =>
      _speak(text, languageCode);

  Future<void> _speak(String text, String languageCode) async {
    try {
      await _tts.setLanguage(_locales[languageCode] ?? 'en-IN');
      await _tts.speak(text);
    } on Exception catch (e) {
      // A phone without a voice for this language stays silent; never crash
      // the gate for a missing voice.
      debugPrint('Text-to-speech unavailable: $e');
    }
  }
}

/// Fingerprint / face unlock for Admin, on top of the PIN.
class LocalAuthBiometricService implements BiometricService {
  new() : _auth = LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<BiometricKind> availableKind() async {
    try {
      if (!await _auth.isDeviceSupported()) return BiometricKind.none;
      final kinds = await _auth.getAvailableBiometrics();
      if (kinds.contains(BiometricType.face)) return BiometricKind.face;
      if (kinds.contains(BiometricType.fingerprint) ||
          kinds.contains(BiometricType.strong) ||
          kinds.contains(BiometricType.weak)) {
        return BiometricKind.fingerprint;
      }
      return BiometricKind.none;
    } on Exception {
      return BiometricKind.none;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } on Exception {
      return false;
    }
  }
}

/// Android screen pinning (lock task mode) through `MainActivity.kt`.
class AndroidKioskService implements KioskService {
  const new();

  @override
  Stream<KioskState> get state async* {
    while (true) {
      yield await _read();
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<KioskState> _read() async {
    try {
      final pinned = await _channel.invokeMethod<bool>('isPinned');
      return (pinned ?? false) ? KioskState.locked : KioskState.unlocked;
    } on PlatformException {
      return KioskState.unknown;
    } on MissingPluginException {
      return KioskState.unknown;
    }
  }

  @override
  Future<void> startPinning() => _channel.invokeMethod<void>('startPinning');

  @override
  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');
}

/// Reads the front camera resolution, memory and Android version through
/// `MainActivity.kt` (ADR-0019 minimum: 5 MP, 3 GB).
class AndroidDeviceCheckService implements DeviceCheckService {
  const new();

  @override
  Future<DeviceInfo> check() async {
    final map = await _channel.invokeMapMethod<String, Object?>('deviceInfo');
    return DeviceInfo(
      cameraMegapixels: (map?['cameraMegapixels'] as num?)?.round() ?? 0,
      memoryGb: (map?['memoryGb'] as num?)?.round() ?? 0,
      systemName: (map?['system'] as String?) ?? 'Android',
    );
  }
}

/// The system file chooser (Android Storage Access Framework).
class SystemFilePickService implements FilePickService {
  const new();

  @override
  Future<PickedFile?> pickFile() async {
    final picked = await FilePicker.pickFile(dialogTitle: 'SyncGate backup');
    if (picked == null) return null;
    final bytes = await picked.xFile.readAsBytes();
    return PickedFile(name: picked.name, bytes: bytes);
  }
}
