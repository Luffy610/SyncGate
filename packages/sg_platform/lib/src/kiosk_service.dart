/// Whether the OS is holding the phone in SyncGate (ADR-0004 §4).
enum KioskState {
  /// Android app pinning or iOS Guided Access is on.
  locked,

  /// Kiosk lock is off; the gate shows a warning.
  unlocked,

  /// The device can't report its kiosk state.
  unknown,
}

/// Android app pinning / iOS Guided Access.
abstract interface class KioskService {
  Stream<KioskState> get state;

  /// Android: starts app pinning (the OS asks the user to confirm).
  /// iOS: no-op; Guided Access is started by the user.
  Future<void> startPinning();

  /// Opens the OS settings page where pinning / Guided Access is enabled.
  Future<void> openSettings();
}
