import 'package:meta/meta.dart';

/// Admin roles (ADR-0004 §2).
enum Role { owner, admin, gateOperator }

/// What a role may do. One table, used by the router and to hide buttons.
enum Capability {
  exitGate,
  manualEntry,
  enrolWorkers,
  deleteWorker,
  corrections,
  reportsAndExports,
  backupRestore,
  licenceAndUsers,
  shiftRules,
}

extension RoleCapabilities on Role {
  bool can(Capability capability) => switch (capability) {
    Capability.exitGate || Capability.manualEntry => true,
    Capability.enrolWorkers ||
    Capability.corrections ||
    Capability.reportsAndExports ||
    Capability.shiftRules => this != Role.gateOperator,
    Capability.deleteWorker ||
    Capability.backupRestore ||
    Capability.licenceAndUsers => this == Role.owner,
  };
}

/// Direction of an attendance mark.
enum Direction { checkIn, checkOut }

/// How a mark was made. Manual marks are flagged in reports.
enum MarkMethod { face, manual, correction }

/// Whether a worker has a face code on this phone.
enum FaceStatus { enrolled, needsFace }

/// Languages the app can show (ADR-0016). Only [en] and [hi] ship strings in
/// this milestone.
enum AppLanguage {
  en('en', 'English', 'English'),
  hi('hi', 'हिन्दी', 'Hindi'),
  gu('gu', 'ગુજરાતી', 'Gujarati · Surat'),
  ta('ta', 'தமிழ்', 'Tamil · Tirupur'),
  pa('pa', 'ਪੰਜਾਬੀ', 'Punjabi · Ludhiana'),
  mr('mr', 'मराठी', 'Marathi · Pune');

  new(this.code, this.nativeName, this.englishName);

  final String code;
  final String nativeName;
  final String englishName;

  /// Whether strings exist for this language yet (decision FE-3: others are
  /// shown as "coming soon").
  bool get isAvailable => this == en || this == hi;

  static AppLanguage fromCode(String code) =>
      values.firstWhere((l) => l.code == code, orElse: () => en);
}

/// A shift window. Times are minutes since midnight; [endMinute] may be less
/// than [startMinute] when the shift crosses midnight.
@immutable
class Shift {
  const new({
    required this.id,
    required this.name,
    required this.startMinute,
    required this.endMinute,
    this.graceMinutes = 10,
    this.weeklyOff = DateTime.sunday,
  });

  final String id;
  final String name;
  final int startMinute;
  final int endMinute;
  final int graceMinutes;
  final int weeklyOff;

  bool get crossesMidnight => endMinute <= startMinute;

  /// Minute of the day after which an IN counts as late.
  int get lateAfterMinute => (startMinute + graceMinutes) % (24 * 60);

  /// True while [now] is inside the window, allowing [earlyMinutes] before
  /// the start for early arrivals.
  bool isRunningAt(DateTime now, {int earlyMinutes = 60}) {
    final minute = now.hour * 60 + now.minute;
    final from = startMinute - earlyMinutes;
    if (crossesMidnight) {
      return minute >= from || minute < endMinute;
    }
    return minute >= from && minute < endMinute;
  }

  Shift copyWith({
    String? name,
    int? startMinute,
    int? endMinute,
    int? graceMinutes,
    int? weeklyOff,
  }) => Shift(
    id: id,
    name: name ?? this.name,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
    graceMinutes: graceMinutes ?? this.graceMinutes,
    weeklyOff: weeklyOff ?? this.weeklyOff,
  );

  @override
  bool operator ==(Object other) =>
      other is Shift &&
      other.id == id &&
      other.name == name &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute &&
      other.graceMinutes == graceMinutes &&
      other.weeklyOff == weeklyOff;

  @override
  int get hashCode =>
      Object.hash(id, name, startMinute, endMinute, graceMinutes, weeklyOff);
}

@immutable
class Worker {
  const new({
    required this.id,
    required this.code,
    required this.name,
    required this.dateOfBirth,
    required this.department,
    required this.designation,
    required this.shiftId,
    this.contractor,
    this.phone,
    this.language = AppLanguage.hi,
    this.faceStatus = FaceStatus.needsFace,
    this.active = true,
    this.onLeave = false,
  });

  final String id;

  /// Human code shown in the UI, e.g. `W-0125`.
  final String code;
  final String name;
  final DateTime dateOfBirth;
  final String department;
  final String designation;
  final String shiftId;
  final String? contractor;
  final String? phone;
  final AppLanguage language;
  final FaceStatus faceStatus;
  final bool active;
  final bool onLeave;

  /// First name, for greetings and voice prompts.
  String get firstName => name.split(' ').first;

  Worker copyWith({
    String? code,
    String? name,
    DateTime? dateOfBirth,
    String? department,
    String? designation,
    String? shiftId,
    String? contractor,
    String? phone,
    AppLanguage? language,
    FaceStatus? faceStatus,
    bool? active,
    bool? onLeave,
  }) => Worker(
    id: id,
    code: code ?? this.code,
    name: name ?? this.name,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    department: department ?? this.department,
    designation: designation ?? this.designation,
    shiftId: shiftId ?? this.shiftId,
    contractor: contractor ?? this.contractor,
    phone: phone ?? this.phone,
    language: language ?? this.language,
    faceStatus: faceStatus ?? this.faceStatus,
    active: active ?? this.active,
    onLeave: onLeave ?? this.onLeave,
  );
}

/// Details entered in the enrolment form (before the worker has an ID).
@immutable
class NewWorker {
  const new({
    required this.code,
    required this.name,
    required this.dateOfBirth,
    required this.department,
    required this.designation,
    required this.shiftId,
    required this.language,
    this.contractor,
    this.phone,
  });

