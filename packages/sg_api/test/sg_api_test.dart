import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sg_api/sg_api.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:test/test.dart';

/// A tiny stand-in server: routes `METHOD path` to a handler and records every
/// request so tests can check what the app really sent.
class FakeServer {
  final routes = <String, http.Response Function(http.Request)>{};
  final seen = <http.Request>[];

  late final MockClient client = MockClient((request) async {
    seen.add(request);
    final key = '${request.method} ${request.url.path}';
    final handler = routes[key];
    if (handler == null) {
      return http.Response(
        '{"code":"NOT_FOUND","message":"x","details":{}}',
        404,
      );
    }
    return handler(request);
  });

  void json(String route, Object body, {int status = 200}) {
    routes[route] = (_) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json'},
    );
  }

  void error(String route, int status, String code, [Map<String, Object?>? d]) {
    json(route, {
      'code': code,
      'message': 'm',
      'details': d ?? {},
    }, status: status);
  }

  List<http.Request> to(String route) =>
      seen.where((r) => '${r.method} ${r.url.path}' == route).toList();
}

ApiBackend backend(
  FakeServer server, {
  DateTime Function()? now,
  FileSaver? saver,
}) => ApiBackend(
  baseUrl: 'http://api.test:8080',
  deviceKey: 'device-key-0123456789',
  httpClient: server.client,
  now: now ?? () => DateTime(2026, 10, 24, 5, 52),
  saveFile: saver ?? (name, bytes) async => '/tmp/$name',
);

final Map<String, Object?> workerJson = {
  'id': '01a1833c-15bd-733b-a3bf-ef6c4baa744c',
  'code': 'W-0101',
  'name': 'Ramesh Kumar',
  'dateOfBirth': '1990-05-01',
  'department': 'Weaving',
  'designation': 'Operator',
  'shiftId': '01a1833c-15b4-7ee7-a681-cc5ab14945d4',
  'contractor': null,
  'phone': null,
  'language': 'hi',
  'faceStatus': 'needsFace',
  'active': true,
  'onLeave': false,
};

