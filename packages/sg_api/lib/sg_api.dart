/// HTTP implementations of the sg_domain repository and service contracts,
/// talking to the SyncGate Spring Boot API (`services/api`).
///
/// Pure Dart: no Flutter and no `dart:io`, so it is tested with `dart test`
/// against a mock HTTP client. The app wires it in `src/wiring/`.
library;

export 'src/api_backend.dart';
export 'src/api_client.dart';
export 'src/ids.dart';
export 'src/json.dart' show dateToJson, instantToJson, monthToJson;
export 'src/refreshable.dart';
export 'src/repositories_core.dart';
export 'src/repositories_people.dart';
export 'src/repositories_records.dart';
export 'src/services.dart';
