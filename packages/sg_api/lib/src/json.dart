import 'package:sg_domain/sg_domain.dart';

/// JSON <-> domain mapping. Enum names match the Dart names on purpose
/// (`checkIn`, `gateOperator`, `needsFace`), so `byName` is the whole story.
typedef Json = Map<String, Object?>;

DateTime parseInstant(Object? value) =>
    DateTime.parse(value! as String).toLocal();

DateTime? parseInstantOrNull(Object? value) =>
    value == null ? null : parseInstant(value);

String instantToJson(DateTime value) => value.toUtc().toIso8601String();

String dateToJson(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String monthToJson(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}';

Worker workerFromJson(Json j) => Worker(
  id: j['id']! as String,
  code: j['code']! as String,
  name: j['name']! as String,
  dateOfBirth: DateTime.parse(j['dateOfBirth']! as String),
  department: j['department']! as String,
  designation: j['designation']! as String,
  shiftId: j['shiftId']! as String,
  contractor: j['contractor'] as String?,
  phone: j['phone'] as String?,
  language: AppLanguage.fromCode(j['language']! as String),
  faceStatus: FaceStatus.values.byName(j['faceStatus']! as String),
  active: j['active']! as bool,
  onLeave: j['onLeave']! as bool,
);

Json workerRequest({
  required String code,
  required String name,
  required DateTime dateOfBirth,
  required String department,
  required String designation,
  required String shiftId,
  required AppLanguage language,
  String? contractor,
  String? phone,
  String? id,
}) => {
  'id': ?id,
  'code': code,
  'name': name,
  'dateOfBirth': dateToJson(dateOfBirth),
  'department': department,
  'designation': designation,
  'shiftId': shiftId,
  'language': language.code,
  'contractor': contractor,
  'phone': phone,
};

Shift shiftFromJson(Json j) => Shift(
  id: j['id']! as String,
  name: j['name']! as String,
  startMinute: (j['startMinute']! as num).toInt(),
  endMinute: (j['endMinute']! as num).toInt(),
  graceMinutes: (j['graceMinutes']! as num).toInt(),
  weeklyOff: (j['weeklyOff']! as num).toInt(),
);

Json shiftToJson(Shift s) => {
  'name': s.name,
  'startMinute': s.startMinute,
  'endMinute': s.endMinute,
  'graceMinutes': s.graceMinutes,
  'weeklyOff': s.weeklyOff,
};

AttendanceEvent eventFromJson(Json j) => AttendanceEvent(
  id: j['id']! as String,
  workerId: j['workerId']! as String,
  at: parseInstant(j['at']),
  direction: Direction.values.byName(j['direction']! as String),
  method: MarkMethod.values.byName(j['method']! as String),
  reason: j['reason'] as String?,
  markedBy: j['markedBy'] as String?,
  onTime: j['onTime']! as bool,
);

ExceptionRecord exceptionFromJson(Json j) => ExceptionRecord(
  id: j['id']! as String,
  kind: ExceptionKind.values.byName(j['kind']! as String),
  at: parseInstant(j['at']),
  workerId: j['workerId'] as String?,
  resolved: j['resolved']! as bool,
  eventId: j['eventId'] as String?,
  actor: j['actor'] as String?,
  reason: j['reason'] == null
      ? null
      : ManualReason.values.byName(j['reason']! as String),
  inAt: parseInstantOrNull(j['inAt']),
  minutes: (j['minutes'] as num?)?.toInt(),
  count: (j['count'] as num?)?.toInt(),
);

AppSettings settingsFromJson(Json j) => AppSettings(
  mode: AppModeKind.values.byName(j['mode']! as String),
  setupStep: (j['setupStep']! as num).toInt(),
  language: AppLanguage.fromCode(j['language']! as String),
  idleMinutes: (j['idleMinutes']! as num).toInt(),
  cooldownSeconds: (j['cooldownSeconds']! as num).toInt(),
  voiceVolume: (j['voiceVolume']! as num).toDouble(),
  screenFillLight: j['screenFillLight']! as bool,
  use24HourClock: j['use24HourClock']! as bool,
  remindBackupDays: (j['remindBackupDays']! as num).toInt(),
  autoBackup: j['autoBackup']! as bool,
  gateOperatorId: j['gateOperatorId']! as String,
  biometricEnabled: j['biometricEnabled']! as bool,
  backupPassphraseSet: j['backupPassphraseSet']! as bool,
);

Json settingsToJson(AppSettings s) => {
  'mode': s.mode.name,
  'setupStep': s.setupStep,
  'language': s.language.code,
  'idleMinutes': s.idleMinutes,
  'cooldownSeconds': s.cooldownSeconds,
  'voiceVolume': s.voiceVolume,
  'screenFillLight': s.screenFillLight,
  'use24HourClock': s.use24HourClock,
  'remindBackupDays': s.remindBackupDays,
  'autoBackup': s.autoBackup,
  'gateOperatorId': s.gateOperatorId,
  'biometricEnabled': s.biometricEnabled,
  'backupPassphraseSet': s.backupPassphraseSet,
};

AppUser userFromJson(Json j) => AppUser(
  id: j['id']! as String,
  name: j['name']! as String,
  role: Role.values.byName(j['role']! as String),
);

LicenceStatus licenceFromJson(Json j) => LicenceStatus(
  state: LicenceState.values.byName(j['state']! as String),
  expiresOn: j['expiresOn'] == null
      ? null
      : DateTime.parse(j['expiresOn']! as String),
  key: j['key'] as String?,
);

AuditEntry auditFromJson(Json j) => AuditEntry(
  at: parseInstant(j['at']),
  actor: j['actor']! as String,
  action: j['action']! as String,
  detail: j['detail'] as String?,
);

MusterRow musterFromJson(Json j) => MusterRow(
  worker: workerFromJson((j['worker']! as Map).cast()),
  present: (j['present']! as num).toInt(),
  absent: (j['absent']! as num).toInt(),
  late: (j['late']! as num).toInt(),
  overtimeHours: (j['overtimeHours']! as num).toDouble(),
  hasOpenExceptions: j['hasOpenExceptions']! as bool,
  days: (j['days']! as List).cast<String>(),
);

DailyRow dailyFromJson(Json j) => DailyRow(
  worker: workerFromJson((j['worker']! as Map).cast()),
  inAt: parseInstantOrNull(j['inAt']),
  outAt: parseInstantOrNull(j['outAt']),
  status: j['status']! as String,
  flagged: j['flagged']! as bool,
);
