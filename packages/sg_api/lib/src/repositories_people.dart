import 'package:sg_api/src/api_client.dart';
import 'package:sg_api/src/ids.dart';
import 'package:sg_api/src/json.dart';
import 'package:sg_api/src/refreshable.dart';
import 'package:sg_domain/sg_domain.dart';

Never _raise(ApiError e) => throw FailureException(failureOf(e));

class ApiWorkerRepository implements WorkerRepository {
  new(this._api)
    : _workers = Refreshable<List<Worker>>(
        () async => [
          for (final w in await _api.getList('api/v1/workers'))
            workerFromJson((w! as Map).cast()),
        ],
      );

  final ApiClient _api;
  final Refreshable<List<Worker>> _workers;

  Future<void> refresh() => _workers.refresh();

  @override
  Stream<List<Worker>> watchAll() => _workers.watch();

  @override
  Future<List<Worker>> all() => _workers.current();

  @override
  Future<Worker?> byId(String id) async {
    try {
      return workerFromJson(await _api.getMap('api/v1/workers/${uuidFor(id)}'));
    } on ApiError catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  @override
  Future<String> nextCode() async =>
      (await _api.getMap('api/v1/workers/next-code'))['code']! as String;

  @override
  Future<bool> isCodeUnique(String code, {String? exceptWorkerId}) async {
    final json = await _api.getMap(
      'api/v1/workers/code-unique',
      query: {'code': code, 'exceptWorkerId': exceptWorkerId},
    );
    return json['unique']! as bool;
  }

  @override
  Future<Worker> add(NewWorker worker) async {
    try {
      final json = await _api.send(
        'POST',
        'api/v1/workers',
        body: workerRequest(
          code: worker.code,
          name: worker.name,
          dateOfBirth: worker.dateOfBirth,
          department: worker.department,
          designation: worker.designation,
          shiftId: uuidFor(worker.shiftId),
          language: worker.language,
          contractor: worker.contractor,
          phone: worker.phone,
        ),
      );
      await _workers.refresh();
      return workerFromJson((json! as Map).cast());
    } on ApiError catch (e) {
      _raise(e);
    }
  }

  @override
  Future<void> update(Worker worker) async {
    try {
      await _api.send(
        'PUT',
        'api/v1/workers/${worker.id}',
        body: workerRequest(
          code: worker.code,
          name: worker.name,
          dateOfBirth: worker.dateOfBirth,
          department: worker.department,
          designation: worker.designation,
          shiftId: uuidFor(worker.shiftId),
          language: worker.language,
          contractor: worker.contractor,
          phone: worker.phone,
        ),
      );
      await _workers.refresh();
    } on ApiError catch (e) {
      _raise(e);
    }
  }

  @override
  Future<void> setFaceStatus(String workerId, FaceStatus status) async {
    await _api.send(
      'PUT',
      'api/v1/workers/$workerId/face-status',
      body: {'status': status.name},
    );
    await _workers.refresh();
  }

  @override
  Future<void> setActive(String workerId, {required bool active}) async {
    await _api.send(
      'PUT',
      'api/v1/workers/$workerId/active',
      body: {'active': active},
    );
    await _workers.refresh();
  }

  @override
  Future<void> delete(String workerId) async {
    await _api.send('DELETE', 'api/v1/workers/$workerId');
    await _workers.refresh();
  }

  @override
  Future<List<String>> departments() async => [
    for (final d in await _api.getList('api/v1/departments')) d! as String,
  ];

  @override
  Future<void> addDepartment(String name) async {
    await _api.send('POST', 'api/v1/departments', body: {'name': name});
  }

  @override
  Future<List<String>> contractors() async => [
    for (final c in await _api.getList('api/v1/contractors')) c! as String,
  ];
}

class ApiShiftRepository implements ShiftRepository {
  new(this._api)
    : _shifts = Refreshable<List<Shift>>(
        () async => [
          for (final s in await _api.getList('api/v1/shifts'))
            shiftFromJson((s! as Map).cast()),
        ],
        interval: const Duration(seconds: 15),
      );

  final ApiClient _api;
  final Refreshable<List<Shift>> _shifts;

  @override
  Stream<List<Shift>> watch() => _shifts.watch();

  @override
  Future<List<Shift>> all() => _shifts.current();

  @override
  Future<void> save(Shift shift) async {
    await _api.send(
      'PUT',
      'api/v1/shifts/${uuidFor(shift.id)}',
      body: shiftToJson(shift),
    );
    await _shifts.refresh();
  }
}

class ApiConsentRepository implements ConsentRepository {
  new(this._api);

  final ApiClient _api;

  @override
  Future<void> record({
    required String workerId,
    required String noticeVersion,
    required AppLanguage language,
    required String adminId,
  }) async {
    await _api.send(
      'POST',
      'api/v1/consents',
      body: {
        'workerId': workerId,
        'noticeVersion': noticeVersion,
        'language': language.code,
        'adminId': adminId,
      },
    );
  }

  @override
  Future<bool> hasConsent(String workerId) async =>
      (await _api.getMap('api/v1/consents/$workerId'))['hasConsent']! as bool;
}
