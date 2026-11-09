import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sg_domain/sg_domain.dart';

/// An error answer from the SyncGate API (`{code, message, details}`), or a
/// transport failure (status 0, code `NO_INTERNET`).
class ApiError implements Exception {
  const new({
    required this.status,
    required this.code,
    required this.message,
    this.details = const {},
  });

  factory offline([String? detail]) => ApiError(
    status: 0,
    code: 'NO_INTERNET',
    message: detail ?? 'Could not reach the SyncGate server',
  );

  final int status;
  final String code;
  final String message;
  final Map<String, Object?> details;

  bool get isNotFound => status == 404;

  @override
  String toString() => 'ApiError($status $code: $message)';
}

/// Maps an API error onto the app's sealed [Failure] classes. Anything the app
/// has no special screen for becomes [Unexpected].
Failure failureOf(ApiError e) {
  final d = e.details;
  switch (e.code) {
    case 'WRONG_PIN':
      final locked = (d['lockedForSeconds'] as num?)?.toInt() ?? 0;
      return WrongPin(
        attemptsLeft: (d['attemptsLeft'] as num?)?.toInt() ?? 0,
        lockedFor: locked > 0 ? Duration(seconds: locked) : null,
      );
    case 'LOCKED_OUT':
      return LockedOut(
        Duration(seconds: (d['retryAfterSeconds'] as num?)?.toInt() ?? 30),
      );
    case 'NOT_ALLOWED':
      return const NotAllowed();
    case 'WORKER_UNDER_AGE':
      return const WorkerUnderAge();
    case 'DUPLICATE_WORKER_CODE':
      return const DuplicateWorkerCode();
    case 'MANUAL_LIMIT_REACHED':
      return const ManualLimitReached();
    case 'ALREADY_MARKED':
      return AlreadyMarked(
        at: DateTime.parse(d['at']! as String).toLocal(),
        direction: Direction.values.byName(d['direction']! as String),
      );
    case 'INVALID_LICENCE_KEY':
      return const InvalidLicenceKey();
    case 'NO_INTERNET':
      return const NoInternet();
    case 'NOT_FOUND':
      return const NotFound();
    case 'INVALID_CORRECTION':
      return const InvalidCorrection();
    default:
      return Unexpected(e.message);
  }
}

/// Holds the two tokens the app uses: the gate phone's own (device) token and
/// the PIN-unlocked admin token. The admin token is dropped when the app goes
/// back to the gate.
class TokenStore {
  String? device;
  String? admin;

  void clearAdmin() => admin = null;
}

/// Thin JSON-over-HTTP client with timeouts, one retry after re-authenticating
/// the device, and no logging of bodies (they can contain PINs).
class ApiClient {
  new({
    required String baseUrl,
    required this.deviceKey,
    http.Client? httpClient,
    TokenStore? tokens,
    this.timeout = const Duration(seconds: 15),
  }) : base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       tokens = tokens ?? TokenStore(),
       _http = httpClient ?? http.Client();

  final Uri base;
  final String deviceKey;
  final TokenStore tokens;
  final Duration timeout;
  final http.Client _http;

  /// Called once an owner exists (after the wizard, or at start-up).
  bool? hasOwner;

  Future<Map<String, Object?>> getMap(
    String path, {
    Map<String, String?>? query,
  }) async => (await send('GET', path, query: query))! as Map<String, Object?>;

  Future<List<Object?>> getList(
    String path, {
    Map<String, String?>? query,
  }) async => (await send('GET', path, query: query))! as List<Object?>;

