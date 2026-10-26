import 'package:sg_domain/sg_domain.dart';
import 'package:syncgate/src/app/app_mode.dart';

/// Every route in the app (frontend plan §3.1).
abstract final class Routes {
  static const root = '/';

  static const setupLanguage = '/setup/language';
  static const setupLicence = '/setup/licence';
  static const setupShift = '/setup/shift';
  static const setupCamera = '/setup/camera';
  static const setupKiosk = '/setup/kiosk';
  static const setupOwner = '/setup/owner';
  static const setupFirstWorker = '/setup/first-worker';

  /// Setup steps in order; step n (1-based) is `setupSteps[n - 1]`.
  static const List<String> setupSteps = [
    setupLanguage,
    setupLicence,
    setupShift,
    setupCamera,
    setupKiosk,
    setupOwner,
    setupFirstWorker,
  ];

  static const gate = '/gate';
  static const manual = '/gate/manual';
  static const unlock = '/unlock';

  static const today = '/admin/today';
  static const workers = '/admin/workers';
  static const reports = '/admin/reports';
  static const settings = '/admin/settings';
  static const exceptions = '/admin/exceptions';

  static const enrolDetails = '/admin/workers/new/details';
  static const enrolNotice = '/admin/workers/new/notice';
  static const enrolFace = '/admin/workers/new/face';

  static const settingsBackup = '/admin/settings/backup';
  static const settingsPassphrase = '/admin/settings/backup/passphrase';
  static const settingsShifts = '/admin/settings/shifts';
  static const settingsUsers = '/admin/settings/users';
  static const settingsTally = '/admin/settings/tally';
  static const settingsLanguage = '/admin/settings/language';
  static const settingsGate = '/admin/settings/gate';
  static const settingsPrivacy = '/admin/settings/privacy';
  static const settingsAbout = '/admin/settings/about';

  static const reportsMuster = '/admin/reports/muster';

  static String worker(String id) => '/admin/workers/$id';

  /// Where each mode starts.
  static String homeFor(AppMode mode) => switch (mode) {
    SetupMode(:final step) => setupSteps[step.clamp(1, setupStepCount) - 1],
    GateMode() => gate,
    AdminMode() => today,
  };
}

/// Pure redirect rules, driven by the mode (frontend plan §3.1). Returns the
/// location to go to, or `null` to stay.
String? redirectFor(AppMode mode, String location) {
  switch (mode) {
    case SetupMode(:final step):
      final index = Routes.setupSteps.indexOf(location);
      // Only steps up to the current one are reachable.
      if (index < 0 || index > step - 1) return Routes.homeFor(mode);
      return null;
    case GateMode():
      const allowed = {Routes.gate, Routes.manual, Routes.unlock};
      return allowed.contains(location) ? null : Routes.gate;
    case AdminMode(:final role):
      if (role == Role.gateOperator) {
        const allowed = {Routes.today, Routes.manual};
        return allowed.contains(location) ? null : Routes.today;
      }
      if (location == Routes.manual) return null;
      if (!location.startsWith('/admin/')) return Routes.today;
      final needsOwner =
          location.startsWith(Routes.settingsBackup) ||
          location.startsWith(Routes.settingsUsers);
      if (needsOwner && !role.can(Capability.backupRestore)) {
        return Routes.settings;
      }
      return null;
  }
}
