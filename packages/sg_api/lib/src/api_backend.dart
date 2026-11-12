import 'package:http/http.dart' as http;
import 'package:sg_api/src/api_client.dart';
import 'package:sg_api/src/json.dart';
import 'package:sg_api/src/repositories_core.dart';
import 'package:sg_api/src/repositories_people.dart';
import 'package:sg_api/src/repositories_records.dart';
import 'package:sg_api/src/services.dart';

/// Every API-backed implementation of the sg_domain contracts, built around
/// one [ApiClient] and wired so a change in one place refreshes the others
/// (a manual mark creates an exception; a passphrase flips a setting).
///
/// The app binds these to its providers in `apps/mobile/lib/src/wiring/`.
class ApiBackend {
  new({
    required String baseUrl,
    required String deviceKey,
    required FileSaver saveFile,
    required DateTime Function() now,
    http.Client? httpClient,
  }) : client = ApiClient(
         baseUrl: baseUrl,
         deviceKey: deviceKey,
         httpClient: httpClient,
       ) {
    settings = ApiSettingsRepository(client);
    users = ApiUserRepository(client, onOwnerCreated: settings.refresh);
    workers = ApiWorkerRepository(client);
    shifts = ApiShiftRepository(client);
    consent = ApiConsentRepository(client);
    exceptions = ApiExceptionRepository(client);
    attendance = ApiAttendanceRepository(
      client,
      onAppended: exceptions.refresh,
    );
    audit = ApiAuditLog(client);
    reports = ApiReportService(client, now);
    export = ApiExportService(client, saveFile);
    backup = ApiBackupService(client, onPassphraseSet: settings.refresh);
    licence = ApiLicenceService(client);
  }

  final ApiClient client;

  late final ApiSettingsRepository settings;
  late final ApiUserRepository users;
  late final ApiWorkerRepository workers;
  late final ApiShiftRepository shifts;
  late final ApiConsentRepository consent;
  late final ApiExceptionRepository exceptions;
  late final ApiAttendanceRepository attendance;
  late final ApiAuditLog audit;
  late final ApiReportService reports;
  late final ApiExportService export;
  late final ApiBackupService backup;
  late final ApiLicenceService licence;

  /// How far the server's clock is from this phone's. Marks are stamped by the
  /// server, so the app shows server time (`phone time + offset`) to stay
  /// consistent with what is recorded.
  Future<Duration> serverClockOffset() async {
    final before = DateTime.now();
    final json = await client.getMap('api/v1/time');
    final after = DateTime.now();
    final server = parseInstant(json['now']);
    final midpoint = before.add(after.difference(before) ~/ 2);
    return server.difference(midpoint);
  }

  void close() => client.close();
}