void main() {
  tallyTests();
  group('uuidFor', () {
    test('real UUIDs pass through, lower-cased', () {
      expect(
        uuidFor('01A1833C-15BD-733B-A3BF-EF6C4BAA744C'),
        '01a1833c-15bd-733b-a3bf-ef6c4baa744c',
      );
    });

    test('readable ids map to a stable v5-style UUID', () {
      final a = uuidFor('ev-1730000000-3');
      expect(a, uuidFor('ev-1730000000-3'));
      expect(a, isNot(uuidFor('ev-1730000000-4')));
      expect(
        a,
        matches(RegExp('^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab]')),
      );
    });
  });

  group('authentication', () {
    test('during setup nothing is sent with a token', () async {
      final s = FakeServer()
        ..json('GET /api/v1/setup/status', {'hasOwner': false})
        ..json('GET /api/v1/shifts', <Object>[]);
      final api = backend(s);
      await api.shifts.all();
      expect(
        s.to('GET /api/v1/shifts').single.headers['Authorization'],
        isNull,
      );
      expect(s.to('POST /api/v1/auth/device'), isEmpty);
    });

    test(
      'after setup the gate phone signs in with its device key once',
      () async {
        final s = FakeServer()
          ..json('GET /api/v1/setup/status', {'hasOwner': true})
          ..json('POST /api/v1/auth/device', {'token': 'DEVICE.TOKEN'})
          ..json('GET /api/v1/shifts', <Object>[]);
        final api = backend(s);
        await api.shifts.all();
        await api.client.getList('api/v1/shifts');
        expect(
          s.to('GET /api/v1/shifts').first.headers['Authorization'],
          'Bearer DEVICE.TOKEN',
        );
        expect(s.to('POST /api/v1/auth/device'), hasLength(1));
        expect(jsonDecode(s.to('POST /api/v1/auth/device').single.body), {
          'deviceKey': 'device-key-0123456789',
        });
      },
    );

    test(
      'an unlocked admin token wins, and returning to the gate drops it',
      () async {
        final s = FakeServer()
          ..json('GET /api/v1/setup/status', {'hasOwner': true})
          ..json('POST /api/v1/auth/device', {'token': 'DEVICE'})
          ..json('POST /api/v1/auth/login', {
            'token': 'ADMIN',
            'user': {'id': 'u1', 'name': 'Owner', 'role': 'owner'},
          })
          ..json('GET /api/v1/settings', _settings('admin'))
          ..json('PUT /api/v1/settings', <String, Object>{}, status: 204)
          ..json('POST /api/v1/auth/logout', <String, Object>{}, status: 204);
        final api = backend(s);
        final result = await api.users.verifyPin(Role.owner, '123456');
        expect(result.isOk, isTrue);
        await api.settings.load();
        expect(
          s.to('GET /api/v1/settings').last.headers['Authorization'],
          'Bearer ADMIN',
        );
        await api.settings.save(
          const AppSettings(mode: AppModeKind.gate, setupStep: 7),
        );
        expect(
          s.to('POST /api/v1/auth/logout').single.headers['Authorization'],
          'Bearer ADMIN',
        );
        await api.client.getMap('api/v1/settings');
        expect(
          s.to('GET /api/v1/settings').last.headers['Authorization'],
          'Bearer DEVICE',
        );
      },
    );

    test(
      'an expired device token is renewed once and the call retried',
      () async {
        var calls = 0;
        final s = FakeServer()
          ..json('GET /api/v1/setup/status', {'hasOwner': true})
          ..json('POST /api/v1/auth/device', {'token': 'FRESH'});
        s.routes['GET /api/v1/shifts'] = (r) {
          calls++;
          return r.headers['Authorization'] == 'Bearer FRESH' && calls > 1
              ? http.Response('[]', 200)
              : http.Response(
                  '{"code":"UNAUTHENTICATED","message":"m","details":{}}',
                  401,
                );
        };
        final api = backend(s);
        expect(await api.shifts.all(), isEmpty);
        expect(calls, 2);
      },
    );

    test('a PIN error becomes a typed failure with attempts left', () async {
      final s = FakeServer()
        ..json('GET /api/v1/setup/status', {'hasOwner': true})
        ..error('POST /api/v1/auth/login', 401, 'WRONG_PIN', {
          'attemptsLeft': 2,
          'lockedForSeconds': 0,
        });
      final api = backend(s);
      final result = await api.users.verifyPin(Role.owner, '000000');
      final failure = (result as Err<AppUser, Failure>).failure;
      expect(failure, isA<WrongPin>());
      expect((failure as WrongPin).attemptsLeft, 2);
      expect(failure.lockedFor, isNull);
    });

    test('lockout carries the wait time', () async {
      final s = FakeServer()
        ..json('GET /api/v1/setup/status', {'hasOwner': true})
        ..error('POST /api/v1/auth/login', 429, 'LOCKED_OUT', {
          'retryAfterSeconds': 45,
        });
      final result = await backend(s).users.verifyPin(Role.owner, '1');
      expect(
        ((result as Err<AppUser, Failure>).failure as LockedOut).remaining,
        const Duration(seconds: 45),
      );
    });
  });

  group('attendance', () {
    late FakeServer s;
    late ApiBackend api;

    setUp(() {
      s = FakeServer()
        ..json('GET /api/v1/setup/status', {'hasOwner': true})
        ..json('POST /api/v1/auth/device', {'token': 'DEVICE'})
        ..json('GET /api/v1/exceptions', <Object>[]);
      api = backend(s);
    });

    Map<String, Object?> stored(
      String method, {
      String direction = 'checkIn',
    }) => {
      'id': '01a1833c-15c3-7222-9d24-362a91575e06',
      'workerId': workerJson['id'],
      'at': '2026-10-24T00:22:00Z',
      'direction': direction,
      'method': method,
      'reason': null,
      'markedBy': null,
      'onTime': true,
    };

    test(
      'a face mark sends the matcher scores, not a time or direction',
      () async {
        s.json(
          'POST /api/v1/attendance/face-marks',
          stored('face'),
          status: 201,
        );
        final event = await api.attendance.append(
          AttendanceEvent(
            id: 'ev-1-0',
            workerId: workerJson['id']! as String,
            at: DateTime(2000),
            direction: Direction.checkOut,
            method: MarkMethod.face,
            matchScore: 0.91,
            matchMargin: 0.22,
            liveness: 0.97,
          ),
        );
        final body = jsonDecode(
          s.to('POST /api/v1/attendance/face-marks').single.body,
        ) as Map<String, Object?>;
        expect(body['score'], 0.91);
        expect(body['margin'], 0.22);
        expect(body['liveness'], 0.97);
        expect(body.containsKey('at'), isFalse);
        expect(body.containsKey('direction'), isFalse);
        expect(body['id'], uuidFor('ev-1-0'));
        // The app shows what the server stored.
        expect(event.direction, Direction.checkIn);
        expect(event.at.toUtc(), DateTime.utc(2026, 10, 24, 0, 22));
      },
    );

    test('a refused mark is a typed failure the use case can show', () async {
      s.error('POST /api/v1/attendance/face-marks', 409, 'ALREADY_MARKED', {
        'at': '2026-10-24T00:22:00Z',
        'direction': 'checkIn',
      });
      await expectLater(
        api.attendance.append(
          AttendanceEvent(
            id: 'ev-2',
            workerId: workerJson['id']! as String,
            at: DateTime(2026),
            direction: Direction.checkIn,
            method: MarkMethod.face,
          ),
        ),
        throwsA(
          isA<FailureException>().having(
            (e) => e.failure,
            'failure',
            isA<AlreadyMarked>().having(
              (f) => f.direction,
              'direction',
              Direction.checkIn,
            ),
          ),
        ),
      );
    });

    test('manual and correction marks go to their own endpoints', () async {
      s
        ..json(
          'POST /api/v1/attendance/manual-marks',
          stored('manual'),
          status: 201,
        )
        ..json(
          'POST /api/v1/attendance/corrections',
          stored('correction', direction: 'checkOut'),
          status: 201,
        );
      await api.attendance.append(
        AttendanceEvent(
          id: 'ev-3',
          workerId: workerJson['id']! as String,
          at: DateTime(2026),
          direction: Direction.checkIn,
          method: MarkMethod.manual,
          reason: 'notRecognised',
          markedBy: 'G-02',
        ),
      );
      await api.attendance.append(
        AttendanceEvent(
          id: 'ev-4',
          workerId: workerJson['id']! as String,
          at: DateTime.utc(2026, 10, 24, 8, 30),
          direction: Direction.checkOut,
          method: MarkMethod.correction,
          reason: 'Forgot to scan',
          markedBy: 'Owner',
        ),
      );
      final manual = jsonDecode(
        s.to('POST /api/v1/attendance/manual-marks').single.body,
      ) as Map<String, Object?>;
      expect(manual['reason'], 'notRecognised');
      expect(manual['markedBy'], 'G-02');
      final fix = jsonDecode(
        s.to('POST /api/v1/attendance/corrections').single.body,
      ) as Map<String, Object?>;
      expect(fix['at'], '2026-10-24T08:30:00.000Z');
      expect(fix['direction'], 'checkOut');
    });

    test('lastEvent is null on 204', () async {
      s.routes['GET /api/v1/attendance/last'] = (_) => http.Response('', 204);
      expect(await api.attendance.lastEvent('w'), isNull);
    });

    test('server-made exceptions are not added a second time', () async {
      await api.exceptions.add(
        ExceptionRecord(
          id: 'ex-1',
          kind: ExceptionKind.manual,
          at: DateTime(2026),
        ),
      );
      expect(s.to('POST /api/v1/exceptions'), isEmpty);
    });
  });

  group('workers and records', () {
    test(
      'adding a worker sends ISO dates and the server UUID shift id',
      () async {
        final s = FakeServer()
          ..json('GET /api/v1/setup/status', {'hasOwner': false})
          ..json('POST /api/v1/workers', workerJson, status: 201)
          ..json('GET /api/v1/workers', [workerJson]);
        final api = backend(s);
        final worker = await api.workers.add(
          NewWorker(
            code: 'W-0101',
            name: 'Ramesh Kumar',
            dateOfBirth: DateTime(1990, 5),
            department: 'Weaving',
            designation: 'Operator',
            shiftId: 'shift-day',
            language: AppLanguage.hi,
          ),
        );
        final body = jsonDecode(
          s.to('POST /api/v1/workers').single.body,
        ) as Map<String, Object?>;
        expect(body['dateOfBirth'], '1990-05-01');
        expect(body['shiftId'], uuidFor('shift-day'));
        expect(body['language'], 'hi');
        expect(worker.faceStatus, FaceStatus.needsFace);
        expect(worker.name, 'Ramesh Kumar');
      },
    );

    test('a duplicate code is a typed failure', () async {
      final s = FakeServer()
        ..json('GET /api/v1/setup/status', {'hasOwner': false})
        ..error('POST /api/v1/workers', 409, 'DUPLICATE_WORKER_CODE');
      await expectLater(
        backend(s).workers.add(
          NewWorker(
            code: 'W-0101',
            name: 'X',
            dateOfBirth: DateTime(1990),
            department: 'd',
            designation: 'd',
            shiftId: 's',
            language: AppLanguage.en,
          ),
        ),
        throwsA(
          isA<FailureException>().having(
            (e) => e.failure,
            'failure',
            isA<DuplicateWorkerCode>(),
          ),
        ),
      );
    });

    test('byId answers null for a missing worker', () async {
      final s = FakeServer()
        ..json('GET /api/v1/setup/status', {'hasOwner': false})
        ..error('GET /api/v1/workers/${workerJson['id']}', 404, 'NOT_FOUND');
      expect(
        await backend(s).workers.byId(workerJson['id']! as String),
        isNull,
      );
    });

    test(
      'a shift is saved with a stable id so retries are idempotent',
      () async {
        final s = FakeServer()
          ..json('GET /api/v1/setup/status', {'hasOwner': false})
          ..json('PUT /api/v1/shifts/${uuidFor('shift-day')}', {})
          ..json('GET /api/v1/shifts', <Object>[]);
        await backend(s).shifts.save(
          const Shift(
            id: 'shift-day',
            name: 'Day',
            startMinute: 360,
            endMinute: 840,
          ),
        );
        final body = jsonDecode(
          s.to('PUT /api/v1/shifts/${uuidFor('shift-day')}').single.body,
        ) as Map<String, Object?>;
        expect(body['startMinute'], 360);
        expect(body.containsKey('id'), isFalse);
      },
    );
  });

  group('reports, export, backup, licence', () {
    test('working days skip Sundays and stop at today', () {
      final api = backend(
        FakeServer(),
        now: () => DateTime(2026, 10, 24, 5, 52),
      );
      expect(api.reports.workingDays(DateTime(2026, 10)), 21);
      expect(api.reports.workingDays(DateTime(2026, 9)), 26);
      expect(api.reports.workingDays(DateTime(2026, 11)), 0);
    });

    test(
      'export saves the downloaded file and reports the row count',
      () async {
        String? savedName;
        List<int>? savedBytes;
        final s = FakeServer()
          ..json('GET /api/v1/setup/status', {'hasOwner': true})
          ..json('POST /api/v1/auth/device', {'token': 'D'})
          ..routes['POST /api/v1/exports'] = (_) => http.Response.bytes(
            utf8.encode('a,b\r\n'),
            200,
            headers: {
              'content-disposition':
                  'attachment; filename="SyncGate_Muster_2026-10.csv"',
              'x-row-count': '24',
            },
          );
        final api = backend(
          s,
          saver: (name, bytes) async {
            savedName = name;
            savedBytes = bytes;
            return '/files/$name';
          },
        );
        final result = await api.export.export(
          ExportFormat.csv,
          ReportFilter(month: DateTime(2026, 10), department: 'Packing'),
        );
        final ok = (result as Ok<ExportResult, Failure>).value;
        expect(ok.path, '/files/SyncGate_Muster_2026-10.csv');
        expect(ok.rows, 24);
        expect(savedName, 'SyncGate_Muster_2026-10.csv');
        expect(utf8.decode(savedBytes!), 'a,b\r\n');
        final sent = jsonDecode(
          s.to('POST /api/v1/exports').single.body,
        ) as Map<String, Object?>;
        expect(sent, containsPair('format', 'csv'));
        expect(sent, containsPair('month', '2026-10'));
        expect(sent, containsPair('department', 'Packing'));
      },
    );

    test('licence errors map to the typed failures', () async {
      final s = FakeServer()
        ..json('GET /api/v1/setup/status', {'hasOwner': false})
        ..error('POST /api/v1/licence/activate', 422, 'INVALID_LICENCE_KEY');
      final bad = await backend(s).licence.activate('nope');
      expect(
        (bad as Err<LicenceStatus, Failure>).failure,
        isA<InvalidLicenceKey>(),
      );

      s.error('POST /api/v1/licence/activate', 503, 'NO_INTERNET');
      final offline = await backend(s).licence.activate('SGT-NONE-T123-4567');
      expect(
        (offline as Err<LicenceStatus, Failure>).failure,
        isA<NoInternet>(),
      );
    });

    test('a dead server is a NoInternet failure, never a crash', () async {
      final client = MockClient(
        (_) async => throw http.ClientException('down'),
      );
      final api = ApiBackend(
        baseUrl: 'http://api.test',
        deviceKey: 'device-key-0123456789',
        httpClient: client,
        now: DateTime.now,
        saveFile: (n, b) async => n,
      );
      final result = await api.licence.activate('SGT-4F7K-2Q9M-A1B2');
      expect(
        (result as Err<LicenceStatus, Failure>).failure,
        isA<NoInternet>(),
      );
    });

    test('server clock offset is measured against the phone', () async {
      final s = FakeServer()
        ..json('GET /api/v1/setup/status', {'hasOwner': false})
        ..routes['GET /api/v1/time'] = (_) => http.Response(
          jsonEncode({
            'now': DateTime.now()
                .add(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
          }),
          200,
        );
      final offset = await backend(s).serverClockOffset();
      expect(offset.inMinutes, inInclusiveRange(59, 61));
    });
  });

  group('Refreshable', () {
    test('replays the last value and reloads on refresh', () async {
      var n = 0;
      final r = Refreshable<int>(
        () async => ++n,
        interval: const Duration(hours: 1),
      );
      expect(await r.current(), 1);
      expect(await r.watch().first, 1);
      await r.refresh();
      expect(await r.watch().first, 2);
      r.dispose();
    });

    test(
      'a failed first load is an error; a later failure keeps the value',
      () async {
        var fail = true;
        final r = Refreshable<int>(() async {
          if (fail) throw StateError('down');
          return 7;
        }, interval: const Duration(hours: 1));
        await expectLater(r.watch(), emitsError(isA<StateError>()));
        fail = false;
        await r.refresh();
        expect(r.value, 7);
        fail = true;
        await r.refresh();
        expect(r.value, 7, reason: 'stale value kept');
        r.dispose();
      },
    );

    test('concurrent refreshes share one request', () async {
      var calls = 0;
      final gate = Completer<void>();
      final r = Refreshable<int>(() async {
        calls++;
        await gate.future;
        return calls;
      }, interval: const Duration(hours: 1));
      final a = r.refresh();
      final b = r.refresh();
      gate.complete();
      await Future.wait([a, b]);
      expect(calls, 1);
      r.dispose();
    });
  });
}

Map<String, Object?> _settings(String mode) => {
  'mode': mode,
  'setupStep': 7,
  'language': 'en',
  'idleMinutes': 2,
  'cooldownSeconds': 120,
  'voiceVolume': 0.8,
  'screenFillLight': true,
  'use24HourClock': false,
  'remindBackupDays': 7,
  'autoBackup': true,
  'gateOperatorId': 'G-02',
  'biometricEnabled': true,
  'backupPassphraseSet': false,
};

void tallyTests() {
  group('Tally', () {
    test('mappings and the match caption come from the server', () async {
      final s = FakeServer()
        ..json('GET /api/v1/setup/status', {'hasOwner': false})
        ..json('GET /api/v1/tally/mappings', {'w1': 'RAMESH KUMAR'})
        ..json('GET /api/v1/tally/match', {'matched': 23, 'total': 24})
        ..json(
          'PUT /api/v1/tally/mappings/w2',
          <String, Object>{},
          status: 204,
        );
      final api = backend(s);
      expect(await api.tally.all(), {'w1': 'RAMESH KUMAR'});
      expect(await api.export.tallyMatch(), (matched: 23, total: 24));
      await api.tally.set('w2', 'SITA DEVI');
      final body = jsonDecode(
        s.to('PUT /api/v1/tally/mappings/w2').single.body,
      ) as Map<String, Object?>;
      expect(body, {'name': 'SITA DEVI'});
    });

    test('a Tally export is saved as .xml with the employee count', () async {
      String? savedName;
      final s = FakeServer()
        ..json('GET /api/v1/setup/status', {'hasOwner': false})
        ..routes['POST /api/v1/exports'] = (_) => http.Response(
          '<ENVELOPE/>',
          200,
          headers: {
            'content-disposition':
                'attachment; filename="SyncGate_Tally_2026-10.xml"',
            'x-row-count': '23',
            'x-unmapped': '1',
          },
        );
      final api = backend(s, saver: (name, bytes) async => savedName = name);
      final result = await api.export.export(
        ExportFormat.tally,
        ReportFilter(month: DateTime(2026, 10)),
      );
      expect((result as Ok<ExportResult, Failure>).value.rows, 23);
      expect(savedName, 'SyncGate_Tally_2026-10.xml');
      final sent = jsonDecode(
        s.to('POST /api/v1/exports').single.body,
      ) as Map<String, Object?>;
      expect(sent['format'], 'tally');
    });
  });
}
