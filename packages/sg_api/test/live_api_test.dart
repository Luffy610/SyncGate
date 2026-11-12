// Drives the real Spring Boot API with the real Dart client, end to end.
//
// Skipped unless a server is running and SG_API_URL points at it, on a FRESH
// database (first-run setup is part of the flow):
//
//   cd services/api && ./mvnw spring-boot:run
//   cd packages/sg_api && SG_API_URL=http://localhost:8080 dart test test/live_api_test.dart
//
// Uses the dev profile's device key. See docs/backend/README.md.
import 'dart:convert';
import 'dart:io';

import 'package:sg_api/sg_api.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:test/test.dart';

void main() {
  final url = Platform.environment['SG_API_URL'];
  final skip = url == null
      ? 'set SG_API_URL to run against a live server'
      : null;

  test('setup, gate marks, reports, export and backup', () async {
    final saved = <String, List<int>>{};
    final api = ApiBackend(
      baseUrl: url!,
      deviceKey:
          Platform.environment['SG_DEVICE_KEY'] ?? 'dev-device-key-local',
      now: DateTime.now,
      saveFile: (name, bytes) async {
        saved[name] = bytes;
        return '/tmp/$name';
      },
    );

    // --- first run: no credentials at all ---------------------------------
    expect(await api.users.hasOwner(), isFalse);
    await api.shifts.save(
      const Shift(
        id: 'shift-day',
        name: 'Day',
        startMinute: 360,
        endMinute: 840,
      ),
    );
    final shifts = await api.shifts.all();
    expect(shifts, hasLength(1));
    final licence = await api.licence.activate('SGT-4F7K-2Q9M-A1B2');
    expect(
      (licence as Ok<LicenceStatus, Failure>).value.state,
      LicenceState.active,
    );

    final worker = await api.workers.add(
      NewWorker(
        code: 'W-0101',
        name: 'Ramesh Kumar',
        dateOfBirth: DateTime(1990, 5),
        department: 'Weaving',
        designation: 'Operator',
        shiftId: shifts.single.id,
        language: AppLanguage.hi,
      ),
    );
    await api.consent.record(
      workerId: worker.id,
      noticeVersion: 'v1',
      language: AppLanguage.hi,
      adminId: 'Owner',
    );
    await api.workers.setFaceStatus(worker.id, FaceStatus.enrolled);

    final recovery = await api.users.createOwner('123456');
    expect(recovery, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$')));
    expect(await api.users.hasOwner(), isTrue);
    await api.settings.save(
      (await api.settings.load()).copyWith(
        mode: AppModeKind.gate,
        setupStep: 7,
      ),
    );

    // --- the gate phone, signed in with its device key ---------------------
    final stored = await api.attendance.append(
      AttendanceEvent(
        id: 'ev-live-1',
        workerId: worker.id,
        at: DateTime(2000),
        direction: Direction.checkOut,
        method: MarkMethod.face,
        matchScore: 0.91,
        matchMargin: 0.22,
        liveness: 0.97,
      ),
    );
    expect(stored.direction, Direction.checkIn, reason: 'server decides');
    expect(stored.method, MarkMethod.face);
    await expectLater(
      api.attendance.append(
        AttendanceEvent(
          id: 'ev-live-2',
          workerId: worker.id,
          at: DateTime(2000),
          direction: Direction.checkIn,
          method: MarkMethod.face,
        ),
      ),
      throwsA(
        isA<FailureException>().having(
          (e) => e.failure,
          'f',
          isA<AlreadyMarked>(),
        ),
      ),
    );
    // A wrong PIN is a typed failure and counts down.
    final wrong = await api.users.verifyPin(Role.owner, '000000');
    expect(
      ((wrong as Err<AppUser, Failure>).failure as WrongPin).attemptsLeft,
      4,
    );
    // The device cannot read reports.
    await expectLater(
      api.reports.monthly(ReportFilter(month: DateTime(2026, 10))),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 403)),
    );

    // --- the owner unlocks Admin -------------------------------------------
    final unlocked = await api.users.verifyPin(Role.owner, '123456');
    expect(unlocked.isOk, isTrue);
    final muster = await api.reports.monthly(
      ReportFilter(month: DateTime(2026, 10)),
    );
    expect(muster.single.worker.code, 'W-0101');
    expect(muster.single.present, 1);

    final csv = await api.export.export(
      ExportFormat.csv,
      ReportFilter(month: DateTime(2026, 10)),
    );
    expect((csv as Ok<ExportResult, Failure>).value.rows, 1);
    final bytes = saved.entries
        .singleWhere((e) => e.key.endsWith('.csv'))
        .value;
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF], reason: 'UTF-8 BOM for Excel');
    expect(utf8.decode(bytes), contains('Ramesh Kumar'));
    final xlsx = await api.export.export(
      ExportFormat.excel,
      ReportFilter(month: DateTime(2026, 10)),
    );
    expect(xlsx.isOk, isTrue);
    expect(saved.keys.any((k) => k.endsWith('.xlsx')), isTrue);

    // --- backup -------------------------------------------------------------
    expect(
      (await api.backup.setPassphrase('bamboo velvet compass pepper')).isOk,
      isTrue,
    );
    expect((await api.backup.backupNow()).isOk, isTrue);
    expect((await api.backup.current()).lastBackupAt, isNotNull);

    // --- audit trail --------------------------------------------------------
    final audit = await api.audit.watch().first;
    expect(
      audit.map((e) => e.action),
      containsAll(['worker.enrolled', 'backup.created']),
    );

    expect((await api.serverClockOffset()).inDays.abs(), lessThan(10000));
    api.close();
  }, skip: skip);
}
