import 'dart:async';

import 'package:sg_api/src/api_client.dart';
import 'package:sg_api/src/json.dart';
import 'package:sg_api/src/refreshable.dart';
import 'package:sg_domain/sg_domain.dart';

/// Writes downloaded bytes to a file the share sheet can send, and returns its
/// path. Supplied by the app so this package stays free of `dart:io`.
typedef FileSaver = Future<String> Function(String fileName, List<int> bytes);

class ApiReportService implements ReportService {
  new(this._api, this._now);

  final ApiClient _api;
  final DateTime Function() _now;

  @override
  Future<List<MusterRow>> monthly(ReportFilter filter) async => [
    for (final r in await _api.getList(
      'api/v1/reports/monthly',
      query: {
        'month': monthToJson(filter.month),
        'department': filter.department,
        'shiftId': filter.shiftId,
        'contractor': filter.contractor,
      },
    ))
      musterFromJson((r! as Map).cast()),
  ];

  @override
  Future<List<DailyRow>> daily(DateTime day) async => [
    for (final r in await _api.getList(
      'api/v1/reports/daily',
      query: {'date': dateToJson(day)},
    ))
      dailyFromJson((r! as Map).cast()),
  ];

  /// Same rule as the server (Sunday off, days that have happened). Computed
  /// here because the interface is synchronous.
  @override
  int workingDays(DateTime month) {
    final today = _now();
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final last = (today.year == month.year && today.month == month.month)
        ? today.day
        : DateTime(month.year, month.month).isAfter(today)
        ? 0
        : daysInMonth;
    var count = 0;
    for (var d = 1; d <= last; d++) {
      if (DateTime(month.year, month.month, d).weekday != DateTime.sunday) {
        count++;
      }
    }
    return count;
  }
}

class ApiExportService implements ExportService {
  new(this._api, this._save);

  final ApiClient _api;
  final FileSaver _save;

  @override
  Future<Result<ExportResult, Failure>> export(
    ExportFormat format,
    ReportFilter filter,
  ) async {
    try {
      final response = await _api.sendForBytes(
        'POST',
        'api/v1/exports',
        body: {
          'format': format.name,
          'month': monthToJson(filter.month),
          'department': filter.department,
          'shiftId': filter.shiftId,
          'contractor': filter.contractor,
        },
      );
      final disposition = response.headers['content-disposition'] ?? '';
      final name =
          RegExp(r'filename\*?=(?:UTF-8\x27\x27)?"?([^";]+)"?')
              .firstMatch(disposition)
              ?.group(1) ??
          'syncgate-muster.${format == ExportFormat.csv ? 'csv' : 'xlsx'}';
      final path = await _save(name, response.bodyBytes);
      return Result.ok(
        ExportResult(
          path: path,
          rows: int.tryParse(response.headers['x-row-count'] ?? '') ?? 0,
        ),
      );
    } on ApiError catch (e) {
      return Result.err(failureOf(e));
    }
  }
}

class ApiBackupService implements BackupService {
  new(this._api, {this.onPassphraseSet})
    : _info = Refreshable<BackupInfo>(() async {
        final json = await _api.getMap('api/v1/backups/info');
        return BackupInfo(
          lastBackupAt: parseInstantOrNull(json['lastBackupAt']),
          destination: json['destination'] as String?,
        );
      }, interval: const Duration(seconds: 20));

  final ApiClient _api;
  final Refreshable<BackupInfo> _info;
  final void Function()? onPassphraseSet;

  @override
  Stream<BackupInfo> watch() => _info.watch();

  @override
  Future<BackupInfo> current() => _info.current();

  @override
  Future<Result<BackupInfo, Failure>> backupNow() async {
    try {
      await _api.send('POST', 'api/v1/backups', body: <String, Object?>{});
      await _info.refresh();
      return Result.ok(await _info.current());
    } on ApiError catch (e) {
      return Result.err(failureOf(e));
    }
  }

  @override
  Future<Result<void, Failure>> setPassphrase(String passphrase) async {
    try {
      await _api.send(
        'PUT',
        'api/v1/backups/passphrase',
        body: {'passphrase': passphrase},
      );
      onPassphraseSet?.call();
      return const Result.ok(null);
    } on ApiError catch (e) {
      return Result.err(failureOf(e));
    }
  }

  @override
  Future<Result<int, Failure>> restore({
    required List<int> file,
    required String passphrase,
  }) async {
    try {
      final response = await _api.sendMultipart(
        'api/v1/backups/restore',
        file: file,
        fileName: 'restore.sgbackup',
        fields: {'passphrase': passphrase},
      );
      final records = RegExp(r'"records":(\d+)').firstMatch(response.body);
      return Result.ok(int.tryParse(records?.group(1) ?? '') ?? 0);
    } on ApiError catch (e) {
      return Result.err(failureOf(e));
    }
  }
}

class ApiLicenceService implements LicenceService {
  new(this._api)
    : _status = Refreshable<LicenceStatus>(
        () async => licenceFromJson(await _api.getMap('api/v1/licence')),
        interval: const Duration(seconds: 30),
      );

  final ApiClient _api;
  final Refreshable<LicenceStatus> _status;

  @override
  Stream<LicenceStatus> watch() => _status.watch();

  @override
  Future<LicenceStatus> current() => _status.current();

  @override
  Future<Result<LicenceStatus, Failure>> activate(String key) async {
    try {
      final json = await _api.send(
        'POST',
        'api/v1/licence/activate',
        body: {'key': key},
      );
      unawaited(_status.refresh());
      return Result.ok(licenceFromJson((json! as Map).cast()));
    } on ApiError catch (e) {
      return Result.err(failureOf(e));
    }
  }

  @override
  Future<LicenceStatus> startTrial() async {
    final json = await _api.send(
      'POST',
      'api/v1/licence/trial',
      body: <String, Object?>{},
    );
    unawaited(_status.refresh());
    return licenceFromJson((json! as Map).cast());
  }
}
