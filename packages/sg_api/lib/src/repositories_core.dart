import 'package:sg_api/src/api_client.dart';
import 'package:sg_api/src/json.dart';
import 'package:sg_api/src/refreshable.dart';
import 'package:sg_domain/sg_domain.dart';

/// Settings live on the server so a restore or a second look at the phone sees
/// the same values. Going back to Gate mode drops the admin token.
class ApiSettingsRepository implements SettingsRepository {
  new(this._api)
    : _settings = Refreshable<AppSettings>(
        () async => settingsFromJson(await _api.getMap('api/v1/settings')),
        interval: const Duration(seconds: 15),
      );

  final ApiClient _api;
  final Refreshable<AppSettings> _settings;

  @override
  Future<AppSettings> load() => _settings.current();

  @override
  Stream<AppSettings> watch() => _settings.watch();

  Future<void> refresh() => _settings.refresh();

  @override
  Future<void> save(AppSettings settings) async {
    await _api.send('PUT', 'api/v1/settings', body: settingsToJson(settings));
    if (settings.mode == AppModeKind.gate) _api.tokens.clearAdmin();
    await _settings.refresh();
  }
}

/// Admin users, PIN sign-in and the owner recovery code.
class ApiUserRepository implements UserRepository {
  new(this._api, {this.onOwnerCreated});

  final ApiClient _api;

  /// Called after the owner is created, so settings can be reloaded with the
  /// new token.
  final void Function()? onOwnerCreated;

  @override
  Future<bool> hasOwner() async {
    final json = await _api.getMap('api/v1/setup/status');
    final has = json['hasOwner']! as bool;
    _api.hasOwner = has;
    return has;
  }

  @override
  Future<String> createOwner(String pin) async {
    final json = await _api.send(
      'POST',
      'api/v1/auth/owner',
      body: {'pin': pin},
      authenticated: false,
    );
    final map = (json! as Map).cast<String, Object?>();
    _api.tokens.admin = map['token']! as String;
    _api.hasOwner = true;
    onOwnerCreated?.call();
    return map['recoveryCode']! as String;
  }

  @override
  Future<Result<AppUser, Failure>> verifyPin(Role role, String pin) async {
    try {
      final json = await _api.send(
        'POST',
        'api/v1/auth/login',
        body: {'role': role.name, 'pin': pin},
        authenticated: false,
      );
      final map = (json! as Map).cast<String, Object?>();
      _api.tokens.admin = map['token']! as String;
      return Result.ok(userFromJson((map['user']! as Map).cast()));
    } on ApiError catch (e) {
      return Result.err(failureOf(e));
    }
  }

  @override
  Future<Result<void, Failure>> resetOwnerPin({
    required String recoveryCode,
    required String newPin,
  }) async {
    try {
      final json = await _api.send(
        'POST',
        'api/v1/auth/reset-owner-pin',
        body: {'recoveryCode': recoveryCode, 'newPin': newPin},
        authenticated: false,
      );
      _api.tokens.admin = (json! as Map)['token']! as String;
      return const Result.ok(null);
    } on ApiError catch (e) {
      // A wrong recovery code is reported like a wrong PIN.
      return Result.err(failureOf(e));
    }
  }

  @override
  Future<List<AppUser>> users() async {
    try {
      return [
        for (final u in await _api.getList('api/v1/users'))
          userFromJson((u! as Map).cast()),
      ];
    } on ApiError catch (e) {
      if (e.status == 403 || e.status == 401) return const [];
      rethrow;
    }
  }

  @override
  Future<void> setPin(String userId, String pin) async {
    await _api.send('PUT', 'api/v1/users/$userId/pin', body: {'pin': pin});
  }
}