  /// Sends a request and returns the decoded JSON (or null for 204/empty).
  Future<Object?> send(
    String method,
    String path, {
    Object? body,
    Map<String, String?>? query,
    bool authenticated = true,
  }) async {
    final response = await _request(
      method,
      path,
      body: body,
      query: query,
      authenticated: authenticated,
    );
    return response.body.isEmpty
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));
  }

  /// For file downloads (exports, backups): returns the raw response.
  Future<http.Response> sendForBytes(
    String method,
    String path, {
    Object? body,
  }) => _request(method, path, body: body);

  Future<http.Response> sendMultipart(
    String path, {
    required List<int> file,
    required String fileName,
    required Map<String, String> fields,
  }) async {
    final token = await _token();
    final request = http.MultipartRequest('POST', _uri(path, null))
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes('file', file, filename: fileName),
      );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    try {
      final streamed = await _http.send(request).timeout(timeout * 4);
      return _check(await http.Response.fromStream(streamed));
    } on ApiError {
      rethrow;
    } on Exception catch (e) {
      throw _offline(e);
    }
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String?>? query,
    bool authenticated = true,
    bool retried = false,
  }) async {
    final token = authenticated ? await _token() : null;
    final request = http.Request(method, _uri(path, query))
      ..headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    try {
      final streamed = await _http.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 401 &&
          authenticated &&
          !retried &&
          token != null &&
          token == tokens.device) {
        // The device token expired: sign the phone in again, once.
        tokens.device = null;
        return await _request(
          method,
          path,
          body: body,
          query: query,
          retried: true,
        );
      }
      return _check(response);
    } on ApiError {
      rethrow;
    } on Exception catch (e) {
      throw _offline(e);
    }
  }

  /// Admin token if unlocked; otherwise the device token, but only once an
  /// owner exists (before that the setup wizard runs without credentials).
  Future<String?> _token() async {
    if (tokens.admin != null) return tokens.admin;
    hasOwner ??= await _fetchHasOwner();
    if (!hasOwner!) return null;
    return tokens.device ??= await _deviceLogin();
  }

  Future<bool> _fetchHasOwner() async {
    final response = await _request(
      'GET',
      'api/v1/setup/status',
      authenticated: false,
    );
    final json = jsonDecode(response.body) as Map<String, Object?>;
    return json['hasOwner']! as bool;
  }

  Future<String> _deviceLogin() async {
    final response = await _request(
      'POST',
      'api/v1/auth/device',
      body: {'deviceKey': deviceKey},
      authenticated: false,
    );
    return (jsonDecode(response.body) as Map<String, Object?>)['token']!
        as String;
  }

  Uri _uri(String path, Map<String, String?>? query) {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    final resolved = base.resolve(clean);
    final params = {
      for (final e in (query ?? const <String, String?>{}).entries)
        if (e.value != null) e.key: e.value!,
    };
    return params.isEmpty
        ? resolved
        : resolved.replace(queryParameters: params);
  }

  http.Response _check(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    var code = 'UNEXPECTED';
    var message = 'The server answered ${response.statusCode}';
    var details = <String, Object?>{};
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is Map<String, Object?>) {
        code = (json['code'] as String?) ?? code;
        message = (json['message'] as String?) ?? message;
        details = (json['details'] as Map?)?.cast<String, Object?>() ?? {};
      }
    } on FormatException {
      // Not JSON (a proxy error page): keep the generic message.
    }
    throw ApiError(
      status: response.statusCode,
      code: code,
      message: message,
      details: details,
    );
  }

  static ApiError _offline(Object e) => switch (e) {
    TimeoutException() => ApiError.offline('The server did not answer in time'),
    _ => ApiError.offline(),
  };

  /// Ends the admin session on the server, then forgets the token. Best
  /// effort: if the server cannot be reached the token still expires on its
  /// own, and the app drops it either way.
  Future<void> endAdminSession() async {
    final token = tokens.admin;
    tokens.clearAdmin();
    if (token == null) return;
    try {
      final request = http.Request('POST', _uri('api/v1/auth/logout', null))
        ..headers['Authorization'] = 'Bearer $token';
      await _http.send(request).timeout(timeout);
    } on Exception {
      // Ignored on purpose, see above.
    }
  }

  void close() => _http.close();
}
