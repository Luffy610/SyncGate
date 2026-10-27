import 'package:meta/meta.dart';
import 'package:sg_domain/src/entities.dart';
import 'package:sg_domain/src/failures.dart';
import 'package:sg_domain/src/result.dart';

/// Where the app is (ADR-0004 §1). Persisted so it survives a restart.
enum AppModeKind { setup, gate, admin }

/// Settings stored on the phone (a key-value table in the real data layer).
@immutable
class AppSettings {
  const new({
    this.mode = AppModeKind.setup,
    this.setupStep = 1,
    this.language = AppLanguage.en,
    this.idleMinutes = 2,
    this.cooldownSeconds = 120,
    this.voiceVolume = 0.8,
    this.screenFillLight = true,
    this.use24HourClock = false,
    this.remindBackupDays = 7,
    this.autoBackup = true,
    this.gateOperatorId = 'G-02',
    this.biometricEnabled = true,
    this.backupPassphraseSet = false,
  });

  final AppModeKind mode;

  /// Last completed setup step (1-based), so a crash resumes correctly.
  final int setupStep;
  final AppLanguage language;
  final int idleMinutes;
  final int cooldownSeconds;
  final double voiceVolume;
  final bool screenFillLight;
  final bool use24HourClock;
  final int remindBackupDays;
  final bool autoBackup;
  final String gateOperatorId;
  final bool biometricEnabled;

  /// Whether the owner has set the passphrase that locks backups.
  final bool backupPassphraseSet;

  AppSettings copyWith({
    AppModeKind? mode,
    int? setupStep,
    AppLanguage? language,
    int? idleMinutes,
    int? cooldownSeconds,
    double? voiceVolume,
    bool? screenFillLight,
    bool? use24HourClock,
    int? remindBackupDays,
    bool? autoBackup,
    String? gateOperatorId,
    bool? biometricEnabled,
    bool? backupPassphraseSet,
  }) => AppSettings(
    mode: mode ?? this.mode,
    setupStep: setupStep ?? this.setupStep,
    language: language ?? this.language,
    idleMinutes: idleMinutes ?? this.idleMinutes,
    cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
    voiceVolume: voiceVolume ?? this.voiceVolume,
    screenFillLight: screenFillLight ?? this.screenFillLight,
    use24HourClock: use24HourClock ?? this.use24HourClock,
    remindBackupDays: remindBackupDays ?? this.remindBackupDays,
    autoBackup: autoBackup ?? this.autoBackup,
    gateOperatorId: gateOperatorId ?? this.gateOperatorId,
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    backupPassphraseSet: backupPassphraseSet ?? this.backupPassphraseSet,
  );
}

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Stream<AppSettings> watch();
  Future<void> save(AppSettings settings);
}

abstract interface class WorkerRepository {
  Stream<List<Worker>> watchAll();
  Future<List<Worker>> all();
  Future<Worker?> byId(String id);

  /// The next free worker code, e.g. `W-0126`.
  Future<String> nextCode();
  Future<bool> isCodeUnique(String code, {String? exceptWorkerId});
  Future<Worker> add(NewWorker worker);
  Future<void> update(Worker worker);
  Future<void> setFaceStatus(String workerId, FaceStatus status);
  Future<void> setActive(String workerId, {required bool active});
  Future<void> delete(String workerId);
  Future<List<String>> departments();
  Future<void> addDepartment(String name);
  Future<List<String>> contractors();
}

abstract interface class AttendanceRepository {
  Stream<List<AttendanceEvent>> watchDay(DateTime day);
  Future<List<AttendanceEvent>> eventsBetween(DateTime from, DateTime to);

  /// The most recent event for [workerId], or `null`.
  Future<AttendanceEvent?> lastEvent(String workerId);

  /// Appends one event. The gate shows confirmation only after this returns
  /// (NFR-REL-02).
  Future<void> append(AttendanceEvent event);
}

abstract interface class ExceptionRepository {
  Stream<List<ExceptionRecord>> watchAll();
  Future<List<ExceptionRecord>> all();
  Future<void> add(ExceptionRecord record);
  Future<void> resolve(String id);
}

abstract interface class ShiftRepository {
  Stream<List<Shift>> watch();
  Future<List<Shift>> all();
  Future<void> save(Shift shift);
}

abstract interface class UserRepository {
  Future<bool> hasOwner();

  /// Creates the owner with [pin] and returns the one-time recovery code.
  Future<String> createOwner(String pin);
  Future<Result<AppUser, Failure>> verifyPin(Role role, String pin);
  Future<Result<void, Failure>> resetOwnerPin({
    required String recoveryCode,
    required String newPin,
  });
  Future<List<AppUser>> users();
  Future<void> setPin(String userId, String pin);
}

abstract interface class ConsentRepository {
  Future<void> record({
    required String workerId,
    required String noticeVersion,
    required AppLanguage language,
    required String adminId,
  });
  Future<bool> hasConsent(String workerId);
}

abstract interface class AuditLog {
  Future<void> append(AuditEntry entry);
  Stream<List<AuditEntry>> watch();
}

abstract interface class ReportService {
  Future<List<MusterRow>> monthly(ReportFilter filter);
  Future<List<DailyRow>> daily(DateTime day);

  /// Working days in the month for the muster header.
  int workingDays(DateTime month);
}

abstract interface class ExportService {
  /// Builds the file and returns where it is saved. Runs off the UI thread
  /// in the real implementation.
  Future<Result<ExportResult, Failure>> export(
    ExportFormat format,
    ReportFilter filter,
  );

  /// Workers matched to Tally employees (design 16 caption).
  Future<({int matched, int total})> tallyMatch();
}

abstract interface class BackupService {
  Stream<BackupInfo> watch();
  Future<BackupInfo> current();
  Future<Result<BackupInfo, Failure>> backupNow();
}

abstract interface class LicenceService {
  Stream<LicenceStatus> watch();
  Future<LicenceStatus> current();
  Future<Result<LicenceStatus, Failure>> activate(String key);
  Future<LicenceStatus> startTrial();
}

/// Which Tally Prime employee each worker is matched to (design 16).
abstract interface class TallyMappingRepository {
  /// Worker ID → Tally employee name, for matched workers only.
  Stream<Map<String, String>> watch();
  Future<Map<String, String>> all();
  Future<void> set(String workerId, String tallyName);
}
