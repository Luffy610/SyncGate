import 'dart:async';

import 'package:sg_api/src/api_client.dart';
import 'package:sg_api/src/ids.dart';
import 'package:sg_api/src/json.dart';
import 'package:sg_api/src/refreshable.dart';
import 'package:sg_domain/sg_domain.dart';

/// Attendance facts. The server stamps time and direction and enforces the
/// cooldown and manual limit, so [append] returns the event as stored and
/// throws [FailureException] when the server refuses.
class ApiAttendanceRepository implements AttendanceRepository {
  new(this._api, {this.onAppended});

  final ApiClient _api;

  /// Lets the exceptions list reload (a manual mark creates one server-side).
  final void Function()? onAppended;

  final _days = <String, Refreshable<List<AttendanceEvent>>>{};

  @override
  Stream<List<AttendanceEvent>> watchDay(DateTime day) => _day(day).watch();

  Refreshable<List<AttendanceEvent>> _day(DateTime day) {
    final key = dateToJson(day);
    return _days.putIfAbsent(
      key,
      () => Refreshable<List<AttendanceEvent>>(
        () async => [
          for (final e in await _api.getList(
            'api/v1/attendance/day',
            query: {'date': key},
          ))
            eventFromJson((e! as Map).cast()),
        ],
        interval: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Future<List<AttendanceEvent>> eventsBetween(
    DateTime from,
    DateTime to,
  ) async => [
    for (final e in await _api.getList(
      'api/v1/attendance/events',
      query: {'from': instantToJson(from), 'to': instantToJson(to)},
    ))
      eventFromJson((e! as Map).cast()),
  ];

  @override
  Future<AttendanceEvent?> lastEvent(String workerId) async {
    final json = await _api.send(
      'GET',
      'api/v1/attendance/last',
      query: {'workerId': workerId},
    );
    return json == null ? null : eventFromJson((json as Map).cast());
  }

  @override
  Future<AttendanceEvent> append(AttendanceEvent event) async {
    final id = uuidFor(event.id);
    final String path;
    final Json body;
    switch (event.method) {
      case MarkMethod.face:
        path = 'api/v1/attendance/face-marks';
        body = {
          'id': id,
          'workerId': event.workerId,
          'score': event.matchScore ?? 0,
          'margin': event.matchMargin ?? 0,
          'liveness': event.liveness ?? 0,
        };
      case MarkMethod.manual:
        path = 'api/v1/attendance/manual-marks';
        body = {
          'id': id,
          'workerId': event.workerId,
          'reason': event.reason,
          'markedBy': event.markedBy,
        };
      case MarkMethod.correction:
        path = 'api/v1/attendance/corrections';
        body = {
          'id': id,
          'workerId': event.workerId,
          'at': instantToJson(event.at),
          'direction': event.direction.name,
          'reason': event.reason,
          'markedBy': event.markedBy,
        };
    }
    try {
      final json = await _api.send('POST', path, body: body);
      final stored = eventFromJson((json! as Map).cast());
      for (final day in _days.values) {
        unawaited(day.refresh());
      }
      onAppended?.call();
      return stored;
    } on ApiError catch (e) {
      throw FailureException(failureOf(e));
    }
  }
}

class ApiExceptionRepository implements ExceptionRepository {
  new(this._api)
    : _items = Refreshable<List<ExceptionRecord>>(
        () async => [
          for (final e in await _api.getList('api/v1/exceptions'))
            exceptionFromJson((e! as Map).cast()),
        ],
        interval: const Duration(seconds: 5),
      );

  final ApiClient _api;
  final Refreshable<List<ExceptionRecord>> _items;

  Future<void> refresh() => _items.refresh();

  @override
  Stream<List<ExceptionRecord>> watchAll() => _items.watch();

  @override
  Future<List<ExceptionRecord>> all() => _items.current();

  @override
  Future<void> add(ExceptionRecord record) async {
    // Manual-entry, low-margin and missing-OUT exceptions are created by the
    // server when the event is recorded; adding them twice would duplicate.
    if (record.kind == ExceptionKind.manual ||
        record.kind == ExceptionKind.lowMargin ||
        record.kind == ExceptionKind.missingOut) {
      await _items.refresh();
      return;
    }
    await _api.send(
      'POST',
      'api/v1/exceptions',
      body: {
        'id': uuidFor(record.id),
        'kind': record.kind.name,
        'workerId': record.workerId,
        'eventId': record.eventId,
        'actor': record.actor,
        'inAt': record.inAt == null ? null : instantToJson(record.inAt!),
        'minutes': record.minutes,
        'count': record.count,
      },
    );
    await _items.refresh();
  }

  @override
  Future<void> resolve(String id) async {
    await _api.send('POST', 'api/v1/exceptions/$id/resolve');
    await _items.refresh();
  }
}

/// Reports admin actions to the server's hash-chained audit log. Reading needs
/// the admin token; without it the list is simply empty.
class ApiAuditLog implements AuditLog {
  new(this._api)
    : _entries = Refreshable<List<AuditEntry>>(() async {
        try {
          return [
            for (final e in await _api.getList('api/v1/audit'))
              auditFromJson((e! as Map).cast()),
          ];
        } on ApiError catch (e) {
          if (e.status == 403 || e.status == 401) return const [];
          rethrow;
        }
      }, interval: const Duration(seconds: 10));

  final ApiClient _api;
  final Refreshable<List<AuditEntry>> _entries;

  @override
  Future<void> append(AuditEntry entry) async {
    await _api.send(
      'POST',
      'api/v1/audit',
      body: {
        'actor': entry.actor,
        'action': entry.action,
        'detail': entry.detail,
      },
    );
    unawaited(_entries.refresh());
  }

  @override
  Stream<List<AuditEntry>> watch() => _entries.watch();
}