  final String code;
  final String name;
  final DateTime dateOfBirth;
  final String department;
  final String designation;
  final String shiftId;
  final AppLanguage language;
  final String? contractor;
  final String? phone;
}

/// One attendance mark. Events are append-only (ADR-0011); corrections add a
/// new event with [MarkMethod.correction] instead of editing.
@immutable
class AttendanceEvent {
  const new({
    required this.id,
    required this.workerId,
    required this.at,
    required this.direction,
    required this.method,
    this.reason,
    this.markedBy,
    this.onTime = true,
  });

  final String id;
  final String workerId;
  final DateTime at;
  final Direction direction;
  final MarkMethod method;

  /// Required for manual and correction events.
  final String? reason;

  /// Who made a manual mark or correction (e.g. "G-02", "Owner").
  final String? markedBy;
  final bool onTime;
}

enum ExceptionKind {
  missingOut,
  manual,
  clock,
  lowMargin,
  duplicate,
  spoofSuspect,
  livenessActive,
}

/// Something an admin should look at before payroll. The UI builds the
/// localised sentence from the structured fields, so no text is stored.
@immutable
class ExceptionRecord {
  const new({
    required this.id,
    required this.kind,
    required this.at,
    this.workerId,
    this.resolved = false,
    this.eventId,
    this.actor,
    this.reason,
    this.inAt,
    this.minutes,
    this.count,
  });

  final String id;
  final ExceptionKind kind;
  final DateTime at;
  final String? workerId;
  final bool resolved;

  /// The attendance event this exception is about, when there is one.
  final String? eventId;

  /// Who made a manual entry, e.g. `G-02`.
  final String? actor;

  /// The reason for a manual entry.
  final ManualReason? reason;

  /// The IN time of a missing-OUT day.
  final DateTime? inAt;

  /// How far the device clock moved (clock exceptions).
  final int? minutes;

  /// How many events are affected (clock exceptions).
  final int? count;

  ExceptionRecord copyWith({bool? resolved}) => ExceptionRecord(
    id: id,
    kind: kind,
    at: at,
    workerId: workerId,
    resolved: resolved ?? this.resolved,
    eventId: eventId,
    actor: actor,
    reason: reason,
    inAt: inAt,
    minutes: minutes,
    count: count,
  );
}

@immutable
class AppUser {
  const new({required this.id, required this.name, required this.role});

  final String id;
  final String name;
  final Role role;
}

/// Who is signed in to Admin mode.
@immutable
class AdminSession {
  const new({required this.user, required this.startedAt});

  final AppUser user;
  final DateTime startedAt;

  Role get role => user.role;
  bool can(Capability capability) => role.can(capability);
}

@immutable
class AuditEntry {
  const new({
    required this.at,
    required this.actor,
    required this.action,
    this.detail,
  });

  final DateTime at;
  final String actor;
  final String action;
  final String? detail;
}

enum LicenceState { none, trial, active, graceOverdue, restricted, revoked }

@immutable
class LicenceStatus {
  const new({required this.state, this.expiresOn, this.key});

  final LicenceState state;
  final DateTime? expiresOn;
  final String? key;
}

/// Today's numbers for the Today screen.
@immutable
class TodaySummary {
  const new({
    required this.expected,
    required this.present,
    required this.absent,
    required this.onLeave,
    required this.late,
    required this.onPremises,
    required this.wentOut,
    required this.lateAfterLabel,
  });

  final int expected;
  final int present;
  final int absent;
  final int onLeave;
  final int late;
  final int onPremises;
  final int wentOut;

  /// "06:10": the time after which an IN counts as late.
  final String lateAfterLabel;
}

/// One row of the monthly muster.
@immutable
class MusterRow {
  const new({
    required this.worker,
    required this.present,
    required this.absent,
    required this.late,
    required this.overtimeHours,
    required this.hasOpenExceptions,
    required this.days,
  });

  final Worker worker;
  final int present;
  final int absent;
  final int late;
  final double overtimeHours;
  final bool hasOpenExceptions;

  /// One code per calendar day: P, A, HD, L, WO.
  final List<String> days;
}

/// Filters for reports.
@immutable
class ReportFilter {
  const new({
    required this.month,
    this.department,
    this.shiftId,
    this.contractor,
  });

  /// First day of the month.
  final DateTime month;
  final String? department;
  final String? shiftId;
  final String? contractor;

  ReportFilter copyWith({
    DateTime? month,
    String? department,
    String? shiftId,
    String? contractor,
    bool clearDepartment = false,
    bool clearShift = false,
    bool clearContractor = false,
  }) => ReportFilter(
    month: month ?? this.month,
    department: clearDepartment ? null : department ?? this.department,
    shiftId: clearShift ? null : shiftId ?? this.shiftId,
    contractor: clearContractor ? null : contractor ?? this.contractor,
  );
}

/// One worker's line in the daily report.
@immutable
class DailyRow {
  const new({
    required this.worker,
    required this.inAt,
    required this.outAt,
    required this.status,
    required this.flagged,
  });

  final Worker worker;
  final DateTime? inAt;
  final DateTime? outAt;

  /// P, A, L (late) or HD.
  final String status;
  final bool flagged;

  Duration? get hours =>
      inAt != null && outAt != null ? outAt!.difference(inAt!) : null;
}

enum ExportFormat { excel, tally }

@immutable
class ExportResult {
  const new({required this.path, required this.rows});

  final String path;
  final int rows;
}

@immutable
class BackupInfo {
  const new({this.lastBackupAt, this.destination});

  final DateTime? lastBackupAt;
  final String? destination;
}

/// Why a guard made a manual entry (ADR-0004 §3). Required.
enum ManualReason { notRecognised, maskHelmet, injury, cameraIssue, newWorker }
